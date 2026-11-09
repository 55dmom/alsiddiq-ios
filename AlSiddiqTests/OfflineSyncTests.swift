import XCTest
@testable import AlSiddiq

/// v3.2 offline sync, tested against a MOCK server (no real database is touched).
final class MockServer: URLProtocol {
    static var online = true
    static var refreshFails = false
    static var received: [(String, String, String)] = []   // method, path, body
    static func reset() { online = true; refreshFails = false; received = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    private func bodyOf(_ r: URLRequest) -> String {
        if let b = r.httpBody { return String(data: b, encoding: .utf8) ?? "" }
        guard let s = r.httpBodyStream else { return "" }
        s.open(); defer { s.close() }
        var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
        return String(data: d, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        guard Self.online else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let url = request.url!
        let path = url.path, q = url.query ?? "", m = request.httpMethod ?? "GET"
        let body = bodyOf(request)
        Self.received.append((m, path + (q.isEmpty ? "" : "?" + q), body))
        let session: [String: Any] = ["access_token": "tok", "refresh_token": "ref", "expires_in": 1, "user": ["id": "m-t"]]
        var code = 200
        var out: Any = []
        switch (m, path) {
        case ("POST", "/functions/v1/access"):
            out = ["session": session, "profile": ["id": "m-t", "access_kind": "teacher", "full_name": "الأستاذ أحمد"], "center_name": "مركز تجريبي"]
        case ("POST", "/auth/v1/token"):
            if Self.refreshFails { code = 400; out = ["error": "invalid_grant", "error_description": "Refresh Token Not Found"] } else { out = session }
        case ("GET", "/rest/v1/centers"): out = [["id": "c1", "name": "مركز تجريبي"]]
        case ("GET", "/rest/v1/profiles"): out = [["id": "m-t", "access_kind": "teacher", "full_name": "الأستاذ أحمد", "active": true]]
        case ("GET", "/rest/v1/circles"): out = [["id": "cA", "center_id": "c1", "name": "حلقته", "teacher_id": "m-t"],
                                                  ["id": "cB", "center_id": "c1", "name": "حلقة غيره", "teacher_id": "m-other"]]
        case ("GET", "/rest/v1/students"): out = [["id": "s1", "center_id": "c1", "full_name": "طالب", "status": "active", "circle_id": "cA"],
                                                   ["id": "s2", "center_id": "c1", "full_name": "طالب آخر", "status": "active", "circle_id": "cB"]]
        case ("GET", _): out = []
        default: code = 201; out = []
        }
        let data = (try? JSONSerialization.data(withJSONObject: out)) ?? Data()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class OfflineSyncTests: XCTestCase {
    let cfg = CloudConfig(url: URL(string: "https://mock.invalid")!, anonKey: "anon")
    let file = "test_state_offline.json"

    override func setUp() async throws {
        SupabaseAPI.extraProtocols = [MockServer.self]
        MockServer.reset()
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
    }

    private func recitation(_ id: String) -> Recitation {
        Recitation(id: id, studentId: "s1", circleId: nil, teacherId: "", kind: .hifz, fromSurah: 1, fromAyah: 1, toSurah: 1, toAyah: 7,
                   grade: .excellent, notes: "offline test")
    }
    /// The app's own sync loop may be mid-attempt: retry a few times until the queue is empty.
    private func settle(_ r: CloudRepository) async throws {
        for _ in 0..<8 { try? await r.refresh(); if r.syncState == .synced { return }; try await Task.sleep(nanoseconds: 300_000_000) }
    }
    private func posts(_ id: String) -> Int { MockServer.received.filter { $0.0 == "POST" && $0.1.hasPrefix("/rest/v1/recitations") && $0.2.contains(id) }.count }

    func testOfflineWriteIsKeptSurvivesRestartAndSyncs() async throws {
        var repo: CloudRepository? = CloudRepository(config: cfg, stateFile: file)
        _ = try await repo!.signIn(password: "333333", kind: .teacher)
        XCTAssertEqual(repo!.currentUser?.role, .teacher)
        XCTAssertNotNil(repo!.snapshot.student("s1"))

        // 1) no network: the write is accepted at once, shown, and queued
        MockServer.online = false
        let id = UUID().uuidString.lowercased()
        _ = try await repo!.logRecitation(recitation(id))
        XCTAssertEqual(repo!.syncState, .pending(1))
        XCTAssertTrue(repo!.isPending(id))
        XCTAssertTrue(repo!.snapshot.recitations.contains { $0.id == id })
        XCTAssertEqual(posts(id), 0)

        // 2) the app restarts while still offline: the queue is still on disk
        repo = nil
        let again = CloudRepository(config: cfg, stateFile: file)
        XCTAssertEqual(again.syncState, .pending(1))
        XCTAssertTrue(again.snapshot.recitations.contains { $0.id == id })

        // 3) network back: it is sent (same client id, idempotent), queue empty
        MockServer.online = true
        try await settle(again)
        XCTAssertEqual(again.syncState, .synced)
        XCTAssertEqual(posts(id), 1)
        // sending again never duplicates: the id is the client's own UUID, upserted
        XCTAssertTrue(MockServer.received.contains { $0.1.contains("on_conflict=id") })
    }

    func testExpiredLoginParksQueueUntilPasswordAgain() async throws {
        let repo = CloudRepository(config: cfg, stateFile: file)
        _ = try await repo.signIn(password: "333333", kind: .teacher)
        MockServer.online = false
        let id = UUID().uuidString.lowercased()
        _ = try await repo.logRecitation(recitation(id))
        XCTAssertEqual(repo.syncState, .pending(1))

        // network back, but the login has ended on the server (password changed / expired)
        MockServer.online = true
        MockServer.refreshFails = true
        for _ in 0..<5 { try? await repo.refresh(); if case .waitingPassword = repo.syncState { break }; try await Task.sleep(nanoseconds: 300_000_000) }
        XCTAssertEqual(repo.syncState, .waitingPassword(1, .teacher), "kept, waiting for the teacher's own password")
        XCTAssertEqual(posts(id), 0)

        // the teachers' password typed again: the parked write goes up
        MockServer.refreshFails = false
        _ = try await repo.signIn(password: "333333", kind: .teacher)
        try await settle(repo)
        XCTAssertEqual(repo.syncState, .synced)
        XCTAssertEqual(posts(id), 1)
    }

    /// v3.3: a teacher edits only his own circle; every other circle is read-only (the server refuses too).
    func testTeacherEditsOnlyHisOwnCircle() async throws {
        let repo = CloudRepository(config: cfg, stateFile: file)
        let me = try await repo.signIn(password: "333333", kind: .teacher)
        let snap = repo.snapshot
        XCTAssertNotNil(snap.student("s2"), "he sees the other circle's student")
        XCTAssertTrue(Permissions.canRecordFor(me, snap.student("s1")!, snap))
        XCTAssertFalse(Permissions.canRecordFor(me, snap.student("s2")!, snap))
        XCTAssertFalse(Permissions.canEditStudent(me, snap.student("s2")!, snap))
        XCTAssertEqual(Permissions.editableCircles(me, snap).map { $0.id }, ["cA"])
        var r = recitation(UUID().uuidString.lowercased()); r.studentId = "s2"
        do { _ = try await repo.logRecitation(r); XCTFail("must be refused") } catch {}
        XCTAssertEqual(repo.syncState, .synced, "nothing queued for a circle that is not his")
    }
}
