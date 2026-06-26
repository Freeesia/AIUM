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
    private let refreshService: UsageRefreshService
    private var periodicRefreshTask: Task<Void, Never>?
    private var periodicRefreshGeneration = 0
    private var automaticRefreshIntervalMinutes = UsageRefreshSchedule.defaultAutomaticIntervalMinutes

    // MARK: - Init

    init(
        usageStore: UsageStore? = nil,
        githubProvider: GitHubUsageProvider = GitHubUsageProvider(),
        codexProvider: PrivateCodexUsageProvider = PrivateCodexUsageProvider()
    ) {
        let resolvedUsageStore = usageStore ?? .shared
        self.usageStore = resolvedUsageStore
        self.githubProvider = githubProvider
        self.codexProvider = codexProvider
        self.refreshService = UsageRefreshService(
            usageStore: resolvedUsageStore,
            githubProvider: githubProvider,
            codexProvider: codexProvider
        )
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
        isRefreshing = true
        lastError = nil

        let result = await refreshService.refreshUsage()
        loadFromStore()
        automaticRefreshIntervalMinutes = result.automaticIntervalMinutes
        lastError = result.errorMessage
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
        UsageRefreshSchedule.refreshSetting()
    }

    private static func nanoseconds(minutes: Int) -> UInt64 {
        UInt64(minutes) * 60 * 1_000_000_000
    }
}
