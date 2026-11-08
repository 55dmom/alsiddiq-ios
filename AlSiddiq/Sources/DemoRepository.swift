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
        var s = all
        s.announcements = all.announcements.filter { Permissions.audienceIncludes($0.audience, user.role) }
        s.notifications = all.notifications.filter { $0.userId == user.id }
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

    func saveTeacherName(id: String?, name: String) async throws {
        try mutate { d, u in
            try require(Permissions.canManageCenter(u))
            let n = name.trimmingCharacters(in: .whitespaces)
            if n.isEmpty { throw AppError.validation("اكتب اسم المعلم") }
            if let id = id, let i = d.teacherNames.firstIndex(where: { $0.id == id }) { d.teacherNames[i].name = n }
            else { d.teacherNames.append(TeacherName(id: newId(), name: n)) }
        }
    }

    func removeTeacherName(_ id: String) async throws {
        try mutate { d, u in
            try require(Permissions.canManageCenter(u))
            d.teacherNames = d.teacherNames.map { var t = $0; if t.id == id { t.active = false }; return t }
            _ = id
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
            if let i = d.students.firstIndex(where: { $0.id == saved.id }) { d.students[i] = saved } else { d.students.append(saved) }
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
            try require(Permissions.canTakeAttendance(u))
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
