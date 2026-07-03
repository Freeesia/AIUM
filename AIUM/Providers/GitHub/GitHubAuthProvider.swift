import Foundation

// MARK: - Configuration

struct GitHubOAuthConfig {
    private static let clientIdInfoPlistKey = "GitHubOAuthClientID"
    private static let placeholderClientId = "YOUR_GITHUB_CLIENT_ID"

    static var clientId: String? {
        resolvedClientId(from: Bundle.main.object(forInfoDictionaryKey: clientIdInfoPlistKey) as? String)
    }

    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    static let scope = "read:user read:org"

    static let keychainService = "io.github.freeesia.aium"
    static let keychainAccount = "github_access_token"

    static func resolvedClientId(from rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != placeholderClientId,
              !trimmed.hasPrefix("$(")
        else { return nil }

        return trimmed
    }
}

protocol GitHubAuthProviding: Actor {
    var accessToken: String? { get async }
    var isAuthenticated: Bool { get async }
}

// MARK: - Device Flow Models

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

private struct GitHubTokenResponse: Decodable {
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

actor GitHubAuthProvider: GitHubAuthProviding {
    private var storedAccessToken: String?
    private let session: URLSession
    private let clientIdProvider: @Sendable () -> String?

    init(
        session: URLSession = .shared,
        clientIdProvider: @escaping @Sendable () -> String? = { GitHubOAuthConfig.clientId }
    ) {
        self.session = session
        self.clientIdProvider = clientIdProvider
        storedAccessToken = KeychainHelper.load(
            service: GitHubOAuthConfig.keychainService,
            account: GitHubOAuthConfig.keychainAccount
        )
    }

    var accessToken: String? {
        get async { storedAccessToken }
    }

    var isAuthenticated: Bool {
        get async { storedAccessToken != nil }
    }

    func startDeviceFlow() async throws -> GitHubDeviceCodeResponse {
        guard let clientId = clientIdProvider() else {
            throw GitHubAuthError.clientIdNotConfigured
        }

        var request = URLRequest(url: GitHubOAuthConfig.deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientId,
            "scope": GitHubOAuthConfig.scope,
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: data)
    }

    func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        guard let clientId = clientIdProvider() else {
            throw GitHubAuthError.clientIdNotConfigured
        }

        var pollInterval = max(interval, 5)
        let deadline = Date().addingTimeInterval(900)
        let grantType = "urn:ietf:params:oauth:grant-type:device_code"

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            var request = URLRequest(url: GitHubOAuthConfig.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody([
                "client_id": clientId,
                "device_code": deviceCode,
                "grant_type": grantType,
            ])

            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            let tokenResponse = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)

            if let accessToken = tokenResponse.accessToken, !accessToken.isEmpty {
                save(accessToken)
                return accessToken
            }

            switch tokenResponse.error {
            case "authorization_pending":
                continue
            case "slow_down":
                pollInterval += 5
            case "expired_token":
                throw GitHubAuthError.deviceCodeExpired
            case "access_denied":
                throw GitHubAuthError.accessDenied
            default:
                if let error = tokenResponse.error {
                    throw GitHubAuthError.unknown(tokenResponse.errorDescription ?? error)
                }
            }
        }

        throw GitHubAuthError.timeout
    }

    func logout() {
        storedAccessToken = nil
        KeychainHelper.delete(
            service: GitHubOAuthConfig.keychainService,
            account: GitHubOAuthConfig.keychainAccount
        )
    }

    private func save(_ accessToken: String) {
        storedAccessToken = accessToken
        KeychainHelper.save(
            accessToken,
            service: GitHubOAuthConfig.keychainService,
            account: GitHubOAuthConfig.keychainAccount
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200..<300).contains(httpResponse.statusCode)
        else { return }

        throw GitHubAuthError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8))
    }

    private func formBody(_ parameters: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

// MARK: - Errors

enum GitHubAuthError: LocalizedError {
    case clientIdNotConfigured
    case deviceCodeExpired
    case accessDenied
    case timeout
    case httpError(Int, String?)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .clientIdNotConfigured:
            return String(localized: "GitHub OAuth Client ID is not configured. Set GITHUB_OAUTH_CLIENT_ID in the AIUM target build settings.")
        case .deviceCodeExpired:
            return String(localized: "Device code expired. Please try again.")
        case .accessDenied:
            return String(localized: "Access denied.")
        case .timeout:
            return String(localized: "Timed out waiting for GitHub authorization.")
        case .httpError(let code, let body):
            return String.localizedStringWithFormat(
                String(localized: "GitHub auth error %lld: %@"),
                Int64(code),
                body ?? String(localized: "no body")
            )
        case .unknown(let message):
            return message
        }
    }
}
