import SwiftUI

/// Bridges the repository to SwiftUI and owns app-wide UI state (toast, navigation).
@MainActor
final class AppModel: ObservableObject {
    let repo: AppRepository
    @Published private(set) var user: Member?
    @Published private(set) var baseUser: Member?
    @Published private(set) var centerName: String = ""
    @Published private(set) var snap = CenterSnapshot()
    @Published private(set) var sync: SyncState = .localOnly
    @Published var toast: String?
    let cloudConfigured: Bool
    private var toastTask: Task<Void, Never>?

    init(repo: AppRepository, cloudConfigured: Bool) {
        self.repo = repo
        self.cloudConfigured = cloudConfigured
        repo.onChange = { [weak self] in self?.pull() }
        pull()
    }

    var isDemo: Bool { repo.mode == .demo }

    func pull() {
        if user != repo.currentUser { user = repo.currentUser }
        if baseUser != repo.baseUser { baseUser = repo.baseUser }
        let cn = repo.centerName.isEmpty ? snap.center.name : repo.centerName
        if centerName != cn { centerName = cn }
        if snap != repo.snapshot { snap = repo.snapshot }
        if sync != repo.syncState { sync = repo.syncState }
    }

    func say(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    /// Runs a repository call, shows its success or error message, then continues.
    func run<T>(_ ok: String?, _ block: @escaping () async throws -> T) {
        run(ok, block, onError: nil, then: { _ in })
    }

    func run<T>(_ ok: String?, _ block: @escaping () async throws -> T, onError: (() -> Void)? = nil, then: @escaping (T) -> Void) {
        Task {
            do {
                let v = try await block()
                pull()
                if let ok = ok { say(ok) }
                then(v)
            } catch {
                onError?()
                say((error as? LocalizedError)?.errorDescription ?? "حدث خطأ، حاول مرة أخرى")
            }
        }
    }
}
