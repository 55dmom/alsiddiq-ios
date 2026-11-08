import Foundation

/// Client-side mirror of the server's Row Level Security rules (v3.3). The server is the
/// authority; this only decides what the UI offers and what the demo store accepts.
///  - VIEWER (general password): reads everything, writes nothing.
///  - TEACHER (his OWN password, made by the admin): reads every circle; records / edits ONLY in his own circle(s).
///  - ADMIN (admin password): everything, including teachers, circles, deleting, passwords and the centre.
enum Permissions {
    static func canManageCenter(_ u: Member) -> Bool { u.role == .admin }
    static func canManagePasswords(_ u: Member) -> Bool { u.role == .admin }
    static func canManageCircles(_ u: Member) -> Bool { u.role == .admin }
    static func canDeleteStudents(_ u: Member) -> Bool { u.role == .admin }
    static func canPostAnnouncement(_ u: Member) -> Bool { u.role == .admin || u.role == .teacher }
    static func isReadOnly(_ u: Member) -> Bool { u.role == .viewer }

    /// v3.3: does this account teach (may edit) this circle?
    static func teaches(_ u: Member, _ circleId: String?, _ snap: CenterSnapshot) -> Bool {
        if u.role == .admin { return true }
        guard u.role == .teacher, let c = circleId else { return false }
        return snap.circle(c)?.teacherId == u.id
    }
    /// The circles this account may edit (all for the admin, his own for a teacher, none for the viewer).
    static func editableCircles(_ u: Member, _ snap: CenterSnapshot) -> [StudyCircle] {
        switch u.role {
        case .admin: return snap.circles.sorted { $0.name < $1.name }
        case .teacher: return snap.circles.filter { $0.teacherId == u.id }.sorted { $0.name < $1.name }
        default: return []
        }
    }

    /// Add a student (admin; a teacher into his own circle).
    static func canEditStudents(_ u: Member, _ snap: CenterSnapshot) -> Bool { !editableCircles(u, snap).isEmpty || u.role == .admin }
    static func canEditStudent(_ u: Member, _ s: Student, _ snap: CenterSnapshot) -> Bool { teaches(u, s.circleId, snap) }
    static func canRecordFor(_ u: Member, _ s: Student, _ snap: CenterSnapshot) -> Bool { teaches(u, s.circleId, snap) }
    static func canTakeAttendance(_ u: Member, _ circleId: String?, _ snap: CenterSnapshot) -> Bool { teaches(u, circleId, snap) }

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
