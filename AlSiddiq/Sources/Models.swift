import Foundation

enum Role: String, Codable, CaseIterable, Identifiable {
    case admin = "ADMIN", teacher = "TEACHER", viewer = "VIEWER"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .admin: return "الإدارة"
        case .teacher: return "المعلمين"
        case .viewer: return "عرض عام"
        }
    }
    /// The value the central database uses (profiles.access_kind).
    var dbValue: String { rawValue.lowercased() }
    init?(db: String) {
        if db.lowercased() == "teachers" { self = .teacher; return }
        self.init(rawValue: db.uppercased())
    }
}

/// v3: an account is one PASSWORD (general/viewer, admin, teachers). There are no student or parent accounts.
struct Member: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var fullName: String
    var phone: String = ""
    var role: Role
    var active: Bool = true
    var createdAt: Date = Date()
}

struct StudyCircle: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var teacherId: String?
    /// v3.1: the circle's teacher, by name (from the admin's list).
    var teacherName: String? = nil
    /// v3.5: the circle's fee in Yemeni rial (admin only; nil = not shown) and its period: monthly | term | once.
    var feeYer: Int? = nil
    var feePeriod: String? = nil
    var level: String = ""
    var schedule: String = ""
    var capacity: Int = 20
    var active: Bool = true
    var createdAt: Date = Date()
    /// v3.8: the circle's photo «لوحة الحلقة» in the student-photos bucket (nil = the usual look).
    var photoPath: String? = nil
}

enum StudentStatus: String, Codable, CaseIterable {
    case active = "ACTIVE", paused = "PAUSED", graduated = "GRADUATED"
    var label: String {
        switch self { case .active: return "منتظم"; case .paused: return "متوقف مؤقتاً"; case .graduated: return "خاتم" }
    }
}

struct Student: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var fullName: String
    var phone: String = ""
    var birthYear: Int? = nil
    var circleId: String?
    /// ISO date yyyy-MM-dd
    var joinedOn: String
    var goalJuz: Int = 30
    var status: StudentStatus = .active
    var notes: String = ""
    /// Path of the student's photo in the private storage bucket (nil = no photo; the initial is shown).
    var photoPath: String? = nil
    var createdAt: Date = Date()
    /// v3.6: false = dismissed (مفصول) by a teacher or the admin. Optional so older saved copies still load (nil = active).
    var activeFlag: Bool? = nil
    var dismissedAt: Date? = nil
    var dismissedBy: String? = nil
    var active: Bool { activeFlag ?? true }
}

enum RecordKind: String, Codable, CaseIterable, Identifiable {
    // build 15 (Android parity): stored values of the first three are unchanged; the last two are appended.
    case hifz = "HIFZ", tasmee = "TASMEE", muraja = "MURAJA", azfar = "AZFAR", sard = "SARD"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hifz: return "حفظ جديد"; case .tasmee: return "تسميع"; case .muraja: return "مراجعة"
        case .azfar: return "لم يسمع"; case .sard: return "سرد السورة"
        }
    }
    var short: String {
        switch self {
        case .hifz: return "حفظ"; case .tasmee: return "تسميع"; case .muraja: return "مراجعة"
        case .azfar: return "لم يسمع"; case .sard: return "سرد"
        }
    }
}

enum Grade: String, Codable, CaseIterable, Identifiable {
    case excellent = "EXCELLENT", veryGood = "VERY_GOOD", good = "GOOD", pass = "PASS", weak = "WEAK"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .excellent: return "ممتاز"
        case .veryGood: return "جيد جداً"
        case .good: return "جيد"
        case .pass: return "مقبول"
        case .weak: return "يحتاج إعادة"
        }
    }
    var score: Int {
        switch self { case .excellent: return 5; case .veryGood: return 4; case .good: return 3; case .pass: return 2; case .weak: return 1 }
    }
}

struct Recitation: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var studentId: String
    var circleId: String?
    var teacherId: String
    var kind: RecordKind
    var fromSurah: Int
    var fromAyah: Int
    var toSurah: Int
    var toAyah: Int
    var grade: Grade
    var mistakes: Int = 0
    var notes: String = ""
    var recordedAt: Date = Date()
    /// v3.1: the teacher who recorded it, picked from the admin's list of names (optional).
    var byName: String = ""
}

/// v3.1: the admin's simple list of teacher names (no passwords; all teachers share one password).
struct TeacherName: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var active: Bool = true
}

enum AttendanceStatus: String, Codable, CaseIterable, Identifiable {
    case present = "PRESENT", late = "LATE", excused = "EXCUSED", absent = "ABSENT"
    var id: String { rawValue }
    var label: String {
        switch self { case .present: return "حاضر"; case .late: return "متأخر"; case .excused: return "مستأذن"; case .absent: return "غائب" }
    }
    var isPresent: Bool { self == .present || self == .late }
}

struct Attendance: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var studentId: String
    var circleId: String?
    /// ISO date yyyy-MM-dd
    var day: String
    var status: AttendanceStatus
    var recordedBy: String
    var recordedAt: Date = Date()
    var byName: String = ""
}

struct Reward: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var studentId: String
    var points: Int
    var reason: String
    var awardedBy: String
    var createdAt: Date = Date()
    var byName: String = ""
}

enum Audience: String, Codable, CaseIterable, Identifiable {
    case all = "ALL", teachers = "TEACHERS", parents = "PARENTS", students = "STUDENTS"
    var id: String { rawValue }
    var label: String {
        switch self { case .all: return "الجميع"; case .teachers: return "المعلمون"; case .parents: return "أولياء الأمور"; case .students: return "الطلاب" }
    }
}

struct Announcement: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String
    var body: String
    var audience: Audience
    var createdBy: String
    var createdAt: Date = Date()
    var byName: String = ""
    /// v3.8: an optional photo (admin only), in the student-photos bucket.
    var imagePath: String? = nil
}

/// v3.8: one extra teacher of a circle (circle_teachers).
struct CircleTeacher: Codable, Equatable, Hashable {
    var circleId: String
    var teacherId: String
}

struct AppNotification: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var userId: String
    var title: String
    var body: String
    var kind: String = "info"
    var refId: String? = nil
    var read: Bool = false
    var createdAt: Date = Date()
}

struct CenterInfo: Codable, Equatable {
    var name: String = "مركز الصديق لتعليم القرآن الكريم"
    var city: String = ""
}

/// Everything the signed-in user is allowed to see, as one immutable snapshot.
struct CenterSnapshot: Codable, Equatable {
    var center = CenterInfo()
    var members: [Member] = []
    var circles: [StudyCircle] = []
    var students: [Student] = []
    var recitations: [Recitation] = []
    var attendance: [Attendance] = []
    var rewards: [Reward] = []
    var announcements: [Announcement] = []
    var notifications: [AppNotification] = []
    var teacherNames: [TeacherName] = []
    /// v3.6: dismissed students (kept for the admin's event cards; hidden from every list).
    var dismissed: [Student]? = nil
    /// v3.6: the admin's bell (teachers' adds and dismissals). Admin only; nil for everyone else.
    var adminEvents: [AdminEvent]? = nil
    /// v3.7: published «المتفوقون» cards, newest first.
    var honorCards: [HonorCard]? = nil
    /// v3.8 (admin only; nil for everyone else): «حضور وغياب المعلمين» and «الميزانية».
    var teacherMarks: [TeacherMark]? = nil
    var budget: [BudgetEntry]? = nil
    /// v3.8 «كشف الاشتراكات»: the admin gets every student's months, a teacher his own circle's; nil for the general view.
    var subscriptions: [StudentSubscription]? = nil
    /// v3.8: extra teachers of a circle (circle_teachers); a circle's teachers = teacherId ∪ these rows.
    var circleTeachers: [CircleTeacher]? = nil

    func member(_ id: String?) -> Member? { members.first { $0.id == id } }
    func circle(_ id: String?) -> StudyCircle? { circles.first { $0.id == id } }
    /// The name of a circle's teacher (from the admin's list of teacher names).
    func teacherName(of c: StudyCircle) -> String? {
        // v3.8: more than one teacher → all names joined with «، »
        let ids = teacherIds(of: c)
        if ids.count > 1 {
            let names = ids.compactMap { teacherName($0) }
            if !names.isEmpty { return names.joined(separator: "، ") }
        }
        if let n = c.teacherName, !n.isEmpty { return n }
        return teacherName(c.teacherId)
    }
    /// v3.8: every teacher account of a circle, the main one (teacher_id) first, no duplicates.
    func teacherIds(of c: StudyCircle) -> [String] {
        var out: [String] = []
        if let t = c.teacherId, !t.isEmpty { out.append(t) }
        for r in (circleTeachers ?? []) where r.circleId == c.id && !out.contains(r.teacherId) { out.append(r.teacherId) }
        return out
    }
    func teacherName(_ id: String?) -> String? {
        guard let id = id else { return nil }
        return teacherNames.first { $0.id == id }?.name ?? members.first { $0.id == id && $0.role == .teacher }?.fullName
    }
    func student(_ id: String?) -> Student? { students.first { $0.id == id } }
    func studentsIn(_ circleId: String?) -> [Student] { students.filter { $0.circleId == circleId && circleId != nil } }
    /// v3.3: the teacher ACCOUNTS (each with his own password), as name entries for pickers.
    func teachers() -> [TeacherName] {
        members.filter { $0.role == .teacher && $0.active }.map { TeacherName(id: $0.id, name: $0.fullName) }.sorted { $0.name < $1.name }
    }
    /// v3.3: the circles this teacher account teaches.
    func circles(of teacherId: String) -> [StudyCircle] { circles.filter { teacherIds(of: $0).contains(teacherId) } }
    var unreadCount: Int { notifications.filter { !$0.read }.count }
    var events: [AdminEvent] { (adminEvents ?? []).sorted { $0.createdAt > $1.createdAt } }
    var unreadEvents: Int { (adminEvents ?? []).filter { $0.readAt == nil }.count }
    var honors: [HonorCard] { (honorCards ?? []).sorted { $0.createdAt > $1.createdAt } }
    /// A student by id, dismissed ones included (for the admin's event cards).
    func anyStudent(_ id: String?) -> Student? { student(id) ?? (dismissed ?? []).first { $0.id == id } }
}

enum AppError: LocalizedError {
    case permissionDenied(String = "ليست لديك صلاحية لهذه العملية")
    case validation(String)
    case network(String)
    var errorDescription: String? {
        switch self {
        case .permissionDenied(let m), .validation(let m), .network(let m): return m
        }
    }
}

/// v3.1: the teacher's own name picked on this phone (optional); records then carry it as by_name.
enum Recorder {
    static let key = "recordedByName"
    /// v3.3: records carry the signed-in teacher's own name (set by the repository); nothing to pick.
    static var name: String? { nil }
}


/// v3.6: one line in the admin's bell — a teacher registered or dismissed a student (written by the server's trigger).
struct AdminEvent: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var kind: String            // student_added | student_dismissed
    var actorName: String
    var studentId: String?
    var circleId: String?
    var createdAt: Date
    var readAt: Date? = nil
    /// The student as he was at that moment (the server's snapshot).
    var fullName: String = ""
    var circleName: String? = nil
    var teacherName: String? = nil
    var level: String? = nil
    var phone: String? = nil
    var birthYear: Int? = nil
    var joinedOn: String? = nil
    var goalJuz: Int? = nil
    var status: String? = nil
    var notes: String? = nil
    var photoPath: String? = nil

    var added: Bool { kind == "student_added" }
    var line: String { actorName + (added ? " سجّل طالب: " : " فصل الطالب: ") + fullName }
}

/// v3.7: one published «المتفوقون» card (the admin's «اظهر تفوق الطالب»).
struct HonorCard: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var title: String = "المتفوقون"
    var students: [HonorStudent] = []
    var message: String? = nil
    var publishedBy: String? = nil
    var createdAt: Date = Date()
}

struct HonorStudent: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var fullName: String
    var photoPath: String? = nil
    var circleName: String? = nil
    var scoreText: String? = nil
}
