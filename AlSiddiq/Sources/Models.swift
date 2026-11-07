import Foundation

enum Role: String, Codable, CaseIterable, Identifiable {
    case admin = "ADMIN", teacher = "TEACHER", student = "STUDENT", parent = "PARENT"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .admin: return "إدارة المركز"
        case .teacher: return "معلم"
        case .student: return "طالب"
        case .parent: return "ولي أمر"
        }
    }
    /// The value the central database uses.
    var dbValue: String { rawValue.lowercased() }
    init?(db: String) { self.init(rawValue: db.uppercased()) }
}

struct Member: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var fullName: String
    var phone: String
    var role: Role
    var active: Bool = true
    /// For a STUDENT account: the student record it belongs to.
    var studentId: String? = nil
    /// For a PARENT account: the children it may see.
    var childIds: [String] = []
    var createdAt: Date = Date()
}

struct StudyCircle: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var teacherId: String?
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
}

struct Reward: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var studentId: String
    var points: Int
    var reason: String
    var awardedBy: String
    var createdAt: Date = Date()
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

    func member(_ id: String?) -> Member? { members.first { $0.id == id } }
    func circle(_ id: String?) -> StudyCircle? { circles.first { $0.id == id } }
    func student(_ id: String?) -> Student? { students.first { $0.id == id } }
    func studentsIn(_ circleId: String?) -> [Student] { students.filter { $0.circleId == circleId && circleId != nil } }
    func teachers() -> [Member] { members.filter { $0.role == .teacher } }
    func parents() -> [Member] { members.filter { $0.role == .parent } }
    func parentsOf(_ studentId: String) -> [Member] { members.filter { $0.role == .parent && $0.childIds.contains(studentId) } }
    var unreadCount: Int { notifications.filter { !$0.read }.count }
}

struct NewMember {
    var fullName: String
    var phone: String
    var role: Role
    var password: String
    var studentId: String? = nil
    var childIds: [String] = []
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
