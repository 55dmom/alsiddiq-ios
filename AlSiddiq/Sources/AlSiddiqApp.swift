import SwiftUI

@main
struct AlSiddiqApp: App {
    @StateObject private var model: AppModel

    init() {
        AppFont.register()
        UIView.appearance().semanticContentAttribute = .forceRightToLeft
        UIScrollView.appearance().keyboardDismissMode = .interactive
        let repo: AppRepository
        let cfg = CloudConfig.fromBundle()
        // Build 1: demo data only. The central database plugs in here once its config is in the build.
        repo = DemoRepository()
        _model = StateObject(wrappedValue: AppModel(repo: repo, cloudConfigured: cfg != nil))
    }

    var body: some Scene {
        WindowGroup {
            RootView(autoLogin: UserDefaults.standard.string(forKey: "autoLogin"),
                     startRoute: UserDefaults.standard.string(forKey: "startRoute"))
                .environmentObject(model)
        }
    }
}
