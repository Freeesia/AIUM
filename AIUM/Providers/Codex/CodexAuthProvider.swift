import Foundation

// MARK: - Configuration

/// Codex OIDC / device-code flow configuration.
/// These endpoints and client IDs are based on OpenAI's current auth infrastructure.
///
/// ⚠️ WARNING: These are private / undocumented endpoints. They may change at any time.
/// Do not use this in a public App Store release until official APIs are available.
struct CodexOAuthConfig {
    // TODO: Replace with real Codex client ID
    static let clientId = "YOUR_CODEX_CLIENT_ID"

    // TODO: Verify these endpoints before use
    static let issuerURL = URL(string: "https://auth.openai.com")!
    static let deviceAuthURL = URL(string: "https://auth.openai.com/oauth/device/code")!
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let audience = "https://api.openai.com/v1"

    static let keychainService = "io.github.freeesia.aium"
    static let keychainAccount = "codex_token_bundle"
}

// MARK: - Token Bundle

/// Stores the full Codex token set returned by the auth server.
struct CodexTokenBundle: Codable, Sendable {
    var idToken: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var accountId: String?
    var email: String?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60) // refresh 1 min early
    }
}

// MARK: - Device Code Response

struct CodexDeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct CodexTokenResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Auth Provider

/// Handles Codex device-code authentication and token refresh with single-flight protection.
actor CodexAuthProvider {
    private var _tokenBundle: CodexTokenBundle?
    private var refreshTask: Task<CodexTokenBundle, Error>?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        _tokenBundle = try? KeychainHelper.loadCodable(CodexTokenBundle.self,
                                                        service: CodexOAuthConfig.keychainService,
                                                        account: CodexOAuthConfig.keychainAccount)
    }

    var tokenBundle: CodexTokenBundle? { _tokenBundle }

    var isAuthenticated: Bool {
        _tokenBundle != nil
    }

    // MARK: - Device Code Flow

    func startDeviceFlow() async throws -> CodexDeviceCodeResponse {
        var request = URLRequest(url: CodexOAuthConfig.deviceAuthURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(CodexOAuthConfig.clientId)&audience=\(CodexOAuthConfig.audience)"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(CodexDeviceCodeResponse.self, from: data)
    }

    func pollForToken(deviceCode: String, interval: Int) async throws -> CodexTokenBundle {
        var pollInterval = max(interval, 5)
        let deadline = Date().addingTimeInterval(300)
        let grantType = "urn:ietf:params:oauth:grant-type:device_code"

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            var request = URLRequest(url: CodexOAuthConfig.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "client_id=\(CodexOAuthConfig.clientId)&device_code=\(deviceCode)&grant_type=\(grantType)"
            request.httpBody = body.data(using: .utf8)

            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(CodexTokenResponse.self, from: data)

            if let accessToken = response.accessToken, !accessToken.isEmpty {
                let bundle = CodexTokenBundle(
                    idToken: response.idToken ?? "",
                    accessToken: accessToken,
                    refreshToken: response.refreshToken,
                    expiresAt: Date().addingTimeInterval(Double(response.expiresIn ?? 3600))
                )
                try saveBundle(bundle)
                return bundle
            }

            switch response.error {
            case "authorization_pending": continue
            case "slow_down": pollInterval += 5
            case "expired_token": throw CodexAuthError.deviceCodeExpired
            case "access_denied": throw CodexAuthError.accessDenied
            default:
                if let error = response.error { throw CodexAuthError.unknown(error) }
            }
        }
        throw CodexAuthError.timeout
    }

    // MARK: - Token Refresh (single-flight)

    /// Returns a valid access token, refreshing if necessary.
    /// Uses single-flight to prevent concurrent refresh races.
    func validAccessToken() async throws -> String {
        guard var bundle = _tokenBundle else {
            throw CodexAuthError.notAuthenticated
        }

        guard bundle.isExpired else { return bundle.accessToken }

        // Single-flight: if a refresh is already in progress, await it.
        if let existing = refreshTask {
            let refreshed = try await existing.value
            return refreshed.accessToken
        }

        let task = Task<CodexTokenBundle, Error> {
            try await self.performRefresh(bundle: bundle)
        }
        refreshTask = task
        defer { refreshTask = nil }

        bundle = try await task.value
        return bundle.accessToken
    }

    func logout() {
        _tokenBundle = nil
        refreshTask?.cancel()
        refreshTask = nil
        KeychainHelper.delete(
            service: CodexOAuthConfig.keychainService,
            account: CodexOAuthConfig.keychainAccount
        )
    }

    // MARK: - Private

    private func performRefresh(bundle: CodexTokenBundle) async throws -> CodexTokenBundle {
        guard let refreshToken = bundle.refreshToken else {
            throw CodexAuthError.noRefreshToken
        }

        var request = URLRequest(url: CodexOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(CodexOAuthConfig.clientId)&grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(CodexTokenResponse.self, from: data)

        guard let accessToken = response.accessToken, !accessToken.isEmpty else {
            throw CodexAuthError.refreshFailed(response.errorDescription ?? "unknown")
        }

        var updated = bundle
        updated = CodexTokenBundle(
            idToken: response.idToken ?? bundle.idToken,
            accessToken: accessToken,
            refreshToken: response.refreshToken ?? bundle.refreshToken,
            expiresAt: Date().addingTimeInterval(Double(response.expiresIn ?? 3600)),
            accountId: bundle.accountId,
            email: bundle.email
        )
        try saveBundle(updated)
        return updated
    }

    private func saveBundle(_ bundle: CodexTokenBundle) throws {
        _tokenBundle = bundle
        try KeychainHelper.saveCodable(
            bundle,
            service: CodexOAuthConfig.keychainService,
            account: CodexOAuthConfig.keychainAccount
        )
    }
}

// MARK: - Errors

enum CodexAuthError: LocalizedError {
    case notAuthenticated
    case deviceCodeExpired
    case accessDenied
    case timeout
    case noRefreshToken
    case refreshFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Codex."
        case .deviceCodeExpired: return "Device code expired. Please try again."
        case .accessDenied: return "Access was denied."
        case .timeout: return "Authentication timed out."
        case .noRefreshToken: return "No refresh token available."
        case .refreshFailed(let msg): return "Token refresh failed: \(msg)"
        case .unknown(let msg): return "Auth error: \(msg)"
        }
    }
}
