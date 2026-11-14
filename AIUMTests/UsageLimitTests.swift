import XCTest
@testable import AIUM

final class UsageLimitTests: XCTestCase {
    func testRingsKeepTheirLimitsWhenResponseOrderAndUsageDiffer() {
        let snapshots = [
            snapshot(plan: .codexLunaReserve, minutes: 7 * 24 * 60, used: 95),
            snapshot(minutes: 7 * 24 * 60, used: 20),
            snapshot(minutes: 5 * 60, used: 45),
        ]

        XCTAssertEqual(
            UsageLimit.limits(for: .codex).map { $0.snapshot(in: snapshots, for: .codex)?.usedPercent },
            [45, 20, 95]
        )
    }

    func testMissingReserveDoesNotReuseTheWeeklyLimit() {
        let snapshots = [snapshot(minutes: 7 * 24 * 60, used: 80)]

        XCTAssertNil(UsageLimit.fiveHour.snapshot(in: snapshots, for: .codex))
        XCTAssertEqual(UsageLimit.weekly.snapshot(in: snapshots, for: .codex)?.usedPercent, 80)
        XCTAssertNil(UsageLimit.lunaReserve.snapshot(in: snapshots, for: .codex))
    }

    func testMissingWeeklyLimitDoesNotReuseReserve() {
        let snapshots = [snapshot(plan: .codexLunaReserve, minutes: 7 * 24 * 60, used: 80)]

        XCTAssertNil(UsageLimit.weekly.snapshot(in: snapshots, for: .codex))
        XCTAssertEqual(UsageLimit.lunaReserve.snapshot(in: snapshots, for: .codex)?.usedPercent, 80)
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

        XCTAssertEqual(UsageLimit.fiveHour.snapshot(in: snapshots, for: .codex)?.usedPercent, 0)
        XCTAssertNil(UsageLimit.weekly.snapshot(in: snapshots, for: .codex))
        XCTAssertNil(UsageLimit.lunaReserve.snapshot(in: snapshots, for: .codex))
    }

    func testSelectsLatestMatchingSnapshotAndExcludesOtherProviders() {
        let old = snapshot(minutes: 5 * 60, used: 90, fetchedAt: 100)
        let latest = snapshot(minutes: 5 * 60, used: 10, fetchedAt: 200)
        let github = UsageSnapshot(
            provider: .githubCopilot, used: 100, limit: 100, source: "github",
            fetchedAt: Date(timeIntervalSince1970: 300), windowDurationMins: 5 * 60
        )

        XCTAssertEqual(UsageLimit.fiveHour.snapshot(in: [latest, github, old], for: .codex)?.usedPercent, 10)
    }

    func testClaudeCodeShowsFiveHourAndWeeklyRingsOnly() {
        XCTAssertEqual(UsageLimit.limits(for: .claudeCode), [.fiveHour, .weekly])
        XCTAssertEqual(UsageLimit.limits(for: .githubCopilot), [])
        XCTAssertTrue(Provider.claudeCode.usesUsageRings)
        XCTAssertTrue(Provider.codex.usesUsageRings)
        XCTAssertFalse(Provider.githubCopilot.usesUsageRings)
    }

    func testClaudeCodeLimitsDoNotMixWithCodexSnapshots() {
        let snapshots = [
            snapshot(minutes: 5 * 60, used: 90),
            snapshot(provider: .claudeCode, plan: .unknown, minutes: 7 * 24 * 60, used: 31),
            snapshot(provider: .claudeCode, plan: .unknown, minutes: 5 * 60, used: 54),
        ]

        XCTAssertEqual(
            UsageLimit.limits(for: .claudeCode).map { $0.snapshot(in: snapshots, for: .claudeCode)?.usedPercent },
            [54, 31]
        )
        XCTAssertNil(UsageLimit.weekly.snapshot(in: snapshots, for: .codex))
    }

    private func snapshot(
        provider: Provider = .codex,
        plan: PlanKind = .codexPro,
        minutes: Int,
        used: Double,
        fetchedAt: TimeInterval = 100
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider, planKind: plan, windowKind: .custom,
            used: used, limit: 100, source: "test",
            fetchedAt: Date(timeIntervalSince1970: fetchedAt), windowDurationMins: minutes
        )
    }
}
