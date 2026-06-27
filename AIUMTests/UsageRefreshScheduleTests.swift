import XCTest
@testable import AIUM

final class UsageRefreshScheduleTests: XCTestCase {
    func testRefreshSettingDefaultsToOneHourWhenUnset() {
        XCTAssertEqual(UsageRefreshSetting(storedValue: nil), .oneHour)
        XCTAssertEqual(UsageRefreshSetting(storedValue: 999), .oneHour)
    }

    func testRefreshSettingReadsAutomaticValue() {
        XCTAssertEqual(UsageRefreshSetting(storedValue: -1), .automatic)
    }

    func testFixedIntervalUsesSelectedSetting() {
        XCTAssertEqual(
            UsageRefreshSchedule.intervalMinutes(
                for: .thirtyMinutes,
                automaticIntervalMinutes: 5
            ),
            30
        )
    }

    func testAutomaticIntervalIsClampedToMinimum() {
        XCTAssertEqual(
            UsageRefreshSchedule.intervalMinutes(
                for: .automatic,
                automaticIntervalMinutes: 1
            ),
            5
        )
    }

    func testAutomaticIntervalDefaultsToOneHourWithoutLargeIncrease() {
        let previous = [snapshot(used: 100, limit: 1_000)]
        let current = [snapshot(used: 140, limit: 1_000)]

        XCTAssertEqual(
            UsageRefreshSchedule.automaticIntervalMinutes(previous: previous, current: current),
            60
        )
    }

    func testAutomaticIntervalShortensToThirtyMinutesAfterModerateIncrease() {
        let previous = [snapshot(used: 100, limit: 1_000)]
        let current = [snapshot(used: 150, limit: 1_000)]

        XCTAssertEqual(
            UsageRefreshSchedule.automaticIntervalMinutes(previous: previous, current: current),
            30
        )
    }

    func testAutomaticIntervalShortensToFifteenMinutesAfterLargeIncrease() {
        let previous = [snapshot(used: 100, limit: 1_000)]
        let current = [snapshot(used: 200, limit: 1_000)]

        XCTAssertEqual(
            UsageRefreshSchedule.automaticIntervalMinutes(previous: previous, current: current),
            15
        )
    }

    func testAutomaticIntervalShortensToFiveMinutesAfterVeryLargeIncrease() {
        let previous = [snapshot(used: 100, limit: 1_000)]
        let current = [snapshot(used: 350, limit: 1_000)]

        XCTAssertEqual(
            UsageRefreshSchedule.automaticIntervalMinutes(previous: previous, current: current),
            5
        )
    }

    func testAutomaticIntervalDefaultsToOneHourWithoutPreviousSnapshot() {
        XCTAssertEqual(
            UsageRefreshSchedule.automaticIntervalMinutes(
                previous: [],
                current: [snapshot(used: 900, limit: 1_000)]
            ),
            60
        )
    }

    func testAutomaticIntervalIgnoresErrorsAndUnknownLimits() {
        let current = [
            UsageSnapshot.error(provider: .codex, message: "failed"),
            snapshot(used: 500, limit: 0),
        ]

        XCTAssertEqual(
            UsageRefreshSchedule.automaticIntervalMinutes(previous: [], current: current),
            60
        )
    }

    private func snapshot(used: Double, limit: Double) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            accountId: "account",
            planKind: .codexPro,
            windowKind: .hourly,
            used: used,
            limit: limit,
            source: "test",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            windowDurationMins: 300
        )
    }
}
