import XCTest
@testable import AIUM

final class CodexParsingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - CodexRateLimitResponse

    func testDecodeFullRateLimitResponse() throws {
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

        let response = try decoder.decode(CodexRateLimitResponse.self, from: json)
        XCTAssertEqual(response.primaryWindow?.limit, 50, accuracy: 0.001)
        XCTAssertEqual(response.primaryWindow?.remaining, 20, accuracy: 0.001)
        XCTAssertNotNil(response.primaryWindow?.resetAt)
        XCTAssertEqual(response.primaryWindow?.windowDurationMins, 60)
        XCTAssertEqual(response.secondaryWindow?.limit, 500, accuracy: 0.001)
        XCTAssertEqual(response.resetCredits, 5.0, accuracy: 0.001)
    }

    func testDecodeEmptyRateLimitResponse() throws {
        let json = "{}".data(using: .utf8)!
        let response = try decoder.decode(CodexRateLimitResponse.self, from: json)
        XCTAssertNil(response.primaryWindow)
        XCTAssertNil(response.secondaryWindow)
        XCTAssertNil(response.resetCredits)
    }

    func testDecodeWithUsedPercent() throws {
        let json = """
        {
          "primary_window": {
            "limit": 100,
            "used_percent": 65.5,
            "window_duration_mins": 60
          }
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(CodexRateLimitResponse.self, from: json)
        XCTAssertEqual(response.primaryWindow?.usedPercent, 65.5, accuracy: 0.001)
    }

    // MARK: - Normalization

    func testNormalizationFromRemainingField() {
        let window = CodexRateLimitResponse.WindowDetail(
            limit: 50,
            remaining: 20,
            resetAt: nil,
            windowDurationMins: 60,
            usedPercent: nil
        )
        let response = CodexRateLimitResponse(
            primaryWindow: window,
            secondaryWindow: nil,
            resetCredits: nil
        )

        let provider = PrivateCodexUsageProvider()
        let snapshots = provider.normalizeSnapshots(response, tokenBundle: nil)

        XCTAssertEqual(snapshots.count, 1)
        let snapshot = snapshots[0]
        XCTAssertEqual(snapshot.used, 30, accuracy: 0.001)  // 50 - 20
        XCTAssertEqual(snapshot.limit, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.usedPercent, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.windowDurationMins, 60)
        XCTAssertEqual(snapshot.provider, .codex)
    }

    func testNormalizationFromUsedPercentField() {
        let window = CodexRateLimitResponse.WindowDetail(
            limit: 100,
            remaining: nil,
            resetAt: nil,
            windowDurationMins: nil,
            usedPercent: 75.0
        )
        let response = CodexRateLimitResponse(
            primaryWindow: window,
            secondaryWindow: nil,
            resetCredits: nil
        )

        let provider = PrivateCodexUsageProvider()
        let snapshots = provider.normalizeSnapshots(response, tokenBundle: nil)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].usedPercent, 75, accuracy: 0.001)
        XCTAssertEqual(snapshots[0].used, 75, accuracy: 0.001)
    }

    func testNormalizationWithBothWindows() {
        let primary = CodexRateLimitResponse.WindowDetail(
            limit: 50, remaining: 10, resetAt: nil, windowDurationMins: 60, usedPercent: nil
        )
        let secondary = CodexRateLimitResponse.WindowDetail(
            limit: 500, remaining: 200, resetAt: nil, windowDurationMins: 1440, usedPercent: nil
        )
        let response = CodexRateLimitResponse(
            primaryWindow: primary, secondaryWindow: secondary, resetCredits: nil
        )

        let provider = PrivateCodexUsageProvider()
        let snapshots = provider.normalizeSnapshots(response, tokenBundle: nil)

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].used, 40, accuracy: 0.001)   // primary: 50 - 10
        XCTAssertEqual(snapshots[1].used, 300, accuracy: 0.001)  // secondary: 500 - 200
        XCTAssertEqual(snapshots[1].windowKind, .daily)
    }

    func testNormalizationWithTokenBundle() {
        let bundle = CodexTokenBundle(
            idToken: "id",
            accessToken: "access",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            accountId: "user-123",
            email: "test@example.com"
        )
        let window = CodexRateLimitResponse.WindowDetail(
            limit: 50, remaining: 25, resetAt: nil, windowDurationMins: nil, usedPercent: nil
        )
        let response = CodexRateLimitResponse(
            primaryWindow: window, secondaryWindow: nil, resetCredits: nil
        )

        let provider = PrivateCodexUsageProvider()
        let snapshots = provider.normalizeSnapshots(response, tokenBundle: bundle)

        XCTAssertEqual(snapshots.first?.accountId, "user-123")
        XCTAssertEqual(snapshots.first?.displayName, "test@example.com")
    }

    // MARK: - Token refresh single-flight

    func testTokenBundleIsExpiredNearExpiry() {
        var bundle = CodexTokenBundle(
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
}

// MARK: - Helper initializers for testing
// Allow constructing model objects without going through Decodable

extension CodexRateLimitResponse.WindowDetail {
    init(limit: Double?, remaining: Double?, resetAt: Date?,
         windowDurationMins: Int?, usedPercent: Double?) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
        self.windowDurationMins = windowDurationMins
        self.usedPercent = usedPercent
    }
}

extension CodexRateLimitResponse {
    init(primaryWindow: WindowDetail?, secondaryWindow: WindowDetail?, resetCredits: Double?) {
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
        self.resetCredits = resetCredits
    }
}
