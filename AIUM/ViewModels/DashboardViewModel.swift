import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    // MARK: - Published state

    @Published var githubSnapshots: [UsageSnapshot] = []
    @Published var codexSnapshots: [UsageSnapshot] = []
    @Published var isRefreshing = false
    @Published var lastError: String?

    // MARK: - Dependencies

    private let usageStore: UsageStore
    private let githubProvider: GitHubUsageProvider
    private let codexProvider: PrivateCodexUsageProvider

    // MARK: - Init

    init(
        usageStore: UsageStore? = nil,
        githubProvider: GitHubUsageProvider = GitHubUsageProvider(),
        codexProvider: PrivateCodexUsageProvider = PrivateCodexUsageProvider()
    ) {
        self.usageStore = usageStore ?? .shared
        self.githubProvider = githubProvider
        self.codexProvider = codexProvider
        loadFromStore()
    }

    // MARK: - Public

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil

        Task {
            await refreshGitHub()
            await refreshCodex()
            isRefreshing = false
        }
    }

    var githubIsAuthenticated: Bool {
        get async { await githubProvider.isAuthenticated }
    }

    var codexIsAuthenticated: Bool {
        get async { await codexProvider.isAuthenticated }
    }

    #if DEBUG
    func debugRefreshGitHubOnly() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil

        Task {
            await refreshGitHub()
            isRefreshing = false
        }
    }
    #endif

    // MARK: - Private

    private func loadFromStore() {
        githubSnapshots = usageStore.snapshots(for: .githubCopilot)
        codexSnapshots = usageStore.snapshots(for: .codex)
    }

    private func refreshGitHub() async {
        do {
            guard await githubProvider.isAuthenticated else { return }
            let snapshots = try await githubProvider.fetchUsage()
            usageStore.replace(provider: .githubCopilot, with: snapshots)
            githubSnapshots = usageStore.snapshots(for: .githubCopilot)
        } catch {
            let errSnapshot = UsageSnapshot.error(provider: .githubCopilot, message: error.localizedDescription)
            usageStore.upsert(errSnapshot)
            githubSnapshots = usageStore.snapshots(for: .githubCopilot)
            lastError = error.localizedDescription
        }
    }

    private func refreshCodex() async {
        do {
            guard await codexProvider.isAuthenticated else { return }
            let snapshots = try await codexProvider.fetchUsage()
            usageStore.replace(provider: .codex, with: snapshots)
            codexSnapshots = usageStore.snapshots(for: .codex)
        } catch {
            let errSnapshot = UsageSnapshot.error(provider: .codex, message: error.localizedDescription)
            usageStore.upsert(errSnapshot)
            codexSnapshots = usageStore.snapshots(for: .codex)
            lastError = (lastError.map { $0 + "\n" } ?? "") + error.localizedDescription
        }
    }
}
