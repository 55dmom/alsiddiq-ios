import SwiftUI

enum Route: Hashable {
    case home, circles, students, reports, more, recordStart, profile, rewards, notifications
    case attendance(String?)
    case history(String?)
    case circle(String), circleEdit(String)
    case student(String), studentEdit(String, String?)
    case record(String)
    case members(Role), memberEdit(Role, String)
    case announcements, announceNew, settings, about

    /// Parses the same route strings as the Android app (used by launch arguments).
    static func parse(_ s: String) -> Route? {
        let parts = s.split(separator: "/", maxSplits: 1).map(String.init)
        let head = parts.first ?? ""
        let arg = parts.count > 1 ? parts[1] : nil
        switch head {
        case "home": return .home
        case "circles": return .circles
        case "students": return .students
        case "reports": return .reports
        case "more": return .more
        case "record_start": return .recordStart
        case "profile": return .profile
        case "rewards": return .rewards
        case "notifications": return .notifications
        case "attendance": return .attendance(arg)
        case "history": return .history(arg)
        case "circle": return arg.map { .circle($0) }
        case "circle_edit": return .circleEdit(arg ?? "new")
        case "student": return arg.map { .student($0) }
        case "student_edit": return .studentEdit(arg ?? "new", nil)
        case "record": return arg.map { .record($0) }
        case "members": return .members(Role(rawValue: arg ?? "TEACHER") ?? .teacher)
        case "announcements": return .announcements
        case "announce_new": return .announceNew
        case "settings": return .settings
        case "about": return .about
        default: return nil
        }
    }
}

struct TabItem {
    let route: Route
    let label: String
    let icon: String
    let selectedIcon: String
}

func tabsFor(_ role: Role) -> [TabItem] {
    switch role {
    case .admin: return [
        TabItem(route: .home, label: "الرئيسية", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill"),
        TabItem(route: .circles, label: "الحلقات", icon: "person.3", selectedIcon: "person.3.fill"),
        TabItem(route: .students, label: "الطلاب", icon: "graduationcap", selectedIcon: "graduationcap.fill"),
        TabItem(route: .reports, label: "التقارير", icon: "chart.bar.xaxis", selectedIcon: "chart.bar.fill"),
        TabItem(route: .more, label: "المزيد", icon: "circle.grid.2x2", selectedIcon: "circle.grid.2x2.fill")
    ]
    case .teacher: return [
        TabItem(route: .home, label: "الرئيسية", icon: "house", selectedIcon: "house.fill"),
        TabItem(route: .circles, label: "حلقاتي", icon: "person.3", selectedIcon: "person.3.fill"),
        TabItem(route: .recordStart, label: "تسجيل", icon: "plus.circle", selectedIcon: "plus.circle.fill"),
        TabItem(route: .attendance(nil), label: "الحضور", icon: "checklist", selectedIcon: "checklist"),
        TabItem(route: .profile, label: "حسابي", icon: "person", selectedIcon: "person.fill")
    ]
    case .student: return [
        TabItem(route: .home, label: "الرئيسية", icon: "house", selectedIcon: "house.fill"),
        TabItem(route: .history(nil), label: "سجلّي", icon: "book", selectedIcon: "book.fill"),
        TabItem(route: .rewards, label: "المكافآت", icon: "trophy", selectedIcon: "trophy.fill"),
        TabItem(route: .notifications, label: "الإشعارات", icon: "bell", selectedIcon: "bell.fill"),
        TabItem(route: .profile, label: "حسابي", icon: "person", selectedIcon: "person.fill")
    ]
    case .parent: return [
        TabItem(route: .home, label: "أبنائي", icon: "figure.2.and.child.holdinghands", selectedIcon: "figure.2.and.child.holdinghands"),
        TabItem(route: .reports, label: "التقارير", icon: "chart.bar.xaxis", selectedIcon: "chart.bar.fill"),
        TabItem(route: .attendance(nil), label: "الحضور", icon: "calendar.badge.clock", selectedIcon: "calendar.badge.clock"),
        TabItem(route: .notifications, label: "الإشعارات", icon: "bell", selectedIcon: "bell.fill"),
        TabItem(route: .profile, label: "حسابي", icon: "person", selectedIcon: "person.fill")
    ]
    }
}

/// One stack per signed-in session, like the Android NavHost: tab roots show the bottom bar,
/// everything pushed on top hides it.
@MainActor
final class Router: ObservableObject {
    let tabs: [TabItem]
    @Published var tab = 0
    @Published var stack: [Route] = []

    init(role: Role) { tabs = tabsFor(role) }

    var current: Route { stack.last ?? tabs[tab].route }
    var showBar: Bool { stack.isEmpty }

    func go(_ r: Route) {
        if let i = tabs.firstIndex(where: { $0.route == r }) {
            withAnimation(.easeOut(duration: 0.24)) { tab = i; stack = [] }
        } else {
            withAnimation(.easeOut(duration: 0.24)) { stack.append(r) }
        }
    }

    func back() {
        guard !stack.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.22)) { _ = stack.removeLast() }
    }

    /// Replace the top screen (used by "save and go to the next student").
    func replaceTop(_ r: Route) {
        withAnimation(.easeOut(duration: 0.24)) {
            if !stack.isEmpty { stack.removeLast() }
            stack.append(r)
        }
    }

    /// Pop back to a tab root (used after deleting the thing a screen showed).
    func popToRoot() { withAnimation(.easeOut(duration: 0.22)) { stack = [] } }

    func select(_ i: Int) {
        guard i != tab || !stack.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) { tab = i; stack = [] }
    }
}

/// App-wide modal host so dialogs look and behave like the Android ones on iOS 15.
@MainActor
final class DialogHost: ObservableObject {
    @Published var content: AnyView?
    func show<V: View>(_ v: V) { withAnimation(.easeOut(duration: 0.18)) { content = AnyView(v) } }
    func dismiss() { withAnimation(.easeIn(duration: 0.15)) { content = nil } }
}
