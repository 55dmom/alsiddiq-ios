import Foundation
import UIKit
import UserNotifications

/// One write waiting to reach the server (kept on disk, so it survives app restarts and no network).
struct PendingOp: Codable, Equatable {
    var id: String = UUID().uuidString.lowercased()
    var type: String            // upsert | patch | delete
    var table: String
    var body: String = ""
    var filter: String = ""
    var onConflict: String = "id"
    var ignoreDuplicates: Bool = false
}

private struct CloudState: Codable {
    var session: Session?
    var me: Member?
    /// The general (viewer) login kept underneath while the admin/teachers section is open.
    var baseSession: Session?
    var baseMe: Member?
    var centerName: String = ""
    var centerId: String?
    var cache = CenterSnapshot()
    var outbox: [PendingOp] = []
    var lastSyncAt: Date?
    var seenNotificationIds: [String] = []
}

/// The real backend: the central Postgres database (Supabase) with server-side security rules —
/// the same project, tables, rules and edge function as the Android app.
/// Reads come from the server and are cached on the phone for offline use; writes appear on screen
/// at once, are queued on disk, and are sent as soon as there is a connection.
@MainActor
final class CloudRepository: AppRepository {
    let mode: BackendMode = .cloud
    var onChange: (() -> Void)?
    private let api: SupabaseAPI
    private let fileURL: URL
    private var st: CloudState
    private var syncing = false
    private var loop: Task<Void, Never>?

    var currentUser: Member? { st.me }
    var baseUser: Member? { st.baseMe }
    var centerName: String { st.centerName }
    private var photoCache: [String: UIImage] = [:]
    var snapshot: CenterSnapshot { st.cache }
    var syncState: SyncState { st.outbox.isEmpty ? .synced : .pending(st.outbox.count) }

    init(config: CloudConfig) {
        api = SupabaseAPI(config: config)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("cloud_state_v3.json")
        if let data = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(CloudState.self, from: data) {
            st = s
        } else {
            st = CloudState()
        }
        // Sync loop while the app runs: every 30 s, and whenever the app comes back to the foreground.
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let self = self, self.st.session != nil { try? await self.syncNow() }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let self = self, self.st.session != nil { try? await self.syncNow() } }
        }
    }

    private func save() {
        let s = st
        let url = fileURL
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }

    private func publish() { onChange?() }

    private func token() async throws -> String {
        guard let s = st.session else { throw AppError.permissionDenied("اكتب كلمة السر أولاً") }
        if s.expiresAt.timeIntervalSinceNow > 60 { return s.accessToken }
        do {
            let fresh = try await api.refresh(s.refreshToken)
            st.session = fresh; save()
            return fresh.accessToken
        } catch let e as APIError {
            if (400...499).contains(e.code) {
                // This login was ended on the server (its password was changed): drop it.
                if let b = st.baseSession, b != s {
                    st.session = b; st.me = st.baseMe; st.baseSession = nil; st.baseMe = nil
                    st.cache = CenterSnapshot(center: st.cache.center); st.outbox = []
                } else {
                    st = CloudState(centerName: st.centerName)
                }
                save(); publish()
            }
            throw e
        }
    }

    // MARK: First-time setup + the «access» function
    private func accessCall(_ body: JSON, token: String? = nil) async throws -> JSON {
        do { return try await api.function(token: token, name: "access", body: body) }
        catch is OfflineError { throw AppError.network("الدخول يحتاج اتصالاً بالإنترنت") }
    }

    func needsSetup() async -> Bool? {
        guard let r = try? await api.function(token: nil, name: "access", body: ["action": "status"]) else { return nil }
        if let n = r["center_name"] as? String, !n.isEmpty { st.centerName = n; save(); publish() }
        return (r["needs_setup"] as? NSNumber)?.boolValue
    }

    private func memberFrom(_ p: JSON) -> Member? {
        guard let id = p["id"] as? String else { return nil }
        let kind = (p["access_kind"] as? String) ?? (p["role"] as? String) ?? "viewer"
        return Member(id: id, fullName: (p["full_name"] as? String) ?? "", role: Role(db: kind) ?? .viewer)
    }

    /// Store a fresh login. keepBase = it was opened from Settings over the general view.
    private func adopt(_ o: JSON, keepBase: Bool) async throws -> Member {
        guard let sj = o["session"] as? JSON, let s = api.sessionFrom(sj),
              let pj = o["profile"] as? JSON, let me = memberFrom(pj) else { throw AppError.network("استجابة غير متوقعة من الخادم") }
        let name = (o["center_name"] as? String) ?? st.centerName
        var base: Session? = nil
        var baseMe: Member? = nil
        if keepBase && me.role != .viewer {
            if st.me?.role == .viewer { base = st.session; baseMe = st.me } else { base = st.baseSession; baseMe = st.baseMe }
        }
        st = CloudState(session: s, me: me, baseSession: base, baseMe: baseMe, centerName: name, centerId: nil)
        save()
        if let rows = try? await api.selectAll(token: s.accessToken, table: "centers", query: "select=id"), let c = rows.first?["id"] as? String {
            st.centerId = c; save()
        }
        try? await reload()
        // Don't raise phone notifications for what was already waiting before this sign-in.
        st.seenNotificationIds = st.cache.notifications.map { $0.id }
        save(); publish()
        return st.me ?? me
    }

    func setup(centerName: String, adminPassword: String, viewerPassword: String, teacherPassword: String?) async throws -> Member {
        let a = Passwords.normalise(adminPassword), v = Passwords.normalise(viewerPassword)
        let t = teacherPassword.map { Passwords.normalise($0) } ?? ""
        if let bad = Passwords.check(a) ?? Passwords.check(v) { throw AppError.validation(bad) }
        if !t.isEmpty, let bad = Passwords.check(t) { throw AppError.validation(bad) }
        if a == v { throw AppError.validation("كلمة سر الإدارة يجب أن تختلف عن كلمة السر العامة") }
        if !t.isEmpty && (t == a || t == v) { throw AppError.validation("كلمة سر المعلمين يجب أن تختلف عن غيرها") }
        var body: JSON = ["action": "setup", "center_name": centerName.trimmingCharacters(in: .whitespaces),
                          "admin_password": a, "viewer_password": v]
        if !t.isEmpty { body["teachers_password"] = t }
        let o = try await accessCall(body)
        return try await adopt(o, keepBase: false)
    }

    // MARK: Auth
    func signIn(password: String, kind: Role?) async throws -> Member {
        let pw = Passwords.normalise(password)
        if pw.isEmpty { throw AppError.validation("اكتب كلمة السر") }
        let k: Any
        switch kind { case .admin?: k = "admin"; case .teacher?: k = "teacher"; default: k = NSNull() }
        let o = try await accessCall(["action": "login", "password": pw, "kind": k])
        Notifier.requestPermission()
        return try await adopt(o, keepBase: kind != nil)
    }

    func leaveRole() async {
        let t = st.session?.accessToken
        if let b = st.baseSession {
            st.session = b; st.me = st.baseMe; st.baseSession = nil; st.baseMe = nil
            st.cache = CenterSnapshot(center: st.cache.center); st.outbox = []
        } else {
            st = CloudState(centerName: st.centerName)
        }
        save(); publish()
        if let t = t { Task { await api.signOut(token: t) } }
        if st.session != nil { Task { try? await self.syncNow() } }
    }

    func signOut() async {
        let ts = [st.session?.accessToken, st.baseSession?.accessToken].compactMap { $0 }
        st = CloudState(centerName: st.centerName); save(); publish()
        for t in ts { Task { await api.signOut(token: t) } }
    }

    // MARK: Sync
    func refresh() async throws { try await syncNow() }

    private func syncNow() async throws {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        try await flushOutbox()
        try await reload()
    }

    /// Pull everything this account may see. RLS on the server decides what that is.
    private func reload() async throws {
        let t = try await token()
        guard let me = st.me else { return }
        async let centers = api.selectAll(token: t, table: "centers")
        async let profiles = api.selectAll(token: t, table: "profiles")
        async let circles = api.selectAll(token: t, table: "circles", query: "select=*&order=name")
        async let students = api.selectAll(token: t, table: "students", query: "select=*&order=full_name")
        async let recs = api.selectAll(token: t, table: "recitations", query: "select=*&order=recorded_at.desc")
        async let att = api.selectAll(token: t, table: "attendance", query: "select=*&order=day.desc")
        async let rewards = api.selectAll(token: t, table: "rewards", query: "select=*&order=created_at.desc")
        async let ann = api.selectAll(token: t, table: "announcements", query: "select=*&order=created_at.desc")
        async let notes = api.selectAll(token: t, table: "notifications", query: "select=*&user_id=eq.\(me.id)&order=created_at.desc")
        async let names = api.selectAll(token: t, table: "teacher_names", query: "select=*&order=name")

        let members = (try await profiles).compactMap { Rows.member($0) }
        if !members.contains(where: { $0.id == me.id }) {
            // v3.1: my own profile is unreadable = this login was ended on the server (its password was changed).
            // Force a refresh: a 4xx there drops this login (see token()).
            if var s = st.session { s.expiresAt = Date(timeIntervalSince1970: 0); st.session = s; save() }
            _ = try await token()
            return
        }
        var fresh = CenterSnapshot()
        fresh.center = (try await centers).first.map { Rows.center($0) } ?? CenterInfo()
        fresh.members = members
        fresh.circles = (try await circles).compactMap { Rows.circle($0) }
        fresh.students = (try await students).compactMap { Rows.student($0) }
        fresh.recitations = (try await recs).compactMap { Rows.recitation($0) }
        fresh.attendance = (try await att).compactMap { Rows.attendance($0) }
        fresh.rewards = (try await rewards).compactMap { Rows.reward($0) }
        fresh.announcements = (try await ann).compactMap { Rows.announcement($0) }
        fresh.notifications = (try await notes).compactMap { Rows.notification($0) }
        fresh.teacherNames = ((try? await names) ?? []).compactMap { Rows.teacherName($0) }

        // Writes still waiting stay visible on screen until the server has them.
        let merged = st.outbox.isEmpty ? fresh : overlayPending(fresh)
        let newOnes = merged.notifications.filter { !$0.read && !st.seenNotificationIds.contains($0.id) }
        st.cache = merged
        st.me = members.first { $0.id == me.id } ?? me
        st.lastSyncAt = Date()
        if !newOnes.isEmpty {
            st.seenNotificationIds = Array((newOnes.map { $0.id } + st.seenNotificationIds).prefix(500))
            if UIApplication.shared.applicationState != .active { Notifier.post(newOnes) }
        }
        save(); publish()
    }

    private func overlayPending(_ fresh: CenterSnapshot) -> CenterSnapshot {
        var ids = Set<String>()
        for op in st.outbox {
            if let d = op.body.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? JSON, let id = o["id"] as? String { ids.insert(id) }
        }
        let old = st.cache
        var out = fresh
        let fr = Set(fresh.recitations.map { $0.id }), fw = Set(fresh.rewards.map { $0.id })
        let fs = Set(fresh.students.map { $0.id }), fc = Set(fresh.circles.map { $0.id })
        out.recitations += old.recitations.filter { ids.contains($0.id) && !fr.contains($0.id) }
        out.rewards += old.rewards.filter { ids.contains($0.id) && !fw.contains($0.id) }
        out.students += old.students.filter { ids.contains($0.id) && !fs.contains($0.id) }
        out.circles += old.circles.filter { ids.contains($0.id) && !fc.contains($0.id) }
        return out
    }

    private func send(_ op: PendingOp) async throws {
        let t = try await token()
        let body: Any = op.body.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [String: Any]()
        switch op.type {
        case "upsert": try await api.upsert(token: t, table: op.table, rows: body, onConflict: op.onConflict, ignore: op.ignoreDuplicates)
        case "patch": try await api.patch(token: t, table: op.table, filter: op.filter, body: body)
        case "delete": try await api.delete(token: t, table: op.table, filter: op.filter)
        default: break
        }
    }

    private func dropOp(_ id: String) { st.outbox.removeAll { $0.id == id }; save(); publish() }

    private func flushOutbox() async throws {
        while let op = st.outbox.first {
            do { try await send(op) }
            catch let e as APIError { if e.code >= 500 { throw e } } // refused by the rules or data: drop it so the queue never jams
            dropOp(op.id)
        }
    }

    /// Send everything queued up to and including `targetId`; the target's own refusal reaches the caller.
    private func flushStrict(_ targetId: String) async throws {
        while let op = st.outbox.first {
            if op.id == targetId { try await send(op); dropOp(op.id); return }
            do { try await send(op) } catch let e as APIError { if e.code >= 500 { throw e } }
            dropOp(op.id)
        }
    }

    /// Apply a change on screen, queue it, and try to send it now.
    /// Online and refused by the server -> the change is undone and the reason returned.
    /// Offline -> kept in the queue and sent automatically later.
    private func write<T>(_ op: PendingOp, _ value: T, _ local: (inout CenterSnapshot) -> Void) async throws -> T {
        local(&st.cache)
        st.outbox.append(op)
        save(); publish()
        do {
            try await flushStrict(op.id)
            Task { try? await self.syncNow() }
            return value
        } catch is OfflineError {
            return value
        } catch {
            st.outbox.removeAll { $0.id == op.id }; save()
            try? await syncNow()
            publish()
            throw error
        }
    }

    private func me() throws -> Member { guard let m = st.me else { throw AppError.permissionDenied("سجّل الدخول أولاً") }; return m }
    private func center() throws -> String { guard let c = st.centerId else { throw AppError.permissionDenied("سجّل الدخول أولاً") }; return c }
    private func require(_ ok: Bool) throws { if !ok { throw AppError.permissionDenied() } }
    private func newId() -> String { UUID().uuidString.lowercased() }
    private func json(_ o: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: Admin
    func updateCenter(_ info: CenterInfo) async throws {
        try require(Permissions.canManageCenter(try me()))
        let cid = try center()
        let body = json(["name": info.name, "city": info.city])
        _ = try await write(PendingOp(type: "patch", table: "centers", body: body, filter: "id=eq.\(cid)"), ()) { $0.center = info }
    }

    private func adminFunction(_ body: JSON) async throws -> JSON {
        do { return try await api.function(token: try await token(), name: "access", body: body) }
        catch is OfflineError { throw AppError.network("هذه العملية تحتاج اتصالاً بالإنترنت") }
    }

    func setAccessPassword(target: Role, password: String) async throws {
        try require(Permissions.canManagePasswords(try me()))
        let pw = Passwords.normalise(password)
        if let bad = Passwords.check(pw) { throw AppError.validation(bad) }
        let t: String
        switch target { case .admin: t = "admin"; case .teacher: t = "teachers"; case .viewer: t = "viewer" }
        _ = try await adminFunction(["action": "set_password", "target": t, "password": pw])
    }

    // MARK: Teacher names (v3.1: names only; admin writes them with plain PostgREST)
    func saveTeacherName(id: String?, name: String) async throws {
        try require(Permissions.canManageCenter(try me()))
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { throw AppError.validation("اكتب اسم المعلم") }
        let tid = id ?? newId()
        let row = json(["id": tid, "center_id": try center(), "name": n, "active": true])
        let old = st.cache.teacherNames.first { $0.id == tid }?.name
        _ = try await write(PendingOp(type: "upsert", table: "teacher_names", body: row), ()) { d in
            if let i = d.teacherNames.firstIndex(where: { $0.id == tid }) { d.teacherNames[i].name = n }
            else { d.teacherNames.append(TeacherName(id: tid, name: n)) }
        }
        // A renamed teacher keeps their circles.
        if let old = old, old != n {
            for c in st.cache.circles where c.teacherName == old {
                var c2 = c; c2.teacherName = n
                _ = try? await saveCircle(c2)
            }
        }
    }

    func removeTeacherName(_ id: String) async throws {
        try require(Permissions.canManageCenter(try me()))
        let body = json(["active": false])
        _ = try await write(PendingOp(type: "patch", table: "teacher_names", body: body, filter: "id=eq.\(id)"), ()) { d in
            d.teacherNames = d.teacherNames.map { var t = $0; if t.id == id { t.active = false }; return t }
        }
    }

    // MARK: Student photos (v3.1: private bucket «student-photos», path <center>/<student>/<random8>.jpg)
    private static let bucket = "student-photos"

    func setStudentPhoto(studentId: String, jpeg: Data?) async throws {
        let u = try me()
        guard let s = st.cache.student(studentId) else { throw AppError.validation("الطالب غير موجود") }
        try require(Permissions.canEditStudent(u, s, st.cache))
        let t: String
        do { t = try await token() } catch is OfflineError { throw AppError.network("الصورة تحتاج اتصالاً بالإنترنت") }
        let old = s.photoPath
        var newPath: String? = nil
        do {
            if let data = jpeg {
                let rnd = String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8))
                let path = "\(try center())/\(studentId)/\(rnd).jpg"
                try await api.storageUpload(token: t, bucket: Self.bucket, path: path, data: data)
                newPath = path
                if let img = UIImage(data: data) { photoCache[path] = img; savePhotoFile(path, data) }
            }
            try await api.patch(token: t, table: "students", filter: "id=eq.\(studentId)", body: ["photo_path": opt(newPath)])
        } catch is OfflineError { throw AppError.network("الصورة تحتاج اتصالاً بالإنترنت") }
        if let i = st.cache.students.firstIndex(where: { $0.id == studentId }) { st.cache.students[i].photoPath = newPath }
        save(); publish()
        if let old = old, old != newPath { Task { try? await api.storageDelete(token: t, bucket: Self.bucket, path: old) } }
    }

    private var photoDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("student-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func photoFile(_ path: String) -> URL { photoDir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_")) }
    private func savePhotoFile(_ path: String, _ data: Data) { try? data.write(to: photoFile(path), options: .atomic) }

    func photo(_ s: Student) async -> UIImage? {
        guard let path = s.photoPath, !path.isEmpty else { return nil }
        if let img = photoCache[path] { return img }
        if let d = try? Data(contentsOf: photoFile(path)), let img = UIImage(data: d) { photoCache[path] = img; return img }
        guard let t = try? await token(), let d = try? await api.storageDownload(token: t, bucket: Self.bucket, path: path),
              let img = UIImage(data: d) else { return nil }
        photoCache[path] = img
        savePhotoFile(path, d)
        return img
    }

    func saveCircle(_ c: StudyCircle) async throws -> StudyCircle {
        try require(Permissions.canManageCircles(try me()))
        if c.name.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب اسم الحلقة") }
        var saved = c
        if saved.id.isEmpty { saved.id = newId() }
        let row = json(Rows.circleRow(saved, try center()))
        return try await write(PendingOp(type: "upsert", table: "circles", body: row), saved) { d in
            if let i = d.circles.firstIndex(where: { $0.id == saved.id }) { d.circles[i] = saved } else { d.circles.append(saved) }
        }
    }

    func deleteCircle(_ id: String) async throws {
        try require(Permissions.canManageCircles(try me()))
        _ = try await write(PendingOp(type: "delete", table: "circles", filter: "id=eq.\(id)"), ()) { d in
            d.circles.removeAll { $0.id == id }
            d.students = d.students.map { var s = $0; if s.circleId == id { s.circleId = nil }; return s }
        }
    }

    func saveStudent(_ s: Student) async throws -> Student {
        try require(Permissions.canEditStudent(try me(), s, st.cache))
        if s.fullName.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب اسم الطالب") }
        var saved = s
        if saved.id.isEmpty { saved.id = newId() }
        let row = json(Rows.studentRow(saved, try center()))
        return try await write(PendingOp(type: "upsert", table: "students", body: row), saved) { d in
            if let i = d.students.firstIndex(where: { $0.id == saved.id }) { d.students[i] = saved } else { d.students.append(saved) }
        }
    }

    func deleteStudent(_ id: String) async throws {
        try require(Permissions.canDeleteStudents(try me()))
        _ = try await write(PendingOp(type: "delete", table: "students", filter: "id=eq.\(id)"), ()) { d in
            d.students.removeAll { $0.id == id }
            d.recitations.removeAll { $0.studentId == id }
            d.attendance.removeAll { $0.studentId == id }
            d.rewards.removeAll { $0.studentId == id }
        }
    }

    // MARK: Teaching
    func logRecitation(_ r: Recitation) async throws -> Recitation {
        let u = try me()
        let d = st.cache
        guard let student = d.student(r.studentId) else { throw AppError.validation("الطالب غير موجود") }
        try require(Permissions.canRecordFor(u, student, d))
        guard Quran.isValid(r.fromSurah, r.fromAyah), Quran.isValid(r.toSurah, r.toAyah) else { throw AppError.validation("رقم الآية غير صحيح") }
        if Quran.ayatBetween(r.fromSurah, r.fromAyah, r.toSurah, r.toAyah) <= 0 { throw AppError.validation("نهاية المقطع قبل بدايته") }
        var saved = r
        if saved.id.isEmpty { saved.id = newId() }
        saved.teacherId = u.id
        saved.circleId = student.circleId
        let row = json(Rows.recitationRow(saved, try center()))
        return try await write(PendingOp(type: "upsert", table: "recitations", body: row, ignoreDuplicates: true), saved) { $0.recitations.insert(saved, at: 0) }
    }

    func deleteRecitation(_ id: String) async throws {
        _ = try await write(PendingOp(type: "delete", table: "recitations", filter: "id=eq.\(id)"), ()) { $0.recitations.removeAll { $0.id == id } }
    }

    func saveAttendance(circleId: String, day: String, marks: [String: AttendanceStatus]) async throws -> Int {
        let u = try me()
        let d = st.cache
        guard let circle = d.circle(circleId) else { throw AppError.validation("الحلقة غير موجودة") }
        try require(Permissions.canTakeAttendance(u))
        _ = circle
        let c = try center()
        let now = Rows.iso(Date())
        let rows: [JSON] = marks.map { sid, s in
            ["center_id": c, "student_id": sid, "circle_id": circleId, "day": day, "status": s.rawValue.lowercased(), "recorded_by": u.id, "recorded_at": now,
             "by_name": opt(Recorder.name)]
        }
        let local = marks.map { Attendance(id: newId(), studentId: $0.key, circleId: circleId, day: day, status: $0.value, recordedBy: u.id) }
        return try await write(PendingOp(type: "upsert", table: "attendance", body: json(rows), onConflict: "student_id,day"), marks.count) { snap in
            snap.attendance.removeAll { $0.day == day && marks.keys.contains($0.studentId) }
            snap.attendance += local
        }
    }

    func giveReward(_ r: Reward) async throws -> Reward {
        let u = try me()
        let d = st.cache
        guard let student = d.student(r.studentId) else { throw AppError.validation("الطالب غير موجود") }
        try require(Permissions.canRecordFor(u, student, d))
        if r.points == 0 { throw AppError.validation("حدّد عدد النقاط") }
        var saved = r
        if saved.id.isEmpty { saved.id = newId() }
        saved.awardedBy = u.id
        if saved.byName.isEmpty { saved.byName = Recorder.name ?? "" }
        let row = json(Rows.rewardRow(saved, try center()))
        return try await write(PendingOp(type: "upsert", table: "rewards", body: row, ignoreDuplicates: true), saved) { $0.rewards.insert(saved, at: 0) }
    }

    // MARK: Communication
    func postAnnouncement(_ a: Announcement) async throws -> Announcement {
        let u = try me()
        try require(Permissions.canPostAnnouncement(u))
        if a.title.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب عنوان الإعلان") }
        var saved = a
        if saved.id.isEmpty { saved.id = newId() }
        saved.createdBy = u.id
        if saved.byName.isEmpty, u.role == .teacher { saved.byName = Recorder.name ?? "" }
        let row = json(Rows.announcementRow(saved, try center()))
        return try await write(PendingOp(type: "upsert", table: "announcements", body: row, ignoreDuplicates: true), saved) { $0.announcements.insert(saved, at: 0) }
    }

    func deleteAnnouncement(_ id: String) async throws {
        _ = try await write(PendingOp(type: "delete", table: "announcements", filter: "id=eq.\(id)"), ()) { $0.announcements.removeAll { $0.id == id } }
    }

    func markNotificationRead(_ id: String) async throws {
        let body = json(["read_at": Rows.iso(Date())])
        _ = try await write(PendingOp(type: "patch", table: "notifications", body: body, filter: "id=eq.\(id)"), ()) { d in
            d.notifications = d.notifications.map { var n = $0; if n.id == id { n.read = true }; return n }
        }
    }

    func markAllNotificationsRead() async throws {
        let u = try me()
        let body = json(["read_at": Rows.iso(Date())])
        _ = try await write(PendingOp(type: "patch", table: "notifications", body: body, filter: "user_id=eq.\(u.id)&read_at=is.null"), ()) { d in
            d.notifications = d.notifications.map { var n = $0; n.read = true; return n }
        }
    }

    // MARK: Background check
    /// New unread notifications since the last check (used by the background refresh).
    func fetchNewNotifications() async -> [AppNotification] {
        guard let u = st.me, let t = try? await token(),
              let rows = try? await api.selectAll(token: t, table: "notifications", query: "select=*&user_id=eq.\(u.id)&read_at=is.null&order=created_at.desc")
        else { return [] }
        let list = rows.compactMap { Rows.notification($0) }
        let seen = Set(st.seenNotificationIds)
        let fresh = list.filter { !seen.contains($0.id) }
        var ids: [String] = []
        for id in list.map({ $0.id }) + st.seenNotificationIds where !ids.contains(id) { ids.append(id) }
        st.seenNotificationIds = Array(ids.prefix(500))
        save()
        return fresh
    }

    var isSignedIn: Bool { st.session != nil }

    #if DEBUG
    /// CI only: raw writes straight to the server, past the app's own checks, so the log shows the SERVER's answer
    /// (2xx = allowed; 401/403 or 0 rows = refused by the server's rules).
    func debugRawWrites(studentId: String, circleId: String?) async -> String {
        guard let t = try? await token(), let me = st.me, let c = st.centerId else { return "no-session" }
        let rec: JSON = ["id": newId(), "center_id": c, "student_id": studentId, "circle_id": opt(circleId), "teacher_id": me.id,
                         "kind": "hifz", "from_surah": 1, "from_ayah": 1, "to_surah": 1, "to_ayah": 7, "grade": "excellent", "notes": "selftest-raw-\(me.role.dbValue)"]
        let att: JSON = ["center_id": c, "student_id": studentId, "circle_id": opt(circleId), "day": "2026-01-01", "status": "absent", "recorded_by": me.id]
        let r1 = await api.rawCall("POST", "/rest/v1/recitations", token: t, body: [rec], headers: ["Prefer": "return=minimal"]).0
        let r2 = await api.rawCall("POST", "/rest/v1/attendance", token: t, body: [att], headers: ["Prefer": "return=minimal"]).0
        let (r3, d3) = await api.rawCall("PATCH", "/rest/v1/students?id=eq.\(studentId)", token: t,
                                         body: ["notes": "selftest-edit-by-\(me.role.dbValue)"], headers: ["Prefer": "return=representation"])
        let n3 = ((try? JSONSerialization.jsonObject(with: d3)) as? [Any])?.count ?? -1
        let jpg = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            UIColor(red: 0.16, green: 0.15, blue: 0.39, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.jpegData(compressionQuality: 0.7) ?? Data()
        let r4 = await api.rawUpload(token: t, bucket: Self.bucket, path: "\(c)/\(studentId)/selftest-\(me.role.dbValue).jpg", data: jpg)
        let (r5, d5) = await api.rawCall("POST", "/rest/v1/students", token: t,
                                         body: [["id": newId(), "center_id": c, "full_name": "TEST raw-\(me.role.dbValue)", "circle_id": opt(circleId)]],
                                         headers: ["Prefer": "return=minimal"])
        _ = d5
        return "recitation=\(r1) attendance=\(r2) student_edit=\(r3)/rows=\(n3) photo_upload=\(r4) student_insert=\(r5)"
    }
    #endif
}

/// Normal iPhone notifications for new centre notifications (absence, new hifz, rewards, announcements).
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(_ list: [AppNotification]) {
        for n in list.prefix(5) {
            let c = UNMutableNotificationContent()
            c.title = n.title
            c.body = n.body
            c.sound = .default
            let req = UNNotificationRequest(identifier: n.id, content: c, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
    }
}
