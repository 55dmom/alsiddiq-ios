import Foundation

struct Session: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
}

/// No network: the operation is kept and retried later.
struct OfflineError: LocalizedError { var errorDescription: String? { "لا يوجد اتصال بالإنترنت" } }

struct APIError: LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}

typealias JSON = [String: Any]

/// A database value or SQL null.
func opt<T>(_ v: T?) -> Any { if let v = v { return v } else { return NSNull() } }

/// Minimal client for Supabase Auth, PostgREST and Edge Functions over HTTPS — the same calls the
/// Android app makes. Only the PUBLIC (anon) key is used; the server's rules decide what each account may do.
final class SupabaseAPI {
    let baseURL: String
    let publicKey: String
    private let http: URLSession

    init(config: CloudConfig) {
        baseURL = config.url.absoluteString.hasSuffix("/") ? String(config.url.absoluteString.dropLast()) : config.url.absoluteString
        publicKey = config.anonKey
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.waitsForConnectivity = false
        http = URLSession(configuration: c)
    }

    private func exec(_ method: String, _ path: String, token: String?, body: Any? = nil, headers: [String: String] = [:]) async throws -> (Int, Data) {
        guard let url = URL(string: baseURL + path) else { throw APIError(code: 0, message: "عنوان الخادم غير صحيح") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(publicKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + (token ?? publicKey), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if method != "GET" && method != "DELETE" {
            req.httpBody = Data("{}".utf8)
        }
        do {
            let (data, resp) = try await http.data(for: req)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw OfflineError()
        }
    }

    private static func hasArabic(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.value >= 0x0621 && $0.value <= 0x064A }
    }

    private func errorText(_ code: Int, _ data: Data) -> String {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? JSON
        var raw = ""
        for k in ["error", "msg", "message", "error_description"] {
            if let v = obj?[k] as? String, !v.isEmpty { raw = v; break }
        }
        let low = raw.lowercased()
        if low.contains("invalid login credentials") { return "كلمة السر غير صحيحة" }
        if code == 429 && !Self.hasArabic(raw) { return "محاولات خاطئة كثيرة، انتظر ربع ساعة ثم حاول" }
        if low.contains("row-level security") || code == 403 { return Self.hasArabic(raw) ? raw : "ليست لديك صلاحية لهذه العملية" }
        if low.contains("duplicate key") { return "هذا السجل موجود مسبقاً" }
        if !raw.isEmpty && Self.hasArabic(raw) { return raw }
        if code == 401 { return "انتهت الجلسة، سجّل الدخول مجدداً" }
        if code >= 500 { return "الخادم غير متاح حالياً، حاول بعد قليل" }
        return "تعذّر تنفيذ العملية (\(code))"
    }

    @discardableResult
    private func ok(_ method: String, _ path: String, token: String?, body: Any? = nil, headers: [String: String] = [:]) async throws -> Data {
        let (code, data) = try await exec(method, path, token: token, body: body, headers: headers)
        guard (200...299).contains(code) else { throw APIError(code: code, message: errorText(code, data)) }
        return data
    }

    private func session(from data: Data) throws -> Session {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
              let at = o["access_token"] as? String, let rt = o["refresh_token"] as? String,
              let user = o["user"] as? JSON, let uid = user["id"] as? String else {
            throw APIError(code: 0, message: "استجابة غير متوقعة من الخادم")
        }
        let expiresIn = (o["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return Session(accessToken: at, refreshToken: rt, expiresAt: Date().addingTimeInterval(expiresIn), userId: uid)
    }

    /// The session object the «access» function returns (Supabase's own token response).
    func sessionFrom(_ o: JSON) -> Session? {
        guard let d = try? JSONSerialization.data(withJSONObject: o) else { return nil }
        return try? session(from: d)
    }

    /// Raw call for the CI self-test: the server's own status code and body.
    func rawCall(_ method: String, _ path: String, token: String, body: Any?, headers: [String: String] = [:]) async -> (Int, Data) {
        (try? await exec(method, path, token: token, body: body, headers: headers)) ?? (-1, Data())
    }

    /// Raw storage upload for the CI self-test: the server's own status code.
    func rawUpload(token: String, bucket: String, path: String, data: Data) async -> Int {
        do { try await storageUpload(token: token, bucket: bucket, path: path, data: data); return 200 }
        catch let e as APIError { return e.code }
        catch { return -1 }
    }

    /// Storage: upload / download / delete an object in a bucket (the user's own token; the bucket's rules decide).
    func storageUpload(token: String, bucket: String, path: String, data: Data, contentType: String = "image/jpeg") async throws {
        guard let url = URL(string: "\(baseURL)/storage/v1/object/\(bucket)/\(path)") else { throw APIError(code: 0, message: "عنوان غير صحيح") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(publicKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = data
        let (d, resp): (Data, URLResponse)
        do { (d, resp) = try await http.data(for: req) } catch { throw OfflineError() }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else { throw APIError(code: code, message: errorText(code, d)) }
    }

    func storageDownload(token: String, bucket: String, path: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/storage/v1/object/authenticated/\(bucket)/\(path)") else { throw APIError(code: 0, message: "عنوان غير صحيح") }
        var req = URLRequest(url: url)
        req.setValue(publicKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (d, resp): (Data, URLResponse)
        do { (d, resp) = try await http.data(for: req) } catch { throw OfflineError() }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else { throw APIError(code: code, message: errorText(code, d)) }
        return d
    }

    func storageDelete(token: String, bucket: String, path: String) async throws {
        try await ok("DELETE", "/storage/v1/object/\(bucket)/\(path)", token: token)
    }

    func signIn(email: String, password: String) async throws -> Session {
        try session(from: try await ok("POST", "/auth/v1/token?grant_type=password", token: nil, body: ["email": email, "password": password]))
    }

    func refresh(_ refreshToken: String) async throws -> Session {
        try session(from: try await ok("POST", "/auth/v1/token?grant_type=refresh_token", token: nil, body: ["refresh_token": refreshToken]))
    }

    func signOut(token: String) async { _ = try? await exec("POST", "/auth/v1/logout", token: token) }

    func updatePassword(token: String, password: String) async throws {
        try await ok("PUT", "/auth/v1/user", token: token, body: ["password": password])
    }

    /// Reads every row the user may see (RLS), page by page.
    func selectAll(token: String, table: String, query: String = "select=*") async throws -> [JSON] {
        var out: [JSON] = []
        let page = 1000
        var offset = 0
        while true {
            let data = try await ok("GET", "/rest/v1/\(table)?\(query)&limit=\(page)&offset=\(offset)", token: token)
            let arr = (try? JSONSerialization.jsonObject(with: data)) as? [JSON] ?? []
            out += arr
            if arr.count < page { break }
            offset += page
        }
        return out
    }

    func upsert(token: String, table: String, rows: Any, onConflict: String, ignore: Bool) async throws {
        let prefer = (ignore ? "resolution=ignore-duplicates" : "resolution=merge-duplicates") + ",return=minimal"
        try await ok("POST", "/rest/v1/\(table)?on_conflict=\(onConflict)", token: token, body: rows, headers: ["Prefer": prefer])
    }

    func patch(token: String, table: String, filter: String, body: Any) async throws {
        try await ok("PATCH", "/rest/v1/\(table)?\(filter)", token: token, body: body, headers: ["Prefer": "return=minimal"])
    }

    func delete(token: String, table: String, filter: String) async throws {
        try await ok("DELETE", "/rest/v1/\(table)?\(filter)", token: token, headers: ["Prefer": "return=minimal"])
    }

    func function(token: String?, name: String, body: JSON) async throws -> JSON {
        let data = try await ok("POST", "/functions/v1/\(name)", token: token, body: body)
        return ((try? JSONSerialization.jsonObject(with: data)) as? JSON) ?? [:]
    }
}

/// Converts between database rows (snake_case, lowercase enums) and app models — same as the Android Mappers.
enum Rows {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    static func ts(_ v: Any?) -> Date {
        guard var s = v as? String, !s.isEmpty else { return Date(timeIntervalSince1970: 0) }
        if s.contains(" ") && !s.contains("T") { s = s.replacingOccurrences(of: " ", with: "T") }
        if let d = isoFrac.date(from: s) ?? isoPlain.date(from: s) { return d }
        // Postgres sends microseconds (6 digits): trim the fraction to milliseconds and retry.
        if let dot = s.firstIndex(of: ".") {
            let after = s[s.index(after: dot)...]
            let digits = after.prefix { $0.isNumber }
            let rest = after.dropFirst(digits.count)
            let ms = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            let fixed = String(s[..<dot]) + "." + ms + rest
            if let d = isoFrac.date(from: fixed) { return d }
            if let d = isoPlain.date(from: String(s[..<dot]) + rest) { return d }
        }
        return Date(timeIntervalSince1970: 0)
    }

    static func iso(_ d: Date) -> String { isoFrac.string(from: d) }

    private static func s(_ o: JSON, _ k: String) -> String? { o[k] as? String }
    private static func i(_ o: JSON, _ k: String) -> Int? { (o[k] as? NSNumber)?.intValue }
    private static func b(_ o: JSON, _ k: String) -> Bool? { (o[k] as? NSNumber)?.boolValue }

    static func center(_ o: JSON) -> CenterInfo { CenterInfo(name: s(o, "name") ?? "", city: s(o, "city") ?? "") }

    /// v3 accounts only (access_kind set); old build-5 phone accounts are ignored.
    static func member(_ o: JSON) -> Member? {
        guard let id = s(o, "id"), let kind = s(o, "access_kind"), let role = Role(db: kind) else { return nil }
        return Member(id: id, fullName: s(o, "full_name") ?? "", role: role, active: b(o, "active") ?? true,
                      createdAt: ts(o["created_at"]))
    }

    static func circle(_ o: JSON) -> StudyCircle? {
        guard let id = s(o, "id") else { return nil }
        return StudyCircle(id: id, name: s(o, "name") ?? "", teacherId: s(o, "teacher_id"), teacherName: s(o, "teacher_name"), level: s(o, "level") ?? "",
                           schedule: s(o, "schedule") ?? "", capacity: i(o, "capacity") ?? 15, active: b(o, "active") ?? true,
                           createdAt: ts(o["created_at"]))
    }

    static func circleRow(_ c: StudyCircle, _ center: String) -> JSON {
        ["id": c.id, "center_id": center, "name": c.name, "teacher_id": opt(c.teacherId), "teacher_name": opt(c.teacherName), "level": c.level,
         "schedule": c.schedule, "capacity": c.capacity, "active": c.active, "updated_at": iso(Date())]
    }

    static func student(_ o: JSON) -> Student? {
        guard let id = s(o, "id") else { return nil }
        return Student(id: id, fullName: s(o, "full_name") ?? "", phone: s(o, "phone") ?? "", birthYear: i(o, "birth_year"),
                       circleId: s(o, "circle_id"), joinedOn: s(o, "joined_on") ?? "", goalJuz: i(o, "goal_juz") ?? 5,
                       status: StudentStatus(rawValue: (s(o, "status") ?? "").uppercased()) ?? .active, notes: s(o, "notes") ?? "",
                       photoPath: s(o, "photo_path"), createdAt: ts(o["created_at"]))
    }

    static func studentRow(_ st: Student, _ center: String) -> JSON {
        let joined: String = st.joinedOn.isEmpty ? Days.iso(Days.today) : st.joinedOn
        return ["id": st.id, "center_id": center, "full_name": st.fullName, "phone": st.phone,
         "birth_year": opt(st.birthYear), "circle_id": opt(st.circleId),
         "joined_on": joined, "goal_juz": st.goalJuz,
         "status": st.status.rawValue.lowercased(), "notes": st.notes, "photo_path": opt(st.photoPath), "updated_at": iso(Date())]
    }

    static func recitation(_ o: JSON) -> Recitation? {
        guard let id = s(o, "id"), let sid = s(o, "student_id") else { return nil }
        return Recitation(id: id, studentId: sid, circleId: s(o, "circle_id"), teacherId: s(o, "teacher_id") ?? "",
                          kind: RecordKind(rawValue: (s(o, "kind") ?? "").uppercased()) ?? .hifz,
                          fromSurah: i(o, "from_surah") ?? 1, fromAyah: i(o, "from_ayah") ?? 1,
                          toSurah: i(o, "to_surah") ?? 1, toAyah: i(o, "to_ayah") ?? 1,
                          grade: Grade(rawValue: (s(o, "grade") ?? "").uppercased()) ?? .good,
                          mistakes: i(o, "mistakes") ?? 0, notes: s(o, "notes") ?? "", recordedAt: ts(o["recorded_at"]),
                          byName: s(o, "by_name") ?? "")
    }

    static func recitationRow(_ r: Recitation, _ center: String) -> JSON {
        ["id": r.id, "center_id": center, "student_id": r.studentId, "circle_id": opt(r.circleId),
         "teacher_id": r.teacherId, "kind": r.kind.rawValue.lowercased(), "from_surah": r.fromSurah, "from_ayah": r.fromAyah,
         "to_surah": r.toSurah, "to_ayah": r.toAyah, "grade": r.grade.rawValue.lowercased(), "mistakes": r.mistakes,
         "notes": r.notes, "recorded_at": iso(r.recordedAt), "by_name": r.byName.isEmpty ? NSNull() : r.byName]
    }

    static func attendance(_ o: JSON) -> Attendance? {
        guard let id = s(o, "id"), let sid = s(o, "student_id") else { return nil }
        return Attendance(id: id, studentId: sid, circleId: s(o, "circle_id"), day: s(o, "day") ?? "",
                          status: AttendanceStatus(rawValue: (s(o, "status") ?? "").uppercased()) ?? .present,
                          recordedBy: s(o, "recorded_by") ?? "", recordedAt: ts(o["recorded_at"]), byName: s(o, "by_name") ?? "")
    }

    static func reward(_ o: JSON) -> Reward? {
        guard let id = s(o, "id"), let sid = s(o, "student_id") else { return nil }
        return Reward(id: id, studentId: sid, points: i(o, "points") ?? 0, reason: s(o, "reason") ?? "",
                      awardedBy: s(o, "awarded_by") ?? "", createdAt: ts(o["created_at"]), byName: s(o, "by_name") ?? "")
    }

    static func rewardRow(_ r: Reward, _ center: String) -> JSON {
        ["id": r.id, "center_id": center, "student_id": r.studentId, "points": r.points, "reason": r.reason,
         "awarded_by": r.awardedBy, "created_at": iso(r.createdAt), "by_name": r.byName.isEmpty ? NSNull() : r.byName]
    }

    static func announcement(_ o: JSON) -> Announcement? {
        guard let id = s(o, "id") else { return nil }
        return Announcement(id: id, title: s(o, "title") ?? "", body: s(o, "body") ?? "",
                            audience: Audience(rawValue: (s(o, "audience") ?? "").uppercased()) ?? .all,
                            createdBy: s(o, "created_by") ?? "", createdAt: ts(o["created_at"]), byName: s(o, "by_name") ?? "")
    }

    static func announcementRow(_ a: Announcement, _ center: String) -> JSON {
        ["id": a.id, "center_id": center, "title": a.title, "body": a.body, "audience": a.audience.rawValue.lowercased(),
         "created_by": a.createdBy, "created_at": iso(a.createdAt), "by_name": a.byName.isEmpty ? NSNull() : a.byName]
    }

    static func teacherName(_ o: JSON) -> TeacherName? {
        guard let id = s(o, "id") else { return nil }
        return TeacherName(id: id, name: s(o, "name") ?? "", active: b(o, "active") ?? true)
    }

    static func notification(_ o: JSON) -> AppNotification? {
        guard let id = s(o, "id") else { return nil }
        return AppNotification(id: id, userId: s(o, "user_id") ?? "", title: s(o, "title") ?? "", body: s(o, "body") ?? "",
                               kind: s(o, "kind") ?? "info", refId: s(o, "ref_id"), read: s(o, "read_at") != nil,
                               createdAt: ts(o["created_at"]))
    }
}
