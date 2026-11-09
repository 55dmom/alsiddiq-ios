import SwiftUI
import BackgroundTasks

@main
struct AlSiddiqApp: App {
    @StateObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    static let refreshTask = "com.alsiddiq.app.refresh"

    init() {
        AppFont.register()
        UIView.appearance().semanticContentAttribute = .forceRightToLeft
        UIScrollView.appearance().keyboardDismissMode = .interactive
        let cfg = CloudConfig.fromBundle()
        let repo: AppRepository
        // The central database is used whenever its address is in the build; "-forceDemo YES" keeps sample data (screenshots).
        if let cfg = cfg, !UserDefaults.standard.bool(forKey: "forceDemo") {
            let cloud = CloudRepository(config: cfg)
            repo = cloud
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTask, using: nil) { task in
                Task { @MainActor in
                    let fresh = await cloud.fetchNewNotifications()
                    Notifier.post(fresh)
                    task.setTaskCompleted(success: true)
                    AlSiddiqApp.scheduleRefresh()
                }
            }
        } else {
            repo = DemoRepository()
        }
        _model = StateObject(wrappedValue: AppModel(repo: repo, cloudConfigured: cfg != nil))
    }

    /// Ask iOS to wake the app now and then to check for new notifications (absences, hifz, announcements).
    static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTask)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    var body: some Scene {
        WindowGroup {
            RootView(autoLogin: UserDefaults.standard.string(forKey: "autoLogin"),
                     startRoute: UserDefaults.standard.string(forKey: "startRoute"))
                .environmentObject(model)
        }
        .onChange(of: phase) { p in
            if p == .background && !model.isDemo && model.user != nil { AlSiddiqApp.scheduleRefresh() }
            if p == .active && !model.isDemo { Task { try? await model.repo.refresh(); model.pull() } }
        }
    }
}
