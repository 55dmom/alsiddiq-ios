import Foundation
import UIKit

/// Where the data lives. The UI only ever talks to this interface.
enum BackendMode { case demo, cloud }

enum SyncState: Equatable {
    case localOnly, synced, pending(Int), error(String)
    /// v3.2: writes kept on the phone after their login ended; they go up after that section's password is typed again.
    case waitingPassword(Int, Role)
}

/// v3 access (same as the Android app): there are no usernames or phone numbers. One password field;
/// the server decides whose password it is — the general (viewer) password, the admin password,
/// or the teachers' password. Students exist only as records managed by the admin and the teachers.
@MainActor
protocol AppRepository: AnyObject {
    var mode: BackendMode { get }
    /// Who is using the app right now (viewer, teachers or the admin).
    var currentUser: Member? { get }
    /// The general (viewer) login kept underneath while the admin/teachers section is open from Settings.
    var baseUser: Member? { get }
    /// The centre name shown on the password screen (cached).
    var centerName: String { get }
    /// Everything the current user is allowed to see; `onChange` fires when it moves.
    var snapshot: CenterSnapshot { get }
    var syncState: SyncState { get }
    /// v3.2: this record/row is still on the phone only («بانتظار الإرسال»).
    func isPending(_ id: String) -> Bool
    var onChange: (() -> Void)? { get set }

    /// True when no admin password exists yet (first-time setup). nil = unknown (offline).
    func needsSetup() async -> Bool?
    /// First run: centre name + admin password + general password (+ the teachers' password when the server takes it).
    func setup(centerName: String, adminPassword: String, viewerPassword: String, teacherPassword: String?) async throws -> Member

    /// kind = nil: the opening screen (any password). kind = .admin / .teacher: the Settings buttons
    /// «الإدارة» / «المعلمين» (only that kind is accepted); the general view stays underneath.
    func signIn(password: String, kind: Role?) async throws -> Member
    /// Leave the admin/teachers section and return to the general view (or the password screen if none).
    func leaveRole() async
    /// Forget every session on this phone.
    func signOut() async

    func refresh() async throws

    // Admin: centre, passwords, teacher names, circles, students
    func updateCenter(_ info: CenterInfo) async throws
    /// Change the general (.viewer), the .admin or the shared .teacher password.
    func setAccessPassword(target: Role, password: String) async throws
    /// v3.3: the admin adds / edits a teacher account (name, his circle, his own password — required when new).
    func saveTeacher(id: String?, name: String, circleId: String?, password: String?) async throws -> Member
    /// v3.3: disable a teacher (he can no longer sign in; his past entries keep his name).
    func removeTeacher(_ id: String) async throws

    // v3.4 «عن المركز» (public; admin edits). Falls back to his bundled text/photo; cached offline.
    var aboutCenter: AboutInfo { get }
    func refreshAbout() async
    func aboutPhoto(_ path: String) async -> UIImage?
    func saveAboutText(_ text: String) async throws
    func addAboutPhoto(_ jpeg: Data) async throws
    func removeAboutPhoto(_ path: String) async throws
    func saveAboutButton(_ b: AboutButton) async throws
    func deleteAboutButton(_ id: String) async throws
    func moveAboutButton(_ id: String, up: Bool) async throws
    func saveCircle(_ c: StudyCircle) async throws -> StudyCircle
    func deleteCircle(_ id: String) async throws
    func saveStudent(_ s: Student) async throws -> Student
    func deleteStudent(_ id: String) async throws
    /// v3.6: «فصل الطالب» — a teacher in his own circle, or the admin. The row stays (active = false); the server tells the admin.
    func dismissStudent(_ id: String) async throws
    /// v3.6: the admin's bell.
    func markEventRead(_ id: String) async throws
    func markAllEventsRead() async throws
    /// v3.7: «اظهر تفوق الطالب» (admin): publish a «المتفوقون» card.
    func publishHonors(_ students: [HonorStudent], message: String?) async throws
    /// v3.8 (admin only): «حضور وغياب المعلمين» — one mark per teacher for the day (teacher id → حاضر/غائب).
    func saveTeacherAttendance(day: String, marks: [String: TeacherMarkStatus]) async throws -> Int
    /// v3.8 (admin only): «الميزانية» — add (empty id) or edit one income/expense entry; delete one.
    func saveBudgetEntry(_ e: BudgetEntry) async throws -> BudgetEntry
    func deleteBudgetEntry(_ id: String) async throws
    /// v3.8 «كشف الاشتراكات»: the admin, or a teacher for his own circle's students. month = 'YYYY-MM-01'.
    func saveSubscriptions(month: String, marks: [String: SubscriptionMark]) async throws -> Int
    /// v3.8 «لوحة الحلقة»: the admin on any circle, a teacher on his own. jpeg nil = remove.
    func setCirclePhoto(circleId: String, jpeg: Data?) async throws
    func circlePhoto(_ c: StudyCircle) async -> UIImage?
    /// Set (jpeg) or remove (nil) the student's photo.
    func setStudentPhoto(studentId: String, jpeg: Data?) async throws
    /// The student's photo, cached on the phone.
    func photo(_ s: Student) async -> UIImage?

    // Teaching
    func logRecitation(_ r: Recitation) async throws -> Recitation
    func deleteRecitation(_ id: String) async throws
    func saveAttendance(circleId: String, day: String, marks: [String: AttendanceStatus]) async throws -> Int
    func giveReward(_ r: Reward) async throws -> Reward

    // Communication (the teachers' «تقرير اليوم» is an announcement to everyone)
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

enum Passwords {
    /// Arabic-Indic (and Persian) digits typed on an Arabic keyboard count as the same password as 0–9 (same as the server).
    static func normalise(_ p: String) -> String {
        var out = ""
        for ch in p {
            if let s = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 {
                let v = s.value
                if v >= 0x0660 && v <= 0x0669 { out.append(String(v - 0x0660)); continue }
                if v >= 0x06F0 && v <= 0x06F9 { out.append(String(v - 0x06F0)); continue }
            }
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static let minLength = 6
    static func check(_ p: String) -> String? {
        p.count < minLength ? "كلمة السر 6 أحرف أو أرقام على الأقل" : nil
    }
}

/// Photos: about 512 px on the long side, JPEG.
enum PhotoTools {
    static func jpeg512(_ image: UIImage) -> Data? { jpeg(image, maxSide: 512) }
    static func jpeg(_ image: UIImage, maxSide: CGFloat) -> Data? {
        let s = image.size
        let scale = min(1, maxSide / max(s.width, s.height, 1))
        let target = CGSize(width: max(1, (s.width * scale).rounded()), height: max(1, (s.height * scale).rounded()))
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: 0.8)
    }
}
