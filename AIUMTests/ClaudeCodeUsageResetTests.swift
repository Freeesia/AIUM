import SwiftUI
import XCTest
@testable import AIUM

@MainActor
final class ClaudeCodeUsageResetTests: XCTestCase {
    // MARK: - Parsing

    func testUsageResponseParsesResetGrantsAndCountsActiveResets() throws {
        let now = Date(timeIntervalSince1970: 1_793_200_000)
        let response = try ClaudeCodeUsageResponse.decode(from: Data(Self.usage(grants: Self.grants).utf8))
        let status = try XCTUnwrap(response.resetStatus)

        XCTAssertTrue(status.eligible)
        XCTAssertEqual(status.grants.map(\.id), ["weekly", "session", "paused", "expired", "spent"])
        XCTAssertEqual(status.nextGrantId, "session")
        XCTAssertEqual(status.availableCount(now: now), 3)
        XCTAssertEqual(status.activeGrants(now: now).map(\.id), ["session", "weekly"])
        XCTAssertEqual(status.grantToUse(now: now)?.id, "session")
        XCTAssertEqual(status.grants[1].kind, .session)
        XCTAssertEqual(status.grants[1].displayTitle, "Bonus reset")
        XCTAssertEqual(status.grants[0].displayTitle, String(localized: "Usage reset"))
        XCTAssertEqual(status.grants[1].endsAt, ISO8601DateFormatter().date(from: "2026-11-20T00:00:00Z"))

        let snapshots = PrivateClaudeCodeUsageProvider.normalizeSnapshots(response, tokenBundle: nil, now: now)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots.allSatisfy { $0.resetCredits == 3 })
    }

    func testGrantSelectionFallsBackToEarliestUsableGrant() throws {
        let now = Date(timeIntervalSince1970: 1_793_200_000)
        let grants = """
        [{"id":"later","resets_left":1,"usable_now":true,"ends_at":"2026-12-20T00:00:00Z"},
         {"id":"needs-limit","resets_left":1,"usable_now":false,"use_requires_limit":true,"ends_at":"2026-11-15T00:00:00Z"},
         {"id":"sooner","resets_left":1,"usable_now":true,"ends_at":"2026-12-01T00:00:00Z"}]
        """
        let status = try XCTUnwrap(ClaudeCodeUsageResponse.decode(
            from: Data(Self.usage(grants: grants, nextGrantId: "needs-limit").utf8)
        ).resetStatus)

        XCTAssertEqual(status.availableCount(now: now), 3)
        XCTAssertEqual(status.grantToUse(now: now)?.id, "sooner")
    }

    func testMalformedOrMissingResetDataIsIgnored() throws {
        let missing = try ClaudeCodeUsageResponse.decode(from: Data(#"{"five_hour":{"utilization":10}}"#.utf8))
        XCTAssertNil(missing.resetStatus)
        XCTAssertNil(PrivateClaudeCodeUsageProvider.normalizeSnapshots(missing, tokenBundle: nil).first?.resetCredits)

        let malformed = try ClaudeCodeUsageResponse.decode(
            from: Data(#"{"five_hour":{"utilization":10},"cedar_ember":{"grants":[]}}"#.utf8)
        )
        XCTAssertNil(malformed.resetStatus)

        let badGrants = """
        [{"id":"Bad ID","resets_left":1,"usable_now":true},
         {"id":"no-count","usable_now":true},
         {"id":"good","resets_left":2,"usable_now":true}]
        """
        let status = try XCTUnwrap(ClaudeCodeUsageResponse.decode(
            from: Data(Self.usage(grants: badGrants, nextGrantId: "Bad ID").utf8)
        ).resetStatus)
        XCTAssertEqual(status.grants.map(\.id), ["good"])
        XCTAssertNil(status.nextGrantId)
        XCTAssertEqual(status.availableCount(), 2)

        let ineligible = try XCTUnwrap(ClaudeCodeUsageResponse.decode(
            from: Data(Self.usage(grants: Self.grants, eligible: false).utf8)
        ).resetStatus)
        XCTAssertEqual(ineligible.availableCount(), 0)
        XCTAssertNil(ineligible.grantToUse())
    }

    // MARK: - Confirmation

    func testPreparingConfirmationDoesNotSendRequest() async throws {
        let fixture = try Fixture()
        var requests = 0
        ResetURLProtocol.handler = { request in
            requests += 1
            return Self.response(request, body: "{}")
        }

        let confirmation = try await fixture.confirmation()

        XCTAssertEqual(confirmation.accountId, "account-a")
        XCTAssertEqual(confirmation.organizationId, "org-a")
        XCTAssertEqual(confirmation.accountDisplayName, "Claude User")
        XCTAssertEqual(confirmation.remainingCount, 3)
        XCTAssertEqual(requests, 0)
        XCTAssertNil(fixture.model.claudeCodeResetOutcome)

        attachPreview(
            UsageResetCard(
                remainingCount: 3, accessibilityIdentifier: "claude-code-reset-usage",
                isDisabled: false, onReset: {}
            )
            .padding()
            .environment(\.locale, Locale(identifier: "ja")),
            name: "Claude Code reset card", height: 220
        )
    }

    func testMissingOrganizationPreventsConfirmation() async throws {
        let fixture = try Fixture()
        await fixture.auth.setOrganization(nil)

        let confirmation = await fixture.model.prepareClaudeCodeUsageReset()

        XCTAssertNil(confirmation)
        XCTAssertNotNil(fixture.model.lastError)
    }

    func testLoadingStatusUsesAuthenticatedGetAndIsCachedForOneMinute() async throws {
        let fixture = try Fixture()
        var requests: [URLRequest] = []
        ResetURLProtocol.handler = { request in
            requests.append(request)
            return Self.response(request, body: Self.usage(grants: Self.grants))
        }
        let confirmation = try await fixture.confirmation()

        await fixture.model.loadClaudeCodeResetStatus(for: confirmation)

        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/api/oauth/usage?cedar_ember=1&skip_spend=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(fixture.model.claudeCodeResetGrantToUse?.id, "session")
        XCTAssertFalse(fixture.model.isLoadingClaudeCodeResetStatus)
        XCTAssertNil(fixture.model.claudeCodeResetStatusError)

        attachPreview(
            ClaudeCodeUsageResetSheet(confirmation: confirmation, viewModel: fixture.model)
                .environment(\.locale, Locale(identifier: "ja")),
            name: "Claude Code reset confirmation", height: 844
        )

        fixture.clock.now.addTimeInterval(59)
        let reopened = try await fixture.confirmation()
        await fixture.model.loadClaudeCodeResetStatus(for: reopened)
        XCTAssertEqual(requests.count, 1)

        fixture.clock.now.addTimeInterval(1)
        let stale = try await fixture.confirmation()
        await fixture.model.loadClaudeCodeResetStatus(for: stale)
        XCTAssertEqual(requests.count, 2)
    }

    func testStatusFailureCanRetryWithoutConsumingReset() async throws {
        let fixture = try Fixture()
        var requests: [URLRequest] = []
        ResetURLProtocol.handler = { request in
            requests.append(request)
            return requests.count == 1
                ? Self.response(request, status: 429, body: #"{"type":"error"}"#)
                : Self.response(request, body: Self.usage(grants: Self.grants))
        }
        let confirmation = try await fixture.confirmation()

        await fixture.model.loadClaudeCodeResetStatus(for: confirmation)
        XCTAssertNil(fixture.model.claudeCodeResetStatus)
        XCTAssertNotNil(fixture.model.claudeCodeResetStatusError)

        await fixture.model.loadClaudeCodeResetStatus(for: confirmation)
        XCTAssertNotNil(fixture.model.claudeCodeResetStatus)
        XCTAssertNil(fixture.model.claudeCodeResetStatusError)
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET"])
    }

    func testAccountChangePreventsLoadingAndReset() async throws {
        let fixture = try Fixture()
        var methods: [String?] = []
        ResetURLProtocol.handler = { request in
            methods.append(request.httpMethod)
            return Self.response(request, body: Self.usage(grants: Self.grants))
        }
        let confirmation = try await fixture.confirmation()
        await fixture.model.loadClaudeCodeResetStatus(for: confirmation)
        await fixture.auth.setAccount("account-b")

        await fixture.model.resetClaudeCodeUsage(confirmation)

        XCTAssertEqual(methods, ["GET"])
        XCTAssertNil(fixture.model.claudeCodeResetOutcome)
        XCTAssertNotNil(fixture.model.claudeCodeResetError)

        await fixture.model.loadClaudeCodeResetStatus(for: confirmation)
        XCTAssertEqual(methods, ["GET"])
        XCTAssertNil(fixture.model.claudeCodeResetStatus)
        XCTAssertNotNil(fixture.model.claudeCodeResetStatusError)
    }

    func testResetRequiresLoadedUsableGrant() async throws {
        let fixture = try Fixture()
        var methods: [String?] = []
        ResetURLProtocol.handler = { request in
            methods.append(request.httpMethod)
            return Self.response(request, body: Self.usage(
                grants: #"[{"id":"needs-limit","resets_left":1,"usable_now":false}]"#
            ))
        }
        let confirmation = try await fixture.confirmation()

        await fixture.model.resetClaudeCodeUsage(confirmation)
        XCTAssertEqual(methods, [])
        XCTAssertNotNil(fixture.model.claudeCodeResetError)

        await fixture.model.loadClaudeCodeResetStatus(for: confirmation)
        await fixture.model.resetClaudeCodeUsage(confirmation)
        XCTAssertEqual(methods, ["GET"])
        XCTAssertNil(fixture.model.claudeCodeResetOutcome)
    }

    // MARK: - Reset

    func testConfirmedResetUsesAuthenticatedPostAndRefreshesUsage() async throws {
        let fixture = try Fixture()
        var requests: [URLRequest] = []
        ResetURLProtocol.handler = { request in
            requests.append(request)
            if request.httpMethod == "POST" {
                return Self.response(request, body: #"{"result":"reset","resets_left":0,"cleared":["five_hour"]}"#)
            }
            let grants = requests.count == 1 ? Self.grants : #"[{"id":"weekly","resets_left":2,"usable_now":true}]"#
            return Self.response(request, body: Self.usage(grants: grants, utilization: requests.count == 1 ? 100 : 0))
        }
        let confirmation = try await fixture.confirmation()
        await fixture.model.loadClaudeCodeResetStatus(for: confirmation)

        await fixture.model.resetClaudeCodeUsage(confirmation)

        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "POST", "GET"])
        let post = requests[1]
        XCTAssertEqual(post.url?.absoluteString, "https://example.test/api/organizations/org-a/reset_rate_limits")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Authorization"), "Bearer access")
        XCTAssertEqual(post.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try Self.requestBody(post)
        XCTAssertEqual(body["program"] as? String, "cedar_ember")
        XCTAssertEqual(body["grant_id"] as? String, "session")
        XCTAssertNotNil((body["request_id"] as? String).flatMap(UUID.init(uuidString:)))
        XCTAssertEqual(fixture.model.claudeCodeResetOutcome, .reset)
        XCTAssertNil(fixture.model.claudeCodeResetStatus)
        XCTAssertEqual(fixture.model.claudeCodeResetCredits, 2)
        XCTAssertEqual(fixture.store.snapshots(for: .claudeCode).first { $0.windowDurationMins == 300 }?.used, 0)
        XCTAssertFalse(fixture.model.isResettingClaudeCodeUsage)

        attachPreview(
            ClaudeCodeUsageResetSheet(confirmation: confirmation, viewModel: fixture.model)
                .environment(\.locale, Locale(identifier: "ja")),
            name: "Claude Code reset completed", height: 500
        )
    }

    func testUnconfirmedResetsReuseRequestIDEvenWithNewModel() async throws {
        for failure in ["lost", "unavailable", "unknown", "http"] {
            let fixture = try Fixture()
            var requestIDs: [String] = []
            ResetURLProtocol.handler = { request in
                if request.httpMethod == "POST" {
                    requestIDs.append(try XCTUnwrap(Self.requestBody(request)["request_id"] as? String))
                    if requestIDs.count > 1 {
                        return Self.response(request, body: #"{"result":"already_used"}"#)
                    }
                    switch failure {
                    case "lost": throw URLError(.networkConnectionLost)
                    case "http": return Self.response(request, status: 429, body: "{}")
                    default: return Self.response(request, body: "{\"result\":\"\(failure)\"}")
                    }
                }
                return Self.response(request, body: Self.usage(grants: Self.grants))
            }
            let confirmation = try await fixture.confirmation()
            await fixture.model.loadClaudeCodeResetStatus(for: confirmation)
            await fixture.model.resetClaudeCodeUsage(confirmation)
            XCTAssertNotNil(fixture.model.claudeCodeResetError, failure)
            XCTAssertNil(fixture.model.claudeCodeResetOutcome, failure)

            let reopenedModel = fixture.makeModel()
            let retryValue = await reopenedModel.prepareClaudeCodeUsageReset()
            let retry = try XCTUnwrap(retryValue)
            await reopenedModel.loadClaudeCodeResetStatus(for: retry)
            await reopenedModel.resetClaudeCodeUsage(retry)

            XCTAssertEqual(requestIDs.count, 2, failure)
            XCTAssertEqual(requestIDs.first, requestIDs.last, failure)
            XCTAssertEqual(reopenedModel.claudeCodeResetOutcome, .alreadyUsed, failure)
        }
    }

    func testDefinitiveOutcomesClearRequestID() async throws {
        let outcomes: [(String, ClaudeCodeUsageResetOutcome)] = [
            ("reset", .reset), ("already_used", .alreadyUsed), ("not_limited", .notLimited),
            ("cooldown", .cooldown), ("ineligible", .ineligible),
        ]
        for (result, expected) in outcomes {
            let fixture = try Fixture()
            var requestIDs: [String] = []
            ResetURLProtocol.handler = { request in
                if request.httpMethod == "POST" {
                    requestIDs.append(try XCTUnwrap(Self.requestBody(request)["request_id"] as? String))
                    return Self.response(request, body: "{\"result\":\"\(result)\"}")
                }
                return Self.response(request, body: Self.usage(grants: Self.grants))
            }
            for _ in 0..<2 {
                let model = fixture.makeModel()
                let value = await model.prepareClaudeCodeUsageReset()
                let confirmation = try XCTUnwrap(value)
                await model.loadClaudeCodeResetStatus(for: confirmation)
                await model.resetClaudeCodeUsage(confirmation)
                XCTAssertEqual(model.claudeCodeResetOutcome, expected, result)
                XCTAssertNil(model.claudeCodeResetError, result)
            }
            XCTAssertEqual(requestIDs.count, 2, result)
            XCTAssertNotEqual(requestIDs.first, requestIDs.last, result)
        }
    }

    func testResetCardHidesForUnavailableCountsAndProviderErrors() throws {
        let fixture = try Fixture()
        for count in [nil, 0, -1, 0.5] as [Double?] {
            fixture.model.claudeCodeSnapshots = [UsageSnapshot(
                provider: .claudeCode, used: 80, limit: 100, source: "test", resetCredits: count
            )]
            XCTAssertNil(fixture.model.claudeCodeResetCredits)
        }
        fixture.model.claudeCodeSnapshots = fixture.store.snapshots(for: .claudeCode)
        XCTAssertEqual(fixture.model.claudeCodeResetCredits, 3)
        fixture.model.claudeCodeSnapshots.append(.error(provider: .claudeCode, message: "expired session"))
        XCTAssertNil(fixture.model.claudeCodeResetCredits)
    }

    // MARK: - Helpers

    private nonisolated static let grants = """
    [{"id":"weekly","label":"","resets_total":2,"resets_left":2,"ends_at":"2026-12-01T00:00:00Z",
      "paused":false,"usable_now":true,"use_requires_limit":false,"type":"weekly"},
     {"id":"session","label":" Bonus reset ","resets_total":1,"resets_left":1,"ends_at":"2026-11-20T00:00:00Z",
      "paused":false,"usable_now":true,"use_requires_limit":true,"type":"session"},
     {"id":"paused","resets_left":4,"paused":true,"usable_now":false},
     {"id":"expired","resets_left":5,"ends_at":"2026-10-01T00:00:00Z","usable_now":true},
     {"id":"spent","resets_left":0,"usable_now":false}]
    """

    private nonisolated static func usage(
        grants: String,
        nextGrantId: String? = "session",
        eligible: Bool = true,
        utilization: Double = 100
    ) -> String {
        let next = nextGrantId.map { "\"\($0)\"" } ?? "null"
        return """
        {"five_hour":{"utilization":\(utilization),"resets_at":"2026-11-14T15:00:00Z"},
         "seven_day":{"utilization":40,"resets_at":"2026-11-18T03:00:00Z"},
         "cedar_ember":{"eligible":\(eligible),"at_limit":true,"grants":\(grants),"next_grant_id":\(next)}}
        """
    }

    private nonisolated static func response(_ request: URLRequest, status: Int = 200, body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    private nonisolated static func requestBody(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var body = Data()
            var bytes = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                body.append(contentsOf: bytes.prefix(count))
            }
            data = body
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func attachPreview<Content: View>(_ content: Content, name: String, height: CGFloat) {
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: height))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class Fixture {
    let suiteName = "claude-code-reset-test.\(UUID().uuidString)"
    let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("claude-code-reset-\(UUID().uuidString).json")
    let defaults: UserDefaults
    let store: UsageStore
    let auth = ResetAuthProvider()
    let clock = ResetTestClock()
    let provider: PrivateClaudeCodeUsageProvider
    lazy var model = makeModel()

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = UsageStore(testingStoreURL: storeURL)
        store.upsert(UsageSnapshot(
            provider: .claudeCode, accountId: "account-a", displayName: "Claude User",
            used: 100, limit: 100, unit: "percent", source: "test",
            windowDurationMins: 300, resetCredits: 3
        ))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResetURLProtocol.self]
        provider = PrivateClaudeCodeUsageProvider(
            authProvider: auth,
            apiBaseURL: URL(string: "https://example.test")!,
            session: URLSession(configuration: configuration)
        )
    }

    func makeModel() -> DashboardViewModel {
        let clock = clock
        return DashboardViewModel(
            usageStore: store,
            demoModeStore: DemoModeStore(defaults: defaults),
            claudeCodeProvider: provider,
            resetRequestStore: .codex(defaults: defaults),
            claudeCodeResetRequestStore: .claudeCode(defaults: defaults),
            now: { clock.now }
        )
    }

    func confirmation() async throws -> ClaudeCodeUsageResetConfirmation {
        let value = await model.prepareClaudeCodeUsageReset()
        return try XCTUnwrap(value)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: storeURL)
        ResetURLProtocol.handler = nil
    }
}

@MainActor
private final class ResetTestClock {
    var now = Date(timeIntervalSince1970: 1_793_200_000)
}

private actor ResetAuthProvider: ClaudeCodeAuthProviding {
    var tokenBundle: ClaudeCodeTokenBundle? = ClaudeCodeTokenBundle(
        accessToken: "access",
        expiresAt: Date().addingTimeInterval(3600),
        accountId: "account-a",
        email: "person@example.com",
        organizationId: "org-a",
        profile: ClaudeCodeAccountProfile(displayName: "Claude User", fullName: nil)
    )
    var isAuthenticated: Bool { tokenBundle != nil }

    func signIn(using session: any ClaudeCodeAuthorizationSession) async throws -> ClaudeCodeTokenBundle {
        try XCTUnwrap(tokenBundle)
    }

    func validAccessToken() async throws -> String { "access" }
    func refreshAccountProfile(accessToken: String) async -> ClaudeCodeAccountProfile? { tokenBundle?.profile }
    func setAccount(_ accountId: String?) { tokenBundle?.accountId = accountId }
    func setOrganization(_ organizationId: String?) { tokenBundle?.organizationId = organizationId }
    func logout() { tokenBundle = nil }
}

private final class ResetURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
