import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var dialogs = DialogHost()
    @State private var splash = true
    let autoLogin: String?
    let startRoute: String?

    var body: some View {
        ZStack {
            Group {
                if splash {
                    SplashView().transition(.opacity).onAppear { StatusBar.set(light: false) }
                } else if let user = model.user {
                    MainShell(user: user, startRoute: autoLogin != nil ? startRoute : nil)
                        .id(user.id)
                        .transition(.opacity)
                } else {
                    LoginView().transition(.opacity).onAppear { StatusBar.set(light: true) }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: splash)
            .animation(.easeInOut(duration: 0.35), value: model.user?.id)

            if let d = dialogs.content {
                Color.black.opacity(0.32).ignoresSafeArea()
                    .onTapGesture { dialogs.dismiss() }
                    .transition(.opacity)
                d.transition(.scale(scale: 0.94).combined(with: .opacity))
                    .zIndex(2)
            }
            if let t = model.toast {
                VStack { Spacer(); ToastView(text: t).padding(.bottom, model.user == nil ? 24 : 92) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
                    .allowsHitTesting(false)
            }
        }
        .environmentObject(dialogs)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .preferredColorScheme(.light)
        .task {
            await handleAutoLogin()
            try? await Task.sleep(nanoseconds: autoLogin == nil ? 900_000_000 : 300_000_000)
            withAnimation { splash = false }
        }
    }

    private func handleAutoLogin() async {
        guard let who = autoLogin else { return }
        if who == "login" || who == "none" {
            if model.user != nil { await model.repo.signOut(); model.pull() }
            return
        }
        let phone: String?
        switch who {
        case "admin": phone = DemoSeed.adminPhone
        case "teacher": phone = DemoSeed.teacherPhone
        case "student": phone = DemoSeed.studentPhone
        case "parent": phone = DemoSeed.parentPhone
        default: phone = nil
        }
        guard model.isDemo, let p = phone else { return }
        if model.user?.phone != p { _ = try? await model.repo.signIn(login: p, password: DemoSeed.demoPassword) }
        model.pull()
    }
}

enum StatusBar {
    /// White status-bar text over the navy headers, dark text over light screens.
    static func set(light: Bool) {
        UIApplication.shared.setStatusBarStyle(light ? .lightContent : .darkContent, animated: true)
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("Logo").resizable().scaledToFit().frame(width: 180, height: 180)
            ProgressView().tint(Brand.navy).scaleEffect(1.1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
    }
}

struct MainShell: View {
    let user: Member
    let startRoute: String?
    @StateObject private var router: Router
    @EnvironmentObject var model: AppModel

    init(user: Member, startRoute: String?) {
        self.user = user
        self.startRoute = startRoute
        _router = StateObject(wrappedValue: Router(role: user.role))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                screen(for: router.tabs[router.tab].route)
                    .environment(\.canGoBack, false)
                    .id("tab\(router.tab)")
                    .transition(.opacity)
                ForEach(Array(router.stack.enumerated()), id: \.offset) { i, r in
                    screen(for: r)
                        .environment(\.canGoBack, true)
                        .background(Brand.bg.ignoresSafeArea())
                        .overlay(alignment: .leading) { if i == router.stack.count - 1 { EdgeSwipeBack() } }
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.985)),
                                                removal: .opacity.combined(with: .scale(scale: 0.985))))
                        .zIndex(Double(i + 1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if router.showBar {
                BottomBar(tabs: router.tabs, selected: router.tab, unread: model.snap.unreadCount) { router.select($0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Brand.bg.ignoresSafeArea())
        .environmentObject(router)
        .onChange(of: router.stack.count) { _ in updateStatusBar() }
        .onChange(of: router.tab) { _ in updateStatusBar() }
        .onAppear {
            updateStatusBar()
            if let s = startRoute, s != "home", let r = Route.parse(s) {
                Task { @MainActor in try? await Task.sleep(nanoseconds: 200_000_000); router.go(r) }
            }
        }
    }

    private func updateStatusBar() {
        StatusBar.set(light: router.stack.isEmpty && router.tabs[router.tab].route == .home)
    }

    @ViewBuilder
    private func screen(for r: Route) -> some View {
        switch r {
        case .home:
            switch user.role {
            case .admin: AdminHome(user: user)
            case .teacher: TeacherHome(user: user)
            case .student: StudentHome(user: user)
            case .parent: ParentHome(user: user)
            }
        case .circles: CirclesScreen(user: user)
        case .students: StudentsScreen(user: user)
        case .reports: ReportsScreen(user: user)
        case .more: MoreScreen(user: user)
        case .recordStart: RecordStartScreen(user: user)
        case .attendance(let cid): AttendanceScreen(user: user, circleId: cid)
        case .profile: ProfileScreen(user: user)
        case .history(let sid): HistoryScreen(user: user, studentId: sid ?? user.studentId)
        case .rewards: RewardsScreen(user: user)
        case .notifications: NotificationsScreen(user: user)
        case .circle(let id): CircleDetailScreen(user: user, id: id)
        case .circleEdit(let id): CircleEditScreen(user: user, id: id)
        case .student(let id): StudentDetailScreen(user: user, id: id)
        case .studentEdit(let id, let c): StudentEditScreen(user: user, id: id, presetCircle: c)
        case .record(let sid): RecordScreen(user: user, studentId: sid).id("record-" + sid)
        case .members(let role): MembersScreen(user: user, role: role)
        case .memberEdit(let role, let id): MemberEditScreen(user: user, role: role, id: id)
        case .announcements: AnnouncementsScreen(user: user)
        case .announceNew: AnnounceNewScreen(user: user)
        case .settings: CenterSettingsScreen(user: user)
        case .about: AboutScreen()
        }
    }
}

/// Swipe from the screen edge to go back (the right edge in Arabic).
struct EdgeSwipeBack: View {
    @EnvironmentObject var router: Router
    var body: some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12).onEnded { v in
                if abs(v.translation.width) > 70 && abs(v.translation.height) < 120 { router.back() }
            })
    }
}

struct BottomBar: View {
    let tabs: [TabItem]
    let selected: Int
    let unread: Int
    let onSelect: (Int) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, t in
                let sel = i == selected
                Button { onSelect(i) } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: sel ? t.selectedIcon : t.icon)
                                .font(.system(size: 19, weight: sel ? .semibold : .regular))
                                .foregroundColor(sel ? Brand.navy : Brand.muted)
                                .frame(width: 60, height: 30)
                                .background(Capsule().fill(sel ? Brand.navySoft : Color.clear))
                            if t.route == .notifications && unread > 0 {
                                Text("\(unread)").font(AppFont.f(10, .bold)).foregroundColor(.white)
                                    .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
                                    .background(Capsule().fill(Brand.maroon))
                                    .offset(x: -6, y: -2)
                            }
                        }
                        Text(t.label).font(T.labelSmall).foregroundColor(sel ? Brand.navy : Brand.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.2), value: sel)
            }
        }
        .padding(.top, 10).padding(.bottom, 6)
        .background(Color.white.ignoresSafeArea(edges: .bottom).shadow(color: Brand.navy.opacity(0.06), radius: 8, x: 0, y: -2))
    }
}
