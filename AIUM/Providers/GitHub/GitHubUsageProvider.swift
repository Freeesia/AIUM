import Foundation

// MARK: - Settings Keys

private let kAICreditLimit = "github_ai_credit_monthly_limit"
private let kPremiumRequestLimit = "github_premium_request_monthly_limit"
private let kBillingOrganization = "github_billing_organization"

// MARK: - GitHub Usage Provider

/// Fetches usage data from GitHub's billing APIs and normalizes into UsageSnapshot values.
/// Currently supports:
///  - AI Credits  (`/users/{u}/settings/billing/ai_credit/usage`)
///  - Premium Requests (`/users/{u}/settings/billing/premium_request/usage`)
actor GitHubUsageProvider: UsageProvider {
    let provider: Provider = .githubCopilot

    private let authProvider: any GitHubAuthProviding
    private let apiClient: any GitHubAPIProviding

    /// Manual override for AI Credit monthly allowance (0 = use API value).
    var aiCreditMonthlyLimit: Double {
        UserDefaults.standard.double(forKey: kAICreditLimit)
    }

    /// Manual override for Premium Request monthly allowance (0 = use API value).
    var premiumRequestMonthlyLimit: Double {
        UserDefaults.standard.double(forKey: kPremiumRequestLimit)
    }

    var billingOrganization: String? {
        let value = UserDefaults.standard.string(forKey: kBillingOrganization)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    init(
        authProvider: any GitHubAuthProviding = GitHubAuthProvider(),
        apiClient: any GitHubAPIProviding = GitHubAPIClient()
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
        let organization = billingOrganization
        var snapshots: [UsageSnapshot] = []

        do {
            let aiSnapshot = try await fetchAICreditSnapshot(
                username: user.login,
                organization: organization,
                token: token,
                user: user
            )
            snapshots.append(aiSnapshot)
        } catch {
            snapshots.append(errorSnapshot(for: .aiCredits, error: error, user: user, organization: organization))
        }

        do {
            let prSnapshot = try await fetchPremiumRequestSnapshot(
                username: user.login,
                organization: organization,
                token: token,
                user: user
            )
            snapshots.append(prSnapshot)
        } catch {
            snapshots.append(errorSnapshot(for: .premiumRequests, error: error, user: user, organization: organization))
        }

        if snapshots.isEmpty {
            throw GitHubUsageError.noDataAvailable
        }

        return snapshots
    }

    // MARK: - Private helpers

    private func fetchAICreditSnapshot(
        username: String,
        organization: String?,
        token: String,
        user: GitHubUser
    ) async throws -> UsageSnapshot {
        let response = try await apiClient.fetchAICreditUsage(username: username, organization: organization, token: token)

        let used = response.usedQuantity
        // The current billing report exposes usage, not plan allowance.
        let limit: Double
        if aiCreditMonthlyLimit > 0 {
            limit = aiCreditMonthlyLimit
        } else {
            limit = 0
        }

        return UsageSnapshot(
            provider: .githubCopilot,
            accountId: String(user.id),
            displayName: displayName(user: user, organization: organization),
            planKind: .aiCredits,
            windowKind: .monthly,
            used: used,
            limit: limit,
            resetAt: response.timePeriod?.periodEndDate(),
            unit: "AI credits",
            source: "GitHub Billing API"
        )
    }

    private func fetchPremiumRequestSnapshot(
        username: String,
        organization: String?,
        token: String,
        user: GitHubUser
    ) async throws -> UsageSnapshot {
        let response = try await apiClient.fetchPremiumRequestUsage(username: username, organization: organization, token: token)

        let used = response.usedQuantity
        // The current billing report exposes usage, not plan allowance.
        let limit: Double
        if premiumRequestMonthlyLimit > 0 {
            limit = premiumRequestMonthlyLimit
        } else {
            limit = 0
        }

        return UsageSnapshot(
            provider: .githubCopilot,
            accountId: String(user.id),
            displayName: displayName(user: user, organization: organization),
            planKind: .premiumRequests,
            windowKind: .monthly,
            used: used,
            limit: limit,
            resetAt: response.timePeriod?.periodEndDate(),
            unit: "premium requests",
            source: "GitHub Billing API"
        )
    }

    private func errorSnapshot(
        for endpoint: GitHubUsageEndpoint,
        error: Error,
        user: GitHubUser,
        organization: String?
    ) -> UsageSnapshot {
        UsageSnapshot.error(
            provider: .githubCopilot,
            accountId: String(user.id),
            displayName: displayName(user: user, organization: organization),
            planKind: endpoint.planKind,
            windowKind: .monthly,
            unit: endpoint.unit,
            source: endpoint.source,
            message: endpoint.errorMessage(for: error, organization: organization)
        )
    }

    private func displayName(user: GitHubUser, organization: String?) -> String {
        let userName = user.name ?? user.login
        guard let organization else { return userName }
        return "\(userName) @ \(organization)"
    }
}

private enum GitHubUsageEndpoint {
    case aiCredits
    case premiumRequests

    var displayName: String {
        switch self {
        case .aiCredits: return "AI Credits"
        case .premiumRequests: return "Premium Requests"
        }
    }

    var planKind: PlanKind {
        switch self {
        case .aiCredits: return .aiCredits
        case .premiumRequests: return .premiumRequests
        }
    }

    var unit: String {
        switch self {
        case .aiCredits: return "AI credits"
        case .premiumRequests: return "premium requests"
        }
    }

    var source: String {
        switch self {
        case .aiCredits: return "GitHub Billing API"
        case .premiumRequests: return "GitHub Billing API"
        }
    }

    func errorMessage(for error: Error, organization: String?) -> String {
        if case GitHubAPIError.httpError(let statusCode, _) = error, statusCode == 404 {
            if let organization {
                return "\(displayName): GitHub API HTTP 404. Organization billing usage was not found for \(organization). Check the organization slug and use a token with organization Administration read permission."
            }
            return "\(displayName): GitHub API HTTP 404. User billing usage only applies to personally billed Copilot plans. For organization-billed seats, set Billing Organization and use an organization token with Administration read permission."
        }
        return "\(displayName): \(error.localizedDescription)"
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
