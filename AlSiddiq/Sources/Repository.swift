import Foundation

/// Where the data lives. The UI only ever talks to this interface.
enum BackendMode { case demo, cloud }

enum SyncState: Equatable {
    case localOnly, synced, pending(Int), error(String)
}

/// Same shape as the Android app's AuthRepository + CenterRepository.
@MainActor
protocol AppRepository: AnyObject {
    var mode: BackendMode { get }
    var currentUser: Member? { get }
    /// Everything the current user is allowed to see; `onChange` fires when it moves.
    var snapshot: CenterSnapshot { get }
    var syncState: SyncState { get }
    var onChange: (() -> Void)? { get set }

    // Auth
    func signIn(login: String, password: String) async throws -> Member
    func signOut() async
    func changePassword(old: String, new: String) async throws

    func refresh() async throws

    // Admin: center, members, circles, students
    func updateCenter(_ info: CenterInfo) async throws
    func createMember(_ m: NewMember) async throws -> Member
    func updateMember(_ m: Member) async throws
    func resetMemberPassword(memberId: String, newPassword: String) async throws
    func saveCircle(_ c: StudyCircle) async throws -> StudyCircle
    func deleteCircle(_ id: String) async throws
    func saveStudent(_ s: Student) async throws -> Student
    func deleteStudent(_ id: String) async throws

    // Teaching
    func logRecitation(_ r: Recitation) async throws -> Recitation
    func deleteRecitation(_ id: String) async throws
    func saveAttendance(circleId: String, day: String, marks: [String: AttendanceStatus]) async throws -> Int
    func giveReward(_ r: Reward) async throws -> Reward

    // Communication
    func postAnnouncement(_ a: Announcement) async throws -> Announcement
    func deleteAnnouncement(_ id: String) async throws
    func markNotificationRead(_ id: String) async throws
    func markAllNotificationsRead() async throws
}

enum Phone {
    /// Keeps digits only, turning Arabic-Indic digits into ASCII.
    static func normalise(_ p: String) -> String {
        var out = ""
        for ch in p {
            if let v = ch.wholeNumberValue, ch.isNumber { out.append(String(v)) }
        }
        return out
    }
}
