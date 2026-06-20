import Foundation

// MARK: - Settings Keys

private let kAICreditLimit = "github_ai_credit_monthly_limit"
private let kPremiumRequestLimit = "github_premium_request_monthly_limit"

// MARK: - GitHub Usage Provider

/// Fetches usage data from GitHub's billing APIs and normalizes into UsageSnapshot values.
/// Currently supports:
///  - AI Credits  (`/users/{u}/settings/billing/ai_credit/usage`)
///  - Premium Requests (`/users/{u}/settings/billing/premium_request/usage`)
actor GitHubUsageProvider: UsageProvider {
    let provider: Provider = .githubCopilot

    private let authProvider: GitHubAuthProvider
    private let apiClient: GitHubAPIClient

    /// Manual override for AI Credit monthly allowance (0 = use API value).
    var aiCreditMonthlyLimit: Double {
        UserDefaults.standard.double(forKey: kAICreditLimit)
    }

    /// Manual override for Premium Request monthly allowance (0 = use API value).
    var premiumRequestMonthlyLimit: Double {
        UserDefaults.standard.double(forKey: kPremiumRequestLimit)
    }

    init(
        authProvider: GitHubAuthProvider = GitHubAuthProvider(),
        apiClient: GitHubAPIClient = GitHubAPIClient()
    ) {
        self.authProvider = authProvider
        self.apiClient = apiClient
    }

    // MARK: - UsageProvider

    var isAuthenticated: Bool {
        get async { await authProvider.isAuthenticated }
    }

    func fetchUsage() async throws -> [UsageSnapshot] {
        guard let token = await authProvider.accessToken else {
            throw GitHubUsageError.notAuthenticated
        }

        let user = try await apiClient.fetchUser(token: token)
        var snapshots: [UsageSnapshot] = []

        // AI Credits
        if let aiSnapshot = try? await fetchAICreditSnapshot(username: user.login, token: token, user: user) {
            snapshots.append(aiSnapshot)
        }

        // Legacy Premium Requests
        if let prSnapshot = try? await fetchPremiumRequestSnapshot(username: user.login, token: token, user: user) {
            snapshots.append(prSnapshot)
        }

        if snapshots.isEmpty {
            throw GitHubUsageError.noDataAvailable
        }

        return snapshots
    }

    // MARK: - Private helpers

    private func fetchAICreditSnapshot(
        username: String,
        token: String,
        user: GitHubUser
    ) async throws -> UsageSnapshot {
        let response = try await apiClient.fetchAICreditUsage(username: username, token: token)

        let used = response.usedInCurrentPeriod ?? 0
        // Use manual override if set, otherwise fall back to API value
        let limit: Double
        if aiCreditMonthlyLimit > 0 {
            limit = aiCreditMonthlyLimit
        } else {
            limit = response.totalAllowance ?? 0
        }

        return UsageSnapshot(
            provider: .githubCopilot,
            accountId: String(user.id),
            displayName: user.name ?? user.login,
            planKind: .aiCredits,
            windowKind: .monthly,
            used: used,
            limit: limit,
            resetAt: response.currentPeriodEnd,
            unit: "AI credits",
            source: "GitHub Billing API"
        )
    }

    private func fetchPremiumRequestSnapshot(
        username: String,
        token: String,
        user: GitHubUser
    ) async throws -> UsageSnapshot {
        let response = try await apiClient.fetchPremiumRequestUsage(username: username, token: token)

        let used = response.usedPremiumRequests ?? 0
        let limit: Double
        if premiumRequestMonthlyLimit > 0 {
            limit = premiumRequestMonthlyLimit
        } else {
            limit = response.includedPremiumRequests ?? 0
        }

        return UsageSnapshot(
            provider: .githubCopilot,
            accountId: String(user.id),
            displayName: user.name ?? user.login,
            planKind: .premiumRequests,
            windowKind: .monthly,
            used: used,
            limit: limit,
            resetAt: nil,
            unit: "premium requests",
            source: "GitHub Billing API (legacy)"
        )
    }
}

// MARK: - Errors

enum GitHubUsageError: LocalizedError {
    case notAuthenticated
    case noDataAvailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to GitHub."
        case .noDataAvailable: return "No usage data available from GitHub."
        }
    }
}
