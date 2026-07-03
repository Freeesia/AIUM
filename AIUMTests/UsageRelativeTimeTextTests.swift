import XCTest
@testable import AIUM

final class UsageRelativeTimeTextTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let locale = Locale(identifier: "en_US")

    func testResetWithinNextMinuteRoundsUpWithoutSeconds() {
        let text = UsageRelativeTimeText.reset(
            at: referenceDate.addingTimeInterval(30),
            relativeTo: referenceDate,
            locale: locale
        )

        XCTAssertTrue(text.contains("1"), "Unexpected relative time: \(text)")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("sec"))
    }

    func testResetWithinPreviousMinuteRoundsDownWithoutSeconds() {
        let text = UsageRelativeTimeText.reset(
            at: referenceDate.addingTimeInterval(-30),
            relativeTo: referenceDate,
            locale: locale
        )

        XCTAssertTrue(text.contains("1"), "Unexpected relative time: \(text)")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("sec"))
    }

    func testRecentFetchDisplaysNowWithoutSeconds() {
        let text = UsageRelativeTimeText.fetched(
            at: referenceDate.addingTimeInterval(-30),
            relativeTo: referenceDate,
            locale: locale
        )

        XCTAssertEqual(text, "now")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("sec"))
    }

    func testOlderFetchDisplaysElapsedMinutesWithoutSeconds() {
        let text = UsageRelativeTimeText.fetched(
            at: referenceDate.addingTimeInterval(-90),
            relativeTo: referenceDate,
            locale: locale
        )

        XCTAssertTrue(text.contains("1"), "Unexpected relative time: \(text)")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("sec"))
    }
}
