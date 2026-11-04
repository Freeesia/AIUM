import CryptoKit
import Foundation
import Security

// MARK: - Configuration

/// Claude Code OAuth (authorization code + PKCE) configuration.
/// These values match the login flow used by the Claude Code CLI and can be
/// overridden from the app target's build settings if Anthropic changes them.
///
/// ⚠️ These endpoints are not part of an officially published API specification and may change at any time.
struct ClaudeCodeOAuthConfig {
    private static let clientIdInfoPlistKey = "ClaudeCodeOAuthClientID"
    private static let placeholderClientId = "YOUR_CLAUDE_CODE_CLIENT_ID"

    /// Authorization endpoint for Claude Pro/Max (claude.ai) accounts.
    static let authorizeURL = URL(string: "https://claude.com/cai/oauth/authorize")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let apiBaseURL = URL(string: "https://api.anthropic.com")!
    static let usageEndpointPath = "/api/oauth/usage"
    static let profileEndpointPath = "/api/oauth/profile"
    static let betaHeader = "oauth-2025-04-20"

    /// Only the profile scope is needed to read plan rate limits. AIUM never
    /// requests inference or API-key scopes.
    static let scopes = ["user:profile"]

    /// The OAuth client only accepts loopback redirects, so the app listens on
    /// `http://localhost:<port>/callback` and forwards the browser to this
    /// scheme, which `ASWebAuthenticationSession` intercepts.
    static let loopbackCallbackPath = "/callback"
    static let callbackScheme = "aium-claude-code"

    static let keychainService = "com.studiofreesia.aium"
    static let keychainAccount = "claude_code_token_bundle"

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

    static func loopbackRedirectURI(port: UInt16) -> URL {
        URL(string: "http://localhost:\(port)\(loopbackCallbackPath)")!
    }

    static func authorizationURL(
        clientId: String,
        redirectURI: URL,
        codeChallenge: String,
        state: String
    ) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            // Matches the Claude Code CLI, which always sends `code=true`.
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
}

// MARK: - PKCE

struct ClaudeCodePKCE: Equatable, Sendable {
    let codeVerifier: String
    let codeChallenge: String

    static func generate() -> ClaudeCodePKCE {
        make(codeVerifier: randomURLSafeString(byteCount: 32))
    }

    static func make(codeVerifier: String) -> ClaudeCodePKCE {
        let digest = SHA256.hash(data: Data(codeVerifier.utf8))
        return ClaudeCodePKCE(
            codeVerifier: codeVerifier,
            codeChallenge: Data(digest).base64URLEncodedString()
        )
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            // SystemRandomNumberGenerator is also cryptographically secure on Apple platforms.
            var generator = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes).base64URLEncodedString()
    }
}

// MARK: - Authorization session

/// Result of the browser leg of the authorization code flow.
struct ClaudeCodeAuthorizationCallback: Sendable {
    /// URL carrying the authorization response (`code`, `state` or `error`).
    let url: URL
    /// Redirect URI sent in the authorization request; the token request must repeat it.
    let redirectURI: URL
}

/// Presents the authorization page and waits for its redirect.
/// The redirect URI is only known once the session has prepared its
/// listener, so the session builds the authorization URL from it.
protocol ClaudeCodeAuthorizationSession: Sendable {
    func authorize(
        buildAuthorizationURL: @escaping @Sendable (URL) -> URL
    ) async throws -> ClaudeCodeAuthorizationCallback
}

protocol ClaudeCodeAuthProviding: Actor {
    var tokenBundle: ClaudeCodeTokenBundle? { get async }
    var isAuthenticated: Bool { get async }

    func signIn(using session: any ClaudeCodeAuthorizationSession) async throws -> ClaudeCodeTokenBundle
    func validAccessToken() async throws -> String
    func refreshAccountProfile(accessToken: String) async -> ClaudeCodeAccountProfile?
    func logout()
}

// MARK: - Token Bundle

struct ClaudeCodeTokenBundle: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scopes: [String]?
    /// Anthropic account UUID.
    var accountId: String?
    var email: String?
    var organizationId: String?
    var profile: ClaudeCodeAccountProfile?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60) // refresh 1 min early
    }

    var accountDisplayName: String? {
        profile?.name
    }
}

// MARK: - Account Profile

/// Claude account profile data used for account display.
struct ClaudeCodeAccountProfile: Codable, Equatable, Sendable {
    let displayName: String?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case fullName = "full_name"
    }

    /// The name shown in the app: the Claude display name, or the full name
    /// when no display name is set.
    var name: String? {
        [displayName, fullName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    static func decode(from data: Data) throws -> ClaudeCodeAccountProfile {
        struct Response: Decodable {
            let account: ClaudeCodeAccountProfile
        }
        return try JSONDecoder().decode(Response.self, from: data).account
    }
}

struct ClaudeCodeTokenPersistence: Sendable {
    let load: @Sendable () throws -> ClaudeCodeTokenBundle?
    let save: @Sendable (ClaudeCodeTokenBundle) throws -> Void
    let delete: @Sendable () -> Void

    static let keychain = ClaudeCodeTokenPersistence(
        load: {
            try KeychainHelper.loadCodable(
                ClaudeCodeTokenBundle.self,
                service: ClaudeCodeOAuthConfig.keychainService,
                account: ClaudeCodeOAuthConfig.keychainAccount
            )
        },
        save: { bundle in
            try KeychainHelper.saveCodable(
                bundle,
                service: ClaudeCodeOAuthConfig.keychainService,
                account: ClaudeCodeOAuthConfig.keychainAccount
            )
        },
        delete: {
            try? KeychainHelper.delete(
                service: ClaudeCodeOAuthConfig.keychainService,
                account: ClaudeCodeOAuthConfig.keychainAccount
            )
        }
    )
}

struct ClaudeCodeTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let scope: String?
    let account: Account?
    let organization: Organization?
    let error: String?
    let errorDescription: String?

    struct Account: Decodable {
        let uuid: String?
        let emailAddress: String?

        enum CodingKeys: String, CodingKey {
            case uuid
            case emailAddress = "email_address"
        }
    }

    struct Organization: Decodable {
        let uuid: String?
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case account
        case organization
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Auth Provider

/// Handles Claude Code authorization-code sign-in and token refresh with single-flight protection.
actor ClaudeCodeAuthProvider: ClaudeCodeAuthProviding {
    private var _tokenBundle: ClaudeCodeTokenBundle?
    private var refreshTask: Task<ClaudeCodeTokenBundle, Error>?
    private let session: URLSession
    private let clientIdProvider: @Sendable () -> String?
    private let pkceGenerator: @Sendable () -> ClaudeCodePKCE
    private let stateGenerator: @Sendable () -> String
    private let persistence: ClaudeCodeTokenPersistence
    private let synchronizesPersistedBundle: Bool

    init(
        session: URLSession = .shared,
        clientIdProvider: @escaping @Sendable () -> String? = { ClaudeCodeOAuthConfig.clientId },
        initialTokenBundle: ClaudeCodeTokenBundle? = nil,
        persistence: ClaudeCodeTokenPersistence = .keychain,
        pkceGenerator: @escaping @Sendable () -> ClaudeCodePKCE = { ClaudeCodePKCE.generate() },
        stateGenerator: @escaping @Sendable () -> String = { ClaudeCodePKCE.randomURLSafeString(byteCount: 32) }
    ) {
        self.session = session
        self.clientIdProvider = clientIdProvider
        self.pkceGenerator = pkceGenerator
        self.stateGenerator = stateGenerator
        self.persistence = persistence
        synchronizesPersistedBundle = initialTokenBundle == nil
        _tokenBundle = initialTokenBundle ?? (try? persistence.load())
    }

    var tokenBundle: ClaudeCodeTokenBundle? {
        try? synchronizedTokenBundle()
    }

    var isAuthenticated: Bool {
        (try? synchronizedTokenBundle()) != nil
    }

    // MARK: - Authorization Code Flow

    func signIn(using authorizationSession: any ClaudeCodeAuthorizationSession) async throws -> ClaudeCodeTokenBundle {
        guard let clientId = clientIdProvider() else {
            throw ClaudeCodeAuthError.clientIdNotConfigured
        }

        let pkce = pkceGenerator()
        let state = stateGenerator()
        let challenge = pkce.codeChallenge

        debugLog("Starting Claude Code authorization: \(ClaudeCodeOAuthConfig.authorizeURL.absoluteString)")
        let callback = try await authorizationSession.authorize { redirectURI in
            ClaudeCodeOAuthConfig.authorizationURL(
                clientId: clientId,
                redirectURI: redirectURI,
                codeChallenge: challenge,
                state: state
            )
        }

        let code = try Self.authorizationCode(from: callback.url, expectedState: state)
        var bundle = try await exchangeAuthorizationCode(
            code,
            state: state,
            codeVerifier: pkce.codeVerifier,
            redirectURI: callback.redirectURI,
            clientId: clientId
        )
        try saveBundle(bundle)
        bundle.profile = await refreshAccountProfile(accessToken: bundle.accessToken)
        debugLog("Claude Code authorization succeeded.")
        return bundle
    }

    /// Validates the authorization response and returns its code.
    static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        if let error = value("error") {
            if error == "access_denied" {
                throw ClaudeCodeAuthError.accessDenied
            }
            throw ClaudeCodeAuthError.authorizationFailed(value("error_description") ?? error)
        }

        // The copy-code page returns `code#state`; accept that shape too.
        let rawCode = value("code")
        let codeParts = rawCode?.split(separator: "#", maxSplits: 1).map(String.init) ?? []
        let state = value("state") ?? (codeParts.count == 2 ? codeParts[1] : nil)

        guard state == expectedState else {
            throw ClaudeCodeAuthError.stateMismatch
        }
        guard let code = codeParts.first, !code.isEmpty else {
            throw ClaudeCodeAuthError.missingAuthorizationCode
        }
        return code
    }

    // MARK: - Token Refresh (single-flight)

    /// Returns a valid access token, refreshing if necessary.
    /// Uses single-flight to prevent concurrent refresh races.
    func validAccessToken() async throws -> String {
        guard var bundle = try synchronizedTokenBundle() else {
            throw ClaudeCodeAuthError.notAuthenticated
        }

        guard bundle.isExpired else { return bundle.accessToken }

        // Single-flight: if a refresh is already in progress, await it.
        if let existing = refreshTask {
            let refreshed = try await existing.value
            return refreshed.accessToken
        }

        let task = Task<ClaudeCodeTokenBundle, Error> {
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
        state: String,
        codeVerifier: String,
        redirectURI: URL,
        clientId: String
    ) async throws -> ClaudeCodeTokenBundle {
        let request = try makeTokenRequest(body: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI.absoluteString,
            "client_id": clientId,
            "code_verifier": codeVerifier,
            "state": state,
        ])

        debugLog("Exchanging Claude Code authorization code: \(ClaudeCodeOAuthConfig.tokenURL.absoluteString)")
        let (data, response) = try await session.data(for: request)
        let tokenResponse = try decodeTokenResponse(from: data, response: response)

        guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
            if let error = tokenResponse.error {
                throw ClaudeCodeAuthError.authorizationFailed(tokenResponse.errorDescription ?? error)
            }
            try validate(response: response, data: data)
            throw ClaudeCodeAuthError.authorizationFailed(
                String(localized: "Claude Code token exchange did not return an access token.")
            )
        }
        try validate(response: response, data: data)

        debugLog("Claude Code authorization-code exchange succeeded.")
        return ClaudeCodeTokenBundle(
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(Double(tokenResponse.expiresIn ?? 3600)),
            scopes: Self.scopes(from: tokenResponse.scope),
            accountId: tokenResponse.account?.uuid,
            email: tokenResponse.account?.emailAddress,
            organizationId: tokenResponse.organization?.uuid
        )
    }

    private func performRefresh(bundle: ClaudeCodeTokenBundle) async throws -> ClaudeCodeTokenBundle {
        guard let clientId = clientIdProvider() else {
            throw ClaudeCodeAuthError.clientIdNotConfigured
        }
        guard let refreshToken = bundle.refreshToken else {
            throw ClaudeCodeAuthError.noRefreshToken
        }

        let scopes = bundle.scopes ?? ClaudeCodeOAuthConfig.scopes
        let request = try makeTokenRequest(body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
            "scope": scopes.joined(separator: " "),
        ])

        debugLog("Refreshing Claude Code token: \(ClaudeCodeOAuthConfig.tokenURL.absoluteString)")
        let (data, response) = try await session.data(for: request)
        let tokenResponse = try decodeTokenResponse(from: data, response: response)

        guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
            if let error = tokenResponse.error {
                throw ClaudeCodeAuthError.refreshFailed(tokenResponse.errorDescription ?? error)
            }
            try validate(response: response, data: data)
            throw ClaudeCodeAuthError.refreshFailed("unknown")
        }
        try validate(response: response, data: data)

        let accountId = tokenResponse.account?.uuid
        let updated = ClaudeCodeTokenBundle(
            accessToken: accessToken,
            refreshToken: tokenResponse.refreshToken ?? bundle.refreshToken,
            expiresAt: Date().addingTimeInterval(Double(tokenResponse.expiresIn ?? 3600)),
            scopes: Self.scopes(from: tokenResponse.scope) ?? bundle.scopes,
            accountId: accountId ?? bundle.accountId,
            email: tokenResponse.account?.emailAddress ?? bundle.email,
            organizationId: tokenResponse.organization?.uuid ?? bundle.organizationId,
            profile: accountId == nil || accountId == bundle.accountId ? bundle.profile : nil
        )
        try saveBundle(updated)
        debugLog("Claude Code token refresh succeeded.")
        return updated
    }

    /// Profile lookup is optional: failure must not prevent login or usage refresh.
    func refreshAccountProfile(accessToken: String) async -> ClaudeCodeAccountProfile? {
        do {
            guard let originalBundle = try synchronizedTokenBundle(),
                  originalBundle.accessToken == accessToken else { return nil }

            var request = URLRequest(
                url: ClaudeCodeOAuthConfig.apiBaseURL.appending(path: ClaudeCodeOAuthConfig.profileEndpointPath),
                timeoutInterval: 10
            )
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("AIUM", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                debugLog("Claude Code profile request failed; keeping cached account display.")
                return nil
            }
            let profile = try ClaudeCodeAccountProfile.decode(from: data)

            // Do not attach an in-flight response to a different login or account.
            guard var bundle = try synchronizedTokenBundle(),
                  bundle.accessToken == accessToken,
                  bundle.accountId == originalBundle.accountId else { return nil }
            if bundle.profile != profile {
                bundle.profile = profile
                try saveBundle(bundle)
            }
            return profile
        } catch {
            debugLog("Unable to refresh Claude Code profile; keeping cached account display.")
            return nil
        }
    }

    private func makeTokenRequest(body: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: ClaudeCodeOAuthConfig.tokenURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AIUM", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private static func scopes(from value: String?) -> [String]? {
        let scopes = value?.split(separator: " ").map(String.init) ?? []
        return scopes.isEmpty ? nil : scopes
    }

    private func saveBundle(_ bundle: ClaudeCodeTokenBundle) throws {
        try persistence.save(bundle)
        _tokenBundle = bundle
    }

    private func synchronizedTokenBundle() throws -> ClaudeCodeTokenBundle? {
        guard synchronizesPersistedBundle else { return _tokenBundle }
        _tokenBundle = try persistence.load()
        return _tokenBundle
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200..<300).contains(httpResponse.statusCode)
        else { return }

        let body = String(data: data, encoding: .utf8)
        debugLog(
            "Claude Code auth HTTP \(httpResponse.statusCode) at \(httpResponse.url?.absoluteString ?? "unknown URL"): \(Self.preview(body))"
        )
        throw ClaudeCodeAuthError.httpError(httpResponse.statusCode, body)
    }

    private func decodeTokenResponse(from data: Data, response: URLResponse) throws -> ClaudeCodeTokenResponse {
        do {
            return try JSONDecoder().decode(ClaudeCodeTokenResponse.self, from: data)
        } catch {
            debugLog("Claude Code token response decode failed: \(Self.preview(String(data: data, encoding: .utf8)))")
            try validate(response: response, data: data)
            throw error
        }
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[AIUM][ClaudeCodeAuth] \(message())")
        #endif
    }

    private static func preview(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return "no body" }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 300 { return singleLine }
        return String(singleLine.prefix(300)) + "..."
    }
}

// MARK: - Errors

enum ClaudeCodeAuthError: LocalizedError, Equatable {
    case clientIdNotConfigured
    case notAuthenticated
    case cancelled
    case accessDenied
    case stateMismatch
    case missingAuthorizationCode
    case callbackListenerUnavailable(String)
    case noRefreshToken
    case httpError(Int, String?)
    case authorizationFailed(String)
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .clientIdNotConfigured:
            return String(localized: "Claude Code OAuth Client ID is not configured. Set CLAUDE_CODE_OAUTH_CLIENT_ID in the AIUM target build settings.")
        case .notAuthenticated: return String(localized: "Not signed in to Claude Code.")
        case .cancelled: return String(localized: "Sign-in was cancelled.")
        case .accessDenied: return String(localized: "Access was denied.")
        case .stateMismatch:
            return String(localized: "Claude Code sign-in returned an unexpected state. Please try again.")
        case .missingAuthorizationCode:
            return String(localized: "Claude Code sign-in did not return an authorization code.")
        case .callbackListenerUnavailable(let reason):
            return String.localizedStringWithFormat(
                String(localized: "Could not start the local sign-in listener: %@"),
                reason
            )
        case .noRefreshToken: return String(localized: "No refresh token available.")
        case .httpError(let code, let body):
            return String.localizedStringWithFormat(
                String(localized: "Claude Code auth error %lld: %@"),
                Int64(code),
                Self.preview(body)
            )
        case .authorizationFailed(let message):
            return String.localizedStringWithFormat(
                String(localized: "Claude Code authorization failed: %@"),
                message
            )
        case .refreshFailed(let msg):
            return String.localizedStringWithFormat(String(localized: "Token refresh failed: %@"), msg)
        }
    }

    private static func preview(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return String(localized: "no body") }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 300 { return singleLine }
        return String(singleLine.prefix(300)) + "..."
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
