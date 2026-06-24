import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published state

    @Published var isGitHubAuthenticated = false
    @Published var isCodexAuthenticated = false
    @Published var isAuthenticatingGitHub = false
    @Published var isAuthenticatingCodex = false
    @Published var isGitHubClientIdConfigured = GitHubOAuthConfig.clientId != nil
    @Published var isCodexClientIdConfigured = CodexOAuthConfig.clientId != nil
    @Published var codexAccountDisplayName: String?
    @Published var authError: String?

    // GitHub device flow state
    @Published var githubUserCode: String?
    @Published var githubVerificationURL: String?

    // Codex device flow state
    @Published var codexUserCode: String?
    @Published var codexVerificationURL: String?

    // MARK: - Settings (UserDefaults)

    @Published var aiCreditMonthlyLimit: String {
        didSet { UserDefaults.standard.set(Double(aiCreditMonthlyLimit) ?? 0,
                                            forKey: "github_ai_credit_monthly_limit") }
    }

    @Published var premiumRequestMonthlyLimit: String {
        didSet { UserDefaults.standard.set(Double(premiumRequestMonthlyLimit) ?? 0,
                                            forKey: "github_premium_request_monthly_limit") }
    }

    @Published var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refresh_interval_minutes") }
    }

    // MARK: - Dependencies

    private let githubAuth: GitHubAuthProvider
    private let codexAuth: CodexAuthProvider
    private let usageStore: UsageStore

    // MARK: - Init

    init(
        githubAuth: GitHubAuthProvider = GitHubAuthProvider(),
        codexAuth: CodexAuthProvider = CodexAuthProvider(),
        usageStore: UsageStore? = nil
    ) {
        self.githubAuth = githubAuth
        self.codexAuth = codexAuth
        self.usageStore = usageStore ?? .shared

        let defaults = UserDefaults.standard
        let aiLimit = defaults.double(forKey: "github_ai_credit_monthly_limit")
        let prLimit = defaults.double(forKey: "github_premium_request_monthly_limit")
        let interval = defaults.integer(forKey: "refresh_interval_minutes")

        self.aiCreditMonthlyLimit = aiLimit > 0 ? String(Int(aiLimit)) : ""
        self.premiumRequestMonthlyLimit = prLimit > 0 ? String(Int(prLimit)) : ""
        self.refreshIntervalMinutes = interval > 0 ? interval : 60
    }

    // MARK: - Auth status

    func checkAuthStatus() {
        Task {
            isGitHubClientIdConfigured = GitHubOAuthConfig.clientId != nil
            isCodexClientIdConfigured = CodexOAuthConfig.clientId != nil
            isGitHubAuthenticated = await githubAuth.isAuthenticated
            isCodexAuthenticated = await codexAuth.isAuthenticated
            codexAccountDisplayName = await codexAuth.tokenBundle?.accountDisplayName
        }
    }

    // MARK: - GitHub

    func startGitHubLogin() {
        guard !isAuthenticatingGitHub else { return }
        guard GitHubOAuthConfig.clientId != nil else {
            isGitHubClientIdConfigured = false
            authError = GitHubAuthError.clientIdNotConfigured.localizedDescription
            return
        }

        isAuthenticatingGitHub = true
        authError = nil
        githubUserCode = nil
        githubVerificationURL = nil

        Task {
            do {
                let response = try await githubAuth.startDeviceFlow()
                githubUserCode = response.userCode
                githubVerificationURL = response.verificationUri

                _ = try await githubAuth.pollForToken(
                    deviceCode: response.deviceCode,
                    interval: response.interval
                )
                isGitHubAuthenticated = true
                githubUserCode = nil
                githubVerificationURL = nil
            } catch {
                authError = error.localizedDescription
            }
            isAuthenticatingGitHub = false
        }
    }

    func logoutGitHub() {
        Task {
            await githubAuth.logout()
            isGitHubAuthenticated = false
            usageStore.clear(provider: .githubCopilot)
        }
    }

    // MARK: - Codex

    func startCodexLogin() {
        guard !isAuthenticatingCodex else { return }
        guard CodexOAuthConfig.clientId != nil else {
            isCodexClientIdConfigured = false
            authError = CodexAuthError.clientIdNotConfigured.localizedDescription
            return
        }

        isAuthenticatingCodex = true
        authError = nil
        codexUserCode = nil
        codexVerificationURL = nil

        Task {
            do {
                let response = try await codexAuth.startDeviceFlow()
                codexUserCode = response.userCode
                codexVerificationURL = response.verificationUri

                _ = try await codexAuth.pollForToken(
                    deviceCode: response.deviceCode,
                    userCode: response.userCode,
                    interval: response.interval
                )
                isCodexAuthenticated = true
                codexAccountDisplayName = await codexAuth.tokenBundle?.accountDisplayName
                codexUserCode = nil
                codexVerificationURL = nil
            } catch {
                authError = error.localizedDescription
            }
            isAuthenticatingCodex = false
        }
    }

    func logoutCodex() {
        Task {
            await codexAuth.logout()
            isCodexAuthenticated = false
            codexAccountDisplayName = nil
            usageStore.clear(provider: .codex)
        }
    }
}
