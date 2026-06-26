import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    // MARK: - Published state

    @Published var githubSnapshots: [UsageSnapshot] = []
    @Published var codexSnapshots: [UsageSnapshot] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var activeRefreshIntervalMinutes = UsageRefreshSchedule.defaultAutomaticIntervalMinutes
    @Published var nextRefreshAt: Date?

    // MARK: - Dependencies

    private let usageStore: UsageStore
    private let githubProvider: GitHubUsageProvider
    private let codexProvider: PrivateCodexUsageProvider
    private var periodicRefreshTask: Task<Void, Never>?
    private var periodicRefreshGeneration = 0
    private var automaticRefreshIntervalMinutes = UsageRefreshSchedule.defaultAutomaticIntervalMinutes

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

    deinit {
        periodicRefreshTask?.cancel()
    }

    // MARK: - Public

    func refresh() {
        Task {
            await refreshNow(shouldReschedulePeriodicRefresh: true)
        }
    }

    func refreshIfNeeded() {
        guard !isRefreshing else { return }
        let snapshots = githubSnapshots + codexSnapshots
        guard snapshots.isEmpty || snapshots.contains(where: \.isStale) else { return }
        Task {
            await refreshNow(shouldReschedulePeriodicRefresh: true)
        }
    }

    func startPeriodicRefresh() {
        periodicRefreshGeneration += 1
        let generation = periodicRefreshGeneration
        periodicRefreshTask?.cancel()
        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let intervalMinutes = self?.prepareNextScheduledRefresh(generation: generation) else { return }

                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(minutes: intervalMinutes))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                await self?.refreshNow(shouldReschedulePeriodicRefresh: false)
            }

            self?.clearNextScheduledRefresh(generation: generation)
        }
    }

    func restartPeriodicRefresh() {
        startPeriodicRefresh()
    }

    func stopPeriodicRefresh() {
        periodicRefreshGeneration += 1
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        nextRefreshAt = nil
    }

    var githubIsAuthenticated: Bool {
        get async { await githubProvider.isAuthenticated }
    }

    var codexIsAuthenticated: Bool {
        get async { await codexProvider.isAuthenticated }
    }

    // MARK: - Private

    private func loadFromStore() {
        githubSnapshots = usageStore.snapshots(for: .githubCopilot)
        codexSnapshots = usageStore.snapshots(for: .codex)
    }

    private func refreshNow(shouldReschedulePeriodicRefresh: Bool) async {
        guard !isRefreshing else { return }
        let previousSnapshots = usageStore.snapshots
        isRefreshing = true
        lastError = nil

        await refreshGitHub()
        await refreshCodex()

        let currentSnapshots = usageStore.snapshots
        automaticRefreshIntervalMinutes = UsageRefreshSchedule.automaticIntervalMinutes(
            previous: previousSnapshots,
            current: currentSnapshots
        )
        isRefreshing = false

        if shouldReschedulePeriodicRefresh,
           currentRefreshSetting.isAutomatic,
           periodicRefreshTask != nil {
            restartPeriodicRefresh()
        }
    }

    private func prepareNextScheduledRefresh(generation: Int) -> Int? {
        guard generation == periodicRefreshGeneration else { return nil }
        let intervalMinutes = UsageRefreshSchedule.intervalMinutes(
            for: currentRefreshSetting,
            automaticIntervalMinutes: automaticRefreshIntervalMinutes
        )
        activeRefreshIntervalMinutes = intervalMinutes
        nextRefreshAt = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
        return intervalMinutes
    }

    private func clearNextScheduledRefresh(generation: Int) {
        guard generation == periodicRefreshGeneration else { return }
        nextRefreshAt = nil
    }

    private var currentRefreshSetting: UsageRefreshSetting {
        UsageRefreshSetting(
            storedValue: UserDefaults.standard.object(forKey: UsageRefreshSetting.storageKey) as? Int
        )
    }

    private static func nanoseconds(minutes: Int) -> UInt64 {
        UInt64(minutes) * 60 * 1_000_000_000
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
