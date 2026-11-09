import Foundation
import Network
import UIKit
import UserNotifications

/// The login ended on the server (expired / password changed); queued writes were parked, not dropped.
struct SessionEndedError: LocalizedError { var errorDescription: String? { "انتهت الجلسة، اكتب كلمة السر مرة أخرى" } }

/// One write waiting to reach the server (kept on disk, so it survives app restarts and no network).
struct PendingOp: Codable, Equatable {
    var id: String = UUID().uuidString.lowercased()
    var type: String            // upsert | patch | delete
    var table: String
    var body: String = ""
    var filter: String = ""
    var onConflict: String = "id"
    var ignoreDuplicates: Bool = false
    /// v3.2: which section queued it (admin | teachers) and when; optional so older saved queues still load.
    var kind: String? = nil
    var at: Date? = nil
    /// The server's words when it refused this write (kept, never silently dropped).
    var refused: String? = nil
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
    /// v3.2: queued writes whose login ended (expired / password changed / section left offline). Never dropped:
    /// they go up after that section's password is typed again.
    var parked: [PendingOp]? = nil
    /// Writes the server refused while they were being sent later (kept for the record; shown on the sync line).
    var refusedOps: [PendingOp]? = nil
    var lastSyncAt: Date?
    var seenNotificationIds: [String] = []
    /// v3.6: admin events already announced by a local notification (nil = none seen yet on this phone).
    var seenEventIds: [String]? = nil
    /// v3.4: the last fetched «عن المركز» (offline copy).
    var about: AboutInfo? = nil
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
    private let pathMonitor = NWPathMonitor()
    var snapshot: CenterSnapshot { st.cache }
    var syncState: SyncState {
        if !st.outbox.isEmpty { return .pending(st.outbox.count) }
        if let p = st.parked, !p.isEmpty {
            return .waitingPassword(p.count, p.contains { $0.kind == "admin" } ? .admin : .teacher)
        }
        if let r = st.refusedOps, !r.isEmpty { return .error("\(r.count) لم يقبلها الخادم") }
        return .synced
    }

    func isPending(_ id: String) -> Bool {
        (st.outbox + (st.parked ?? [])).contains { $0.body.contains("\"\(id)\"") || $0.filter.contains(id) }
    }

    /// Replace the login state but keep what must survive it: parked and refused writes.
    private func replace(_ new: CloudState) {
        let parked = st.parked, refused = st.refusedOps
        st = new
        st.parked = parked
        st.refusedOps = refused
    }

    /// The current login is ending: its queued writes wait for the same section's password (never dropped).
    private func parkOutbox() {
        guard !st.outbox.isEmpty else { return }
        let who = st.me?.role.dbValue
        let ops = st.outbox.map { op -> PendingOp in var o = op; if o.kind == nil { o.kind = who }; return o }
        st.parked = (st.parked ?? []) + ops
        st.outbox = []
    }

    /// A login opened: writes parked for this section (or any, for the admin) go back in the queue and are sent.
    private func unparkFor(_ me: Member) {
        guard let p = st.parked, !p.isEmpty, me.role != .viewer else { return }
        let mine = p.filter { me.role == .admin || $0.kind == me.role.dbValue || $0.kind == nil }
        guard !mine.isEmpty else { return }
        st.outbox = mine + st.outbox
        let ids = Set(mine.map { $0.id })
        st.parked = p.filter { !ids.contains($0.id) }
        save()
    }

    init(config: CloudConfig, stateFile: String = "cloud_state_v3.json") {
        api = SupabaseAPI(config: config)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(stateFile)
        if let data = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(CloudState.self, from: data) {
            st = s
        } else {
            st = CloudState()
        }
        // v3.2: the moment the network comes back, send what is queued.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                if let self = self, self.st.session != nil, !self.st.outbox.isEmpty { try? await self.syncNow() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "alsiddiq.net"))
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
                // v3.2: anything still queued waits for this section's password again (never dropped).
                parkOutbox()
                if let b = st.baseSession, b != s {
                    st.session = b; st.me = st.baseMe; st.baseSession = nil; st.baseMe = nil
                } else {
                    replace(CloudState(centerName: st.centerName, cache: st.cache))
                }
                save(); publish()
                throw SessionEndedError()
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
        let keptCache = st.cache
        parkOutbox()   // a different login now: what the previous one queued waits for its own password
        replace(CloudState(session: s, me: me, baseSession: base, baseMe: baseMe, centerName: name, centerId: nil, cache: keptCache))
        save()
        if let rows = try? await api.selectAll(token: s.accessToken, table: "centers", query: "select=id"), let c = rows.first?["id"] as? String {
            st.centerId = c; save()
        }
        unparkFor(me)
        try? await flushOutbox()
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
        // v3.2: send what is queued first; offline, it waits (parked) for this section's password.
        if !st.outbox.isEmpty { try? await flushOutbox() }
        parkOutbox()
        let t = st.session?.accessToken
        if let b = st.baseSession {
            st.session = b; st.me = st.baseMe; st.baseSession = nil; st.baseMe = nil
        } else {
            replace(CloudState(centerName: st.centerName, cache: st.cache))
        }
        save(); publish()
        if let t = t { Task { await api.signOut(token: t) } }
        if st.session != nil { Task { try? await self.syncNow() } }
    }

    func signOut() async {
        let ts = [st.session?.accessToken, st.baseSession?.accessToken].compactMap { $0 }
        if !st.outbox.isEmpty { try? await flushOutbox() }
        parkOutbox()
        replace(CloudState(centerName: st.centerName, cache: st.cache)); save(); publish()
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
        async let honors = api.selectAll(token: t, table: "honor_cards", query: "select=*&order=created_at.desc")
        let isAdmin = me.role == .admin
        async let events = adminEventRows(t, isAdmin)
        async let tmarks = adminRows(t, isAdmin, "teacher_attendance", "select=*&order=day.desc")
        async let budgetRows = adminRows(t, isAdmin, "budget_entries", "select=*&order=day.desc")
        // v3.8: RLS gives the admin every student's months and a teacher his own circle's; the general view never asks
        async let subRows = adminRows(t, me.role != .viewer, "student_subscriptions", "select=*&order=month.desc")
        async let ctRows = api.selectAll(token: t, table: "circle_teachers", query: "select=circle_id,teacher_profile_id&order=created_at")

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
        let allStudents = (try await students).compactMap { Rows.student($0) }
        fresh.students = allStudents.filter { $0.active }
        fresh.dismissed = allStudents.filter { !$0.active }
        fresh.recitations = (try await recs).compactMap { Rows.recitation($0) }
        fresh.attendance = (try await att).compactMap { Rows.attendance($0) }
        fresh.rewards = (try await rewards).compactMap { Rows.reward($0) }
        fresh.announcements = (try await ann).compactMap { Rows.announcement($0) }
        fresh.notifications = (try await notes).compactMap { Rows.notification($0) }
        fresh.teacherNames = ((try? await names) ?? []).compactMap { Rows.teacherName($0) }
        fresh.honorCards = ((try? await honors) ?? []).compactMap { Rows.honorCard($0) }
        let eventRows = (try? await events) ?? []
        fresh.adminEvents = isAdmin ? eventRows.compactMap { Rows.adminEvent($0) } : nil
        // v3.8: admin only (a server without the tables yet gives empty lists)
        fresh.teacherMarks = isAdmin ? ((try? await tmarks) ?? []).compactMap { Rows.teacherMark($0) } : nil
        fresh.budget = isAdmin ? ((try? await budgetRows) ?? []).compactMap { Rows.budgetEntry($0) } : nil
        fresh.subscriptions = me.role != .viewer ? ((try? await subRows) ?? []).compactMap { Rows.subscription($0) } : nil
        // v3.8: a server without circle_teachers = one teacher per circle, as before
        fresh.circleTeachers = ((try? await ctRows) ?? []).compactMap { o -> CircleTeacher? in
            guard let c = o["circle_id"] as? String, let t = o["teacher_profile_id"] as? String else { return nil }
            return CircleTeacher(circleId: c, teacherId: t)
        }

        // Writes still waiting stay visible on screen until the server has them.
        let merged = st.outbox.isEmpty ? fresh : overlayPending(fresh)
        let newOnes = merged.notifications.filter { !$0.read && !st.seenNotificationIds.contains($0.id) }
        let seenEvents = Set(st.seenEventIds ?? [])
        let newEvents = (merged.adminEvents ?? []).filter { $0.readAt == nil && !seenEvents.contains($0.id) }
        st.cache = merged
        st.me = members.first { $0.id == me.id } ?? me
        st.lastSyncAt = Date()
        if !newOnes.isEmpty {
            st.seenNotificationIds = Array((newOnes.map { $0.id } + st.seenNotificationIds).prefix(500))
            if UIApplication.shared.applicationState != .active { Notifier.post(newOnes) }
        }
        if !newEvents.isEmpty {
            // the first sync after sign-in only remembers what was already waiting (no burst of old events)
            if st.seenEventIds != nil { Notifier.postEvents(newEvents) }
            st.seenEventIds = Array((newEvents.map { $0.id } + (st.seenEventIds ?? [])).prefix(500))
        } else if st.seenEventIds == nil && isAdmin {
            st.seenEventIds = []
        }
        save(); publish()
    }

    /// v3.6: the admin's bell rows (only the admin may read them; nobody else asks).
    private func adminEventRows(_ t: String, _ isAdmin: Bool) async throws -> [JSON] {
        guard isAdmin else { return [] }
        return try await api.selectAll(token: t, table: "admin_events", query: "select=*&order=created_at.desc")
    }

    /// v3.8: rows only the admin may read (nobody else asks).
    private func adminRows(_ t: String, _ isAdmin: Bool, _ table: String, _ query: String) async throws -> [JSON] {
        guard isAdmin else { return [] }
        return try await api.selectAll(token: t, table: table, query: query)
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
        // v3.6: a dismissal still on the phone keeps the student out of the lists; queued read marks stay read
        let dismissing = Set(st.outbox.filter { $0.table == "students" && $0.type == "patch" && $0.body.contains("\"active\":false") }
            .compactMap { $0.filter.components(separatedBy: "&").first?.replacingOccurrences(of: "id=eq.", with: "") })
        if !dismissing.isEmpty {
            let moved = out.students.filter { dismissing.contains($0.id) }.map { s -> Student in var x = s; x.activeFlag = false; return x }
            out.students.removeAll { dismissing.contains($0.id) }
            out.dismissed = (out.dismissed ?? []) + moved
        }
        if st.outbox.contains(where: { $0.table == "admin_events" }) {
            let oldRead = Set((old.adminEvents ?? []).filter { $0.readAt != nil }.map { $0.id })
            out.adminEvents = out.adminEvents?.map { var e = $0; if e.readAt == nil && oldRead.contains(e.id) { e.readAt = Date() }; return e }
        }
        // v3.8: while a teacher-attendance or budget write waits, the phone's own list stays on screen
        if st.outbox.contains(where: { $0.table == "teacher_attendance" }), out.teacherMarks != nil { out.teacherMarks = old.teacherMarks ?? out.teacherMarks }
        if st.outbox.contains(where: { $0.table == "budget_entries" }), out.budget != nil { out.budget = old.budget ?? out.budget }
        if st.outbox.contains(where: { $0.table == "student_subscriptions" }), out.subscriptions != nil { out.subscriptions = old.subscriptions ?? out.subscriptions }
        if st.outbox.contains(where: { $0.table == "circle_teachers" }) { out.circleTeachers = old.circleTeachers ?? out.circleTeachers }
        if st.outbox.contains(where: { $0.table == "honor_cards" }) {
            let have = Set((out.honorCards ?? []).map { $0.id })
            out.honorCards = (old.honorCards ?? []).filter { !have.contains($0.id) } + (out.honorCards ?? [])
        }
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

    /// Send the queue in order. Offline / server down / session problem: stop and keep everything.
    /// A write the server refuses on its rules or data is moved to refusedOps (kept, shown), so the queue never jams.
    private func flushOutbox() async throws {
        while let op = st.outbox.first {
            do { try await send(op) }
            catch let e as APIError {
                if e.code >= 500 || e.code == 401 || e.code == 0 { throw e }
                var r = op; r.refused = e.message
                st.refusedOps = Array(((st.refusedOps ?? []) + [r]).suffix(200))
            }
            dropOp(op.id)
        }
    }

    /// Send everything queued up to and including `targetId`; the target's own refusal reaches the caller.
    private func flushStrict(_ targetId: String) async throws {
        while let op = st.outbox.first {
            if op.id == targetId { try await send(op); dropOp(op.id); return }
            do { try await send(op) } catch let e as APIError {
                if e.code >= 500 || e.code == 401 || e.code == 0 { throw e }
                var r = op; r.refused = e.message
                st.refusedOps = Array(((st.refusedOps ?? []) + [r]).suffix(200))
            }
            dropOp(op.id)
        }
    }

    /// Apply a change on screen, queue it, and try to send it now.
    /// Online and refused by the server -> the change is undone and the reason returned.
    /// Offline -> kept in the queue and sent automatically later.
    private func write<T>(_ op: PendingOp, _ value: T, _ local: (inout CenterSnapshot) -> Void) async throws -> T {
        local(&st.cache)
        var op = op; op.kind = st.me?.role.dbValue; op.at = Date()
        st.outbox.append(op)
        save(); publish()
        do {
            try await flushStrict(op.id)
            Task { try? await self.syncNow() }
            return value
        } catch is OfflineError {
            return value
        } catch let e as APIError where e.code >= 500 || e.code == 401 || e.code == 0 {
            return value   // server busy / session to renew: kept in the queue, sent later
        } catch is SessionEndedError {
            return value   // the login ended: the write is parked until the password is typed again
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

    // MARK: Teachers (v3.3: each teacher is his own account; the admin makes it through the «access» function)
    func saveTeacher(id: String?, name: String, circleId: String?, password: String?) async throws -> Member {
        try require(Permissions.canManagePasswords(try me()))
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { throw AppError.validation("اكتب اسم المعلم") }
        let pw = password.map { Passwords.normalise($0) } ?? ""
        if id == nil && pw.isEmpty { throw AppError.validation("اختر كلمة سر للمعلم") }
        if !pw.isEmpty, let bad = Passwords.check(pw) { throw AppError.validation(bad) }
        var body: JSON = ["action": "teacher_save", "name": n, "circle_id": opt(circleId)]
        if let id = id { body["id"] = id }
        if !pw.isEmpty { body["password"] = pw }
        let o = try await adminFunction(body)
        try? await syncNow()
        if let p = o["profile"] as? JSON, let m = memberFrom(p) { return m }
        return Member(id: id ?? "", fullName: n, role: .teacher)
    }

    func removeTeacher(_ id: String) async throws {
        try require(Permissions.canManagePasswords(try me()))
        _ = try await adminFunction(["action": "teacher_remove", "id": id])
        try? await syncNow()
    }

    // MARK: v3.4 «عن المركز» (public read; admin writes). Tables centre_about / centre_about_buttons, bucket center-about.
    static let aboutBucket = "center-about"
    var aboutCenter: AboutInfo { st.about ?? .fallback }

    private func readToken() async -> String { (try? await token()) ?? api.publicKey }

    func refreshAbout() async {
        let t = await readToken()
        do {
            let rows = try await api.selectAll(token: t, table: "centre_about", query: "select=*&limit=1")
            let btnRows = (try? await api.selectAll(token: t, table: "centre_about_buttons", query: "select=*&order=sort")) ?? []
            var a = AboutInfo.fallback
            a.contactButton = st.about?.contactButton   // kept when the switch row cannot be read
            a.contactPhone = st.about?.contactPhone
            // v3.9: «تواصل مع المركز» switch and its number (public read; a server without the row keeps the last value)
            if let sw = try? await api.selectAll(token: t, table: "centre_settings", query: "select=contact_button,contact_phone"), let r0 = sw.first {
                a.contactButton = (r0["contact_button"] as? NSNumber)?.boolValue ?? false
                a.contactPhone = (r0["contact_phone"] as? String) ?? ""
            }
            if let r = rows.first {
                if let b = r["body"] as? String, !b.isEmpty { a.body = b }
                a.fromServer = true
                let cid = (r["center_id"] as? String) ?? st.centerId ?? ""
                _ = cid
                a.photos = (r["photos"] as? [Any])?.compactMap { $0 as? String } ?? []
                a.updatedAt = r["updated_at"] == nil ? nil : Rows.ts(r["updated_at"])
            }
            a.buttons = btnRows.compactMap { o in
                guard let id = o["id"] as? String else { return nil }
                return AboutButton(id: id, label: o["label"] as? String ?? "", kind: o["kind"] as? String ?? "link",
                                   value: o["value"] as? String ?? "", sort: (o["sort"] as? NSNumber)?.intValue ?? 0)
            }
            st.about = a; save()
        } catch {
            // offline or not on the server yet: keep the cached copy (or the bundled one)
        }
    }

    private var aboutDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("center-about", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func aboutPhoto(_ path: String) async -> UIImage? {
        let f = aboutDir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
        if let d = try? Data(contentsOf: f), let i = UIImage(data: d) { return i }
        guard let d = try? await api.publicDownload(bucket: Self.aboutBucket, path: path), let i = UIImage(data: d) else { return nil }
        try? d.write(to: f, options: .atomic)
        return i
    }

    private func adminWrite<T>(_ block: (String, String) async throws -> T) async throws -> T {
        try require(Permissions.canManageCenter(try me()))
        do { return try await block(try await token(), try center()) }
        catch is OfflineError { throw AppError.network("هذه العملية تحتاج اتصالاً بالإنترنت") }
    }

    func saveAboutText(_ text: String) async throws {
        try await adminWrite { t, c in
            try await api.upsert(token: t, table: "centre_about", rows: [["center_id": c, "body": text, "updated_at": Rows.iso(Date())]], onConflict: "center_id", ignore: false)
        }
        await refreshAbout()
    }

    func addAboutPhoto(_ jpeg: Data) async throws {
        await refreshAbout()
        let current = st.about ?? .fallback
        try await adminWrite { t, c in
            var list = current.fromServer ? current.photos : []
            // the first photo the admin adds keeps his bundled photo as the first one (uploaded once), so it is not lost
            if list.isEmpty, let b = AboutInfo.bundledPhoto, let bd = PhotoTools.jpeg(b, maxSide: 1280) {
                let bp = "\(c)/\(UUID().uuidString.lowercased().prefix(8)).jpg"
                try await api.storageUpload(token: t, bucket: Self.aboutBucket, path: bp, data: bd)
                try? bd.write(to: aboutDir.appendingPathComponent(bp.replacingOccurrences(of: "/", with: "_")))
                list.append(bp)
            }
            let p = "\(c)/\(UUID().uuidString.lowercased().prefix(8)).jpg"
            try await api.storageUpload(token: t, bucket: Self.aboutBucket, path: p, data: jpeg)
            try? jpeg.write(to: aboutDir.appendingPathComponent(p.replacingOccurrences(of: "/", with: "_")))
            list.append(p)
            try await api.upsert(token: t, table: "centre_about",
                                 rows: [["center_id": c, "body": current.body, "photos": list, "updated_at": Rows.iso(Date())]],
                                 onConflict: "center_id", ignore: false)
        }
        await refreshAbout()
    }

    func removeAboutPhoto(_ path: String) async throws {
        try await adminWrite { t, c in
            let list = (st.about?.photos ?? []).filter { $0 != path }
            try await api.upsert(token: t, table: "centre_about",
                                 rows: [["center_id": c, "body": aboutCenter.body, "photos": list, "updated_at": Rows.iso(Date())]],
                                 onConflict: "center_id", ignore: false)
            try? await api.storageDelete(token: t, bucket: Self.aboutBucket, path: path)
        }
        await refreshAbout()
    }

    func saveAboutButton(_ b: AboutButton) async throws {
        try await adminWrite { t, c in
            let id = b.id.isEmpty ? UUID().uuidString.lowercased() : b.id
            try await api.upsert(token: t, table: "centre_about_buttons",
                                 rows: [["id": id, "center_id": c, "label": b.label, "kind": b.kind, "value": b.value, "sort": b.sort]],
                                 onConflict: "id", ignore: false)
        }
        await refreshAbout()
    }

    func deleteAboutButton(_ id: String) async throws {
        try await adminWrite { t, _ in try await api.delete(token: t, table: "centre_about_buttons", filter: "id=eq.\(id)") }
        await refreshAbout()
    }

    func moveAboutButton(_ id: String, up: Bool) async throws {
        var list = aboutCenter.buttons.sorted { $0.sort < $1.sort }
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i - 1 : i + 1
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        try await adminWrite { t, c in
            for (k, b) in list.enumerated() {
                try await api.patch(token: t, table: "centre_about_buttons", filter: "id=eq.\(b.id)", body: ["sort": k + 1])
            }
            _ = c
        }
        await refreshAbout()
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

    func dismissStudent(_ id: String) async throws {
        let u = try me()
        guard let s = st.cache.student(id) else { return }
        try require(Permissions.canDismissStudent(u, s, st.cache))
        let now = Date()
        let body = json(["active": false, "dismissed_at": Rows.iso(now), "dismissed_by": u.id, "updated_at": Rows.iso(now)])
        _ = try await write(PendingOp(type: "patch", table: "students", body: body, filter: "id=eq.\(id)&active=eq.true"), ()) { d in
            if let i = d.students.firstIndex(where: { $0.id == id }) {
                var x = d.students.remove(at: i)
                x.activeFlag = false; x.dismissedAt = now; x.dismissedBy = u.id
                d.dismissed = (d.dismissed ?? []) + [x]
            }
        }
    }

    func markEventRead(_ id: String) async throws {
        try require(try me().role == .admin)
        let body = json(["read_at": Rows.iso(Date())])
        _ = try await write(PendingOp(type: "patch", table: "admin_events", body: body, filter: "id=eq.\(id)&read_at=is.null"), ()) { d in
            if let i = d.adminEvents?.firstIndex(where: { $0.id == id }) { d.adminEvents?[i].readAt = Date() }
        }
    }

    func markAllEventsRead() async throws {
        try require(try me().role == .admin)
        let body = json(["read_at": Rows.iso(Date())])
        _ = try await write(PendingOp(type: "patch", table: "admin_events", body: body, filter: "read_at=is.null"), ()) { d in
            let now = Date()
            d.adminEvents = d.adminEvents?.map { var e = $0; if e.readAt == nil { e.readAt = now }; return e }
        }
    }

    func publishHonors(_ students: [HonorStudent], message: String?) async throws {
        let u = try me()
        try require(u.role == .admin)
        if students.isEmpty { throw AppError.validation("اختر طالباً واحداً على الأقل") }
        let m = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = HonorCard(id: newId(), students: students, message: (m?.isEmpty ?? true) ? nil : m, publishedBy: u.id, createdAt: Date())
        let row = json(Rows.honorCardRow(card, try center()))
        _ = try await write(PendingOp(type: "upsert", table: "honor_cards", body: row, ignoreDuplicates: true), ()) { d in
            d.honorCards = [card] + (d.honorCards ?? [])
        }
    }

    // MARK: v3.8 admin: teacher attendance, budget
    func saveTeacherAttendance(day: String, marks: [TeacherMark]) async throws -> Int {
        let u = try me()
        try require(u.role == .admin)
        if marks.isEmpty { throw AppError.validation("اختر حاضر أو غائب أو مستأذن لمعلم واحد على الأقل") }
        let c = try center()
        // v3.9: check_in / check_out "HH:mm" (null when absent or not set); غائب sends no times
        let rows: [JSON] = marks.map { m -> JSON in
            let keep = m.status != .absent
            let row: JSON = ["center_id": c, "teacher_profile_id": m.teacherId, "day": day, "status": m.status.rawValue, "marked_by": u.id,
                             "check_in": opt(keep ? m.checkIn : nil), "check_out": opt(keep ? m.checkOut : nil)]
            return row
        }
        let local = marks.map { m -> TeacherMark in
            let keep = m.status != .absent
            return TeacherMark(id: newId(), teacherId: m.teacherId, day: day, status: m.status, markedBy: u.id,
                               checkIn: keep ? m.checkIn : nil, checkOut: keep ? m.checkOut : nil)
        }
        let ids = Set(marks.map { $0.teacherId })
        return try await write(PendingOp(type: "upsert", table: "teacher_attendance", body: json(rows), onConflict: "teacher_profile_id,day"), marks.count) { snap in
            var list = snap.teacherMarks ?? []
            list.removeAll { $0.day == day && ids.contains($0.teacherId) }
            snap.teacherMarks = local + list
        }
    }

    /// v3.9 (admin): the «تواصل مع المركز» switch, in the same row as «عن المركز» (anon-readable).
    func saveContactButton(_ on: Bool, phone: String) async throws {
        let num = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        try await adminWrite { t, c in
            let row: JSON = ["center_id": c, "contact_button": on, "contact_phone": num, "updated_at": Rows.iso(Date())]
            try await api.upsert(token: t, table: "centre_settings", rows: [row], onConflict: "center_id", ignore: false)
        }
        var a = aboutCenter
        a.contactButton = on
        a.contactPhone = num
        st.about = a
        save()
    }

    func saveBudgetEntry(_ e: BudgetEntry) async throws -> BudgetEntry {
        let u = try me()
        try require(u.role == .admin)
        if e.amount <= 0 { throw AppError.validation("اكتب المبلغ") }
        let note = e.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.kind == .expense && (note ?? "").isEmpty { throw AppError.validation("اكتب ملاحظة لعملية الصرف") }
        var saved = e
        saved.note = (note ?? "").isEmpty ? nil : note
        if saved.kind == .expense { saved.studentId = nil }
        let fields: JSON = ["kind": saved.kind.rawValue, "amount": saved.amount, "day": saved.day,
                            "student_id": opt(saved.studentId), "note": opt(saved.note)]
        if saved.id.isEmpty {
            saved.id = newId(); saved.createdBy = u.id; saved.createdAt = Date()
            var row = fields; row["id"] = saved.id; row["center_id"] = try center(); row["created_by"] = u.id
            return try await write(PendingOp(type: "upsert", table: "budget_entries", body: json(row), ignoreDuplicates: true), saved) { d in
                d.budget = [saved] + (d.budget ?? [])
            }
        }
        return try await write(PendingOp(type: "patch", table: "budget_entries", body: json(fields), filter: "id=eq.\(saved.id)"), saved) { d in
            if let i = d.budget?.firstIndex(where: { $0.id == saved.id }) { d.budget?[i] = saved }
        }
    }

    func deleteBudgetEntry(_ id: String) async throws {
        try require(try me().role == .admin)
        _ = try await write(PendingOp(type: "delete", table: "budget_entries", filter: "id=eq.\(id)"), ()) { d in
            d.budget?.removeAll { $0.id == id }
        }
    }

    func saveSubscriptions(month: String, marks: [String: SubscriptionMark]) async throws -> Int {
        let u = try me()
        let d = st.cache
        if marks.isEmpty { return 0 }
        for sid in marks.keys {
            guard let s = d.student(sid) else { throw AppError.validation("الطالب غير موجود") }
            try require(Permissions.canEditStudent(u, s, d))
        }
        let c = try center()
        let now = Rows.iso(Date())
        let rows: [JSON] = marks.map { sid, m in
            ["center_id": c, "student_id": sid, "month": month, "paid": m.paid, "amount": opt(m.paid ? m.amount : nil),
             "marked_by": u.id, "updated_at": now]
        }
        let local = marks.map { StudentSubscription(id: newId(), studentId: $0.key, month: month, paid: $0.value.paid, amount: $0.value.paid ? $0.value.amount : nil) }
        return try await write(PendingOp(type: "upsert", table: "student_subscriptions", body: json(rows), onConflict: "student_id,month"), marks.count) { snap in
            var list = snap.subscriptions ?? []
            list.removeAll { $0.month == month && marks.keys.contains($0.studentId) }
            snap.subscriptions = local + list
        }
    }

    func setCirclePhoto(circleId: String, jpeg: Data?) async throws {
        let u = try me()
        guard let circle = st.cache.circle(circleId) else { throw AppError.validation("الحلقة غير موجودة") }
        try require(Permissions.canTakeAttendance(u, circle.id, st.cache))
        let t: String
        do { t = try await token() } catch is OfflineError { throw AppError.network("الصورة تحتاج اتصالاً بالإنترنت") }
        let old = circle.photoPath
        var newPath: String? = nil
        do {
            if let data = jpeg {
                let path = "\(try center())/circles/\(circleId)/\(newId()).jpg"
                try await api.storageUpload(token: t, bucket: Self.bucket, path: path, data: data)
                newPath = path
                if let img = UIImage(data: data) { photoCache[path] = img; savePhotoFile(path, data) }
            }
            // teachers have no UPDATE on circles: one code path through the RPC for everyone
            try await api.rpc(token: t, name: "set_circle_photo", body: ["cid": circleId, "path": opt(newPath)])
        } catch is OfflineError { throw AppError.network("الصورة تحتاج اتصالاً بالإنترنت") }
        if let i = st.cache.circles.firstIndex(where: { $0.id == circleId }) { st.cache.circles[i].photoPath = newPath }
        save(); publish()
        if let old = old, old != newPath { Task { try? await api.storageDelete(token: t, bucket: Self.bucket, path: old) } }
    }

    func setCircleTeachers(circleId: String, teacherIds: [String]) async throws {
        try require(Permissions.canManageCircles(try me()))
        var kept: [String] = []
        for t in teacherIds where !kept.contains(t) { kept.append(t) }
        let delFilter = kept.isEmpty ? "circle_id=eq.\(circleId)" : "circle_id=eq.\(circleId)&teacher_profile_id=not.in.(\(kept.joined(separator: ",")))"
        _ = try await write(PendingOp(type: "delete", table: "circle_teachers", filter: delFilter), ()) { d in
            d.circleTeachers = (d.circleTeachers ?? []).filter { $0.circleId != circleId || kept.contains($0.teacherId) }
        }
        guard !kept.isEmpty else { return }
        let rows: [JSON] = kept.map { ["circle_id": circleId, "teacher_profile_id": $0] }
        _ = try await write(PendingOp(type: "upsert", table: "circle_teachers", body: json(rows), onConflict: "circle_id,teacher_profile_id", ignoreDuplicates: true), ()) { d in
            var list = (d.circleTeachers ?? []).filter { $0.circleId != circleId }
            list += kept.map { CircleTeacher(circleId: circleId, teacherId: $0) }
            d.circleTeachers = list
        }
    }

    func uploadAnnouncementImage(announcementId: String, jpeg: Data) async throws -> String {
        try require(try me().role == .admin)
        let t: String
        do { t = try await token() } catch is OfflineError { throw AppError.network("الصورة تحتاج اتصالاً بالإنترنت") }
        let rnd = String(newId().replacingOccurrences(of: "-", with: "").prefix(8))
        let path = "\(try center())/announcements/\(announcementId)/\(rnd).jpg"
        do { try await api.storageUpload(token: t, bucket: Self.bucket, path: path, data: jpeg) }
        catch is OfflineError { throw AppError.network("الصورة تحتاج اتصالاً بالإنترنت") }
        if let img = UIImage(data: jpeg) { photoCache[path] = img; savePhotoFile(path, jpeg) }
        return path
    }

    func announcementImage(_ path: String) async -> UIImage? {
        if let img = photoCache[path] { return img }
        if let d = try? Data(contentsOf: photoFile(path)), let img = UIImage(data: d) { photoCache[path] = img; return img }
        guard let t = try? await token(), let d = try? await api.storageDownload(token: t, bucket: Self.bucket, path: path),
              let img = UIImage(data: d) else { return nil }
        photoCache[path] = img
        savePhotoFile(path, d)
        return img
    }

    func circlePhoto(_ c: StudyCircle) async -> UIImage? {
        guard let path = c.photoPath, !path.isEmpty else { return nil }
        if let img = photoCache[path] { return img }
        if let d = try? Data(contentsOf: photoFile(path)), let img = UIImage(data: d) { photoCache[path] = img; return img }
        guard let t = try? await token(), let d = try? await api.storageDownload(token: t, bucket: Self.bucket, path: path),
              let img = UIImage(data: d) else { return nil }
        photoCache[path] = img
        savePhotoFile(path, d)
        return img
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
        if saved.byName.isEmpty, u.role == .teacher { saved.byName = u.fullName }
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
        try require(Permissions.canTakeAttendance(u, circle.id, d))
        let c = try center()
        let now = Rows.iso(Date())
        let rows: [JSON] = marks.map { sid, s in
            ["center_id": c, "student_id": sid, "circle_id": circleId, "day": day, "status": s.rawValue.lowercased(), "recorded_by": u.id, "recorded_at": now,
             "by_name": opt(u.role == .teacher ? u.fullName : nil)]
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
        if saved.byName.isEmpty, u.role == .teacher { saved.byName = u.fullName }
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
        if saved.byName.isEmpty, u.role == .teacher { saved.byName = u.fullName }
        let row = json(Rows.announcementRow(saved, try center()))
        return try await write(PendingOp(type: "upsert", table: "announcements", body: row, ignoreDuplicates: true), saved) { $0.announcements.insert(saved, at: 0) }
    }

    func deleteAnnouncement(_ id: String) async throws {
        let img = st.cache.announcements.first { $0.id == id }?.imagePath
        _ = try await write(PendingOp(type: "delete", table: "announcements", filter: "id=eq.\(id)"), ()) { $0.announcements.removeAll { $0.id == id } }
        // v3.8: its photo too (best effort)
        if let p = img, let t = try? await token() { Task { try? await api.storageDelete(token: t, bucket: Self.bucket, path: p) } }
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

    /// v3.6: the admin's bell, as a local notification when a sync brings new teacher actions (no push: the app must sync).
    static func postEvents(_ list: [AdminEvent]) {
        for e in list.prefix(5) {
            let c = UNMutableNotificationContent()
            c.title = e.added ? "طالب جديد" : "فصل طالب"
            c.body = e.line + ((e.circleName ?? "").isEmpty ? "" : " — حلقة " + (e.circleName ?? ""))
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ev-" + e.id, content: c, trigger: nil))
        }
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
