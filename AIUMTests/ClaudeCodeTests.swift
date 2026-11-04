import XCTest
@testable import AIUM

final class ClaudeCodeTests: XCTestCase {
    override func tearDown() {
        ClaudeCodeMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - PKCE / authorization request

    func testPKCEChallengeMatchesRFC7636Example() {
        let pkce = ClaudeCodePKCE.make(codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        XCTAssertEqual(pkce.codeChallenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedPKCEVerifierIsURLSafeAndUnique() {
        let first = ClaudeCodePKCE.generate()
        let second = ClaudeCodePKCE.generate()

        XCTAssertNotEqual(first.codeVerifier, second.codeVerifier)
        XCTAssertTrue((43...128).contains(first.codeVerifier.count))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssertTrue(first.codeVerifier.unicodeScalars.allSatisfy(allowed.contains))
        XCTAssertEqual(first.codeChallenge, ClaudeCodePKCE.make(codeVerifier: first.codeVerifier).codeChallenge)
    }

    func testAuthorizationURLContainsPKCEAndState() throws {
        let redirectURI = ClaudeCodeOAuthConfig.loopbackRedirectURI(port: 54_321)
        let url = ClaudeCodeOAuthConfig.authorizationURL(
            clientId: "client-id",
            redirectURI: redirectURI,
            codeChallenge: "challenge",
            state: "state-value"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.host, ClaudeCodeOAuthConfig.authorizeURL.host)
        XCTAssertEqual(query["client_id"], "client-id")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["redirect_uri"], "http://localhost:54321/callback")
        XCTAssertEqual(query["scope"], "user:profile")
        XCTAssertEqual(query["code_challenge"], "challenge")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["state"], "state-value")
    }

    func testResolvedClientIdRejectsPlaceholders() {
        XCTAssertNil(ClaudeCodeOAuthConfig.resolvedClientId(from: nil))
        XCTAssertNil(ClaudeCodeOAuthConfig.resolvedClientId(from: " "))
        XCTAssertNil(ClaudeCodeOAuthConfig.resolvedClientId(from: "YOUR_CLAUDE_CODE_CLIENT_ID"))
        XCTAssertNil(ClaudeCodeOAuthConfig.resolvedClientId(from: "$(CLAUDE_CODE_OAUTH_CLIENT_ID)"))
        XCTAssertEqual(ClaudeCodeOAuthConfig.resolvedClientId(from: " abc "), "abc")
    }

    // MARK: - Authorization response

    func testAuthorizationCodeRequiresMatchingState() {
        let url = URL(string: "aium-claude-code://oauth/callback?code=abc&state=other")!

        XCTAssertThrowsError(try ClaudeCodeAuthProvider.authorizationCode(from: url, expectedState: "expected")) {
            XCTAssertEqual($0 as? ClaudeCodeAuthError, .stateMismatch)
        }
    }

    func testAuthorizationCodeRequiresState() {
        let url = URL(string: "aium-claude-code://oauth/callback?code=abc")!

        XCTAssertThrowsError(try ClaudeCodeAuthProvider.authorizationCode(from: url, expectedState: "expected")) {
            XCTAssertEqual($0 as? ClaudeCodeAuthError, .stateMismatch)
        }
    }

    func testAuthorizationCodeAcceptsCopyCodeFormat() throws {
        let url = URL(string: "aium-claude-code://oauth/callback?code=abc%23expected")!

        XCTAssertEqual(try ClaudeCodeAuthProvider.authorizationCode(from: url, expectedState: "expected"), "abc")
    }

    func testAuthorizationErrorIsReported() {
        let url = URL(string: "aium-claude-code://oauth/callback?error=access_denied&state=expected")!

        XCTAssertThrowsError(try ClaudeCodeAuthProvider.authorizationCode(from: url, expectedState: "expected")) {
            XCTAssertEqual($0 as? ClaudeCodeAuthError, .accessDenied)
        }
    }

    func testSignInWithMismatchedStateDoesNotExchangeCode() async {
        var tokenRequests = 0
        ClaudeCodeMockURLProtocol.requestHandler = { request in
            tokenRequests += 1
            return (Self.httpResponse(for: request), Data())
        }
        let persistence = inMemoryPersistence()
        let provider = makeAuthProvider(persistence: persistence)
        let session = StubAuthorizationSession { _ in
            URL(string: "aium-claude-code://oauth/callback?code=abc&state=forged")!
        }

        do {
            _ = try await provider.signIn(using: session)
            XCTFail("Expected state mismatch")
        } catch {
            XCTAssertEqual(error as? ClaudeCodeAuthError, .stateMismatch)
        }
        XCTAssertEqual(tokenRequests, 0)
        let isAuthenticated = await provider.isAuthenticated
        XCTAssertFalse(isAuthenticated)
    }

    func testSignInExchangesCodeAndSavesTokenBundle() async throws {
        var tokenRequestBody: [String: Any] = [:]
        var profileAuthorization: String?
        ClaudeCodeMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/oauth/profile" {
                profileAuthorization = request.value(forHTTPHeaderField: "Authorization")
                return (Self.httpResponse(for: request), Data("""
                {
                  "account": {
                    "uuid": "account-uuid",
                    "email": "user@example.com",
                    "display_name": "Freesia",
                    "full_name": "Freesia Studio"
                  },
                  "organization": { "uuid": "org-uuid" }
                }
                """.utf8))
            }
            XCTAssertEqual(request.url, ClaudeCodeOAuthConfig.tokenURL)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            tokenRequestBody = Self.jsonBody(of: request)
            return (Self.httpResponse(for: request), Data("""
            {
              "access_token": "access-token",
              "refresh_token": "refresh-token",
              "expires_in": 28800,
              "scope": "user:profile",
              "token_type": "Bearer",
              "account": { "uuid": "account-uuid", "email_address": "user@example.com" },
              "organization": { "uuid": "org-uuid", "name": "Org" }
            }
            """.utf8))
        }
        let persistence = inMemoryPersistence()
        let provider = makeAuthProvider(persistence: persistence)
        let session = StubAuthorizationSession { authorizationURL in
            let state = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            return URL(string: "aium-claude-code://oauth/callback?code=auth-code&state=\(state)")!
        }

        let bundle = try await provider.signIn(using: session)

        XCTAssertEqual(bundle.accessToken, "access-token")
        XCTAssertEqual(bundle.refreshToken, "refresh-token")
        XCTAssertEqual(bundle.accountId, "account-uuid")
        XCTAssertEqual(bundle.accountDisplayName, "Freesia")
        XCTAssertEqual(bundle.scopes, ["user:profile"])
        XCTAssertEqual(try persistence.load()?.accessToken, "access-token")
        XCTAssertEqual(try persistence.load()?.accountDisplayName, "Freesia")
        XCTAssertEqual(profileAuthorization, "Bearer access-token")
        let isAuthenticated = await provider.isAuthenticated
        XCTAssertTrue(isAuthenticated)

        XCTAssertEqual(tokenRequestBody["grant_type"] as? String, "authorization_code")
        XCTAssertEqual(tokenRequestBody["code"] as? String, "auth-code")
        XCTAssertEqual(tokenRequestBody["state"] as? String, "fixed-state")
        XCTAssertEqual(tokenRequestBody["code_verifier"] as? String, "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(tokenRequestBody["client_id"] as? String, "client-id")
        XCTAssertEqual(tokenRequestBody["redirect_uri"] as? String, session.redirectURI.absoluteString)
    }

    func testRefreshTokenUpdatesAccessToken() async throws {
        var refreshBody: [String: Any] = [:]
        ClaudeCodeMockURLProtocol.requestHandler = { request in
            refreshBody = Self.jsonBody(of: request)
            return (Self.httpResponse(for: request), Data("""
            { "access_token": "new-access", "refresh_token": "new-refresh", "expires_in": 3600 }
            """.utf8))
        }
        let persistence = inMemoryPersistence()
        try persistence.save(ClaudeCodeTokenBundle(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(-10),
            scopes: ["user:profile"],
            accountId: "account-uuid",
            email: "user@example.com",
            profile: ClaudeCodeAccountProfile(displayName: "Freesia", fullName: nil)
        ))
        let provider = makeAuthProvider(persistence: persistence)

        let token = try await provider.validAccessToken()

        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(refreshBody["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(refreshBody["refresh_token"] as? String, "old-refresh")
        XCTAssertEqual(refreshBody["scope"] as? String, "user:profile")
        let saved = try XCTUnwrap(persistence.load())
        XCTAssertEqual(saved.accessToken, "new-access")
        XCTAssertEqual(saved.refreshToken, "new-refresh")
        XCTAssertEqual(saved.email, "user@example.com")
        XCTAssertEqual(saved.accountDisplayName, "Freesia")
        XCTAssertFalse(saved.isExpired)
    }

    // MARK: - Account profile

    func testProfileNamePrefersDisplayNameThenFullNameAndNeverEmail() throws {
        let both = try ClaudeCodeAccountProfile.decode(from: Data(
            #"{"account":{"email":"user@example.com","display_name":" Freesia ","full_name":"Freesia Studio"}}"#.utf8
        ))
        let fullOnly = try ClaudeCodeAccountProfile.decode(from: Data(
            #"{"account":{"email":"user@example.com","display_name":"","full_name":"Freesia Studio"}}"#.utf8
        ))
        let none = try ClaudeCodeAccountProfile.decode(from: Data(
            #"{"account":{"email":"user@example.com","display_name":null}}"#.utf8
        ))

        XCTAssertEqual(both.name, "Freesia")
        XCTAssertEqual(fullOnly.name, "Freesia Studio")
        XCTAssertNil(none.name)
        XCTAssertNil(ClaudeCodeTokenBundle(accessToken: "a", expiresAt: Date(), email: "user@example.com").accountDisplayName)
    }

    func testProfileFailureKeepsCachedName() async throws {
        ClaudeCodeMockURLProtocol.requestHandler = { request in
            (Self.httpResponse(for: request, statusCode: 500), Data())
        }
        let persistence = inMemoryPersistence()
        try persistence.save(ClaudeCodeTokenBundle(
            accessToken: "access",
            expiresAt: Date().addingTimeInterval(3600),
            accountId: "account-uuid",
            profile: ClaudeCodeAccountProfile(displayName: "Cached", fullName: nil)
        ))
        let provider = makeAuthProvider(persistence: persistence)

        let profile = await provider.refreshAccountProfile(accessToken: "access")

        XCTAssertNil(profile)
        XCTAssertEqual(try persistence.load()?.accountDisplayName, "Cached")
    }

    // MARK: - Usage parsing

    func testUsageResponseCreatesFiveHourAndSevenDaySnapshots() throws {
        let json = Data("""
        {
          "five_hour": { "utilization": 37.0, "resets_at": "2026-11-04T15:00:00.123456+00:00" },
          "seven_day": { "utilization": 12, "resets_at": "2026-11-08T03:00:00Z" },
          "seven_day_opus": null,
          "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """.utf8)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let bundle = ClaudeCodeTokenBundle(
            accessToken: "a", expiresAt: now, accountId: "account-uuid", email: "user@example.com",
            profile: ClaudeCodeAccountProfile(displayName: "Freesia", fullName: nil)
        )

        let response = try ClaudeCodeUsageResponse.decode(from: json)
        let snapshots = PrivateClaudeCodeUsageProvider.normalizeSnapshots(response, tokenBundle: bundle, now: now)

        XCTAssertEqual(snapshots.count, 2)
        let fiveHour = try XCTUnwrap(snapshots.first { $0.windowDurationMins == 300 })
        XCTAssertEqual(fiveHour.provider, .claudeCode)
        XCTAssertEqual(fiveHour.used, 37, accuracy: 0.001)
        XCTAssertEqual(fiveHour.limit, 100)
        XCTAssertEqual(fiveHour.usedPercent, 37, accuracy: 0.001)
        XCTAssertEqual(fiveHour.planKind, .unknown)
        XCTAssertEqual(fiveHour.windowKind, .custom)
        XCTAssertEqual(fiveHour.source, "claude-code-private-api")
        XCTAssertEqual(fiveHour.accountId, "account-uuid")
        XCTAssertEqual(fiveHour.displayName, "Freesia")
        XCTAssertEqual(fiveHour.fetchedAt, now)
        XCTAssertEqual(
            try XCTUnwrap(fiveHour.resetAt).timeIntervalSince1970,
            try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T15:00:00Z")).timeIntervalSince1970 + 0.123,
            accuracy: 0.001
        )

        let sevenDay = try XCTUnwrap(snapshots.first { $0.windowDurationMins == 10_080 })
        XCTAssertEqual(sevenDay.used, 12, accuracy: 0.001)
        XCTAssertEqual(sevenDay.resetAt, ISO8601DateFormatter().date(from: "2026-11-08T03:00:00Z"))
        XCTAssertNotEqual(fiveHour.id, sevenDay.id)
    }

    /// The endpoint reports utilization in percent (the Claude Code CLI renders
    /// `Math.floor(utilization)% used`), so small values must not be scaled.
    func testUtilizationIsTreatedAsPercent() throws {
        let json = Data(#"{ "five_hour": { "utilization": 0.5, "resets_at": null } }"#.utf8)

        let response = try ClaudeCodeUsageResponse.decode(from: json)

        XCTAssertEqual(try XCTUnwrap(response.fiveHour).usedPercent, 0.5, accuracy: 0.0001)
        XCTAssertNil(response.fiveHour?.resetAt)
        XCTAssertNil(response.sevenDay)
    }

    func testWeeklyOnlyPlanReturnsSevenDayWindow() throws {
        let json = Data(#"{ "five_hour": null, "seven_day": { "utilization": 80, "resets_at": 1790000000 } }"#.utf8)

        let response = try ClaudeCodeUsageResponse.decode(from: json)

        XCTAssertNil(response.fiveHour)
        XCTAssertEqual(response.windows.map(\.windowDurationMins), [10_080])
    }

    func testResetDatesAcceptEpochSecondsMillisecondsAndISO8601() {
        let expected = Date(timeIntervalSince1970: 1_790_000_000)

        XCTAssertEqual(ClaudeCodeUsageResponse.parseDate(1_790_000_000), expected)
        XCTAssertEqual(ClaudeCodeUsageResponse.parseDate(NSNumber(value: 1_790_000_000_000.0)), expected)
        XCTAssertEqual(ClaudeCodeUsageResponse.parseDate("1790000000"), expected)
        XCTAssertEqual(ClaudeCodeUsageResponse.parseDate("1790000000000"), expected)
        XCTAssertEqual(ClaudeCodeUsageResponse.parseDate("2026-09-21T14:13:20Z"), expected)
        XCTAssertEqual(ClaudeCodeUsageResponse.parseDate("2026-09-21T14:13:20.000Z"), expected)
        XCTAssertEqual(ClaudeCodeUsageResponse.parseDate("2026-09-21T14:13:20.000000+00:00"), expected)
        XCTAssertNil(ClaudeCodeUsageResponse.parseDate("not a date"))
    }

    func testNonObjectUsageResponseThrowsDecodeError() {
        XCTAssertThrowsError(try ClaudeCodeUsageResponse.decode(from: Data("[]".utf8))) { error in
            guard case ClaudeCodeUsageError.decodeError = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - Usage provider

    func testFetchUsageSendsBearerTokenAndReturnsTwoSnapshots() async throws {
        var usageRequest: URLRequest?
        ClaudeCodeMockURLProtocol.requestHandler = { request in
            usageRequest = request
            return (Self.httpResponse(for: request), Data("""
            {
              "five_hour": { "utilization": 54, "resets_at": "2026-11-04T15:00:00Z" },
              "seven_day": { "utilization": 31, "resets_at": "2026-11-08T03:00:00Z" }
            }
            """.utf8))
        }
        let provider = PrivateClaudeCodeUsageProvider(
            authProvider: FakeClaudeCodeAuthProvider(),
            session: mockSession()
        )

        let snapshots = try await provider.fetchUsage()

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots.allSatisfy { $0.provider == .claudeCode && $0.errorMessage == nil })
        XCTAssertEqual(Set(snapshots.compactMap(\.windowDurationMins)), [300, 10_080])
        XCTAssertEqual(usageRequest?.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(usageRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer fake-access")
        XCTAssertEqual(usageRequest?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertTrue(snapshots.allSatisfy { $0.displayName == "Profile Name" })
    }

    func testFetchUsageThrowsHTTPErrorForRateLimit() async {
        ClaudeCodeMockURLProtocol.requestHandler = { request in
            (Self.httpResponse(for: request, statusCode: 429), Data(#"{"type":"error","error":{"type":"rate_limit_error"}}"#.utf8))
        }
        let provider = PrivateClaudeCodeUsageProvider(
            authProvider: FakeClaudeCodeAuthProvider(),
            session: mockSession()
        )

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected HTTP error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("429"))
            XCTAssertTrue(error.localizedDescription.contains("rate_limit_error"))
        }
    }

    func testFetchUsageWithoutWindowsThrowsNoUsageData() async {
        ClaudeCodeMockURLProtocol.requestHandler = { request in
            (Self.httpResponse(for: request), Data(#"{"five_hour":null,"seven_day":null}"#.utf8))
        }
        let provider = PrivateClaudeCodeUsageProvider(
            authProvider: FakeClaudeCodeAuthProvider(),
            session: mockSession()
        )

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected no usage data error")
        } catch {
            guard case ClaudeCodeUsageError.noUsageData = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - Loopback redirect

    func testLoopbackCallbackRedirectsToAppScheme() throws {
        let request = Data("GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: localhost:1234\r\n\r\n".utf8)

        let response = try XCTUnwrap(ClaudeCodeLoopbackServer.response(for: request))
        let text = String(decoding: response.data, as: UTF8.self)

        XCTAssertEqual(response.callbackURL?.absoluteString, "aium-claude-code://oauth/callback?code=abc&state=xyz")
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 302 Found\r\n"))
        XCTAssertTrue(text.contains("Location: aium-claude-code://oauth/callback?code=abc&state=xyz\r\n"))
    }

    func testLoopbackIgnoresOtherPathsAndIncompleteRequests() throws {
        let favicon = try XCTUnwrap(ClaudeCodeLoopbackServer.response(
            for: Data("GET /favicon.ico HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        ))
        XCTAssertNil(favicon.callbackURL)
        XCTAssertTrue(String(decoding: favicon.data, as: UTF8.self).hasPrefix("HTTP/1.1 404"))

        XCTAssertNil(ClaudeCodeLoopbackServer.response(for: Data("GET /callback?code=abc HTTP/1.1\r\n".utf8)))
    }

    func testLoopbackServerReceivesRedirectOverLocalhost() async throws {
        let server = ClaudeCodeLoopbackServer()
        defer { server.stop() }
        let received = expectation(description: "callback received")
        let receivedURL = LockedValue<URL?>(nil)
        server.onCallback = { url in
            receivedURL.set(url)
            received.fulfill()
        }

        let port = try await server.start()
        let redirectURI = ClaudeCodeOAuthConfig.loopbackRedirectURI(port: port)
        var components = try XCTUnwrap(URLComponents(url: redirectURI, resolvingAgainstBaseURL: false))
        components.queryItems = [URLQueryItem(name: "code", value: "abc"), URLQueryItem(name: "state", value: "xyz")]
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let (_, response) = try await session.data(from: try XCTUnwrap(components.url))

        await fulfillment(of: [received], timeout: 5)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 302)
        XCTAssertEqual(receivedURL.get()?.absoluteString, "aium-claude-code://oauth/callback?code=abc&state=xyz")
    }

    // MARK: - Widget target isolation

    func testWidgetTargetExcludesClaudeCodeNetworkingSources() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        let widgetStart = try XCTUnwrap(project.range(of: "\n  AIUMWidget:\n"))
        let widgetEnd = project.range(of: "\n  AIUMTests:\n", range: widgetStart.upperBound..<project.endIndex)
        let widgetTarget = project[widgetStart.upperBound..<(widgetEnd?.lowerBound ?? project.endIndex)]
        let sources = widgetTarget
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- path:") }

        XCTAssertFalse(sources.isEmpty)
        for source in sources {
            XCTAssertFalse(source.contains("Providers"), "Widget must not compile provider code: \(source)")
            XCTAssertFalse(source.contains("ClaudeCode"), "Widget must not compile Claude Code auth: \(source)")
            XCTAssertNotEqual(source.trimmingCharacters(in: .whitespaces), "- path: AIUM")
        }
    }

    // MARK: - Helpers

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClaudeCodeMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeAuthProvider(persistence: ClaudeCodeTokenPersistence) -> ClaudeCodeAuthProvider {
        ClaudeCodeAuthProvider(
            session: mockSession(),
            clientIdProvider: { "client-id" },
            persistence: persistence,
            pkceGenerator: { ClaudeCodePKCE.make(codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") },
            stateGenerator: { "fixed-state" }
        )
    }

    private func inMemoryPersistence() -> ClaudeCodeTokenPersistence {
        let store = LockedValue<ClaudeCodeTokenBundle?>(nil)
        return ClaudeCodeTokenPersistence(
            load: { store.get() },
            save: { store.set($0) },
            delete: { store.set(nil) }
        )
    }

    private static func httpResponse(for request: URLRequest, statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private static func jsonBody(of request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// MARK: - Test doubles

private struct StubAuthorizationSession: ClaudeCodeAuthorizationSession {
    let redirectURI = ClaudeCodeOAuthConfig.loopbackRedirectURI(port: 49_152)
    let respond: @Sendable (URL) -> URL

    init(respond: @escaping @Sendable (URL) -> URL) {
        self.respond = respond
    }

    func authorize(
        buildAuthorizationURL: @escaping @Sendable (URL) -> URL
    ) async throws -> ClaudeCodeAuthorizationCallback {
        let authorizationURL = buildAuthorizationURL(redirectURI)
        return ClaudeCodeAuthorizationCallback(url: respond(authorizationURL), redirectURI: redirectURI)
    }
}

private actor FakeClaudeCodeAuthProvider: ClaudeCodeAuthProviding {
    var tokenBundle: ClaudeCodeTokenBundle? {
        ClaudeCodeTokenBundle(
            accessToken: "fake-access",
            expiresAt: Date().addingTimeInterval(3600),
            accountId: "account-uuid",
            email: "user@example.com"
        )
    }

    var isAuthenticated: Bool { true }

    func signIn(using session: any ClaudeCodeAuthorizationSession) async throws -> ClaudeCodeTokenBundle {
        try XCTUnwrap(tokenBundle)
    }

    func validAccessToken() async throws -> String { "fake-access" }

    func refreshAccountProfile(accessToken: String) async -> ClaudeCodeAccountProfile? {
        ClaudeCodeAccountProfile(displayName: "Profile Name", fullName: nil)
    }

    func logout() {}
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

private final class ClaudeCodeMockURLProtocol: URLProtocol {
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
