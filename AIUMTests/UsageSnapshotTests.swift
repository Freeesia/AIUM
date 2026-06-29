import XCTest
@testable import AIUM

final class UsageSnapshotTests: XCTestCase {
    // MARK: - usedPercent

    func testUsedPercentBasic() {
        let snapshot = UsageSnapshot(
            provider: .githubCopilot,
            used: 500,
            limit: 1000,
            source: "test"
        )
        XCTAssertEqual(snapshot.usedPercent, 50, accuracy: 0.001)
    }

    func testUsedPercentZeroLimit() {
        let snapshot = UsageSnapshot(
            provider: .githubCopilot,
            used: 100,
            limit: 0,
            source: "test"
        )
        XCTAssertEqual(snapshot.usedPercent, 0)
    }

    func testUsedPercentCapsAt100() {
        let snapshot = UsageSnapshot(
            provider: .githubCopilot,
            used: 1200,
            limit: 1000,
            source: "test"
        )
        XCTAssertEqual(snapshot.usedPercent, 100, accuracy: 0.001)
    }

    // MARK: - remainingPercent

    func testRemainingPercentBasic() {
        let snapshot = UsageSnapshot(
            provider: .codex,
            used: 300,
            limit: 1000,
            source: "test"
        )
        XCTAssertEqual(snapshot.remainingPercent, 70, accuracy: 0.001)
    }

    func testRemainingPercentFloorAtZero() {
        let snapshot = UsageSnapshot(
            provider: .codex,
            used: 1500,
            limit: 1000,
            source: "test"
        )
        XCTAssertEqual(snapshot.remainingPercent, 0)
    }

    // MARK: - Placeholder / Error factories

    func testPlaceholderHasNoError() {
        let s = UsageSnapshot.placeholder(provider: .githubCopilot)
        XCTAssertNil(s.errorMessage)
        XCTAssertEqual(s.provider, .githubCopilot)
        XCTAssertEqual(s.used, 0)
    }

    func testErrorSnapshotHasMessage() {
        let s = UsageSnapshot.error(provider: .codex, message: "Network failure")
        XCTAssertEqual(s.errorMessage, "Network failure")
        XCTAssertEqual(s.provider, .codex)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = UsageSnapshot(
            provider: .githubCopilot,
            accountId: "123",
            displayName: "octocat",
            planKind: .aiCredits,
            windowKind: .monthly,
            used: 750,
            limit: 1000,
            resetAt: Date(timeIntervalSince1970: 1_700_000_000),
            unit: "AI credits",
            source: "GitHub Billing API"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.provider, original.provider)
        XCTAssertEqual(decoded.accountId, original.accountId)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.planKind, original.planKind)
        XCTAssertEqual(decoded.windowKind, original.windowKind)
        XCTAssertEqual(decoded.used, original.used, accuracy: 0.001)
        XCTAssertEqual(decoded.limit, original.limit, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(decoded.resetAt?.timeIntervalSinceReferenceDate),
                       try XCTUnwrap(original.resetAt?.timeIntervalSinceReferenceDate),
                       accuracy: 1)
        XCTAssertEqual(decoded.unit, original.unit)
        XCTAssertEqual(decoded.source, original.source)
    }

    // MARK: - ID uniqueness

    func testSnapshotIDDiffers() {
        let a = UsageSnapshot(provider: .githubCopilot, planKind: .aiCredits,
                              used: 0, limit: 0, source: "test")
        let b = UsageSnapshot(provider: .githubCopilot, planKind: .premiumRequests,
                              used: 0, limit: 0, source: "test")
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - Widget display selection

    func testDisplaySnapshotFiltersByProviderAndSelectsHighestUsage() throws {
        let github = UsageSnapshot(
            provider: .githubCopilot,
            used: 90,
            limit: 100,
            source: "test"
        )
        let codexLow = UsageSnapshot(
            provider: .codex,
            used: 30,
            limit: 100,
            source: "low"
        )
        let codexHigh = UsageSnapshot(
            provider: .codex,
            used: 80,
            limit: 100,
            source: "high"
        )

        let selected = try XCTUnwrap(UsageSnapshot.displaySnapshot(
            from: [github, codexLow, codexHigh],
            for: .codex
        ))

        XCTAssertEqual(selected.source, "high")
    }

    func testDisplaySnapshotPrefersSuccessfulSnapshotOverError() throws {
        let error = UsageSnapshot.error(
            provider: .githubCopilot,
            planKind: .premiumRequests,
            source: "endpoint",
            message: "Unavailable"
        )
        let successful = UsageSnapshot(
            provider: .githubCopilot,
            used: 0,
            limit: 100,
            source: "successful"
        )

        let selected = try XCTUnwrap(UsageSnapshot.displaySnapshot(
            from: [error, successful],
            for: .githubCopilot
        ))

        XCTAssertEqual(selected.source, "successful")
        XCTAssertNil(selected.errorMessage)
    }

    func testDisplaySnapshotPrefersProviderErrorOverStaleSuccess() throws {
        let successful = UsageSnapshot(
            provider: .codex,
            used: 80,
            limit: 100,
            source: "successful",
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let authenticationError = UsageSnapshot(
            provider: .codex,
            planKind: .unknown,
            used: 0,
            limit: 0,
            source: "error",
            fetchedAt: Date(timeIntervalSince1970: 200),
            errorMessage: "Authentication failed"
        )

        let selected = try XCTUnwrap(UsageSnapshot.displaySnapshot(
            from: [successful, authenticationError],
            for: .codex
        ))

        XCTAssertEqual(selected.errorMessage, "Authentication failed")
    }

    func testDisplaySnapshotReturnsErrorWhenNoSuccessfulSnapshotExists() throws {
        let error = UsageSnapshot.error(
            provider: .codex,
            source: "error",
            message: "Unavailable"
        )

        let selected = try XCTUnwrap(UsageSnapshot.displaySnapshot(
            from: [error],
            for: .codex
        ))

        XCTAssertEqual(selected.errorMessage, "Unavailable")
    }

    func testDisplaySnapshotReturnsNilWhenProviderHasNoData() {
        let github = UsageSnapshot(
            provider: .githubCopilot,
            used: 50,
            limit: 100,
            source: "test"
        )

        XCTAssertNil(UsageSnapshot.displaySnapshot(from: [github], for: .codex))
    }
}
