import Foundation

// MARK: - Configuration

/// Replace `clientId` with your real GitHub OAuth App or GitHub App client ID.
/// Register a device-flow-capable OAuth App at https://github.com/settings/developers
struct GitHubOAuthConfig {
    /// GitHub OAuth App client ID (device-flow capable).
    /// Replace this placeholder before building.
    static let clientId = "YOUR_GITHUB_CLIENT_ID"  // TODO: Replace with real client ID

    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    static let scopes = ["read:user", "read:org"]
    static let keychainService = "io.github.freeesia.aium"
    static let keychainAccount = "github_access_token"
}

// MARK: - Device Flow Response models

struct GitHubDeviceCodeResponse: Decodable {
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

struct GitHubTokenResponse: Decodable {
    let accessToken: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Auth Provider

/// Implements GitHub Device Flow authentication.
/// See: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
actor GitHubAuthProvider {
    // MARK: - Stored token

    private var _accessToken: String?

    var accessToken: String? {
        if _accessToken == nil {
            _accessToken = KeychainHelper.load(
                service: GitHubOAuthConfig.keychainService,
                account: GitHubOAuthConfig.keychainAccount
            )
        }
        return _accessToken
    }

    var isAuthenticated: Bool {
        accessToken != nil
    }

    func logout() {
        _accessToken = nil
        KeychainHelper.delete(
            service: GitHubOAuthConfig.keychainService,
            account: GitHubOAuthConfig.keychainAccount
        )
    }

    // MARK: - Device Flow

    /// Starts the device code flow. Returns the user-facing code and URL.
    func startDeviceFlow() async throws -> GitHubDeviceCodeResponse {
        var request = URLRequest(url: GitHubOAuthConfig.deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(GitHubOAuthConfig.clientId)&scope=\(GitHubOAuthConfig.scopes.joined(separator: "%20"))"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        return try decoder.decode(GitHubDeviceCodeResponse.self, from: data)
    }

    /// Polls GitHub for an access token after the user has entered the user code.
    func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        let grantType = "urn:ietf:params:oauth:grant-type:device_code"
        var pollInterval = max(interval, 5)
        let deadline = Date().addingTimeInterval(300) // 5 minute timeout

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            var request = URLRequest(url: GitHubOAuthConfig.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "client_id=\(GitHubOAuthConfig.clientId)&device_code=\(deviceCode)&grant_type=\(grantType)"
            request.httpBody = body.data(using: .utf8)

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)

            if let token = response.accessToken, !token.isEmpty {
                saveToken(token)
                return token
            }

            switch response.error {
            case "authorization_pending":
                continue  // Still waiting
            case "slow_down":
                pollInterval += 5
            case "expired_token":
                throw GitHubAuthError.deviceCodeExpired
            case "access_denied":
                throw GitHubAuthError.accessDenied
            default:
                if let error = response.error {
                    throw GitHubAuthError.unknown(error)
                }
            }
        }
        throw GitHubAuthError.timeout
    }

    // MARK: - Private

    private func saveToken(_ token: String) {
        _accessToken = token
        KeychainHelper.save(
            token,
            service: GitHubOAuthConfig.keychainService,
            account: GitHubOAuthConfig.keychainAccount
        )
    }
}

// MARK: - Errors

enum GitHubAuthError: LocalizedError {
    case deviceCodeExpired
    case accessDenied
    case timeout
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .deviceCodeExpired: return "Device code expired. Please try again."
        case .accessDenied: return "Access was denied."
        case .timeout: return "Authentication timed out."
        case .unknown(let msg): return "Auth error: \(msg)"
        }
    }
}
