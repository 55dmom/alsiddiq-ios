import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var dialogs = DialogHost()
    @StateObject private var tools = ToolsHost()
    @ObservedObject private var theme = ThemeStore.shared
    @State private var greeting: OccasionTheme?
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
            .id(theme.active.id)   // a theme change redraws everything in the new colours
            .animation(.easeInOut(duration: 0.35), value: splash)
            .animation(.easeInOut(duration: 0.35), value: model.user?.id)

            if let d = dialogs.content {
                Color.black.opacity(0.32).ignoresSafeArea()
                    .onTapGesture { dialogs.dismiss() }
                    .transition(.opacity)
                d.transition(.scale(scale: 0.94).combined(with: .opacity))
                    .zIndex(2)
            }
            if let g = greeting, !splash {
                OccasionGreeting(occasion: g) { withAnimation(.easeOut(duration: 0.25)) { greeting = nil } }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .zIndex(4)
            }
            if let t = model.toast {
                VStack { Spacer(); ToastView(text: t).padding(.bottom, model.user == nil ? 24 : 92) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
                    .allowsHitTesting(false)
            }
        }
        .environmentObject(dialogs)
        .environmentObject(tools)
        .sheet(isPresented: $tools.open) { ToolsSheet().environmentObject(tools).environmentObject(model) }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .preferredColorScheme(theme.active.palette.dark ? .dark : .light)
        .task {
            await handleAutoLogin()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "selfTest") {
                let tries = UserDefaults.standard.string(forKey: "tryStudents") ?? ""
                Task { await SelfTest.run(model, tries: tries) }
            }
            #endif
            let hold = UserDefaults.standard.double(forKey: "holdSplash") // CI screenshots of the splash
            try? await Task.sleep(nanoseconds: hold > 0 ? UInt64(hold * 1e9) : (autoLogin == nil ? 1_800_000_000 : 300_000_000))
            withAnimation { splash = false }
            if let o = theme.occasion, o.card != nil, OccasionGreeting.shouldShow(o) {
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { greeting = o }
                OccasionGreeting.markShown(o)
            }
            if let t = UserDefaults.standard.string(forKey: "openTool") { // CI screenshots
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                tools.show(ToolItem(rawValue: t))
            }
        }
    }

    /// CI only: "-ciLogin admin|teacher|viewer" with "-ciPass" (and "-ciViewerPass" kept underneath); demo passwords when omitted.
    private func handleAutoLogin() async {
        guard let who = autoLogin else { return }
        if who == "login" || who == "none" {
            if model.user != nil { await model.repo.signOut(); model.pull() }
            return
        }
        let d = UserDefaults.standard
        let kind: Role? = who == "admin" ? .admin : (who == "teacher" ? .teacher : (who == "viewer" ? .viewer : nil))
        guard let k = kind else { return }
        let pass = d.string(forKey: "ciPass") ?? (k == .admin ? DemoSeed.adminPassword : (k == .teacher ? DemoSeed.teacherPassword : DemoSeed.viewerPassword))
        let viewerPass = d.string(forKey: "ciViewerPass") ?? DemoSeed.viewerPassword
        if model.user?.role == k { return }
        await model.repo.signOut()
        if k != .viewer {
            if (try? await model.repo.signIn(password: viewerPass, kind: nil)) == nil { NSLog("ALSIDDIQ_CI viewer sign-in failed") }
            do { _ = try await model.repo.signIn(password: pass, kind: k) } catch { NSLog("ALSIDDIQ_CI sign-in \(who) failed: \(error.localizedDescription)") }
        } else {
            do { _ = try await model.repo.signIn(password: pass, kind: nil) } catch { NSLog("ALSIDDIQ_CI viewer failed: \(error.localizedDescription)") }
        }
        model.pull()
    }
}

enum StatusBar {
    /// White status-bar text over the navy headers, dark text over light screens.
    static func set(light: Bool) {
        UIApplication.shared.setStatusBarStyle(light ? .lightContent : .darkContent, animated: true)
    }
}

/// Animated splash: the ORIGINAL logo (never redrawn) rises in, a gold glow breathes behind it
/// like light from the dome, then the welcome line.
struct SplashView: View {
    @State private var appear = false
    @State private var glow = false
    @State private var line = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.white, Brand.goldSoft.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    RadialGradient(colors: [Brand.gold.opacity(glow ? 0.55 : 0.18), Brand.gold.opacity(0)], center: .center, startRadius: 10, endRadius: glow ? 150 : 90)
                        .frame(width: 320, height: 320)
                    Image("Logo").resizable().scaledToFit().frame(width: 190, height: 190)
                        .scaleEffect(appear ? 1 : 0.82)
                        .opacity(appear ? 1 : 0)
                }
                .frame(height: 260)
                VStack(spacing: 6) {
                    Text("أهلاً بكم في مركز الصديق").font(T.headlineSmall).foregroundColor(Brand.navy)
                    Text("«خيركم من تعلّم القرآن وعلّمه»").font(T.bodyLarge).foregroundColor(Brand.maroon)
                }
                .opacity(line ? 1 : 0)
                .offset(y: line ? 0 : 12)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { appear = true }
            withAnimation(.easeInOut(duration: 1.1).delay(0.25).repeatForever(autoreverses: true)) { glow = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.55)) { line = true }
        }
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
        let top = router.stack.last
        var light = router.stack.isEmpty && router.tabs[router.tab].route == .home
        if case .roleLogin? = top { light = true }
        StatusBar.set(light: light)
    }

    @ViewBuilder
    private func screen(for r: Route) -> some View {
        switch r {
        case .home:
            switch user.role {
            case .admin: AdminHome(user: user)
            case .teacher: TeacherHome(user: user)
            case .viewer: ViewerHome(user: user)
            }
        case .circles: CirclesScreen(user: user)
        case .students: StudentsScreen(user: user)
        case .reports: ReportsScreen(user: user)
        case .more: MoreScreen(user: user)
        case .teacherMore: TeacherMoreScreen(user: user)
        case .viewerSettings: ViewerSettingsScreen(user: user)
        case .recordStart: RecordStartScreen(user: user)
        case .attendance(let cid): AttendanceScreen(user: user, circleId: cid)
        case .history(let sid): HistoryScreen(user: user, studentId: sid ?? "")
        case .rewards: RewardsScreen(user: user)
        case .notifications: NotificationsScreen(user: user)
        case .circle(let id): CircleDetailScreen(user: user, id: id)
        case .circleEdit(let id): CircleEditScreen(user: user, id: id)
        case .student(let id): StudentDetailScreen(user: user, id: id)
        case .studentEdit(let id, let c): StudentEditScreen(user: user, id: id, presetCircle: c)
        case .record(let sid): RecordScreen(user: user, studentId: sid).id("record-" + sid)
        case .announcements: AnnouncementsScreen(user: user)
        case .announceNew: AnnounceNewScreen(user: user)
        case .centerSettings: CenterSettingsScreen(user: user)
        case .about: AboutScreen()
        case .passwords: PasswordsScreen(user: user)
        case .teacherNames: TeacherNamesScreen(user: user)
        case .circleReport(let cid): CircleReportScreen(user: user, circleId: cid)
        case .roleLogin(let k): RoleLoginView(kind: k) { router.back() }
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
