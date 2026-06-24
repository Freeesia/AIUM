import Foundation

// MARK: - Configuration

/// Codex OIDC / device-code flow configuration.
/// These values match the current Codex app-server login flow and can be overridden
/// from the app target's build settings when OpenAI changes the private API.
///
/// ⚠️ WARNING: These are private / undocumented endpoints. They may change at any time.
/// Do not use this in a public App Store release until official APIs are available.
struct CodexOAuthConfig {
    private static let clientIdInfoPlistKey = "CodexOAuthClientID"
    private static let placeholderClientId = "YOUR_CODEX_CLIENT_ID"

    static let issuerURL = URL(string: "https://auth.openai.com")!
    static let authAPIBaseURL = URL(string: "https://auth.openai.com/api/accounts")!
    static let deviceUserCodeURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!
    static let deviceTokenURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let deviceVerificationURL = URL(string: "https://auth.openai.com/codex/device")!
    static let deviceRedirectURL = URL(string: "https://auth.openai.com/deviceauth/callback")!
    static let backendBaseURL = URL(string: "https://chatgpt.com/backend-api")!
    static let usageEndpointPath = "/api/codex/usage"
    static let profileEndpointPath = "/api/codex/profiles/me"

    static let keychainService = "io.github.freeesia.aium"
    static let keychainAccount = "codex_token_bundle"

    static var clientId: String? {
        resolvedClientId(from: Bundle.main.object(forInfoDictionaryKey: clientIdInfoPlistKey) as? String)
    }

    static func resolvedClientId(from rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != placeholderClientId,
              !trimmed.hasPrefix("$(")
        else { return nil }

        return trimmed
    }
}

protocol CodexAuthProviding: Actor {
    var tokenBundle: CodexTokenBundle? { get async }
    var isAuthenticated: Bool { get async }

    func startDeviceFlow() async throws -> CodexDeviceCodeResponse
    func pollForToken(deviceCode: String, userCode: String, interval: Int) async throws -> CodexTokenBundle
    func validAccessToken() async throws -> String
    func updateAccount(accountId: String?, email: String?) throws
    func logout()
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

    var accountDisplayName: String? {
        email ?? accountId
    }
}

struct CodexTokenPersistence: Sendable {
    let load: @Sendable () -> CodexTokenBundle?
    let save: @Sendable (CodexTokenBundle) throws -> Void
    let delete: @Sendable () -> Void

    static let keychain = CodexTokenPersistence(
        load: {
            try? KeychainHelper.loadCodable(
                CodexTokenBundle.self,
                service: CodexOAuthConfig.keychainService,
                account: CodexOAuthConfig.keychainAccount
            )
        },
        save: { bundle in
            try KeychainHelper.saveCodable(
                bundle,
                service: CodexOAuthConfig.keychainService,
                account: CodexOAuthConfig.keychainAccount
            )
        },
        delete: {
            KeychainHelper.delete(
                service: CodexOAuthConfig.keychainService,
                account: CodexOAuthConfig.keychainAccount
            )
        }
    )
}

// MARK: - Account Identity

struct CodexAccountIdentity: Equatable, Sendable {
    let accountId: String?
    let email: String?

    static func extract(accessToken: String?, idToken: String?) -> CodexAccountIdentity {
        let accessClaims = jwtPayload(accessToken)
        let idClaims = jwtPayload(idToken)

        let accessAuth = accessClaims["https://api.openai.com/auth"] as? [String: Any]
        let idAuth = idClaims["https://api.openai.com/auth"] as? [String: Any]
        let accessProfile = accessClaims["https://api.openai.com/profile"] as? [String: Any]

        let accountId = firstString(
            accessAuth?["chatgpt_account_id"],
            idAuth?["chatgpt_account_id"],
            accessClaims["account_id"],
            idClaims["account_id"]
        )
        let email = firstString(
            accessProfile?["email"],
            accessClaims["email"],
            idClaims["email"]
        )

        return CodexAccountIdentity(accountId: accountId, email: email)
    }

    static func extract(jsonData: Data) -> CodexAccountIdentity? {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let accountId = firstString(
            json["account_id"],
            json["accountId"],
            json["chatgpt_account_id"],
            json["chatgptAccountId"],
            (json["account"] as? [String: Any])?["id"],
            (json["profile"] as? [String: Any])?["account_id"]
        )
        let email = firstString(
            json["email"],
            (json["profile"] as? [String: Any])?["email"],
            (json["user"] as? [String: Any])?["email"]
        )

        guard accountId != nil || email != nil else { return nil }
        return CodexAccountIdentity(accountId: accountId, email: email)
    }

    private static func jwtPayload(_ token: String?) -> [String: Any] {
        guard let token else { return [:] }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        switch payload.count % 4 {
        case 2:
            payload += "=="
        case 3:
            payload += "="
        case 0:
            break
        default:
            return [:]
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        return json
    }

    private static func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
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
        case deviceCode = "device_auth_id"
        case userCode = "user_code"
        case verificationUri = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }

    init(
        deviceCode: String,
        userCode: String,
        verificationUri: String = CodexOAuthConfig.deviceVerificationURL.absoluteString,
        expiresIn: Int = 900,
        interval: Int
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.expiresIn = expiresIn
        self.interval = interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceCode = try container.decode(String.self, forKey: .deviceCode)
        userCode = try container.decode(String.self, forKey: .userCode)
        verificationUri = try container.decodeIfPresent(String.self, forKey: .verificationUri)
            ?? CodexOAuthConfig.deviceVerificationURL.absoluteString
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 900

        if let intervalString = try? container.decode(String.self, forKey: .interval),
           let parsed = Int(intervalString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            interval = parsed
        } else {
            interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 5
        }
    }
}

struct CodexDeviceAuthorizationResponse: Decodable {
    let authorizationCode: String
    let codeChallenge: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeChallenge = "code_challenge"
        case codeVerifier = "code_verifier"
    }
}

struct CodexTokenResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Auth Provider

/// Handles Codex device-code authentication and token refresh with single-flight protection.
actor CodexAuthProvider: CodexAuthProviding {
    private var _tokenBundle: CodexTokenBundle?
    private var refreshTask: Task<CodexTokenBundle, Error>?
    private let session: URLSession
    private let clientIdProvider: @Sendable () -> String?
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let persistence: CodexTokenPersistence
    private let synchronizesPersistedBundle: Bool

    init(
        session: URLSession = .shared,
        clientIdProvider: @escaping @Sendable () -> String? = { CodexOAuthConfig.clientId },
        initialTokenBundle: CodexTokenBundle? = nil,
        persistence: CodexTokenPersistence = .keychain,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.session = session
        self.clientIdProvider = clientIdProvider
        self.sleep = sleep
        self.persistence = persistence
        synchronizesPersistedBundle = initialTokenBundle == nil
        _tokenBundle = initialTokenBundle ?? persistence.load()
    }

    var tokenBundle: CodexTokenBundle? {
        synchronizedTokenBundle()
    }

    var isAuthenticated: Bool {
        synchronizedTokenBundle() != nil
    }

    // MARK: - Device Code Flow

    func startDeviceFlow() async throws -> CodexDeviceCodeResponse {
        guard let clientId = clientIdProvider() else {
            throw CodexAuthError.clientIdNotConfigured
        }

        debugLog("Starting Codex device user-code request: \(CodexOAuthConfig.deviceUserCodeURL.absoluteString)")
        var request = URLRequest(url: CodexOAuthConfig.deviceUserCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["client_id": clientId])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        debugLog("Codex device user-code request succeeded.")
        return try JSONDecoder().decode(CodexDeviceCodeResponse.self, from: data)
    }

    func pollForToken(deviceCode: String, userCode: String, interval: Int) async throws -> CodexTokenBundle {
        guard let clientId = clientIdProvider() else {
            throw CodexAuthError.clientIdNotConfigured
        }

        let pollInterval = max(interval, 5)
        let deadline = Date().addingTimeInterval(900)

        while Date() < deadline {
            try await sleep(UInt64(pollInterval) * 1_000_000_000)

            var request = URLRequest(url: CodexOAuthConfig.deviceTokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode([
                "device_auth_id": deviceCode,
                "user_code": userCode,
            ])

            debugLog("Polling Codex device authorization endpoint: \(CodexOAuthConfig.deviceTokenURL.absoluteString)")
            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 403 || httpResponse.statusCode == 404 {
                debugLog("Codex device authorization still pending: HTTP \(httpResponse.statusCode)")
                continue
            }

            try validate(response: response, data: data)
            let authorization = try JSONDecoder().decode(CodexDeviceAuthorizationResponse.self, from: data)
            let bundle = try await exchangeAuthorizationCode(
                authorization.authorizationCode,
                codeVerifier: authorization.codeVerifier,
                clientId: clientId
            )
            try saveBundle(bundle)
            debugLog("Codex device authorization succeeded.")
            return bundle
        }
        throw CodexAuthError.timeout
    }

    // MARK: - Token Refresh (single-flight)

    /// Returns a valid access token, refreshing if necessary.
    /// Uses single-flight to prevent concurrent refresh races.
    func validAccessToken() async throws -> String {
        guard var bundle = synchronizedTokenBundle() else {
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
        persistence.delete()
    }

    // MARK: - Private

    private func exchangeAuthorizationCode(
        _ code: String,
        codeVerifier: String,
        clientId: String
    ) async throws -> CodexTokenBundle {
        var request = URLRequest(url: CodexOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": CodexOAuthConfig.deviceRedirectURL.absoluteString,
        ])

        debugLog("Exchanging Codex authorization code: \(CodexOAuthConfig.tokenURL.absoluteString)")
        let (data, response) = try await session.data(for: request)
        let tokenResponse = try decodeTokenResponse(from: data, response: response)

        guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
            if let error = tokenResponse.error {
                throw CodexAuthError.unknown(tokenResponse.errorDescription ?? error)
            }
            try validate(response: response, data: data)
            throw CodexAuthError.unknown("Codex token exchange did not return an access token.")
        }
        try validate(response: response, data: data)

        let identity = CodexAccountIdentity.extract(
            accessToken: tokenResponse.accessToken,
            idToken: tokenResponse.idToken
        )
        debugLog("Codex authorization-code exchange succeeded.")
        return CodexTokenBundle(
            idToken: tokenResponse.idToken ?? "",
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(Double(tokenResponse.expiresIn ?? 3600)),
            accountId: identity.accountId,
            email: identity.email
        )
    }

    private func performRefresh(bundle: CodexTokenBundle) async throws -> CodexTokenBundle {
        guard let clientId = clientIdProvider() else {
            throw CodexAuthError.clientIdNotConfigured
        }
        guard let refreshToken = bundle.refreshToken else {
            throw CodexAuthError.noRefreshToken
        }

        var request = URLRequest(url: CodexOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        debugLog("Refreshing Codex token: \(CodexOAuthConfig.tokenURL.absoluteString)")
        let (data, response) = try await session.data(for: request)
        let tokenResponse = try decodeTokenResponse(from: data, response: response)

        guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
            if let error = tokenResponse.error {
                throw CodexAuthError.refreshFailed(tokenResponse.errorDescription ?? error)
            }
            try validate(response: response, data: data)
            throw CodexAuthError.refreshFailed("unknown")
        }
        try validate(response: response, data: data)

        let identity = CodexAccountIdentity.extract(
            accessToken: tokenResponse.accessToken,
            idToken: tokenResponse.idToken
        )
        let updated = CodexTokenBundle(
            idToken: tokenResponse.idToken ?? bundle.idToken,
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken ?? bundle.refreshToken,
            expiresAt: Date().addingTimeInterval(Double(tokenResponse.expiresIn ?? 3600)),
            accountId: identity.accountId ?? bundle.accountId,
            email: identity.email ?? bundle.email
        )
        try saveBundle(updated)
        debugLog("Codex token refresh succeeded.")
        return updated
    }

    func updateAccount(accountId: String?, email: String?) throws {
        guard var bundle = synchronizedTokenBundle() else { return }

        let resolvedAccountId = accountId ?? bundle.accountId
        let resolvedEmail = email ?? bundle.email
        guard resolvedAccountId != bundle.accountId || resolvedEmail != bundle.email else { return }

        bundle.accountId = resolvedAccountId
        bundle.email = resolvedEmail
        try saveBundle(bundle)
    }

    private func saveBundle(_ bundle: CodexTokenBundle) throws {
        try persistence.save(bundle)
        _tokenBundle = bundle
    }

    private func synchronizedTokenBundle() -> CodexTokenBundle? {
        guard synchronizesPersistedBundle else { return _tokenBundle }
        _tokenBundle = persistence.load()
        return _tokenBundle
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200..<300).contains(httpResponse.statusCode)
        else { return }

        let body = String(data: data, encoding: .utf8)
        debugLog(
            "Codex auth HTTP \(httpResponse.statusCode) at \(httpResponse.url?.absoluteString ?? "unknown URL"): \(Self.preview(body))"
        )
        throw CodexAuthError.httpError(httpResponse.statusCode, body)
    }

    private func decodeTokenResponse(from data: Data, response: URLResponse) throws -> CodexTokenResponse {
        do {
            return try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        } catch {
            debugLog("Codex token response decode failed: \(Self.preview(String(data: data, encoding: .utf8)))")
            try validate(response: response, data: data)
            throw error
        }
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[AIUM][CodexAuth] \(message())")
        #endif
    }

    private static func preview(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return "no body" }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 300 { return singleLine }
        return String(singleLine.prefix(300)) + "..."
    }

    private func formBody(_ parameters: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

// MARK: - Errors

enum CodexAuthError: LocalizedError {
    case clientIdNotConfigured
    case notAuthenticated
    case deviceCodeExpired
    case accessDenied
    case timeout
    case noRefreshToken
    case httpError(Int, String?)
    case refreshFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .clientIdNotConfigured:
            return "Codex OAuth Client ID is not configured. Set CODEX_OAUTH_CLIENT_ID in the AIUM target build settings."
        case .notAuthenticated: return "Not signed in to Codex."
        case .deviceCodeExpired: return "Device code expired. Please try again."
        case .accessDenied: return "Access was denied."
        case .timeout: return "Authentication timed out."
        case .noRefreshToken: return "No refresh token available."
        case .httpError(let code, let body):
            return "Codex auth error \(code): \(Self.preview(body))"
        case .refreshFailed(let msg): return "Token refresh failed: \(msg)"
        case .unknown(let msg): return msg
        }
    }

    private static func preview(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return "no body" }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 300 { return singleLine }
        return String(singleLine.prefix(300)) + "..."
    }
}
