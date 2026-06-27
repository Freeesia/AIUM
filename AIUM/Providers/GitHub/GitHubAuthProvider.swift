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

    static let keychainService = "io.github.freeesia.aium"
    static let keychainAccount = "github_app_user_token"

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
    func validAccessToken() async throws -> String?
    var isAuthenticated: Bool { get async }
}

protocol GitHubTokenStoring: Sendable {
    func load() -> GitHubTokenBundle?
    func save(_ bundle: GitHubTokenBundle) throws
    func delete()
}

struct KeychainGitHubTokenStore: GitHubTokenStoring {
    func load() -> GitHubTokenBundle? {
        try? KeychainHelper.loadCodable(
            GitHubTokenBundle.self,
            service: GitHubOAuthConfig.keychainService,
            account: GitHubOAuthConfig.keychainAccount
        )
    }

    func save(_ bundle: GitHubTokenBundle) throws {
        try KeychainHelper.saveCodable(
            bundle,
            service: GitHubOAuthConfig.keychainService,
            account: GitHubOAuthConfig.keychainAccount
        )
    }

    func delete() {
        KeychainHelper.delete(
            service: GitHubOAuthConfig.keychainService,
            account: GitHubOAuthConfig.keychainAccount
        )
    }
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

struct GitHubTokenBundle: Codable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date?
    let refreshToken: String?
    let refreshTokenExpiresAt: Date?

    func hasUsableCredentials(now: Date = Date()) -> Bool {
        if let accessTokenExpiresAt, accessTokenExpiresAt <= now {
            guard let refreshToken,
                  !refreshToken.isEmpty,
                  refreshTokenExpiresAt.map({ $0 > now }) ?? true
            else { return false }
        }
        return !accessToken.isEmpty
    }
}

private struct GitHubTokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Auth Provider

actor GitHubAuthProvider: GitHubAuthProviding {
    private let session: URLSession
    private let clientIdProvider: @Sendable () -> String?
    private let tokenStore: any GitHubTokenStoring

    init(
        session: URLSession = .shared,
        clientIdProvider: @escaping @Sendable () -> String? = { GitHubOAuthConfig.clientId },
        tokenStore: any GitHubTokenStoring = KeychainGitHubTokenStore()
    ) {
        self.session = session
        self.clientIdProvider = clientIdProvider
        self.tokenStore = tokenStore
    }

    var isAuthenticated: Bool {
        get async { tokenStore.load()?.hasUsableCredentials() == true }
    }

    func validAccessToken() async throws -> String? {
        guard let bundle = tokenStore.load() else { return nil }
        guard let expiresAt = bundle.accessTokenExpiresAt,
              expiresAt <= Date().addingTimeInterval(60)
        else { return bundle.accessToken }

        guard let refreshToken = bundle.refreshToken,
              bundle.refreshTokenExpiresAt.map({ $0 > Date() }) ?? true
        else {
            logout()
            throw GitHubAuthError.sessionExpired
        }

        return try await refreshAccessToken(refreshToken).accessToken
    }

    func startDeviceFlow() async throws -> GitHubDeviceCodeResponse {
        guard let clientId = clientIdProvider() else {
            throw GitHubAuthError.clientIdNotConfigured
        }

        var request = URLRequest(url: GitHubOAuthConfig.deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["client_id": clientId])

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

            let tokenResponse: GitHubTokenResponse
            do {
                tokenResponse = try await requestToken([
                    "client_id": clientId,
                    "device_code": deviceCode,
                    "grant_type": grantType,
                ])
            } catch let error as URLError where Self.isTransient(error) {
                continue
            }

            if let bundle = tokenBundle(from: tokenResponse) {
                try save(bundle)
                return bundle.accessToken
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
        tokenStore.delete()
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> GitHubTokenBundle {
        guard let clientId = clientIdProvider() else {
            throw GitHubAuthError.clientIdNotConfigured
        }

        let tokenResponse = try await requestToken([
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        if let bundle = tokenBundle(from: tokenResponse) {
            try save(bundle)
            return bundle
        }

        logout()
        throw GitHubAuthError.sessionExpired
    }

    private func requestToken(_ parameters: [String: String]) async throws -> GitHubTokenResponse {
        var request = URLRequest(url: GitHubOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(parameters)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(GitHubTokenResponse.self, from: data)
    }

    private func tokenBundle(from response: GitHubTokenResponse, now: Date = Date()) -> GitHubTokenBundle? {
        guard let accessToken = response.accessToken, !accessToken.isEmpty else { return nil }
        return GitHubTokenBundle(
            accessToken: accessToken,
            accessTokenExpiresAt: response.expiresIn.map { now.addingTimeInterval(TimeInterval($0)) },
            refreshToken: response.refreshToken,
            refreshTokenExpiresAt: response.refreshTokenExpiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
        )
    }

    private func save(_ bundle: GitHubTokenBundle) throws {
        try tokenStore.save(bundle)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200..<300).contains(httpResponse.statusCode)
        else { return }

        throw GitHubAuthError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8))
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost:
            return true
        default:
            return false
        }
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
    case sessionExpired
    case httpError(Int, String?)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .clientIdNotConfigured:
            return "GitHub App Client ID is not configured. Set GITHUB_OAUTH_CLIENT_ID in the AIUM target build settings."
        case .deviceCodeExpired:
            return "Device code expired. Please try again."
        case .accessDenied:
            return "Access denied."
        case .timeout:
            return "Timed out waiting for GitHub authorization."
        case .sessionExpired:
            return "Your GitHub session expired. Sign in again."
        case .httpError(let code, let body):
            return "GitHub auth error \(code): \(body ?? "no body")"
        case .unknown(let message):
            return message
        }
    }
}
