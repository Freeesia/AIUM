import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    private static let codexResetCreditDetailsCacheDuration: TimeInterval = 60
    private static let claudeCodeResetStatusCacheDuration: TimeInterval = 60

    // MARK: - Published state

    @Published var githubSnapshots: [UsageSnapshot] = []
    @Published var codexSnapshots: [UsageSnapshot] = []
    @Published var claudeCodeSnapshots: [UsageSnapshot] = []
    @Published private(set) var isResettingCodexUsage = false
    @Published private(set) var codexResetError: String?
    @Published private(set) var codexResetOutcome: CodexUsageResetOutcome?
    @Published private(set) var codexResetCreditDetails: CodexResetCreditDetails?
    @Published private(set) var isLoadingCodexResetCreditDetails = false
    @Published private(set) var codexResetCreditDetailsError: String?
    @Published private(set) var isResettingClaudeCodeUsage = false
    @Published private(set) var claudeCodeResetError: String?
    @Published private(set) var claudeCodeResetOutcome: ClaudeCodeUsageResetOutcome?
    @Published private(set) var claudeCodeResetStatus: ClaudeCodeResetStatus?
    @Published private(set) var isLoadingClaudeCodeResetStatus = false
    @Published private(set) var claudeCodeResetStatusError: String?
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
    private let claudeCodeProvider: PrivateClaudeCodeUsageProvider
    private let resetRequestStore: UsageResetRequestStore
    private let claudeCodeResetRequestStore: UsageResetRequestStore
    private let now: () -> Date
    private var codexResetCreditDetailsAccountId: String?
    private var codexResetCreditDetailsFetchedAt: Date?
    private var codexResetCreditDetailsRequestID: UUID?
    private var claudeCodeResetStatusAccountId: String?
    private var claudeCodeResetStatusFetchedAt: Date?
    private var claudeCodeResetStatusRequestID: UUID?
    private var periodicRefreshTask: Task<Void, Never>?
    private var periodicRefreshGeneration = 0
    private var automaticRefreshIntervalMinutes = UsageRefreshSchedule.storedAutomaticIntervalMinutes()

    // MARK: - Init

    init(
        usageStore: UsageStore? = nil,
        demoModeStore: DemoModeStore = DemoModeStore(),
        githubProvider: GitHubUsageProvider = GitHubUsageProvider(),
        codexProvider: PrivateCodexUsageProvider = PrivateCodexUsageProvider(),
        claudeCodeProvider: PrivateClaudeCodeUsageProvider = PrivateClaudeCodeUsageProvider(),
        resetRequestStore: UsageResetRequestStore? = nil,
        claudeCodeResetRequestStore: UsageResetRequestStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedUsageStore = usageStore ?? .shared
        self.usageStore = resolvedUsageStore
        self.demoModeStore = demoModeStore
        self.githubProvider = githubProvider
        self.codexProvider = codexProvider
        self.claudeCodeProvider = claudeCodeProvider
        self.resetRequestStore = resetRequestStore ?? .codex()
        self.claudeCodeResetRequestStore = claudeCodeResetRequestStore ?? .claudeCode()
        self.now = now
        self.refreshService = UsageRefreshService(
            usageStore: resolvedUsageStore,
            resolver: AppUsageProviderResolver(
                demoModeStore: demoModeStore,
                githubProvider: githubProvider,
                codexProvider: codexProvider,
                claudeCodeProvider: claudeCodeProvider
            )
        )
        loadFromStore()
    }

    deinit {
        periodicRefreshTask?.cancel()
    }

    // MARK: - Public

    /// True while either provider's reset request is in flight.
    var isResettingUsage: Bool {
        isResettingCodexUsage || isResettingClaudeCodeUsage
    }

    var codexResetCredits: Int? {
        guard let snapshot = UsageSnapshot.displaySnapshot(from: codexSnapshots, for: .codex),
              snapshot.errorMessage == nil,
              let value = snapshot.resetCredits,
              let count = Int(exactly: value), count > 0 else { return nil }
        return count
    }

    func prepareCodexUsageReset() async -> CodexUsageResetConfirmation? {
        guard !isDemoMode, !demoModeStore.isEnabled,
              !isRefreshing, !isResettingUsage,
              let remainingCount = codexResetCredits else { return nil }
        let identity = await codexProvider.accountIdentity
        guard !isRefreshing, !isResettingUsage else { return nil }
        guard let accountId = identity.accountId,
              codexSnapshots.contains(where: { $0.accountId == accountId }) else {
            invalidateCodexResetCreditDetails()
            lastError = String(localized: "Refresh Codex usage before resetting it.")
            return nil
        }
        codexResetError = nil
        codexResetOutcome = nil
        if codexResetCreditDetailsAccountId != accountId {
            invalidateCodexResetCreditDetails()
        }
        codexResetCreditDetailsError = nil
        codexResetCreditDetailsRequestID = nil
        isLoadingCodexResetCreditDetails = false
        return CodexUsageResetConfirmation(
            accountId: accountId,
            accountDisplayName: identity.profileName,
            remainingCount: remainingCount
        )
    }

    func loadCodexResetCreditDetails(for confirmation: CodexUsageResetConfirmation) async {
        guard !isDemoMode, !demoModeStore.isEnabled,
              !isLoadingCodexResetCreditDetails, !isResettingCodexUsage,
              codexResetOutcome == nil else { return }
        let requestID = UUID()
        codexResetCreditDetailsRequestID = requestID
        isLoadingCodexResetCreditDetails = true
        codexResetCreditDetailsError = nil
        defer {
            if codexResetCreditDetailsRequestID == requestID {
                isLoadingCodexResetCreditDetails = false
            }
        }

        let identity = await codexProvider.accountIdentity
        guard !Task.isCancelled, codexResetCreditDetailsRequestID == requestID else { return }
        guard identity.accountId == confirmation.accountId else {
            invalidateCodexResetCreditDetails()
            codexResetCreditDetailsError = CodexUsageResetError.accountChanged.localizedDescription
            return
        }
        if hasFreshCodexResetCreditDetails(for: confirmation.accountId) { return }

        do {
            let details = try await codexProvider.fetchResetCreditDetails(accountId: confirmation.accountId)
            try Task.checkCancellation()
            guard codexResetCreditDetailsRequestID == requestID else { return }
            codexResetCreditDetails = details
            codexResetCreditDetailsAccountId = confirmation.accountId
            codexResetCreditDetailsFetchedAt = now()
        } catch {
            guard !Task.isCancelled, codexResetCreditDetailsRequestID == requestID else { return }
            if let error = error as? CodexUsageResetError {
                invalidateCodexResetCreditDetails()
                codexResetCreditDetailsError = error.localizedDescription
            } else {
                codexResetCreditDetailsError = String(localized: "Could not load reset expiration dates. Try again.")
            }
        }
    }

    func resetCodexUsage(_ confirmation: CodexUsageResetConfirmation) async {
        guard !isResettingUsage, !isRefreshing, codexResetOutcome == nil,
              !isDemoMode, !demoModeStore.isEnabled else { return }
        isResettingCodexUsage = true
        codexResetError = nil
        lastError = nil
        invalidateCodexResetCreditDetails()
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

    // MARK: - Claude Code usage reset

    var claudeCodeResetCredits: Int? {
        guard let snapshot = UsageSnapshot.displaySnapshot(from: claudeCodeSnapshots, for: .claudeCode),
              snapshot.errorMessage == nil,
              let value = snapshot.resetCredits,
              let count = Int(exactly: value), count > 0 else { return nil }
        return count
    }

    func prepareClaudeCodeUsageReset() async -> ClaudeCodeUsageResetConfirmation? {
        guard !isDemoMode, !demoModeStore.isEnabled,
              !isRefreshing, !isResettingUsage,
              let remainingCount = claudeCodeResetCredits else { return nil }
        let identity = await claudeCodeProvider.accountIdentity
        guard !isRefreshing, !isResettingUsage else { return nil }
        guard let accountId = identity.accountId,
              claudeCodeSnapshots.contains(where: { $0.accountId == accountId }) else {
            invalidateClaudeCodeResetStatus()
            lastError = String(localized: "Refresh Claude Code usage before resetting it.")
            return nil
        }
        guard let organizationId = identity.organizationId, !organizationId.isEmpty else {
            invalidateClaudeCodeResetStatus()
            lastError = String(localized: "Sign in to Claude Code again before resetting usage.")
            return nil
        }
        claudeCodeResetError = nil
        claudeCodeResetOutcome = nil
        if claudeCodeResetStatusAccountId != accountId {
            invalidateClaudeCodeResetStatus()
        }
        claudeCodeResetStatusError = nil
        claudeCodeResetStatusRequestID = nil
        isLoadingClaudeCodeResetStatus = false
        return ClaudeCodeUsageResetConfirmation(
            accountId: accountId,
            organizationId: organizationId,
            accountDisplayName: identity.profileName,
            remainingCount: remainingCount
        )
    }

    /// The grant a confirmed reset will use, once the status has loaded.
    var claudeCodeResetGrantToUse: ClaudeCodeResetGrant? {
        claudeCodeResetStatus?.grantToUse(now: now())
    }

    func loadClaudeCodeResetStatus(for confirmation: ClaudeCodeUsageResetConfirmation) async {
        guard !isDemoMode, !demoModeStore.isEnabled,
              !isLoadingClaudeCodeResetStatus, !isResettingClaudeCodeUsage,
              claudeCodeResetOutcome == nil else { return }
        let requestID = UUID()
        claudeCodeResetStatusRequestID = requestID
        isLoadingClaudeCodeResetStatus = true
        claudeCodeResetStatusError = nil
        defer {
            if claudeCodeResetStatusRequestID == requestID {
                isLoadingClaudeCodeResetStatus = false
            }
        }

        let identity = await claudeCodeProvider.accountIdentity
        guard !Task.isCancelled, claudeCodeResetStatusRequestID == requestID else { return }
        guard identity.accountId == confirmation.accountId,
              identity.organizationId == confirmation.organizationId else {
            invalidateClaudeCodeResetStatus()
            claudeCodeResetStatusError = ClaudeCodeUsageResetError.accountChanged.localizedDescription
            return
        }
        if hasFreshClaudeCodeResetStatus(for: confirmation.accountId) { return }

        do {
            let status = try await claudeCodeProvider.fetchResetStatus(accountId: confirmation.accountId)
            try Task.checkCancellation()
            guard claudeCodeResetStatusRequestID == requestID else { return }
            claudeCodeResetStatus = status
            claudeCodeResetStatusAccountId = confirmation.accountId
            claudeCodeResetStatusFetchedAt = now()
        } catch {
            guard !Task.isCancelled, claudeCodeResetStatusRequestID == requestID else { return }
            if let error = error as? ClaudeCodeUsageResetError {
                invalidateClaudeCodeResetStatus()
                claudeCodeResetStatusError = error.localizedDescription
            } else {
                claudeCodeResetStatusError = String(localized: "Could not load reset details. Try again.")
            }
        }
    }

    func resetClaudeCodeUsage(_ confirmation: ClaudeCodeUsageResetConfirmation) async {
        guard !isResettingUsage, !isRefreshing, claudeCodeResetOutcome == nil,
              !isLoadingClaudeCodeResetStatus,
              !isDemoMode, !demoModeStore.isEnabled else { return }
        guard claudeCodeResetStatusAccountId == confirmation.accountId,
              let grant = claudeCodeResetGrantToUse else {
            claudeCodeResetError = ClaudeCodeUsageResetError.noUsableReset.localizedDescription
            return
        }
        isResettingClaudeCodeUsage = true
        claudeCodeResetError = nil
        lastError = nil
        // Keep the grant for a retry, but do not reuse the counts afterwards.
        claudeCodeResetStatusFetchedAt = nil
        defer { isResettingClaudeCodeUsage = false }

        let requestKey = "\(confirmation.accountId).\(grant.id)"
        let requestID = claudeCodeResetRequestStore.requestID(for: requestKey)
        do {
            let outcome = try await claudeCodeProvider.resetUsage(
                requestID: requestID,
                grantId: grant.id,
                accountId: confirmation.accountId,
                organizationId: confirmation.organizationId
            )
            claudeCodeResetRequestStore.clear(for: requestKey)
            claudeCodeResetOutcome = outcome
            invalidateClaudeCodeResetStatus()

            // The old limits and reset count no longer describe the account.
            // A refresh failure must not turn a completed reset into a retry.
            usageStore.clear(provider: .claudeCode)
            loadFromStore()
            do {
                let snapshots = try await claudeCodeProvider.fetchUsage()
                usageStore.replace(provider: .claudeCode, with: snapshots)
                loadFromStore()
            } catch {
                lastError = String(localized: "Could not refresh usage. Close this sheet and refresh the dashboard.")
            }
        } catch let error as ClaudeCodeUsageResetError {
            if case .accountChanged = error { invalidateClaudeCodeResetStatus() }
            claudeCodeResetError = error.localizedDescription
        } catch {
            claudeCodeResetError = ClaudeCodeUsageResetError.unconfirmed.localizedDescription
        }
    }

    func refresh() {
        Task {
            await refreshNow(shouldReschedulePeriodicRefresh: true)
        }
    }

    func refreshIfNeeded() {
        guard !isRefreshing else { return }
        let snapshots = githubSnapshots + codexSnapshots + claudeCodeSnapshots
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
            let isAuthenticated = await codexProvider.isAuthenticated
            if !isAuthenticated { invalidateCodexResetCreditDetails() }
            return isAuthenticated
        }
    }

    var claudeCodeIsAuthenticated: Bool {
        get async {
            if isDemoMode { return true }
            let isAuthenticated = await claudeCodeProvider.isAuthenticated
            if !isAuthenticated { invalidateClaudeCodeResetStatus() }
            return isAuthenticated
        }
    }

    /// Reads the current demo mode flag and applies any state changes needed.
    func reloadDemoMode() {
        let wasEnabled = isDemoMode
        let isEnabled = demoModeStore.isEnabled
        isDemoMode = isEnabled
        if wasEnabled != isEnabled {
            invalidateCodexResetCreditDetails()
            invalidateClaudeCodeResetStatus()
        }

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
            usageStore.replace(
                provider: .claudeCode,
                with: DemoUsageDataFactory.snapshots(for: .claudeCode, now: now)
            )
            loadFromStore()
        } else if wasEnabled && !isEnabled {
            // Demo mode turned OFF: clear the demo cache
            usageStore.clear(provider: .githubCopilot)
            usageStore.clear(provider: .codex)
            usageStore.clear(provider: .claudeCode)
            loadFromStore()
        }
    }

    // MARK: - Private

    private func hasFreshCodexResetCreditDetails(for accountId: String) -> Bool {
        guard codexResetCreditDetailsAccountId == accountId,
              let details = codexResetCreditDetails,
              let fetchedAt = codexResetCreditDetailsFetchedAt else { return false }
        let currentDate = now()
        let age = currentDate.timeIntervalSince(fetchedAt)
        return age >= 0 && age < Self.codexResetCreditDetailsCacheDuration
            && details.credits.allSatisfy { credit in
                credit.expiresAt.map { $0 > currentDate } ?? true
            }
    }

    private func invalidateCodexResetCreditDetails() {
        codexResetCreditDetails = nil
        codexResetCreditDetailsAccountId = nil
        codexResetCreditDetailsFetchedAt = nil
        codexResetCreditDetailsRequestID = nil
        codexResetCreditDetailsError = nil
        isLoadingCodexResetCreditDetails = false
    }

    private func hasFreshClaudeCodeResetStatus(for accountId: String) -> Bool {
        guard claudeCodeResetStatusAccountId == accountId,
              let status = claudeCodeResetStatus,
              let fetchedAt = claudeCodeResetStatusFetchedAt else { return false }
        let currentDate = now()
        let age = currentDate.timeIntervalSince(fetchedAt)
        // A grant that was usable when fetched but has since expired makes
        // the cached counts wrong; grants that were already expired do not.
        return age >= 0 && age < Self.claudeCodeResetStatusCacheDuration
            && status.activeGrants(now: fetchedAt).allSatisfy { grant in
                grant.endsAt.map { $0 > currentDate } ?? true
            }
    }

    private func invalidateClaudeCodeResetStatus() {
        claudeCodeResetStatus = nil
        claudeCodeResetStatusAccountId = nil
        claudeCodeResetStatusFetchedAt = nil
        claudeCodeResetStatusRequestID = nil
        claudeCodeResetStatusError = nil
        isLoadingClaudeCodeResetStatus = false
    }

    private func loadFromStore() {
        githubSnapshots = usageStore.snapshots(for: .githubCopilot)
        codexSnapshots = usageStore.snapshots(for: .codex)
        claudeCodeSnapshots = usageStore.snapshots(for: .claudeCode)
    }

    private func refreshNow(shouldReschedulePeriodicRefresh: Bool) async {
        guard !isRefreshing, !isResettingUsage else { return }
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
