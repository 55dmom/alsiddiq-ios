import SwiftUI

enum Route: Hashable {
    case home, circles, students, reports, more, teacherMore, viewerSettings, recordStart, rewards, notifications
    case attendance(String?)
    case history(String?)
    case circle(String), circleEdit(String)
    case student(String), studentEdit(String, String?)
    case record(String)
    case announcements, announceNew, centerSettings, about
    case tools   // «الأدوات» tab: the same menu as the old header button
    case adminEvents, adminEvent(String)   // v3.6 the admin's bell
    case honors, honorPublish               // v3.7 «المتفوقون»
    case teacherAttendance, budget          // v3.8 admin only
    case subscriptions                      // v3.8 «كشف الاشتراكات» (admin + teachers)
    case passwords, teacherNames
    case circleReport(String)
    case roleLogin(Role)

    /// Parses the same route strings as the Android app (used by launch arguments in CI).
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
        case "teacher_more": return .teacherMore
        case "viewer_settings", "settings": return .viewerSettings
        case "record_start": return .recordStart
        case "rewards": return .rewards
        case "notifications": return .notifications
        case "attendance": return .attendance(arg)
        case "history": return .history(arg)
        case "circle": return arg.map { .circle($0) }
        case "circle_edit": return .circleEdit(arg ?? "new")
        case "student": return arg.map { .student($0) }
        case "student_edit": return .studentEdit(arg ?? "new", nil)
        case "record": return arg.map { .record($0) }
        case "announcements": return .announcements
        case "announce_new": return .announceNew
        case "center": return .centerSettings
        case "about": return .about
        case "tools": return .tools
        case "events": return .adminEvents
        case "event": return arg.map { .adminEvent($0) }
        case "honors": return .honors
        case "honor_publish": return .honorPublish
        case "teacher_attendance": return .teacherAttendance
        case "budget": return .budget
        case "subscriptions": return .subscriptions
        case "passwords": return .passwords
        case "teachers", "teacher_names": return .teacherNames
        case "circle_report": return .circleReport(arg ?? "")
        case "role_login": return .roleLogin(arg == "admin" ? .admin : .teacher)
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
    case .viewer: return [
        TabItem(route: .home, label: "الرئيسية", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill"),
        TabItem(route: .students, label: "الطلاب", icon: "graduationcap", selectedIcon: "graduationcap.fill"),
        TabItem(route: .circles, label: "الحلقات", icon: "person.3", selectedIcon: "person.3.fill"),
        TabItem(route: .reports, label: "التقارير", icon: "chart.bar.xaxis", selectedIcon: "chart.bar.fill"),
        TabItem(route: .tools, label: "الأدوات", icon: "square.grid.3x3", selectedIcon: "square.grid.3x3.fill"),
        TabItem(route: .viewerSettings, label: "الإعدادات", icon: "gearshape", selectedIcon: "gearshape.fill")
    ]
    case .admin: return [
        TabItem(route: .home, label: "الرئيسية", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill"),
        TabItem(route: .circles, label: "الحلقات", icon: "person.3", selectedIcon: "person.3.fill"),
        TabItem(route: .students, label: "الطلاب", icon: "graduationcap", selectedIcon: "graduationcap.fill"),
        TabItem(route: .reports, label: "التقارير", icon: "chart.bar.xaxis", selectedIcon: "chart.bar.fill"),
        TabItem(route: .tools, label: "الأدوات", icon: "square.grid.3x3", selectedIcon: "square.grid.3x3.fill"),
        TabItem(route: .more, label: "الإدارة", icon: "lock.shield", selectedIcon: "lock.shield.fill")
    ]
    case .teacher: return [
        TabItem(route: .home, label: "الرئيسية", icon: "house", selectedIcon: "house.fill"),
        TabItem(route: .circles, label: "الحلقات", icon: "person.3", selectedIcon: "person.3.fill"),
        TabItem(route: .recordStart, label: "تسجيل", icon: "plus.circle", selectedIcon: "plus.circle.fill"),
        TabItem(route: .attendance(nil), label: "الحضور", icon: "checklist", selectedIcon: "checklist"),
        TabItem(route: .teacherMore, label: "المزيد", icon: "circle.grid.2x2", selectedIcon: "circle.grid.2x2.fill"),
        TabItem(route: .tools, label: "الأدوات", icon: "square.grid.3x3", selectedIcon: "square.grid.3x3.fill")
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

    /// The signed-in member who was on the «الأدوات» tab: a theme picked there redraws the whole shell,
    /// and the new shell opens on the same tab instead of jumping back to the home tab.
    static var toolsTabUser: String?

    init(role: Role, userId: String? = nil) {
        tabs = tabsFor(role)
        if let u = userId, u == Router.toolsTabUser, let i = tabs.firstIndex(where: { $0.route == .tools }) { tab = i }
    }

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
