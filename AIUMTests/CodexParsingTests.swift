import XCTest
@testable import AIUM

final class CodexParsingTests: XCTestCase {
    // MARK: - Codex usage decoding

    func testDecodeCodexBackendRateLimitResponse() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "rateLimits": [
            {
              "limitId": "gpt-5-codex",
              "limitName": "GPT-5 Codex",
              "individualLimit": 100,
              "primary": {
                "remaining": 25,
                "limitWindowSeconds": 18000,
                "resetAfterSeconds": 3600
              },
              "secondary": {
                "usedPercent": 40,
                "windowDurationMins": 10080,
                "resetsAt": "2024-01-16T00:00:00Z"
              }
            }
          ],
          "rateLimitResetCredits": { "remaining": 2 }
        }
        """.data(using: .utf8)!

        let response = try CodexUsageResponse.decode(from: json, now: now)

        XCTAssertEqual(response.windows.count, 2)
        XCTAssertEqual(try XCTUnwrap(response.resetCredits), 2, accuracy: 0.001)

        let primary = response.windows[0]
        XCTAssertEqual(primary.used, 75, accuracy: 0.001)
        XCTAssertEqual(primary.limit, 100, accuracy: 0.001)
        XCTAssertEqual(primary.windowDurationMins, 300)
        XCTAssertEqual(primary.windowKind, .custom)
        XCTAssertEqual(primary.resetAt, now.addingTimeInterval(3600))

        let secondary = response.windows[1]
        XCTAssertEqual(secondary.used, 40, accuracy: 0.001)
        XCTAssertEqual(secondary.limit, 100, accuracy: 0.001)
        XCTAssertEqual(secondary.windowDurationMins, 10080)
    }

    func testDecodeLegacySnakeCaseRateLimitResponse() throws {
        let json = """
        {
          "primary_window": {
            "limit": 50,
            "remaining": 20,
            "reset_at": "2024-01-15T12:00:00Z",
            "window_duration_mins": 60
          },
          "secondary_window": {
            "limit": 500,
            "remaining": 350,
            "reset_at": "2024-01-16T00:00:00Z",
            "window_duration_mins": 1440
          },
          "reset_credits": 5.0
        }
        """.data(using: .utf8)!

        let response = try CodexUsageResponse.decode(from: json)

        XCTAssertEqual(response.windows.count, 2)
        XCTAssertEqual(response.windows[0].used, 30, accuracy: 0.001)
        XCTAssertEqual(response.windows[0].limit, 50, accuracy: 0.001)
        XCTAssertEqual(response.windows[0].windowKind, .hourly)
        XCTAssertEqual(response.windows[1].used, 150, accuracy: 0.001)
        XCTAssertEqual(response.windows[1].windowKind, .daily)
        XCTAssertEqual(try XCTUnwrap(response.resetCredits), 5, accuracy: 0.001)
    }

    func testDecodePercentOnlyWindowUsesPercentUnit() throws {
        let json = """
        {
          "rateLimits": [
            {
              "limitName": "Plus",
              "primary": {
                "usedPercent": 0.655,
                "windowDurationMins": 300
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try CodexUsageResponse.decode(from: json)
        let window = try XCTUnwrap(response.windows.first)

        XCTAssertEqual(window.used, 65.5, accuracy: 0.001)
        XCTAssertEqual(window.limit, 100, accuracy: 0.001)
        XCTAssertEqual(window.unit, "percent")
    }

    func testNormalizationWithTokenBundle() throws {
        let bundle = CodexTokenBundle(
            idToken: "id",
            accessToken: "access",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            accountId: "acct-token",
            email: "token@example.com"
        )
        let json = """
        {
          "primary_window": {
            "limit": 50,
            "remaining": 25
          }
        }
        """.data(using: .utf8)!

        let response = try CodexUsageResponse.decode(from: json)
        let provider = PrivateCodexUsageProvider()
        let snapshots = provider.normalizeSnapshots(response, tokenBundle: bundle)

        XCTAssertEqual(snapshots.first?.accountId, "acct-token")
        XCTAssertEqual(snapshots.first?.displayName, "token@example.com")
        XCTAssertEqual(snapshots.first?.used, 25)
    }

    func testResponseAccountOverridesTokenBundle() throws {
        let bundle = CodexTokenBundle(
            idToken: "id",
            accessToken: "access",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            accountId: "acct-token",
            email: "token@example.com"
        )
        let json = """
        {
          "accountId": "acct-response",
          "email": "response@example.com",
          "primary": {
            "limit": 10,
            "used": 4
          }
        }
        """.data(using: .utf8)!

        let response = try CodexUsageResponse.decode(from: json)
        let provider = PrivateCodexUsageProvider()
        let snapshots = provider.normalizeSnapshots(response, tokenBundle: bundle)

        XCTAssertEqual(snapshots.first?.accountId, "acct-response")
        XCTAssertEqual(snapshots.first?.displayName, "response@example.com")
    }

    // MARK: - OAuth configuration

    func testCodexClientIdRejectsPlaceholderAndEmptyValues() {
        XCTAssertNil(CodexOAuthConfig.resolvedClientId(from: nil))
        XCTAssertNil(CodexOAuthConfig.resolvedClientId(from: ""))
        XCTAssertNil(CodexOAuthConfig.resolvedClientId(from: "   "))
        XCTAssertNil(CodexOAuthConfig.resolvedClientId(from: "YOUR_CODEX_CLIENT_ID"))
        XCTAssertNil(CodexOAuthConfig.resolvedClientId(from: "$(CODEX_OAUTH_CLIENT_ID)"))
    }

    func testCodexClientIdAcceptsConfiguredValue() {
        XCTAssertEqual(
            CodexOAuthConfig.resolvedClientId(from: "  app_EMoamEEZ73f0CkXaXp7hrann  "),
            "app_EMoamEEZ73f0CkXaXp7hrann"
        )
    }

    func testStartDeviceFlowFailsBeforeNetworkWhenClientIdIsMissing() async throws {
        let session = URLSession(configuration: .ephemeral)
        let provider = CodexAuthProvider(session: session, clientIdProvider: { nil })

        do {
            _ = try await provider.startDeviceFlow()
            XCTFail("Expected missing client ID to fail before starting device flow.")
        } catch CodexAuthError.clientIdNotConfigured {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCodexDeviceCodeResponseDecodesCurrentUserCodeShape() throws {
        let data = Data("""
        {
          "device_auth_id": "deviceauth-123",
          "user_code": "ABCD-EFGH",
          "interval": "5",
          "expires_at": "2026-06-23T14:52:11.780132+00:00"
        }
        """.utf8)

        let response = try JSONDecoder().decode(CodexDeviceCodeResponse.self, from: data)

        XCTAssertEqual(response.deviceCode, "deviceauth-123")
        XCTAssertEqual(response.userCode, "ABCD-EFGH")
        XCTAssertEqual(response.interval, 5)
        XCTAssertEqual(response.verificationUri, "https://auth.openai.com/codex/device")
    }

    func testPollForTokenContinuesAfterPendingDeviceAuthorization() async throws {
        defer { CodexMockURLProtocol.requestHandler = nil }

        var requestCount = 0
        CodexMockURLProtocol.requestHandler = { request in
            requestCount += 1
            let statusCode = requestCount == 1 ? 404 : 200
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!

            if requestCount == 1 {
                return (response, Data())
            }

            if request.url?.path.contains("/deviceauth/token") == true {
                return (response, Data("""
                {
                  "authorization_code": "authorization-code",
                  "code_challenge": "challenge",
                  "code_verifier": "verifier"
                }
                """.utf8))
            }

            return (response, Data("""
            {
              "id_token": "id-token",
              "access_token": "access-token",
              "refresh_token": "refresh-token",
              "expires_in": 3600
            }
            """.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexMockURLProtocol.self]
        let provider = CodexAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "client-id" },
            sleep: { _ in }
        )

        let bundle = try await provider.pollForToken(deviceCode: "device-code", userCode: "USER-CODE", interval: 0)

        XCTAssertEqual(bundle.accessToken, "access-token")
        XCTAssertEqual(bundle.refreshToken, "refresh-token")
        XCTAssertEqual(requestCount, 3)
        await provider.logout()
    }

    func testAuthStateSynchronizesAcrossProviderInstances() async throws {
        let store = CodexTokenPersistenceBox()
        let persistence = CodexTokenPersistence(
            load: { store.load() },
            save: { store.save($0) },
            delete: { store.delete() }
        )
        let firstProvider = CodexAuthProvider(persistence: persistence)
        let secondProvider = CodexAuthProvider(persistence: persistence)
        let bundle = CodexTokenBundle(
            idToken: "id",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )

        let firstInitialStatus = await firstProvider.isAuthenticated
        let secondInitialStatus = await secondProvider.isAuthenticated
        XCTAssertFalse(firstInitialStatus)
        XCTAssertFalse(secondInitialStatus)

        try persistence.save(bundle)

        let firstAuthenticatedStatus = await firstProvider.isAuthenticated
        let secondBundle = await secondProvider.tokenBundle
        XCTAssertTrue(firstAuthenticatedStatus)
        XCTAssertEqual(secondBundle?.accessToken, "access")

        await secondProvider.logout()

        let firstLoggedOutStatus = await firstProvider.isAuthenticated
        let firstLoggedOutBundle = await firstProvider.tokenBundle
        XCTAssertFalse(firstLoggedOutStatus)
        XCTAssertNil(firstLoggedOutBundle)
    }

    // MARK: - Account identity

    func testAccountIdentityExtractsClaimsFromTokens() {
        let accessToken = makeJWT(payload: """
        {
          "https://api.openai.com/auth": {
            "chatgpt_account_id": "acct-access"
          },
          "https://api.openai.com/profile": {
            "email": "access@example.com"
          }
        }
        """)

        let identity = CodexAccountIdentity.extract(accessToken: accessToken, idToken: nil)

        XCTAssertEqual(identity.accountId, "acct-access")
        XCTAssertEqual(identity.email, "access@example.com")
    }

    // MARK: - Token refresh single-flight

    func testTokenBundleIsExpiredNearExpiry() {
        let bundle = CodexTokenBundle(
            idToken: "id",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(30) // expires in 30s (< 60s threshold)
        )
        XCTAssertTrue(bundle.isExpired)
    }

    func testTokenBundleIsNotExpiredFarFromExpiry() {
        let bundle = CodexTokenBundle(
            idToken: "id",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(bundle.isExpired)
    }

    func testValidAccessTokenRefreshesExpiredBundleAndPreservesAccount() async throws {
        defer { CodexMockURLProtocol.requestHandler = nil }

        var requestCount = 0
        CodexMockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            return (response, Data("""
            {
              "id_token": "new-id",
              "access_token": "new-access",
              "refresh_token": "new-refresh",
              "expires_in": 7200
            }
            """.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexMockURLProtocol.self]
        let expiredBundle = CodexTokenBundle(
            idToken: "old-id",
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(-10),
            accountId: "acct-old",
            email: "old@example.com"
        )
        let provider = CodexAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "client-id" },
            initialTokenBundle: expiredBundle
        )

        let accessToken = try await provider.validAccessToken()
        let updatedBundle = await provider.tokenBundle

        XCTAssertEqual(accessToken, "new-access")
        XCTAssertEqual(updatedBundle?.refreshToken, "new-refresh")
        XCTAssertEqual(updatedBundle?.accountId, "acct-old")
        XCTAssertEqual(updatedBundle?.email, "old@example.com")
        XCTAssertEqual(requestCount, 1)
        await provider.logout()
    }

    // MARK: - Usage provider networking

    func testUsageProviderSendsAccountHeaderAndUpdatesProfile() async throws {
        var seenRequests: [URLRequest] = []
        CodexMockURLProtocol.requestHandler = { request in
            seenRequests.append(request)

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            if request.url?.path.contains("/profiles/me") == true {
                return (response, Data(#"{"accountId":"acct-profile","email":"profile@example.com"}"#.utf8))
            }

            return (response, Data("""
            {
              "rateLimits": [
                {
                  "limitName": "Plus",
                  "individualLimit": 100,
                  "primary": { "remaining": 60, "windowDurationMins": 300 }
                }
              ]
            }
            """.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexMockURLProtocol.self]
        let auth = FakeCodexAuthProvider(
            bundle: CodexTokenBundle(
                idToken: "id",
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600),
                accountId: "acct-token",
                email: nil
            )
        )
        let provider = PrivateCodexUsageProvider(
            authProvider: auth,
            backendBaseURL: URL(string: "https://example.test/backend-api")!,
            session: URLSession(configuration: configuration)
        )

        let snapshots = try await provider.fetchUsage()

        XCTAssertEqual(snapshots.count, 1)
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.used, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.displayName, "profile@example.com")
        let updatedBundle = await auth.tokenBundle
        XCTAssertEqual(updatedBundle?.accountId, "acct-profile")

        let usageRequest = try XCTUnwrap(seenRequests.last)
        XCTAssertEqual(usageRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access")
        XCTAssertEqual(usageRequest.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct-profile")
    }

    // MARK: - Helpers

    private func makeJWT(payload: String) -> String {
        let header = #"{"alg":"none"}"#.data(using: .utf8)!.base64URLEncodedString()
        let body = payload.data(using: .utf8)!.base64URLEncodedString()
        return "\(header).\(body).signature"
    }
}

private actor FakeCodexAuthProvider: CodexAuthProviding {
    private var bundle: CodexTokenBundle?

    init(bundle: CodexTokenBundle?) {
        self.bundle = bundle
    }

    var tokenBundle: CodexTokenBundle? {
        get async { bundle }
    }

    var isAuthenticated: Bool {
        get async { bundle != nil }
    }

    func startDeviceFlow() async throws -> CodexDeviceCodeResponse {
        throw CodexAuthError.unknown("not implemented")
    }

    func pollForToken(deviceCode: String, userCode: String, interval: Int) async throws -> CodexTokenBundle {
        throw CodexAuthError.unknown("not implemented")
    }

    func validAccessToken() async throws -> String {
        guard let accessToken = bundle?.accessToken else {
            throw CodexAuthError.notAuthenticated
        }
        return accessToken
    }

    func updateAccount(accountId: String?, email: String?) throws {
        bundle?.accountId = accountId ?? bundle?.accountId
        bundle?.email = email ?? bundle?.email
    }

    func logout() {
        bundle = nil
    }
}

private final class CodexTokenPersistenceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var bundle: CodexTokenBundle?

    func load() -> CodexTokenBundle? {
        lock.lock()
        defer { lock.unlock() }
        return bundle
    }

    func save(_ bundle: CodexTokenBundle) {
        lock.lock()
        defer { lock.unlock() }
        self.bundle = bundle
    }

    func delete() {
        lock.lock()
        defer { lock.unlock() }
        bundle = nil
    }
}

private final class CodexMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
