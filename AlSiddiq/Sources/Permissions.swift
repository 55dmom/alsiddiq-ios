import Foundation

/// Client-side mirror of the server's Row Level Security rules. The server is the
/// authority; this only decides what the UI offers and what the demo store accepts.
enum Permissions {
    static func canManageCenter(_ u: Member) -> Bool { u.role == .admin }
    static func canManageMembers(_ u: Member) -> Bool { u.role == .admin }
    static func canManageCircles(_ u: Member) -> Bool { u.role == .admin }
    static func canManageStudents(_ u: Member) -> Bool { u.role == .admin }
    static func canPostAnnouncement(_ u: Member) -> Bool { u.role == .admin || u.role == .teacher }

    static func teachesCircle(_ u: Member, _ c: StudyCircle?) -> Bool {
        guard let c = c else { return false }
        return u.role == .teacher && c.teacherId == u.id
    }

    static func canRecordFor(_ u: Member, _ s: Student, _ snap: CenterSnapshot) -> Bool {
        switch u.role {
        case .admin: return true
        case .teacher: return teachesCircle(u, snap.circle(s.circleId))
        default: return false
        }
    }

    static func canSeeStudent(_ u: Member, _ s: Student, _ snap: CenterSnapshot) -> Bool {
        switch u.role {
        case .admin: return true
        case .teacher: return teachesCircle(u, snap.circle(s.circleId))
        case .student: return u.studentId == s.id
        case .parent: return u.childIds.contains(s.id)
        }
    }

    static func visibleStudents(_ u: Member, _ snap: CenterSnapshot) -> [Student] {
        snap.students.filter { canSeeStudent(u, $0, snap) }.sorted { $0.fullName < $1.fullName }
    }

    static func visibleCircles(_ u: Member, _ snap: CenterSnapshot) -> [StudyCircle] {
        let list: [StudyCircle]
        switch u.role {
        case .admin: list = snap.circles
        case .teacher: list = snap.circles.filter { $0.teacherId == u.id }
        case .student: list = snap.circles.filter { c in snap.student(u.studentId)?.circleId == c.id }
        case .parent: list = snap.circles.filter { c in u.childIds.contains { snap.student($0)?.circleId == c.id } }
        }
        return list.sorted { $0.name < $1.name }
    }

    static func audienceIncludes(_ a: Audience, _ role: Role) -> Bool {
        switch a {
        case .all: return true
        case .teachers: return role == .teacher || role == .admin
        case .parents: return role == .parent || role == .admin
        case .students: return role == .student || role == .admin
        }
    }
}
