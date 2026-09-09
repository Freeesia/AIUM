import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    // MARK: - Published state

    @Published var githubSnapshots: [UsageSnapshot] = []
    @Published var codexSnapshots: [UsageSnapshot] = []
    @Published private(set) var isResettingCodexUsage = false
    @Published private(set) var codexResetError: String?
    @Published private(set) var codexResetOutcome: CodexUsageResetOutcome?
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var activeRefreshIntervalMinutes = UsageRefreshSchedule.defaultAutomaticIntervalMinutes
    @Published var nextRefreshAt: Date?
    @Published var isDemoMode = false

    // MARK: - Dependencies

    private let usageStore: UsageStore
    private let refreshService: UsageRefreshService
    private let demoModeStore: DemoModeStore
    private let githubProvider: GitHubUsageProvider
    private let codexProvider: PrivateCodexUsageProvider
    private let resetRequestStore: CodexResetRequestStore
    private var periodicRefreshTask: Task<Void, Never>?
    private var periodicRefreshGeneration = 0
    private var automaticRefreshIntervalMinutes = UsageRefreshSchedule.storedAutomaticIntervalMinutes()

    // MARK: - Init

    init(
        usageStore: UsageStore? = nil,
        demoModeStore: DemoModeStore = DemoModeStore(),
        githubProvider: GitHubUsageProvider = GitHubUsageProvider(),
        codexProvider: PrivateCodexUsageProvider = PrivateCodexUsageProvider(),
        resetRequestStore: CodexResetRequestStore? = nil
    ) {
        let resolvedUsageStore = usageStore ?? .shared
        self.usageStore = resolvedUsageStore
        self.demoModeStore = demoModeStore
        self.githubProvider = githubProvider
        self.codexProvider = codexProvider
        self.resetRequestStore = resetRequestStore ?? CodexResetRequestStore()
        self.refreshService = UsageRefreshService(
            usageStore: resolvedUsageStore,
            resolver: AppUsageProviderResolver(
                demoModeStore: demoModeStore,
                githubProvider: githubProvider,
                codexProvider: codexProvider
            )
        )
        loadFromStore()
    }

    deinit {
        periodicRefreshTask?.cancel()
    }

    // MARK: - Public

    var codexResetCredits: Int? {
        guard let snapshot = UsageSnapshot.displaySnapshot(from: codexSnapshots, for: .codex),
              snapshot.errorMessage == nil,
              let value = snapshot.resetCredits,
              let count = Int(exactly: value), count > 0 else { return nil }
        return count
    }

    func prepareCodexUsageReset() async -> CodexUsageResetConfirmation? {
        guard !isDemoMode, !demoModeStore.isEnabled,
              !isRefreshing, !isResettingCodexUsage,
              let remainingCount = codexResetCredits else { return nil }
        let identity = await codexProvider.accountIdentity
        guard !isRefreshing, !isResettingCodexUsage else { return nil }
        guard let accountId = identity.accountId,
              codexSnapshots.contains(where: { $0.accountId == accountId }) else {
            lastError = String(localized: "Refresh Codex usage before resetting it.")
            return nil
        }
        codexResetError = nil
        codexResetOutcome = nil
        return CodexUsageResetConfirmation(
            accountId: accountId,
            accountDisplayName: identity.profileName,
            remainingCount: remainingCount
        )
    }

    func resetCodexUsage(_ confirmation: CodexUsageResetConfirmation) async {
        guard !isResettingCodexUsage, !isRefreshing, codexResetOutcome == nil,
              !isDemoMode, !demoModeStore.isEnabled else { return }
        isResettingCodexUsage = true
        codexResetError = nil
        lastError = nil
        defer { isResettingCodexUsage = false }

        let requestID = resetRequestStore.requestID(for: confirmation.accountId)
        do {
            let outcome = try await codexProvider.resetUsage(
                requestID: requestID,
                accountId: confirmation.accountId
            )
            resetRequestStore.clear(for: confirmation.accountId)
            codexResetOutcome = outcome

            // The old limits and credit count no longer describe the account.
            // A refresh failure must not turn a completed reset into a retry.
            usageStore.clear(provider: .codex)
            loadFromStore()
            do {
                let snapshots = try await codexProvider.fetchUsage()
                usageStore.replace(provider: .codex, with: snapshots)
                loadFromStore()
            } catch {
                lastError = String(localized: "Could not refresh usage. Close this sheet and refresh the dashboard.")
            }
        } catch let error as CodexUsageResetError {
            codexResetError = error.localizedDescription
        } catch {
            codexResetError = String(localized: "Could not confirm the reset. Retry to check the same request without using an additional reset.")
        }
    }

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
        get async {
            if isDemoMode { return true }
            return await githubProvider.isAuthenticated
        }
    }

    var codexIsAuthenticated: Bool {
        get async {
            if isDemoMode { return true }
            return await codexProvider.isAuthenticated
        }
    }

    /// Reads the current demo mode flag and applies any state changes needed.
    func reloadDemoMode() {
        let wasEnabled = isDemoMode
        let isEnabled = demoModeStore.isEnabled
        isDemoMode = isEnabled

        if !wasEnabled && isEnabled {
            // Demo mode turned ON: populate store with demo snapshots
            let now = Date()
            usageStore.replace(
                provider: .githubCopilot,
                with: DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
            )
            usageStore.replace(
                provider: .codex,
                with: DemoUsageDataFactory.snapshots(for: .codex, now: now)
            )
            loadFromStore()
        } else if wasEnabled && !isEnabled {
            // Demo mode turned OFF: clear the demo cache
            usageStore.clear(provider: .githubCopilot)
            usageStore.clear(provider: .codex)
            loadFromStore()
        }
    }

    // MARK: - Private

    private func loadFromStore() {
        githubSnapshots = usageStore.snapshots(for: .githubCopilot)
        codexSnapshots = usageStore.snapshots(for: .codex)
    }

    private func refreshNow(shouldReschedulePeriodicRefresh: Bool) async {
        guard !isRefreshing, !isResettingCodexUsage else { return }
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
