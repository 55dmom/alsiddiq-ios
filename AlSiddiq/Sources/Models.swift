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
}

enum RecordKind: String, Codable, CaseIterable, Identifiable {
    case hifz = "HIFZ", tasmee = "TASMEE", muraja = "MURAJA"
    var id: String { rawValue }
    var label: String {
        switch self { case .hifz: return "حفظ جديد"; case .tasmee: return "تسميع"; case .muraja: return "مراجعة" }
    }
    var short: String {
        switch self { case .hifz: return "حفظ"; case .tasmee: return "تسميع"; case .muraja: return "مراجعة" }
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

    func member(_ id: String?) -> Member? { members.first { $0.id == id } }
    func circle(_ id: String?) -> StudyCircle? { circles.first { $0.id == id } }
    /// The name of a circle's teacher (from the admin's list of teacher names).
    func teacherName(of c: StudyCircle) -> String? {
        if let n = c.teacherName, !n.isEmpty { return n }
        return teacherName(c.teacherId)
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
    func circles(of teacherId: String) -> [StudyCircle] { circles.filter { $0.teacherId == teacherId } }
    var unreadCount: Int { notifications.filter { !$0.read }.count }
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
