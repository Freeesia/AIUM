import SwiftUI
import XCTest
@testable import AIUM

@MainActor
final class CodexUsageResetTests: XCTestCase {
    func testPreparingConfirmationDoesNotSendRequest() async throws {
        let fixture = try Fixture()
        var requests = 0
        ResetURLProtocol.handler = { request in
            requests += 1
            return Self.response(request, body: "{}")
        }

        let confirmation = try await fixture.confirmation()

        attachPreview(
            CodexResetCreditsCard(remainingCount: 2, isDisabled: false, onReset: {})
                .padding()
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "ja")),
            name: "Codex reset card", height: 220
        )
        attachPreview(
            CodexUsageResetSheet(confirmation: confirmation, viewModel: fixture.model)
                .environment(\.locale, Locale(identifier: "ja")),
            name: "Codex reset confirmation", height: 500
        )

        XCTAssertEqual(confirmation.accountId, "account-a")
        XCTAssertEqual(confirmation.accountDisplayName, "Codex User")
        XCTAssertEqual(confirmation.remainingCount, 2)
        XCTAssertEqual(requests, 0)
        XCTAssertNil(fixture.model.codexResetOutcome)
    }

    func testConfirmedResetUsesAuthenticatedPostAndRefreshesCache() async throws {
        let fixture = try Fixture()
        var requests: [URLRequest] = []
        ResetURLProtocol.handler = { request in
            requests.append(request)
            return Self.response(request, body: request.httpMethod == "POST"
                ? #"{"code":"reset"}"# : Self.usage(remaining: 1))
        }
        let confirmation = try await fixture.confirmation()

        await fixture.model.resetCodexUsage(confirmation)

        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET"])
        let post = try XCTUnwrap(requests.first)
        XCTAssertEqual(post.url?.path, "/backend-api/wham/rate-limit-reset-credits/consume")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Authorization"), "Bearer access")
        XCTAssertEqual(post.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-a")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try Self.requestBody(post)
        XCTAssertTrue(body["credit_id"] is NSNull)
        XCTAssertNotNil((body["redeem_request_id"] as? String).flatMap(UUID.init(uuidString:)))
        XCTAssertEqual(fixture.model.codexResetOutcome, .reset)
        XCTAssertEqual(fixture.model.codexResetCredits, 1)
        XCTAssertEqual(fixture.store.snapshots(for: .codex).first?.used, 0)
        XCTAssertEqual(fixture.store.snapshots(for: .codex).first?.resetCredits, 1)
        XCTAssertFalse(fixture.model.isResettingCodexUsage)
    }

    func testRetryAfterLostResponseReusesRequestIDEvenWithNewModel() async throws {
        let fixture = try Fixture()
        var requestIDs: [String] = []
        ResetURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                requestIDs.append(try XCTUnwrap(Self.requestBody(request)["redeem_request_id"] as? String))
                if requestIDs.count == 1 { throw URLError(.networkConnectionLost) }
                return Self.response(request, body: #"{"code":"already_redeemed"}"#)
            }
            return Self.response(request, body: Self.usage(remaining: 1))
        }
        let confirmation = try await fixture.confirmation()
        await fixture.model.resetCodexUsage(confirmation)
        XCTAssertNotNil(fixture.model.codexResetError)
        XCTAssertNil(fixture.model.codexResetOutcome)

        let reopenedModel = fixture.makeModel()
        let retryValue = await reopenedModel.prepareCodexUsageReset()
        let retry = try XCTUnwrap(retryValue)
        await reopenedModel.resetCodexUsage(retry)

        XCTAssertEqual(requestIDs.count, 2)
        XCTAssertEqual(requestIDs.first, requestIDs.last)
        XCTAssertEqual(reopenedModel.codexResetOutcome, .alreadyRedeemed)
        XCTAssertEqual(reopenedModel.codexResetCredits, 1)
        XCTAssertNil(reopenedModel.codexResetError)
    }

    func testOverlappingAndRepeatedConfirmationsSendOnlyOnePost() async throws {
        let fixture = try Fixture()
        var posts = 0
        ResetURLProtocol.handler = { request in
            if request.httpMethod == "POST" { posts += 1 }
            return Self.response(request, body: request.httpMethod == "POST"
                ? #"{"code":"reset"}"# : Self.usage(remaining: 1))
        }
        let confirmation = try await fixture.confirmation()
        async let first: Void = fixture.model.resetCodexUsage(confirmation)
        async let second: Void = fixture.model.resetCodexUsage(confirmation)
        _ = await (first, second)
        await fixture.model.resetCodexUsage(confirmation)

        XCTAssertEqual(posts, 1)
        XCTAssertEqual(fixture.model.codexResetOutcome, .reset)
    }

    func testRefreshFailureAfterSuccessDoesNotRetryCompletedReset() async throws {
        let fixture = try Fixture()
        var posts = 0
        ResetURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                posts += 1
                return Self.response(request, body: #"{"code":"reset"}"#)
            }
            return Self.response(request, status: 503, body: "{}")
        }
        let confirmation = try await fixture.confirmation()
        await fixture.model.resetCodexUsage(confirmation)
        await fixture.model.resetCodexUsage(confirmation)

        XCTAssertEqual(posts, 1)
        XCTAssertEqual(fixture.model.codexResetOutcome, .reset)
        XCTAssertNil(fixture.model.codexResetError)
        XCTAssertNotNil(fixture.model.lastError)
        XCTAssertNil(fixture.model.codexResetCredits)
        XCTAssertTrue(fixture.store.snapshots(for: .codex).isEmpty)
    }

    func testAccountChangeAfterConfirmationDoesNotSendPost() async throws {
        let fixture = try Fixture()
        var posts = 0
        ResetURLProtocol.handler = { request in
            posts += 1
            return Self.response(request, body: #"{"code":"reset"}"#)
        }
        let confirmation = try await fixture.confirmation()
        await fixture.auth.updateAccount(accountId: "account-b", email: "other@example.com")

        await fixture.model.resetCodexUsage(confirmation)

        XCTAssertEqual(posts, 0)
        XCTAssertNotNil(fixture.model.codexResetError)
        XCTAssertNil(fixture.model.codexResetOutcome)
    }

    func testDemoModeCannotPrepareOrSubmitRealReset() async throws {
        let fixture = try Fixture()
        let confirmation = try await fixture.confirmation()
        fixture.defaults.set(true, forKey: DemoModeStore.enabledKey)
        var requests = 0
        ResetURLProtocol.handler = { request in
            requests += 1
            return Self.response(request, body: #"{"code":"reset"}"#)
        }

        let demoConfirmation = await fixture.model.prepareCodexUsageReset()
        await fixture.model.resetCodexUsage(confirmation)

        XCTAssertNil(demoConfirmation)
        XCTAssertEqual(requests, 0)
    }

    func testNoCreditAndNothingToResetRemainDistinctFromSuccess() async throws {
        for (code, expected) in [("no_credit", CodexUsageResetOutcome.noCredit), ("nothing_to_reset", .nothingToReset)] {
            let fixture = try Fixture()
            ResetURLProtocol.handler = { request in
                Self.response(request, body: request.httpMethod == "POST"
                    ? "{\"code\":\"\(code)\"}" : Self.usage(remaining: 0))
            }
            let confirmation = try await fixture.confirmation()
            await fixture.model.resetCodexUsage(confirmation)

            XCTAssertEqual(fixture.model.codexResetOutcome, expected)
            XCTAssertNil(fixture.model.codexResetCredits)
        }
    }

    func testUnknownAndHTTPErrorResponsesPreserveRequestIDForRetry() async throws {
        let fixture = try Fixture()
        var requestIDs: [String] = []
        ResetURLProtocol.handler = { request in
            requestIDs.append(try XCTUnwrap(Self.requestBody(request)["redeem_request_id"] as? String))
            if requestIDs.count == 1 {
                return Self.response(request, status: 500, body: "{}")
            }
            return Self.response(request, body: #"{"code":"new_unknown_outcome"}"#)
        }
        let confirmation = try await fixture.confirmation()
        await fixture.model.resetCodexUsage(confirmation)
        await fixture.model.resetCodexUsage(confirmation)

        XCTAssertEqual(requestIDs.count, 2)
        XCTAssertEqual(requestIDs.first, requestIDs.last)
        XCTAssertNil(fixture.model.codexResetOutcome)
        XCTAssertNotNil(fixture.model.codexResetError)
    }

    func testResetCardHidesForUnavailableOrInvalidCountsAndProviderErrors() throws {
        let fixture = try Fixture()
        for count in [nil, 0, -1, 0.5, .infinity, .nan] as [Double?] {
            fixture.model.codexSnapshots = [UsageSnapshot(
                provider: .codex, used: 80, limit: 100, source: "test", resetCredits: count
            )]
            XCTAssertNil(fixture.model.codexResetCredits)
        }
        fixture.model.codexSnapshots = fixture.store.snapshots(for: .codex)
        XCTAssertEqual(fixture.model.codexResetCredits, 2)
        fixture.model.codexSnapshots.append(.error(provider: .codex, message: "expired session"))
        XCTAssertNil(fixture.model.codexResetCredits)
    }

    private nonisolated static func response(_ request: URLRequest, status: Int = 200, body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    private nonisolated static func usage(remaining: Int) -> String {
        """
        {"rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000}},
         "rate_limit_reset_credits":{"available_count":\(remaining)}}
        """
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
    let suiteName = "codex-reset-test.\(UUID().uuidString)"
    let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("codex-reset-\(UUID().uuidString).json")
    let defaults: UserDefaults
    let store: UsageStore
    let auth = ResetAuthProvider()
    let provider: PrivateCodexUsageProvider
    lazy var model = makeModel()

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = UsageStore(testingStoreURL: storeURL)
        store.upsert(UsageSnapshot(
            provider: .codex, accountId: "account-a", displayName: "person@example.com",
            used: 80, limit: 100, source: "test", resetCredits: 2
        ))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResetURLProtocol.self]
        provider = PrivateCodexUsageProvider(
            authProvider: auth,
            backendBaseURL: URL(string: "https://example.test/backend-api")!,
            session: URLSession(configuration: configuration)
        )
    }

    func makeModel() -> DashboardViewModel {
        DashboardViewModel(
            usageStore: store,
            demoModeStore: DemoModeStore(defaults: defaults),
            codexProvider: provider,
            resetRequestStore: CodexResetRequestStore(defaults: defaults)
        )
    }

    func confirmation() async throws -> CodexUsageResetConfirmation {
        let value = await model.prepareCodexUsageReset()
        return try XCTUnwrap(value)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: storeURL)
        ResetURLProtocol.handler = nil
    }
}

private actor ResetAuthProvider: CodexAuthProviding {
    var tokenBundle: CodexTokenBundle? = CodexTokenBundle(
        idToken: "id", accessToken: "access", refreshToken: "refresh",
        expiresAt: Date().addingTimeInterval(3600), accountId: "account-a", email: "person@example.com",
        profile: CodexAccountProfile(displayName: "Codex User")
    )
    var isAuthenticated: Bool { tokenBundle != nil }
    func validAccessToken() async throws -> String { "access" }
    func refreshAccountProfile(accessToken: String) async -> CodexAccountProfile? { tokenBundle?.profile }
    func updateAccount(accountId: String?, email: String?) {
        tokenBundle?.accountId = accountId
        tokenBundle?.email = email
    }
    func startDeviceFlow() async throws -> CodexDeviceCodeResponse { throw CodexAuthError.notAuthenticated }
    func pollForToken(deviceCode: String, userCode: String, interval: Int) async throws -> CodexTokenBundle {
        throw CodexAuthError.notAuthenticated
    }
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
