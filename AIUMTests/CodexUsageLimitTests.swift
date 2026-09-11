import XCTest
@testable import AIUM

final class CodexUsageLimitTests: XCTestCase {
    func testRingsKeepTheirLimitsWhenResponseOrderAndUsageDiffer() {
        let snapshots = [
            snapshot(plan: .codexLunaReserve, minutes: 7 * 24 * 60, used: 95),
            snapshot(minutes: 7 * 24 * 60, used: 20),
            snapshot(minutes: 5 * 60, used: 45),
        ]

        XCTAssertEqual(
            CodexUsageLimit.allCases.map { $0.snapshot(in: snapshots)?.usedPercent },
            [45, 20, 95]
        )
    }

    func testMissingReserveDoesNotReuseTheWeeklyLimit() {
        let snapshots = [snapshot(minutes: 7 * 24 * 60, used: 80)]

        XCTAssertNil(CodexUsageLimit.fiveHour.snapshot(in: snapshots))
        XCTAssertEqual(CodexUsageLimit.weekly.snapshot(in: snapshots)?.usedPercent, 80)
        XCTAssertNil(CodexUsageLimit.lunaReserve.snapshot(in: snapshots))
    }

    func testMissingWeeklyLimitDoesNotReuseReserve() {
        let snapshots = [snapshot(plan: .codexLunaReserve, minutes: 7 * 24 * 60, used: 80)]

        XCTAssertNil(CodexUsageLimit.weekly.snapshot(in: snapshots))
        XCTAssertEqual(CodexUsageLimit.lunaReserve.snapshot(in: snapshots)?.usedPercent, 80)
    }

    func testZeroUsageIsAvailableButUnknownAndFailedLimitsAreNot() {
        let zero = snapshot(minutes: 5 * 60, used: 0)
        let unavailable = UsageSnapshot(
            provider: .codex, used: 0, limit: 0, source: "unknown",
            windowDurationMins: 7 * 24 * 60
        )
        let failed = UsageSnapshot(
            provider: .codex, planKind: .codexLunaReserve, used: 0, limit: 100,
            source: "failed", errorMessage: "Unavailable", windowDurationMins: 7 * 24 * 60
        )
        let snapshots = [zero, unavailable, failed]

        XCTAssertEqual(CodexUsageLimit.fiveHour.snapshot(in: snapshots)?.usedPercent, 0)
        XCTAssertNil(CodexUsageLimit.weekly.snapshot(in: snapshots))
        XCTAssertNil(CodexUsageLimit.lunaReserve.snapshot(in: snapshots))
    }

    func testSelectsLatestMatchingSnapshotAndExcludesOtherProviders() {
        let old = snapshot(minutes: 5 * 60, used: 90, fetchedAt: 100)
        let latest = snapshot(minutes: 5 * 60, used: 10, fetchedAt: 200)
        let github = UsageSnapshot(
            provider: .githubCopilot, used: 100, limit: 100, source: "github",
            fetchedAt: Date(timeIntervalSince1970: 300), windowDurationMins: 5 * 60
        )

        XCTAssertEqual(CodexUsageLimit.fiveHour.snapshot(in: [latest, github, old])?.usedPercent, 10)
    }

    private func snapshot(
        plan: PlanKind = .codexPro,
        minutes: Int,
        used: Double,
        fetchedAt: TimeInterval = 100
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex, planKind: plan, windowKind: .custom,
            used: used, limit: 100, source: "test",
            fetchedAt: Date(timeIntervalSince1970: fetchedAt), windowDurationMins: minutes
        )
    }
}
