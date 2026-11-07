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
    var snapshot: CenterSnapshot { st.cache }
    var syncState: SyncState { st.outbox.isEmpty ? .synced : .pending(st.outbox.count) }

    init(config: CloudConfig) {
        api = SupabaseAPI(config: config)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("cloud_state.json")
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

    private func emailFor(_ phone: String) -> String { Phone.normalise(phone) + "@alsiddiq.app" }

    private func token() async throws -> String {
        guard let s = st.session else { throw AppError.permissionDenied("سجّل الدخول أولاً") }
        if s.expiresAt.timeIntervalSinceNow > 60 { return s.accessToken }
        do {
            let fresh = try await api.refresh(s.refreshToken)
            st.session = fresh; save()
            return fresh.accessToken
        } catch let e as APIError {
            if (400...499).contains(e.code) { st = CloudState(); save(); publish() }
            throw e
        }
    }

    // MARK: First-time setup
    func needsSetup() async -> Bool? {
        guard let r = try? await api.function(token: nil, name: "admin-members", body: ["action": "status"]) else { return nil }
        return (r["needs_setup"] as? NSNumber)?.boolValue
    }

    func bootstrap(centerName: String, fullName: String, phone: String, password: String) async throws -> Member {
        do {
            _ = try await api.function(token: nil, name: "admin-members", body: [
                "action": "bootstrap", "center_name": centerName, "full_name": fullName,
                "phone": Phone.normalise(phone), "password": password
            ])
        } catch is OfflineError { throw AppError.network("لا يوجد اتصال بالإنترنت") }
        return try await signIn(login: phone, password: password)
    }

    // MARK: Auth
    func signIn(login: String, password: String) async throws -> Member {
        if Phone.normalise(login).count < 8 { throw AppError.validation("رقم الجوال غير صحيح") }
        let s: Session
        do { s = try await api.signIn(email: emailFor(login), password: password) }
        catch is OfflineError { throw AppError.network("لا يوجد اتصال بالإنترنت") }
        let rows = try await api.selectAll(token: s.accessToken, table: "profiles", query: "select=*&id=eq.\(s.userId)")
        guard let prof = rows.first, let me = Rows.member(prof, [:]) else { throw AppError.validation("الحساب غير مكتمل، راجع إدارة المركز") }
        if !me.active { throw AppError.validation("هذا الحساب موقوف، راجع إدارة المركز") }
        st = CloudState(session: s, me: me, centerId: prof["center_id"] as? String)
        save()
        try? await reload()
        // Don't raise phone notifications for what was already waiting before this sign-in.
        st.seenNotificationIds = st.cache.notifications.map { $0.id }
        save(); publish()
        Notifier.requestPermission()
        return st.me ?? me
    }

    func signOut() async {
        let t = st.session?.accessToken
        st = CloudState(); save(); publish()
        if let t = t { Task { await api.signOut(token: t) } }
    }

    func changePassword(old: String, new: String) async throws {
        guard let me = st.me else { throw AppError.permissionDenied() }
        if new.count < 6 { throw AppError.validation("كلمة المرور 6 أحرف على الأقل") }
        do { _ = try await api.signIn(email: emailFor(me.phone), password: old) }
        catch is APIError { throw AppError.validation("كلمة المرور الحالية غير صحيحة") }
        try await api.updatePassword(token: try await token(), password: new)
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
        async let links = api.selectAll(token: t, table: "parent_students")
        async let circles = api.selectAll(token: t, table: "circles", query: "select=*&order=name")
        async let students = api.selectAll(token: t, table: "students", query: "select=*&order=full_name")
        async let recs = api.selectAll(token: t, table: "recitations", query: "select=*&order=recorded_at.desc")
        async let att = api.selectAll(token: t, table: "attendance", query: "select=*&order=day.desc")
        async let rewards = api.selectAll(token: t, table: "rewards", query: "select=*&order=created_at.desc")
        async let ann = api.selectAll(token: t, table: "announcements", query: "select=*&order=created_at.desc")
        async let notes = api.selectAll(token: t, table: "notifications", query: "select=*&user_id=eq.\(me.id)&order=created_at.desc")

        var children: [String: [String]] = [:]
        for l in try await links {
            if let p = l["parent_id"] as? String, let s = l["student_id"] as? String { children[p, default: []].append(s) }
        }
        let members = (try await profiles).compactMap { Rows.member($0, children) }
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
        do { return try await api.function(token: try await token(), name: "admin-members", body: body) }
        catch is OfflineError { throw AppError.network("إدارة الحسابات تحتاج اتصالاً بالإنترنت") }
    }

    func createMember(_ m: NewMember) async throws -> Member {
        try require(Permissions.canManageMembers(try me()))
        if m.fullName.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب الاسم") }
        if Phone.normalise(m.phone).count < 8 { throw AppError.validation("رقم الجوال غير صحيح") }
        if m.password.count < 6 { throw AppError.validation("كلمة المرور 6 أحرف على الأقل") }
        let res = try await adminFunction([
            "action": "create", "full_name": m.fullName.trimmingCharacters(in: .whitespaces), "phone": Phone.normalise(m.phone),
            "role": m.role.dbValue, "password": m.password, "student_id": opt(m.studentId), "child_ids": m.childIds
        ])
        guard let prof = res["profile"] as? JSON, let pid = prof["id"] as? String, let member = Rows.member(prof, [pid: m.childIds]) else {
            throw AppError.validation("تعذّر إنشاء الحساب")
        }
        st.cache.members.append(member); save(); publish()
        Task { try? await self.syncNow() }
        return member
    }

    func updateMember(_ m: Member) async throws {
        try require(Permissions.canManageMembers(try me()))
        _ = try await adminFunction([
            "action": "update", "id": m.id, "full_name": m.fullName, "phone": Phone.normalise(m.phone), "active": m.active,
            "student_id": opt(m.studentId), "child_ids": m.childIds
        ])
        st.cache.members = st.cache.members.map { $0.id == m.id ? m : $0 }
        if st.me?.id == m.id { st.me = m }
        save(); publish()
        Task { try? await self.syncNow() }
    }

    func resetMemberPassword(memberId: String, newPassword: String) async throws {
        try require(Permissions.canManageMembers(try me()))
        if newPassword.count < 6 { throw AppError.validation("كلمة المرور 6 أحرف على الأقل") }
        _ = try await adminFunction(["action": "reset_password", "id": memberId, "password": newPassword])
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
        try require(Permissions.canManageStudents(try me()))
        if s.fullName.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب اسم الطالب") }
        var saved = s
        if saved.id.isEmpty { saved.id = newId() }
        let row = json(Rows.studentRow(saved, try center()))
        return try await write(PendingOp(type: "upsert", table: "students", body: row), saved) { d in
            if let i = d.students.firstIndex(where: { $0.id == saved.id }) { d.students[i] = saved } else { d.students.append(saved) }
        }
    }

    func deleteStudent(_ id: String) async throws {
        try require(Permissions.canManageStudents(try me()))
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
        try require(u.role == .admin || Permissions.teachesCircle(u, circle))
        let c = try center()
        let now = Rows.iso(Date())
        let rows: [JSON] = marks.map { sid, s in
            ["center_id": c, "student_id": sid, "circle_id": circleId, "day": day, "status": s.rawValue.lowercased(), "recorded_by": u.id, "recorded_at": now]
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
