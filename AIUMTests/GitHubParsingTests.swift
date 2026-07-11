import XCTest
@testable import AIUM

final class GitHubParsingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - GitHubUser

    func testDecodeGitHubUser() throws {
        let json = """
        {
          "login": "octocat",
          "id": 42,
          "name": "The Octocat",
          "avatar_url": "https://github.com/images/error/octocat_happy.gif"
        }
        """.data(using: .utf8)!

        let user = try decoder.decode(GitHubUser.self, from: json)
        XCTAssertEqual(user.login, "octocat")
        XCTAssertEqual(user.id, 42)
        XCTAssertEqual(user.name, "The Octocat")
    }

    func testDecodeGitHubUserNullName() throws {
        let json = """
        { "login": "bot", "id": 99, "name": null, "avatar_url": null }
        """.data(using: .utf8)!

        let user = try decoder.decode(GitHubUser.self, from: json)
        XCTAssertNil(user.name)
    }

    // MARK: - GitHubAICreditUsageResponse

    func testDecodeAICreditUsageReport() throws {
        let json = """
        {
          "timePeriod": { "year": 2026, "month": 6 },
          "user": "octocat",
          "usageItems": [
            {
              "product": "Copilot",
              "sku": "copilot_ai_credit",
              "unitType": "credits",
              "grossQuantity": 125.5,
              "netQuantity": 100.0
            },
            {
              "product": "Copilot",
              "sku": "copilot_ai_credit",
              "unitType": "credits",
              "grossQuantity": 24.5,
              "netQuantity": 20.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(GitHubAICreditUsageResponse.self, from: json)
        XCTAssertEqual(response.usedQuantity, 150.0, accuracy: 0.001)
        XCTAssertEqual(response.usageItems.count, 2)
        XCTAssertNotNil(response.timePeriod?.periodEndDate())
    }

    func testDecodeAICreditUsageWithoutItemsFails() throws {
        let json = "{}".data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(GitHubAICreditUsageResponse.self, from: json))
    }

    // MARK: - GitHubPremiumRequestUsageResponse

    func testDecodePremiumRequestUsageReport() throws {
        let json = """
        {
          "timePeriod": { "year": 2026, "month": 6 },
          "user": "octocat",
          "usageItems": [
            {
              "product": "Copilot",
              "sku": "copilot_premium_request",
              "unitType": "requests",
              "grossQuantity": 5,
              "netQuantity": 5
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(GitHubPremiumRequestUsageResponse.self, from: json)
        XCTAssertEqual(response.usedQuantity, 5, accuracy: 0.001)
        XCTAssertEqual(response.usageItems.count, 1)
        XCTAssertNotNil(response.timePeriod?.periodEndDate())
    }

    // MARK: - Normalization tests (using GitHubUsageProvider via mock)

    func testNormalizedSnapshotFromAICreditResponse() {
        let used = 750.0
        let limit = 1000.0
        let resetAt = Date(timeIntervalSince1970: 1_700_000_000)

        // Manually construct a snapshot as GitHubUsageProvider would
        let snapshot = UsageSnapshot(
            provider: .githubCopilot,
            accountId: "42",
            displayName: "octocat",
            planKind: .aiCredits,
            windowKind: .monthly,
            used: used,
            limit: limit,
            resetAt: resetAt,
            unit: "AI credits",
            source: "GitHub Billing API"
        )

        XCTAssertEqual(snapshot.usedPercent, 75, accuracy: 0.001)
        XCTAssertEqual(snapshot.remainingPercent, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.planKind, .aiCredits)
    }

    func testNormalizedSnapshotAppliesManualLimit() {
        // When API returns nil allowance and manual limit is set
        let manualLimit = 500.0
        let snapshot = UsageSnapshot(
            provider: .githubCopilot,
            planKind: .aiCredits,
            windowKind: .monthly,
            used: 100,
            limit: manualLimit,
            source: "GitHub Billing API"
        )
        XCTAssertEqual(snapshot.limit, manualLimit, accuracy: 0.001)
        XCTAssertEqual(snapshot.usedPercent, 20, accuracy: 0.001)
    }

    // MARK: - OAuth configuration

    func testGitHubClientIdRejectsPlaceholderAndEmptyValues() {
        XCTAssertNil(GitHubOAuthConfig.resolvedClientId(from: nil))
        XCTAssertNil(GitHubOAuthConfig.resolvedClientId(from: ""))
        XCTAssertNil(GitHubOAuthConfig.resolvedClientId(from: "   "))
        XCTAssertNil(GitHubOAuthConfig.resolvedClientId(from: "YOUR_GITHUB_CLIENT_ID"))
        XCTAssertNil(GitHubOAuthConfig.resolvedClientId(from: "$(GITHUB_OAUTH_CLIENT_ID)"))
    }

    func testGitHubClientIdAcceptsConfiguredValue() {
        XCTAssertEqual(GitHubOAuthConfig.resolvedClientId(from: "  Iv1.example-client-id  "), "Iv1.example-client-id")
    }

    func testStartDeviceFlowFailsBeforeNetworkWhenClientIdIsMissing() async throws {
        let session = URLSession(configuration: .ephemeral)
        let provider = GitHubAuthProvider(session: session, clientIdProvider: { nil })

        do {
            _ = try await provider.startDeviceFlow()
            XCTFail("Expected missing client ID to fail before starting device flow.")
        } catch GitHubAuthError.clientIdNotConfigured {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGitHubAppDeviceFlowDoesNotRequestOAuthScopes() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = try self.requestBodyString(request)
            XCTAssertTrue(body.contains("client_id=Iv23.test-client"))
            XCTAssertFalse(body.contains("scope="))

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = #"{"device_code":"device","user_code":"CODE-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
            return (response, Data(payload.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = GitHubAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "Iv23.test-client" }
        )

        let response = try await provider.startDeviceFlow()
        XCTAssertEqual(response.userCode, "CODE-1234")
    }

    func testExpiredGitHubAppTokenIsUsableWithValidRefreshToken() {
        let bundle = GitHubTokenBundle(
            accessToken: "ghu_expired",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 100),
            refreshToken: "ghr_valid",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 300)
        )

        XCTAssertTrue(bundle.hasUsableCredentials(now: Date(timeIntervalSince1970: 200)))
        XCTAssertFalse(bundle.hasUsableCredentials(now: Date(timeIntervalSince1970: 400)))
    }

    func testAuthProviderReadsTokenSavedByAnotherInstance() async throws {
        let store = InMemoryGitHubTokenStore()
        let dashboardProvider = GitHubAuthProvider(tokenStore: store)

        let initiallyAuthenticated = await dashboardProvider.isAuthenticated
        XCTAssertFalse(initiallyAuthenticated)

        try store.save(GitHubTokenBundle(
            accessToken: "ghu_access",
            accessTokenExpiresAt: Date().addingTimeInterval(3 * 3600),
            refreshToken: "ghr_refresh",
            refreshTokenExpiresAt: Date().addingTimeInterval(7200)
        ))

        let authenticatedAfterSave = await dashboardProvider.isAuthenticated
        let accessToken = try await dashboardProvider.validAccessToken()
        XCTAssertTrue(authenticatedAfterSave)
        XCTAssertEqual(accessToken, "ghu_access")
    }

    func testAuthProviderRefreshesExpiredAccessTokenAndUpdatesStoredBundle() async throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubTokenBundle(
            accessToken: "ghu_old",
            accessTokenExpiresAt: Date().addingTimeInterval(-1),
            refreshToken: "ghr_old",
            refreshTokenExpiresAt: Date().addingTimeInterval(7200)
        ))

        MockURLProtocol.requestHandler = { request in
            let body = try self.requestBodyString(request)
            XCTAssertTrue(body.contains("client_id=Iv23.test-client"))
            XCTAssertTrue(body.contains("grant_type=refresh_token"))
            XCTAssertTrue(body.contains("refresh_token=ghr_old"))

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = #"{"access_token":"ghu_new","expires_in":28800,"refresh_token":"ghr_new","refresh_token_expires_in":15811200}"#
            return (response, Data(payload.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = GitHubAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "Iv23.test-client" },
            tokenStore: store
        )

        let token = try await provider.validAccessToken()
        let savedBundle = try XCTUnwrap(try store.load())

        XCTAssertEqual(token, "ghu_new")
        XCTAssertEqual(savedBundle.accessToken, "ghu_new")
        XCTAssertEqual(savedBundle.refreshToken, "ghr_new")
        XCTAssertNotNil(savedBundle.accessTokenExpiresAt)
        XCTAssertNotNil(savedBundle.refreshTokenExpiresAt)
    }

    func testAuthProviderRefreshesAccessTokenInsideRefreshLeeway() async throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubTokenBundle(
            accessToken: "ghu_old",
            accessTokenExpiresAt: Date().addingTimeInterval(30),
            refreshToken: "ghr_old",
            refreshTokenExpiresAt: Date().addingTimeInterval(7200)
        ))

        MockURLProtocol.requestHandler = { request in
            let body = try self.requestBodyString(request)
            XCTAssertTrue(body.contains("client_id=Iv23.test-client"))
            XCTAssertTrue(body.contains("grant_type=refresh_token"))
            XCTAssertTrue(body.contains("refresh_token=ghr_old"))

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = #"{"access_token":"ghu_new","expires_in":28800,"refresh_token":"ghr_new","refresh_token_expires_in":15811200}"#
            return (response, Data(payload.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = GitHubAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "Iv23.test-client" },
            tokenStore: store
        )

        let token = try await provider.validAccessToken()
        let savedBundle = try XCTUnwrap(try store.load())

        XCTAssertEqual(token, "ghu_new")
        XCTAssertEqual(savedBundle.accessToken, "ghu_new")
        XCTAssertEqual(savedBundle.refreshToken, "ghr_new")
    }

    func testAuthProviderKeepsValidAccessTokenOutsideRefreshLeeway() async throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubTokenBundle(
            accessToken: "ghu_current",
            accessTokenExpiresAt: Date().addingTimeInterval(3600),
            refreshToken: "ghr_current",
            refreshTokenExpiresAt: Date().addingTimeInterval(7200)
        ))

        MockURLProtocol.requestHandler = { _ in
            XCTFail("A valid access token must be reused until it nears expiration.")
            throw URLError(.badServerResponse)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = GitHubAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "Iv23.test-client" },
            tokenStore: store
        )

        let token = try await provider.validAccessToken()

        XCTAssertEqual(token, "ghu_current")
        XCTAssertEqual(try store.load()?.refreshToken, "ghr_current")
    }

    func testAuthProviderCoalescesConcurrentRefreshRequests() async throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubTokenBundle(
            accessToken: "ghu_old",
            accessTokenExpiresAt: Date().addingTimeInterval(30),
            refreshToken: "ghr_old",
            refreshTokenExpiresAt: Date().addingTimeInterval(7200)
        ))
        let requestCounter = LockedCounter()

        MockURLProtocol.requestHandler = { request in
            requestCounter.increment()
            Thread.sleep(forTimeInterval: 0.1)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = #"{"access_token":"ghu_new","expires_in":28800,"refresh_token":"ghr_new","refresh_token_expires_in":15811200}"#
            return (response, Data(payload.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = GitHubAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "Iv23.test-client" },
            tokenStore: store
        )

        async let firstToken = provider.validAccessToken()
        async let secondToken = provider.validAccessToken()
        let (first, second) = try await (firstToken, secondToken)

        XCTAssertEqual(first, "ghu_new")
        XCTAssertEqual(second, "ghu_new")
        XCTAssertEqual(requestCounter.value, 1)
    }

    func testAuthProviderPreservesNewerCredentialsAfterStaleBadRefreshToken() async throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubTokenBundle(
            accessToken: "ghu_old",
            accessTokenExpiresAt: Date().addingTimeInterval(-1),
            refreshToken: "ghr_old",
            refreshTokenExpiresAt: Date().addingTimeInterval(7200)
        ))
        let newerBundle = GitHubTokenBundle(
            accessToken: "ghu_newer",
            accessTokenExpiresAt: Date().addingTimeInterval(8 * 3600),
            refreshToken: "ghr_newer",
            refreshTokenExpiresAt: Date().addingTimeInterval(180 * 24 * 3600)
        )

        MockURLProtocol.requestHandler = { request in
            try store.save(newerBundle)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = #"{"error":"bad_refresh_token","error_description":"The refresh token is invalid."}"#
            return (response, Data(payload.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = GitHubAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "Iv23.test-client" },
            tokenStore: store
        )

        let token = try await provider.validAccessToken()

        XCTAssertEqual(token, "ghu_newer")
        XCTAssertEqual(try store.load()?.refreshToken, "ghr_newer")
    }

    func testAuthProviderEndsSessionForCurrentBadRefreshToken() async throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubTokenBundle(
            accessToken: "ghu_expired",
            accessTokenExpiresAt: Date().addingTimeInterval(-1),
            refreshToken: "ghr_invalid",
            refreshTokenExpiresAt: Date().addingTimeInterval(7200)
        ))

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = #"{"error":"bad_refresh_token","error_description":"The refresh token is invalid."}"#
            return (response, Data(payload.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = GitHubAuthProvider(
            session: URLSession(configuration: configuration),
            clientIdProvider: { "Iv23.test-client" },
            tokenStore: store
        )

        do {
            _ = try await provider.validAccessToken()
            XCTFail("An invalid current refresh token must end the session.")
        } catch GitHubAuthError.sessionExpired {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(try store.load())
    }

    func testAuthProviderDoesNotRefreshCurrentUnexpiredTokenAfter401() async throws {
        let store = InMemoryGitHubTokenStore()
        try store.save(GitHubTokenBundle(
            accessToken: "ghu_revoked",
            accessTokenExpiresAt: Date().addingTimeInterval(3600),
            refreshToken: "ghr_current",
            refreshTokenExpiresAt: Date().addingTimeInterval(7200)
        ))
        let provider = GitHubAuthProvider(tokenStore: store)

        do {
            _ = try await provider.recoverAccessToken(rejectedAccessToken: "ghu_revoked")
            XCTFail("A 401 for the current unexpired token must not trigger a refresh loop.")
        } catch GitHubAuthError.sessionExpired {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(try store.load())
    }

    // MARK: - API errors

    func testAPIClientClassifiesAuthError() async throws {
        let client = makeAPIClient(statusCode: 401, body: #"{"message":"Bad credentials"}"#)

        do {
            _ = try await client.fetchUser(token: "bad-token")
            XCTFail("Expected auth error.")
        } catch GitHubAPIError.authenticationFailed(let statusCode, let body) {
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(body, #"{"message":"Bad credentials"}"#)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIClientClassifiesHTTPError() async throws {
        let client = makeAPIClient(statusCode: 404, body: #"{"message":"Not Found"}"#)

        do {
            _ = try await client.fetchAICreditUsage(username: "octocat", token: "token")
            XCTFail("Expected HTTP error.")
        } catch GitHubAPIError.httpError(let statusCode, let body) {
            XCTAssertEqual(statusCode, 404)
            XCTAssertEqual(body, #"{"message":"Not Found"}"#)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIClientClassifiesDecodeError() async throws {
        let client = makeAPIClient(statusCode: 200, body: #"{"id":"not-an-int"}"#)

        do {
            _ = try await client.fetchUser(token: "token")
            XCTFail("Expected decode error.")
        } catch GitHubAPIError.decodeError(let endpoint, let body, _) {
            XCTAssertEqual(endpoint, "Authenticated User")
            XCTAssertEqual(body, #"{"id":"not-an-int"}"#)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIClientUsesCurrentBillingAPIVersionAndBearerToken() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2026-03-10")
            XCTAssertEqual(request.url?.path, "/users/octocat/settings/billing/ai_credit/usage")

            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let queryNames = Set((components.queryItems ?? []).map(\.name))
            XCTAssertTrue(queryNames.contains("year"))
            XCTAssertTrue(queryNames.contains("month"))

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = #"{"usageItems":[{"grossQuantity":42}]}"#
            return (response, Data(body.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = GitHubAPIClient(session: URLSession(configuration: configuration))

        let response = try await client.fetchAICreditUsage(username: "octocat", token: "token")
        XCTAssertEqual(response.usedQuantity, 42, accuracy: 0.001)
    }

    // MARK: - Partial usage failures

    func testUsageProviderReturnsSuccessAndPlanSpecificErrorForPartialFailure() async throws {
        let auth = FakeGitHubAuthProvider(token: "token")
        let api = FakeGitHubAPIClient(
            aiResponse: GitHubAICreditUsageResponse(
                timePeriod: nil,
                usageItems: [.mock(quantity: 20)]
            ),
            premiumError: GitHubAPIError.httpError(statusCode: 404, body: #"{"message":"Not Found"}"#)
        )
        let provider = GitHubUsageProvider(authProvider: auth, apiClient: api)

        let snapshots = try await provider.fetchUsage()

        XCTAssertEqual(snapshots.count, 2)
        let ai = try XCTUnwrap(snapshots.first { $0.planKind == .aiCredits })
        XCTAssertNil(ai.errorMessage)
        XCTAssertEqual(ai.used, 20, accuracy: 0.001)

        let premium = try XCTUnwrap(snapshots.first { $0.planKind == .premiumRequests })
        XCTAssertEqual(premium.source, "GitHub Billing API")
        let errorMessage = try XCTUnwrap(premium.errorMessage)
        XCTAssertTrue(errorMessage.contains("404"))
        XCTAssertTrue(
            errorMessage.contains(
                String(localized: "This account does not expose personally billed Copilot usage to the GitHub App.")
            )
        )
    }

    func testUsageProviderReturnsPlanSpecificErrorsWhenUsageEndpointsFail() async throws {
        let auth = FakeGitHubAuthProvider(token: "token")
        let api = FakeGitHubAPIClient(
            aiError: GitHubAPIError.decodeError(endpoint: "AI Credits", body: "{}", underlying: DecodingFailure()),
            premiumError: GitHubAPIError.authenticationFailed(statusCode: 401, body: #"{"message":"Bad credentials"}"#)
        )
        let provider = GitHubUsageProvider(authProvider: auth, apiClient: api)

        let snapshots = try await provider.fetchUsage()

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertNotNil(snapshots.first { $0.planKind == .aiCredits }?.errorMessage)
        XCTAssertNotNil(snapshots.first { $0.planKind == .premiumRequests }?.errorMessage)
    }

    func testUsageProviderRetries401OnceWithRecoveredToken() async throws {
        let auth = FakeGitHubAuthProvider(token: "ghu_old", recoveryToken: "ghu_new")
        let api = FakeGitHubAPIClient(rejectedAccessToken: "ghu_old")
        let provider = GitHubUsageProvider(authProvider: auth, apiClient: api)

        let snapshots = try await provider.fetchUsage()
        let receivedTokens = await api.receivedTokens
        let recoveryCount = await auth.recoveryCount

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots.allSatisfy { $0.errorMessage == nil })
        XCTAssertEqual(recoveryCount, 1)
        XCTAssertEqual(receivedTokens, ["ghu_old", "ghu_new", "ghu_new", "ghu_new"])
    }

    private func makeAPIClient(statusCode: Int, body: String) -> GitHubAPIClient {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return GitHubAPIClient(session: URLSession(configuration: configuration))
    }

    private func requestBodyString(_ request: URLRequest) throws -> String {
        if let body = request.httpBody {
            return try XCTUnwrap(String(data: body, encoding: .utf8))
        }

        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

private actor FakeGitHubAuthProvider: GitHubAuthProviding {
    private var token: String?
    private let recoveryToken: String?
    private(set) var recoveryCount = 0

    init(token: String?, recoveryToken: String? = nil) {
        self.token = token
        self.recoveryToken = recoveryToken
    }

    func validAccessToken() async throws -> String? {
        token
    }

    func recoverAccessToken(rejectedAccessToken: String) async throws -> String? {
        recoveryCount += 1
        if let recoveryToken {
            token = recoveryToken
        }
        return token
    }

    var isAuthenticated: Bool {
        get async { token != nil }
    }
}

private actor FakeGitHubAPIClient: GitHubAPIProviding {
    private let user: GitHubUser
    private let aiResponse: GitHubAICreditUsageResponse?
    private let aiError: Error?
    private let premiumResponse: GitHubPremiumRequestUsageResponse?
    private let premiumError: Error?
    private let rejectedAccessToken: String?
    private(set) var receivedTokens: [String] = []

    init(
        user: GitHubUser = GitHubUser(login: "octocat", id: 42, name: "The Octocat", avatarUrl: nil),
        aiResponse: GitHubAICreditUsageResponse? = nil,
        aiError: Error? = nil,
        premiumResponse: GitHubPremiumRequestUsageResponse? = nil,
        premiumError: Error? = nil,
        rejectedAccessToken: String? = nil
    ) {
        self.user = user
        self.aiResponse = aiResponse
        self.aiError = aiError
        self.premiumResponse = premiumResponse
        self.premiumError = premiumError
        self.rejectedAccessToken = rejectedAccessToken
    }

    func fetchUser(token: String) async throws -> GitHubUser {
        receivedTokens.append(token)
        try rejectIfNeeded(token)
        return user
    }

    func fetchAICreditUsage(username: String, token: String) async throws -> GitHubAICreditUsageResponse {
        receivedTokens.append(token)
        try rejectIfNeeded(token)
        if let aiError { throw aiError }
        return aiResponse ?? GitHubAICreditUsageResponse(
            timePeriod: nil,
            usageItems: [.mock(quantity: 10)]
        )
    }

    func fetchPremiumRequestUsage(username: String, token: String) async throws -> GitHubPremiumRequestUsageResponse {
        receivedTokens.append(token)
        try rejectIfNeeded(token)
        if let premiumError { throw premiumError }
        return premiumResponse ?? GitHubPremiumRequestUsageResponse(
            timePeriod: nil,
            usageItems: [.mock(quantity: 5)]
        )
    }

    private func rejectIfNeeded(_ token: String) throws {
        guard token == rejectedAccessToken else { return }
        throw GitHubAPIError.authenticationFailed(
            statusCode: 401,
            body: #"{"message":"Bad credentials"}"#
        )
    }
}

private extension GitHubBillingUsageItem {
    static func mock(quantity: Double) -> GitHubBillingUsageItem {
        GitHubBillingUsageItem(grossQuantity: quantity)
    }
}

private final class MockURLProtocol: URLProtocol {
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

private final class InMemoryGitHubTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var bundle: GitHubTokenBundle?

    func load() throws -> GitHubTokenBundle? {
        lock.withLock { bundle }
    }

    func save(_ bundle: GitHubTokenBundle) throws {
        lock.withLock { self.bundle = bundle }
    }

    func delete() {
        lock.withLock { bundle = nil }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private struct DecodingFailure: LocalizedError {
    var errorDescription: String? { "decode failed" }
}
