import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published state

    @Published var isDemoMode = false
    @Published var isGitHubAuthenticated = false
    @Published var isCodexAuthenticated = false
    @Published var isClaudeCodeAuthenticated = false
    @Published var isAuthenticatingGitHub = false
    @Published var isAuthenticatingCodex = false
    @Published var isAuthenticatingClaudeCode = false
    @Published var isGitHubClientIdConfigured = GitHubOAuthConfig.clientId != nil
    @Published var isCodexClientIdConfigured = CodexOAuthConfig.clientId != nil
    @Published var isClaudeCodeClientIdConfigured = ClaudeCodeOAuthConfig.clientId != nil
    @Published var codexAccountDisplayName: String?
    @Published var claudeCodeAccountDisplayName: String?
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

    @Published var refreshSetting: UsageRefreshSetting {
        didSet { UserDefaults.standard.set(refreshSetting.rawValue, forKey: UsageRefreshSetting.storageKey) }
    }

    // MARK: - Dependencies

    private let githubAuth: GitHubAuthProvider
    private let codexAuth: CodexAuthProvider
    private let claudeCodeAuth: ClaudeCodeAuthProvider
    private let usageStore: UsageStore
    private let demoModeStore: DemoModeStore

    // MARK: - Init

    init(
        githubAuth: GitHubAuthProvider = .shared,
        codexAuth: CodexAuthProvider = CodexAuthProvider(),
        claudeCodeAuth: ClaudeCodeAuthProvider = ClaudeCodeAuthProvider(),
        usageStore: UsageStore? = nil,
        demoModeStore: DemoModeStore = DemoModeStore()
    ) {
        self.githubAuth = githubAuth
        self.codexAuth = codexAuth
        self.claudeCodeAuth = claudeCodeAuth
        self.usageStore = usageStore ?? .shared
        self.demoModeStore = demoModeStore

        let defaults = UserDefaults.standard
        let aiLimit = defaults.double(forKey: "github_ai_credit_monthly_limit")
        let prLimit = defaults.double(forKey: "github_premium_request_monthly_limit")
        let interval = defaults.object(forKey: UsageRefreshSetting.storageKey) as? Int

        self.aiCreditMonthlyLimit = aiLimit > 0 ? String(Int(aiLimit)) : ""
        self.premiumRequestMonthlyLimit = prLimit > 0 ? String(Int(prLimit)) : ""
        self.refreshSetting = UsageRefreshSetting(storedValue: interval)
    }

    // MARK: - Demo Mode

    func checkDemoMode() {
        isDemoMode = demoModeStore.isEnabled
    }

    // MARK: - Auth status

    func checkAuthStatus() {
        checkDemoMode()
        Task {
            isGitHubClientIdConfigured = GitHubOAuthConfig.clientId != nil
            isCodexClientIdConfigured = CodexOAuthConfig.clientId != nil
            isClaudeCodeClientIdConfigured = ClaudeCodeOAuthConfig.clientId != nil
            isGitHubAuthenticated = await githubAuth.isAuthenticated
            isClaudeCodeAuthenticated = await claudeCodeAuth.isAuthenticated
            claudeCodeAccountDisplayName = await claudeCodeAuth.tokenBundle?.accountDisplayName
            isCodexAuthenticated = await codexAuth.isAuthenticated
            codexAccountDisplayName = await codexAuth.tokenBundle?.accountDisplayName
            if isCodexAuthenticated, let accessToken = try? await codexAuth.validAccessToken() {
                _ = await codexAuth.refreshAccountProfile(accessToken: accessToken)
                codexAccountDisplayName = await codexAuth.tokenBundle?.accountDisplayName
            }
            if isClaudeCodeAuthenticated, let accessToken = try? await claudeCodeAuth.validAccessToken() {
                _ = await claudeCodeAuth.refreshAccountProfile(accessToken: accessToken)
                claudeCodeAccountDisplayName = await claudeCodeAuth.tokenBundle?.accountDisplayName
            }
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

    // MARK: - Claude Code

    func startClaudeCodeLogin() {
        guard !isAuthenticatingClaudeCode else { return }
        guard ClaudeCodeOAuthConfig.clientId != nil else {
            isClaudeCodeClientIdConfigured = false
            authError = ClaudeCodeAuthError.clientIdNotConfigured.localizedDescription
            return
        }

        isAuthenticatingClaudeCode = true
        authError = nil

        Task {
            do {
                let bundle = try await claudeCodeAuth.signIn(using: ClaudeCodeWebAuthorizationSession())
                isClaudeCodeAuthenticated = true
                claudeCodeAccountDisplayName = bundle.accountDisplayName
            } catch ClaudeCodeAuthError.cancelled {
                // Closing the sign-in sheet is not an error.
            } catch {
                authError = error.localizedDescription
            }
            isAuthenticatingClaudeCode = false
        }
    }

    func logoutClaudeCode() {
        Task {
            await claudeCodeAuth.logout()
            isClaudeCodeAuthenticated = false
            claudeCodeAccountDisplayName = nil
            usageStore.clear(provider: .claudeCode)
        }
    }
}
