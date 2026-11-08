import Foundation

/// Client-side mirror of the server's Row Level Security rules (v3.1). The server is the
/// authority; this only decides what the UI offers and what the demo store accepts.
///  - VIEWER (general password): reads everything, writes nothing.
///  - TEACHER (the one shared teachers' password): reads everything and records / edits students in ANY circle.
///  - ADMIN (admin password): everything, including circles, deleting, passwords and the centre.
enum Permissions {
    static func canManageCenter(_ u: Member) -> Bool { u.role == .admin }
    static func canManagePasswords(_ u: Member) -> Bool { u.role == .admin }
    static func canManageCircles(_ u: Member) -> Bool { u.role == .admin }
    static func canDeleteStudents(_ u: Member) -> Bool { u.role == .admin }
    static func canPostAnnouncement(_ u: Member) -> Bool { u.role == .admin || u.role == .teacher }
    static func isReadOnly(_ u: Member) -> Bool { u.role == .viewer }

    /// Add or edit a student (admin and teachers, any circle).
    static func canEditStudents(_ u: Member) -> Bool { u.role == .admin || u.role == .teacher }
    static func canEditStudent(_ u: Member, _ s: Student, _ snap: CenterSnapshot) -> Bool { canEditStudents(u) }
    static func canRecordFor(_ u: Member, _ s: Student, _ snap: CenterSnapshot) -> Bool { u.role == .admin || u.role == .teacher }
    static func canTakeAttendance(_ u: Member) -> Bool { u.role == .admin || u.role == .teacher }

    static func canSeeStudent(_ u: Member, _ s: Student, _ snap: CenterSnapshot) -> Bool { true }

    static func visibleStudents(_ u: Member, _ snap: CenterSnapshot) -> [Student] {
        snap.students.sorted { $0.fullName < $1.fullName }
    }

    static func visibleCircles(_ u: Member, _ snap: CenterSnapshot) -> [StudyCircle] {
        snap.circles.sorted { $0.name < $1.name }
    }

    static func audienceIncludes(_ a: Audience, _ role: Role) -> Bool {
        switch a {
        case .all: return true
        case .teachers: return role == .teacher || role == .admin
        case .parents, .students: return role == .admin
        }
    }
}
