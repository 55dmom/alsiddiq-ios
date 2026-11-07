import Foundation

/// Local-only store used until the central database is connected. It persists to a
/// file on the device and applies the same permission rules the server enforces,
/// so screens behave exactly as they will with the real backend. It does NOT sync.
@MainActor
final class DemoRepository: AppRepository {
    let mode: BackendMode = .demo
    private(set) var currentUser: Member?
    private(set) var snapshot = CenterSnapshot()
    let syncState: SyncState = .localOnly
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
        if user.role == .admin {
            var s = all
            s.notifications = all.notifications.filter { $0.userId == user.id }
            return s
        }
        let students = Permissions.visibleStudents(user, all)
        let ids = Set(students.map { $0.id })
        let circles = Permissions.visibleCircles(user, all)
        var memberIds: Set<String> = [user.id]
        circles.compactMap { $0.teacherId }.forEach { memberIds.insert($0) }
        if user.role == .teacher {
            all.members.filter { m in m.role == .parent && m.childIds.contains { ids.contains($0) } }.forEach { memberIds.insert($0.id) }
        }
        return CenterSnapshot(
            center: all.center,
            members: all.members.filter { memberIds.contains($0.id) },
            circles: circles,
            students: students,
            recitations: all.recitations.filter { ids.contains($0.studentId) },
            attendance: all.attendance.filter { ids.contains($0.studentId) },
            rewards: all.rewards.filter { ids.contains($0.studentId) },
            announcements: all.announcements.filter { Permissions.audienceIncludes($0.audience, user.role) },
            notifications: all.notifications.filter { $0.userId == user.id }
        )
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

    // MARK: Auth
    func signIn(login: String, password: String) async throws -> Member {
        let key = Phone.normalise(login)
        guard !key.isEmpty, let m = store.data.members.first(where: { Phone.normalise($0.phone) == key }) else {
            throw AppError.validation("لا يوجد حساب بهذا الرقم")
        }
        guard m.active else { throw AppError.validation("هذا الحساب موقوف، راجع إدارة المركز") }
        guard store.passwordHashes[m.id] == sha256(password) else { throw AppError.validation("كلمة المرور غير صحيحة") }
        store.currentUserId = m.id
        currentUser = m
        persist(); publish()
        return m
    }

    func signOut() async {
        store.currentUserId = nil
        currentUser = nil
        persist(); publish()
    }

    func changePassword(old: String, new: String) async throws {
        let u = try requireUser()
        guard store.passwordHashes[u.id] == sha256(old) else { throw AppError.validation("كلمة المرور الحالية غير صحيحة") }
        guard new.count >= 6 else { throw AppError.validation("كلمة المرور 6 أحرف على الأقل") }
        store.passwordHashes[u.id] = sha256(new)
        persist()
    }

    func refresh() async throws { publish() }

    // MARK: Admin
    func updateCenter(_ info: CenterInfo) async throws {
        try mutate { d, u in try require(Permissions.canManageCenter(u)); d.center = info }
    }

    func createMember(_ m: NewMember) async throws -> Member {
        let u = try requireUser()
        try require(Permissions.canManageMembers(u))
        let phone = Phone.normalise(m.phone)
        if m.fullName.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب الاسم") }
        if phone.count < 8 { throw AppError.validation("رقم الجوال غير صحيح") }
        if store.data.members.contains(where: { Phone.normalise($0.phone) == phone }) { throw AppError.validation("هذا الرقم مسجّل مسبقاً") }
        if m.password.count < 6 { throw AppError.validation("كلمة المرور 6 أحرف على الأقل") }
        let member = Member(id: newId(), fullName: m.fullName.trimmingCharacters(in: .whitespaces), phone: phone, role: m.role,
                            active: true, studentId: m.studentId, childIds: m.childIds)
        store.data.members.append(member)
        store.passwordHashes[member.id] = sha256(m.password)
        persist(); publish()
        return member
    }

    func updateMember(_ m: Member) async throws {
        try mutate { d, u in
            try require(Permissions.canManageMembers(u))
            if m.id == u.id && m.role != u.role { throw AppError.validation("لا يمكنك تغيير دورك بنفسك") }
            d.members = d.members.map { $0.id == m.id ? m : $0 }
        }
        if m.id == currentUser?.id { currentUser = m; publish() }
    }

    func resetMemberPassword(memberId: String, newPassword: String) async throws {
        let u = try requireUser()
        try require(Permissions.canManageMembers(u))
        guard newPassword.count >= 6 else { throw AppError.validation("كلمة المرور 6 أحرف على الأقل") }
        store.passwordHashes[memberId] = sha256(newPassword)
        persist()
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
            try require(Permissions.canManageStudents(u))
            if s.fullName.trimmingCharacters(in: .whitespaces).isEmpty { throw AppError.validation("اكتب اسم الطالب") }
            var saved = s
            if saved.id.isEmpty { saved.id = newId() }
            if let i = d.students.firstIndex(where: { $0.id == saved.id }) { d.students[i] = saved } else { d.students.append(saved) }
            return saved
        }
    }

    func deleteStudent(_ id: String) async throws {
        try mutate { d, u in
            try require(Permissions.canManageStudents(u))
            d.students.removeAll { $0.id == id }
            d.recitations.removeAll { $0.studentId == id }
            d.attendance.removeAll { $0.studentId == id }
            d.rewards.removeAll { $0.studentId == id }
            d.members = d.members.map { var m = $0; m.childIds.removeAll { $0 == id }; return m }
        }
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
            let title = "\(saved.kind.label): \(student.fullName)"
            let body = "\(Stats.describeRange(saved)) • \(ayat) آية • \(saved.grade.label)"
            d.recitations.append(saved)
            d.notifications += notify(recipientsFor(d, student.id), title, body, "record", saved.id)
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
            try require(u.role == .admin || Permissions.teachesCircle(u, circle))
            d.attendance.removeAll { $0.day == day && marks.keys.contains($0.studentId) }
            let added = marks.map { Attendance(id: newId(), studentId: $0.key, circleId: circleId, day: day, status: $0.value, recordedBy: u.id) }
            d.attendance += added
            for (sid, st) in marks where st == .absent {
                let s = d.student(sid)
                d.notifications += notify(d.parentsOf(sid).map { $0.id }, "غياب \(s?.fullName ?? "")", "سُجّل غياب في \(circle.name) بتاريخ \(day)", "absence", sid)
            }
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
            d.notifications += notify(recipientsFor(d, student.id), "مكافأة \(student.fullName) 🎉", "+\(r.points) نقطة: \(r.reason)", "reward", saved.id)
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
            try require(u.role == .admin || a.createdBy == u.id)
            d.announcements.removeAll { $0.id == id }
        }
    }

    func markNotificationRead(_ id: String) async throws {
        try mutate { d, u in d.notifications = d.notifications.map { var n = $0; if n.id == id && n.userId == u.id { n.read = true }; return n } }
    }

    func markAllNotificationsRead() async throws {
        try mutate { d, u in d.notifications = d.notifications.map { var n = $0; if n.userId == u.id { n.read = true }; return n } }
    }

    private func recipientsFor(_ d: CenterSnapshot, _ studentId: String) -> [String] {
        d.parentsOf(studentId).map { $0.id } + d.members.filter { $0.role == .student && $0.studentId == studentId }.map { $0.id }
    }

    private func notify(_ userIds: [String], _ title: String, _ body: String, _ kind: String, _ ref: String?) -> [AppNotification] {
        var seen = Set<String>()
        return userIds.filter { seen.insert($0).inserted }.map {
            AppNotification(id: newId(), userId: $0, title: title, body: body, kind: kind, refId: ref)
        }
    }
}
