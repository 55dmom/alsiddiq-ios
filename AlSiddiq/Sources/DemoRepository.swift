import Foundation
import UIKit

/// Local-only store used until the central database is connected. It persists to a
/// file on the device and applies the same permission rules the server enforces,
/// so screens behave exactly as they will with the real backend. It does NOT sync.
@MainActor
final class DemoRepository: AppRepository {
    let mode: BackendMode = .demo
    private(set) var currentUser: Member?
    private(set) var snapshot = CenterSnapshot()
    /// CI screenshots only (Debug): "-ciPending N" shows the «بانتظار الإرسال» state as it looks offline. Never in Release.
    var syncState: SyncState {
        #if DEBUG
        let n = UserDefaults.standard.integer(forKey: "ciPending")
        if n > 0 { return .pending(n) }
        #endif
        return .localOnly
    }
    func isPending(_ id: String) -> Bool {
        #if DEBUG
        let n = UserDefaults.standard.integer(forKey: "ciPending")
        if n > 0 { return store.data.recitations.filter { $0.studentId == "s1" }.sorted { $0.recordedAt > $1.recordedAt }.prefix(n).contains { $0.id == id } }
        #endif
        return false
    }
    var onChange: (() -> Void)?

    private var store: DemoStore
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("demo_store.json")
        if let data = try? Data(contentsOf: fileURL),
           let s = try? JSONDecoder().decode(DemoStore.self, from: data),
           s.seedVersion == DemoSeed.version {
            store = s
        } else {
            store = DemoSeed.create()
        }
        currentUser = store.data.member(store.currentUserId)
        snapshot = visibleTo(currentUser)
    }

    private func persist() {
        let s = store
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(s) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func publish() {
        snapshot = visibleTo(currentUser)
        onChange?()
    }

    private func visibleTo(_ user: Member?) -> CenterSnapshot {
        let all = store.data
        guard let user = user else { return CenterSnapshot(center: all.center) }
        var s = all
        s.announcements = all.announcements.filter { Permissions.audienceIncludes($0.audience, user.role) }
        s.notifications = all.notifications.filter { $0.userId == user.id }
        s.students = all.students.filter { $0.active }
        s.dismissed = (all.dismissed ?? []) + all.students.filter { !$0.active }
        s.adminEvents = user.role == .admin ? (all.adminEvents ?? []) : nil
        // v3.8: admin only
        s.teacherMarks = user.role == .admin ? (all.teacherMarks ?? []) : nil
        s.budget = user.role == .admin ? (all.budget ?? []) : nil
        s.subscriptions = user.role == .viewer ? nil : (all.subscriptions ?? []).filter { sub in
            user.role == .admin || Permissions.editableCircles(user, all).contains { $0.id == all.student(sub.studentId)?.circleId }
        }
        #if DEBUG
        // CI screenshots only: "-ciV38Demo YES" also marks a few of this month's subscriptions and gives the circles a «لوحة»
        if user.role != .viewer, UserDefaults.standard.bool(forKey: "ciV38Demo"), (s.subscriptions ?? []).isEmpty {
            let month = String(Days.iso(Days.today).prefix(7)) + "-01"
            let mine = user.role == .admin ? s.students : s.students.filter { st in Permissions.editableCircles(user, s).contains { $0.id == st.circleId } }
            s.subscriptions = mine.prefix(4).enumerated().map { k, x in
                StudentSubscription(id: "ss-\(k)", studentId: x.id, month: month, paid: k != 2, amount: k != 2 ? Double(s.circle(x.circleId)?.feeYer ?? 5000) : nil)
            }
        }
        if UserDefaults.standard.bool(forKey: "ciV38Demo") {
            s.circles = s.circles.map { var c = $0; if c.photoPath == nil { c.photoPath = "ci/home_bg_real.jpg" }; return c }
            // a second teacher on the first circle, and a photo on the newest announcement
            if (s.circleTeachers ?? []).isEmpty, let c = s.circles.first, let other = s.teachers().first(where: { $0.id != c.teacherId }) {
                s.circleTeachers = [CircleTeacher(circleId: c.id, teacherId: other.id)]
            }
            if let i = s.announcements.indices.max(by: { s.announcements[$0].createdAt < s.announcements[$1].createdAt }), s.announcements[i].imagePath == nil {
                s.announcements[i].imagePath = "ci/home_bg_real.jpg"
            }
        }
        // CI screenshots only: "-ciV38Demo YES" fills a little sample teacher attendance and budget
        if user.role == .admin, UserDefaults.standard.bool(forKey: "ciV38Demo") {
            if (s.teacherMarks ?? []).isEmpty {
                let ts = s.teachers()
                var xs: [TeacherMark] = []
                for back in 1...6 {
                    let day = Days.iso(Days.add(Days.today, -back))
                    for (k, t) in ts.enumerated() { xs.append(TeacherMark(id: "tm-\(back)-\(k)", teacherId: t.id, day: day, status: (back + k) % 4 == 0 ? .absent : .present)) }
                }
                s.teacherMarks = xs
            }
            if (s.budget ?? []).isEmpty {
                let st = s.students.prefix(3)
                var xs: [BudgetEntry] = st.enumerated().map { k, x in
                    BudgetEntry(id: "be-i\(k)", kind: .income, amount: Double(s.circle(x.circleId)?.feeYer ?? 5000), day: Days.iso(Days.add(Days.today, -k)), studentId: x.id, createdAt: Date().addingTimeInterval(Double(-k * 3600)))
                }
                xs.append(BudgetEntry(id: "be-e1", kind: .expense, amount: 3500, day: Days.iso(Days.today), note: "مصاحف وأقلام للحلقات", createdAt: Date()))
                xs.append(BudgetEntry(id: "be-e2", kind: .expense, amount: 2000, day: Days.iso(Days.add(Days.today, -2)), note: "فاتورة الكهرباء", createdAt: Date().addingTimeInterval(-7200)))
                s.budget = xs
            }
        }
        #endif
        #if DEBUG
        // CI screenshots only: "-ciHonorCard YES" shows a published «المتفوقون» card (and its once-only congratulation)
        if UserDefaults.standard.bool(forKey: "ciHonorCard"), (s.honorCards ?? []).isEmpty {
            let top = Honors.rank(s, period: .month).prefix(3)
            s.honorCards = [HonorCard(id: "hc-demo", students: top.map { Honors.entry($0, s) }, message: "بارك الله فيكم وجعلكم من أهل القرآن، واصلوا على هذا التميّز.", publishedBy: "m-admin", createdAt: Date().addingTimeInterval(-1800))]
        }
        #endif
        return s
    }

    private func requireUser() throws -> Member {
        guard let u = currentUser else { throw AppError.permissionDenied("سجّل الدخول أولاً") }
        return u
    }
    private func require(_ ok: Bool) throws { if !ok { throw AppError.permissionDenied() } }
    private func newId() -> String { UUID().uuidString.lowercased() }

    private func mutate<T>(_ block: (inout CenterSnapshot, Member) throws -> T) throws -> T {
        let u = try requireUser()
        var d = store.data
        let v = try block(&d, u)
        store.data = d
        persist()
        publish()
        return v
    }

    var baseUser: Member? { store.data.member(store.baseUserId) }
    var centerName: String { store.data.center.name }

    // MARK: Setup (the demo store is already set up)
    func needsSetup() async -> Bool? { false }
    func setup(centerName: String, adminPassword: String, viewerPassword: String, teacherPassword: String?) async throws -> Member {
        throw AppError.validation("الإعداد الأول متاح فقط مع قاعدة البيانات المركزية")
    }

    // MARK: Auth (one password field; the password decides who you are)
    func signIn(password: String, kind: Role?) async throws -> Member {
        let pw = Passwords.normalise(password)
        if pw.isEmpty { throw AppError.validation("اكتب كلمة السر") }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard let m = store.data.members.first(where: { $0.active && store.passwordHashes[$0.id] == sha256(pw) && (kind == nil || $0.role == kind) }) else {
            throw AppError.validation("كلمة السر غير صحيحة")
        }
        if kind != nil, let cur = currentUser, cur.role == .viewer, m.role != .viewer { store.baseUserId = cur.id }
        if m.role == .viewer { store.baseUserId = nil }
        store.currentUserId = m.id
        currentUser = m
        persist(); publish()
        return m
    }

    func leaveRole() async {
        store.currentUserId = store.baseUserId
        store.baseUserId = nil
        currentUser = store.data.member(store.currentUserId)
        persist(); publish()
    }

    func signOut() async {
        store.currentUserId = nil
        store.baseUserId = nil
        currentUser = nil
        persist(); publish()
    }

    func refresh() async throws { publish() }

    // MARK: Admin
    func updateCenter(_ info: CenterInfo) async throws {
        try mutate { d, u in try require(Permissions.canManageCenter(u)); d.center = info }
    }

    func setAccessPassword(target: Role, password: String) async throws {
        let u = try requireUser()
        try require(Permissions.canManagePasswords(u))
        let pw = Passwords.normalise(password)
        if let bad = Passwords.check(pw) { throw AppError.validation(bad) }
        guard let acc = store.data.members.first(where: { $0.role == target }) else { throw AppError.validation("الحساب غير موجود") }
        if store.passwordHashes.contains(where: { $0.key != acc.id && $0.value == sha256(pw) }) {
            throw AppError.validation("كلمة السر هذي مستخدمة لحساب ثاني، اختر غيرها")
        }
        store.passwordHashes[acc.id] = sha256(pw)
        persist()
    }

    /// v3.3: the admin adds / edits a teacher ACCOUNT: name, his circle and his own password.
    func saveTeacher(id: String?, name: String, circleId: String?, password: String?) async throws -> Member {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { throw AppError.validation("اكتب اسم المعلم") }
        let pw = password.map { Passwords.normalise($0) } ?? ""
        if id == nil && pw.isEmpty { throw AppError.validation("اختر كلمة سر للمعلم") }
        if !pw.isEmpty, let bad = Passwords.check(pw) { throw AppError.validation(bad) }
        var saved: Member!
        try mutate { d, u in
            try require(Permissions.canManagePasswords(u))
            if !pw.isEmpty, store.passwordHashes.contains(where: { $0.key != id && $0.value == sha256(pw) }) {
                throw AppError.validation("كلمة السر هذي مستخدمة لحساب ثاني، اختر غيرها")
            }
            let tid = id ?? "m-" + newId()
            if let i = d.members.firstIndex(where: { $0.id == tid }) { d.members[i].fullName = n; d.members[i].active = true; saved = d.members[i] }
            else { let m = Member(id: tid, fullName: n, role: .teacher); d.members.append(m); saved = m }
            if !pw.isEmpty { store.passwordHashes[tid] = sha256(pw) }
            for k in d.circles.indices where d.circles[k].teacherId == tid && d.circles[k].id != circleId { d.circles[k].teacherId = nil; d.circles[k].teacherName = nil }
            if let c = circleId, let k = d.circles.firstIndex(where: { $0.id == c }) { d.circles[k].teacherId = tid; d.circles[k].teacherName = n }
        }
        return saved
    }

    // MARK: v3.4 about (demo: on the phone only)
    private var aboutStore: AboutInfo {
        get { (UserDefaults.standard.data(forKey: "demo_about")).flatMap { try? JSONDecoder().decode(AboutInfo.self, from: $0) } ?? .fallback }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "demo_about") }
    }
    var aboutCenter: AboutInfo { aboutStore }
    func refreshAbout() async {}
    func aboutPhoto(_ path: String) async -> UIImage? { store.photos["about/" + path].flatMap { UIImage(data: $0) } }
    func saveAboutText(_ text: String) async throws {
        try require(Permissions.canManageCenter(try requireUser()))
        var a = aboutStore; a.body = text; a.fromServer = true; aboutStore = a
    }
    func addAboutPhoto(_ jpeg: Data) async throws {
        try require(Permissions.canManageCenter(try requireUser()))
        let p = newId() + ".jpg"
        store.photos["about/" + p] = jpeg; persist()
        var a = aboutStore; a.photos.append(p); a.fromServer = true; aboutStore = a
    }
    func removeAboutPhoto(_ path: String) async throws {
        try require(Permissions.canManageCenter(try requireUser()))
        store.photos["about/" + path] = nil; persist()
        var a = aboutStore; a.photos.removeAll { $0 == path }; aboutStore = a
    }
    func saveAboutButton(_ b: AboutButton) async throws {
        try require(Permissions.canManageCenter(try requireUser()))
        var a = aboutStore; var nb = b; if nb.id.isEmpty { nb.id = newId() }
        if let i = a.buttons.firstIndex(where: { $0.id == nb.id }) { a.buttons[i] = nb } else { a.buttons.append(nb) }
        aboutStore = a
    }
    func deleteAboutButton(_ id: String) async throws {
        try require(Permissions.canManageCenter(try requireUser()))
        var a = aboutStore; a.buttons.removeAll { $0.id == id }; aboutStore = a
    }
    func moveAboutButton(_ id: String, up: Bool) async throws {
        var a = aboutStore
        var list = a.buttons.sorted { $0.sort < $1.sort }
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i - 1 : i + 1
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        for k in list.indices { list[k].sort = k + 1 }
        a.buttons = list; aboutStore = a
    }

    /// v3.3: disable a teacher (his past entries keep his name; he can no longer sign in).
    func removeTeacher(_ id: String) async throws {
        try mutate { d, u in
            try require(Permissions.canManagePasswords(u))
            if let i = d.members.firstIndex(where: { $0.id == id }) { d.members[i].active = false }
            for k in d.circles.indices where d.circles[k].teacherId == id { d.circles[k].teacherId = nil; d.circles[k].teacherName = nil }
            store.passwordHashes[id] = nil
        }
    }

    func setStudentPhoto(studentId: String, jpeg: Data?) async throws {
        try mutate { d, u in
            guard let i = d.students.firstIndex(where: { $0.id == studentId }) else { throw AppError.validation("الطالب غير موجود") }
            try require(Permissions.canEditStudent(u, d.students[i], d))
            d.students[i].photoPath = jpeg == nil ? nil : "demo/\(studentId)-\(Int(Date().timeIntervalSince1970)).jpg"
        }
        store.photos[studentId] = jpeg
        persist(); publish()
    }

    func photo(_ s: Student) async -> UIImage? {
        guard s.photoPath != nil, let d = store.photos[s.id] else { return nil }
        return UIImage(data: d)
    }

    func saveCircle(_ c: StudyCircle) async throws -> StudyCircle {
        try mutate { d, u in
            try require(Permissions.canManageCircles(u))
            if c.name.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب اسم الحلقة") }
            var saved = c
            if saved.id.isEmpty { saved.id = newId() }
            if let i = d.circles.firstIndex(where: { $0.id == saved.id }) { d.circles[i] = saved } else { d.circles.append(saved) }
            return saved
        }
    }

    func deleteCircle(_ id: String) async throws {
        try mutate { d, u in
            try require(Permissions.canManageCircles(u))
            d.circles.removeAll { $0.id == id }
            d.students = d.students.map { var s = $0; if s.circleId == id { s.circleId = nil }; return s }
        }
    }

    func saveStudent(_ s: Student) async throws -> Student {
        try mutate { d, u in
            try require(Permissions.canEditStudent(u, s, d))
            if s.fullName.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب اسم الطالب") }
            var saved = s
            if saved.id.isEmpty { saved.id = newId() }
            if let i = d.students.firstIndex(where: { $0.id == saved.id }) { d.students[i] = saved } else {
                d.students.append(saved)
                if u.role == .teacher { // v3.6: as the server's trigger does
                    d.adminEvents = [DemoSeed.event(newId(), .added, u.fullName, saved, d.circle(saved.circleId), Date())] + (d.adminEvents ?? [])
                }
            }
            return saved
        }
    }

    func deleteStudent(_ id: String) async throws {
        try mutate { d, u in
            try require(Permissions.canDeleteStudents(u))
            d.students.removeAll { $0.id == id }
            d.recitations.removeAll { $0.studentId == id }
            d.attendance.removeAll { $0.studentId == id }
            d.rewards.removeAll { $0.studentId == id }
        }
    }

    func dismissStudent(_ id: String) async throws {
        try mutate { d, u in
            guard let i = d.students.firstIndex(where: { $0.id == id }) else { return }
            try require(Permissions.canDismissStudent(u, d.students[i], d))
            var x = d.students.remove(at: i)
            x.activeFlag = false; x.dismissedAt = Date(); x.dismissedBy = u.id
            d.dismissed = (d.dismissed ?? []) + [x]
            if u.role == .teacher { // the server's trigger logs teachers' actions only
                d.adminEvents = [DemoSeed.event(newId(), .dismissed, u.fullName, x, d.circle(x.circleId), Date())] + (d.adminEvents ?? [])
            }
        }
    }

    func markEventRead(_ id: String) async throws {
        try mutate { d, u in
            try require(u.role == .admin)
            if let i = d.adminEvents?.firstIndex(where: { $0.id == id }), d.adminEvents?[i].readAt == nil { d.adminEvents?[i].readAt = Date() }
        }
    }

    func markAllEventsRead() async throws {
        try mutate { d, u in
            try require(u.role == .admin)
            let now = Date()
            d.adminEvents = d.adminEvents?.map { var e = $0; if e.readAt == nil { e.readAt = now }; return e }
        }
    }

    func publishHonors(_ students: [HonorStudent], message: String?) async throws {
        try mutate { d, u in
            try require(u.role == .admin)
            if students.isEmpty { throw AppError.validation("اختر طالباً واحداً على الأقل") }
            let m = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let card = HonorCard(id: newId(), students: students, message: (m?.isEmpty ?? true) ? nil : m, publishedBy: u.id, createdAt: Date())
            d.honorCards = [card] + (d.honorCards ?? [])
        }
    }

    // MARK: v3.8 admin: teacher attendance, budget
    func saveTeacherAttendance(day: String, marks: [String: TeacherMarkStatus]) async throws -> Int {
        try mutate { d, u in
            try require(u.role == .admin)
            if marks.isEmpty { throw AppError.validation("اختر حاضر أو غائب لمعلم واحد على الأقل") }
            var list = d.teacherMarks ?? []
            list.removeAll { $0.day == day && marks.keys.contains($0.teacherId) }
            d.teacherMarks = marks.map { TeacherMark(id: newId(), teacherId: $0.key, day: day, status: $0.value, markedBy: u.id) } + list
            return marks.count
        }
    }

    func saveBudgetEntry(_ e: BudgetEntry) async throws -> BudgetEntry {
        try mutate { d, u in
            try require(u.role == .admin)
            if e.amount <= 0 { throw AppError.validation("اكتب المبلغ") }
            let note = e.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            if e.kind == .expense && (note ?? "").isEmpty { throw AppError.validation("اكتب ملاحظة لعملية الصرف") }
            var saved = e
            saved.note = (note ?? "").isEmpty ? nil : note
            if saved.kind == .expense { saved.studentId = nil }
            var list = d.budget ?? []
            if saved.id.isEmpty {
                saved.id = newId(); saved.createdBy = u.id; saved.createdAt = Date()
                list.insert(saved, at: 0)
            } else if let i = list.firstIndex(where: { $0.id == saved.id }) {
                list[i] = saved
            }
            d.budget = list
            return saved
        }
    }

    func deleteBudgetEntry(_ id: String) async throws {
        try mutate { d, u in
            try require(u.role == .admin)
            d.budget?.removeAll { $0.id == id }
        }
    }

    func saveSubscriptions(month: String, marks: [String: SubscriptionMark]) async throws -> Int {
        try mutate { d, u in
            for sid in marks.keys {
                guard let s = d.student(sid) else { throw AppError.validation("الطالب غير موجود") }
                try require(Permissions.canEditStudent(u, s, d))
            }
            var list = d.subscriptions ?? []
            list.removeAll { $0.month == month && marks.keys.contains($0.studentId) }
            d.subscriptions = marks.map { StudentSubscription(id: newId(), studentId: $0.key, month: month, paid: $0.value.paid, amount: $0.value.paid ? $0.value.amount : nil) } + list
            return marks.count
        }
    }

    func setCirclePhoto(circleId: String, jpeg: Data?) async throws {
        try mutate { d, u in
            guard let i = d.circles.firstIndex(where: { $0.id == circleId }) else { throw AppError.validation("الحلقة غير موجودة") }
            try require(Permissions.canTakeAttendance(u, circleId, d))
            d.circles[i].photoPath = jpeg == nil ? nil : "demo/circles/\(circleId)-\(Int(Date().timeIntervalSince1970)).jpg"
        }
        store.photos["circle/" + circleId] = jpeg
        persist(); publish()
    }

    func setCircleTeachers(circleId: String, teacherIds: [String]) async throws {
        try mutate { d, u in
            try require(Permissions.canManageCircles(u))
            var kept: [String] = []
            for t in teacherIds where !kept.contains(t) { kept.append(t) }
            d.circleTeachers = (d.circleTeachers ?? []).filter { $0.circleId != circleId } + kept.map { CircleTeacher(circleId: circleId, teacherId: $0) }
        }
    }

    func uploadAnnouncementImage(announcementId: String, jpeg: Data) async throws -> String {
        let u = try requireUser()
        try require(u.role == .admin)
        let path = "demo/announcements/\(announcementId).jpg"
        store.photos["ann/" + path] = jpeg
        persist()
        return path
    }

    func announcementImage(_ path: String) async -> UIImage? {
        if let d = store.photos["ann/" + path] { return UIImage(data: d) }
        #if DEBUG
        if path.hasPrefix("ci/"), let p = Bundle.main.path(forResource: "home_bg_real", ofType: "jpg") { return UIImage(contentsOfFile: p) }
        #endif
        return nil
    }

    func circlePhoto(_ c: StudyCircle) async -> UIImage? {
        guard let p = c.photoPath else { return nil }
        if let d = store.photos["circle/" + c.id] { return UIImage(data: d) }
        #if DEBUG
        if p.hasPrefix("ci/"), let path = Bundle.main.path(forResource: "home_bg_real", ofType: "jpg") { return UIImage(contentsOfFile: path) }
        #endif
        return nil
    }

    // MARK: Teaching
    func logRecitation(_ r: Recitation) async throws -> Recitation {
        try mutate { d, u in
            guard let student = d.student(r.studentId) else { throw AppError.validation("الطالب غير موجود") }
            try require(Permissions.canRecordFor(u, student, d))
            guard Quran.isValid(r.fromSurah, r.fromAyah), Quran.isValid(r.toSurah, r.toAyah) else { throw AppError.validation("رقم الآية غير صحيح") }
            let ayat = Quran.ayatBetween(r.fromSurah, r.fromAyah, r.toSurah, r.toAyah)
            if ayat <= 0 { throw AppError.validation("نهاية المقطع قبل بدايته") }
            var saved = r
            if saved.id.isEmpty { saved.id = newId() }
            saved.teacherId = u.id
            saved.circleId = student.circleId
            d.recitations.append(saved)
            return saved
        }
    }

    func deleteRecitation(_ id: String) async throws {
        try mutate { d, u in
            guard let r = d.recitations.first(where: { $0.id == id }) else { throw AppError.validation("السجل غير موجود") }
            guard let s = d.student(r.studentId) else { throw AppError.validation("الطالب غير موجود") }
            try require(Permissions.canRecordFor(u, s, d))
            d.recitations.removeAll { $0.id == id }
        }
    }

    func saveAttendance(circleId: String, day: String, marks: [String: AttendanceStatus]) async throws -> Int {
        try mutate { d, u in
            guard let circle = d.circle(circleId) else { throw AppError.validation("الحلقة غير موجودة") }
            try require(Permissions.canTakeAttendance(u, circle.id, d))
            d.attendance.removeAll { $0.day == day && marks.keys.contains($0.studentId) }
            let added = marks.map { Attendance(id: newId(), studentId: $0.key, circleId: circleId, day: day, status: $0.value, recordedBy: u.id) }
            d.attendance += added
            _ = circle
            return added.count
        }
    }

    func giveReward(_ r: Reward) async throws -> Reward {
        try mutate { d, u in
            guard let student = d.student(r.studentId) else { throw AppError.validation("الطالب غير موجود") }
            try require(Permissions.canRecordFor(u, student, d))
            if r.points == 0 { throw AppError.validation("حدّد عدد النقاط") }
            var saved = r
            if saved.id.isEmpty { saved.id = newId() }
            saved.awardedBy = u.id
            d.rewards.append(saved)
            return saved
        }
    }

    // MARK: Communication
    func postAnnouncement(_ a: Announcement) async throws -> Announcement {
        try mutate { d, u in
            try require(Permissions.canPostAnnouncement(u))
            if a.title.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب عنوان الإعلان") }
            var saved = a
            if saved.id.isEmpty { saved.id = newId() }
            saved.createdBy = u.id
            let targets = d.members.filter { $0.id != u.id && Permissions.audienceIncludes(a.audience, $0.role) }.map { $0.id }
            d.announcements.append(saved)
            d.notifications += notify(targets, "إعلان: \(a.title)", String(a.body.prefix(120)), "announcement", saved.id)
            return saved
        }
    }

    func deleteAnnouncement(_ id: String) async throws {
        try mutate { d, u in
            guard let a = d.announcements.first(where: { $0.id == id }) else { throw AppError.validation("الإعلان غير موجود") }
            try require(u.role == .admin || (u.role == .teacher && a.createdBy == u.id))
            d.announcements.removeAll { $0.id == id }
        }
    }

    func markNotificationRead(_ id: String) async throws {
        try mutate { d, u in d.notifications = d.notifications.map { var n = $0; if n.id == id && n.userId == u.id { n.read = true }; return n } }
    }

    func markAllNotificationsRead() async throws {
        try mutate { d, u in d.notifications = d.notifications.map { var n = $0; if n.userId == u.id { n.read = true }; return n } }
    }

    private func notify(_ userIds: [String], _ title: String, _ body: String, _ kind: String, _ ref: String?) -> [AppNotification] {
        var seen = Set<String>()
        return userIds.filter { seen.insert($0).inserted }.map {
            AppNotification(id: newId(), userId: $0, title: title, body: body, kind: kind, refId: ref)
        }
    }
}
