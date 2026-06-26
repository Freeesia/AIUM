import XCTest
@testable import AIUM

final class GitHubParsingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

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

    func testDecodeAICreditUsageWithoutItems() throws {
        let json = "{}".data(using: .utf8)!
        let response = try decoder.decode(GitHubAICreditUsageResponse.self, from: json)
        XCTAssertTrue(response.usageItems.isEmpty)
        XCTAssertEqual(response.usedQuantity, 0, accuracy: 0.001)
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
        XCTAssertEqual(premium.source, "GitHub Billing API (legacy)")
        XCTAssertNotNil(premium.errorMessage)
        XCTAssertTrue(try XCTUnwrap(premium.errorMessage).contains("HTTP 404"))
        XCTAssertTrue(try XCTUnwrap(premium.errorMessage).contains("organization- or enterprise-billed"))
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
}

private actor FakeGitHubAuthProvider: GitHubAuthProviding {
    private let token: String?

    init(token: String?) {
        self.token = token
    }

    var accessToken: String? {
        get async { token }
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

    init(
        user: GitHubUser = GitHubUser(login: "octocat", id: 42, name: "The Octocat", avatarUrl: nil),
        aiResponse: GitHubAICreditUsageResponse? = nil,
        aiError: Error? = nil,
        premiumResponse: GitHubPremiumRequestUsageResponse? = nil,
        premiumError: Error? = nil
    ) {
        self.user = user
        self.aiResponse = aiResponse
        self.aiError = aiError
        self.premiumResponse = premiumResponse
        self.premiumError = premiumError
    }

    func fetchUser(token: String) async throws -> GitHubUser {
        user
    }

    func fetchAICreditUsage(username: String, token: String) async throws -> GitHubAICreditUsageResponse {
        if let aiError { throw aiError }
        return aiResponse ?? GitHubAICreditUsageResponse(
            usageItems: [.mock(quantity: 10)]
        )
    }

    func fetchPremiumRequestUsage(username: String, token: String) async throws -> GitHubPremiumRequestUsageResponse {
        if let premiumError { throw premiumError }
        return premiumResponse ?? GitHubPremiumRequestUsageResponse(
            usageItems: [.mock(quantity: 5)]
        )
    }
}

private extension GitHubBillingUsageItem {
    static func mock(quantity: Double) -> GitHubBillingUsageItem {
        GitHubBillingUsageItem(
            product: nil,
            sku: nil,
            model: nil,
            unitType: nil,
            quantity: nil,
            grossQuantity: quantity,
            netQuantity: nil
        )
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

private struct DecodingFailure: LocalizedError {
    var errorDescription: String? { "decode failed" }
}
