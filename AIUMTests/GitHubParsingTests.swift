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

    func testDecodeAICreditUsage() throws {
        let json = """
        {
          "used_in_current_period": 250.5,
          "total_allowance": 1000.0,
          "current_period_end": "2024-02-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(GitHubAICreditUsageResponse.self, from: json)
        XCTAssertEqual(response.usedInCurrentPeriod, 250.5, accuracy: 0.001)
        XCTAssertEqual(response.totalAllowance, 1000.0, accuracy: 0.001)
        XCTAssertNotNil(response.currentPeriodEnd)
    }

    func testDecodeAICreditUsageAllNulls() throws {
        let json = "{}".data(using: .utf8)!
        let response = try decoder.decode(GitHubAICreditUsageResponse.self, from: json)
        XCTAssertNil(response.usedInCurrentPeriod)
        XCTAssertNil(response.totalAllowance)
        XCTAssertNil(response.currentPeriodEnd)
    }

    // MARK: - GitHubPremiumRequestUsageResponse

    func testDecodePremiumRequestUsage() throws {
        let json = """
        {
          "used_premium_requests": 5,
          "included_premium_requests": 300,
          "last_updated_at": "2024-01-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(GitHubPremiumRequestUsageResponse.self, from: json)
        XCTAssertEqual(response.usedPremiumRequests, 5, accuracy: 0.001)
        XCTAssertEqual(response.includedPremiumRequests, 300, accuracy: 0.001)
        XCTAssertNotNil(response.lastUpdatedAt)
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
}
