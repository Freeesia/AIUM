import XCTest
@testable import AIUM

final class DashboardColumnsLayoutTests: XCTestCase {
    func testColumnsAreEqualWithoutDivision() {
        let layout = DashboardColumnsLayout(columnCount: 2, spacing: 16, division: nil, minimumColumnWidth: 320)

        let columns = layout.columns(width: 1016, count: 2)

        XCTAssertEqual(columns.map(\.x), [0, 516])
        XCTAssertEqual(columns.map(\.width), [500, 500])
    }

    func testTwoColumnsSplitAroundNarrowFold() {
        // A folded display: the fold is right of the center because trailing bars take space.
        let layout = DashboardColumnsLayout(columnCount: 2, spacing: 16, division: 480...480, minimumColumnWidth: 320)

        let columns = layout.columns(width: 880, count: 2)

        XCTAssertEqual(columns[0].x, 0)
        XCTAssertEqual(columns[0].width, 472)
        XCTAssertEqual(columns[1].x, 488)
        XCTAssertEqual(columns[1].width, 392)
    }

    func testTwoColumnsAvoidWideDivision() {
        let layout = DashboardColumnsLayout(columnCount: 2, spacing: 16, division: 440...480, minimumColumnWidth: 320)

        let columns = layout.columns(width: 900, count: 2)

        XCTAssertEqual(columns[0].width, 440)
        XCTAssertEqual(columns[1].x, 480)
        XCTAssertEqual(columns[1].width, 420)
    }

    func testDivisionIsIgnoredWhenAColumnWouldBeTooNarrow() {
        let layout = DashboardColumnsLayout(columnCount: 2, spacing: 16, division: 700...700, minimumColumnWidth: 320)

        let columns = layout.columns(width: 900, count: 2)

        XCTAssertEqual(columns.map(\.width), [442, 442])
    }

    func testDivisionIsIgnoredForOtherColumnCounts() {
        let layout = DashboardColumnsLayout(columnCount: 3, spacing: 16, division: 400...400, minimumColumnWidth: 200)

        XCTAssertEqual(layout.columns(width: 1040, count: 3).map(\.x), [0, 352, 704])
        XCTAssertEqual(layout.columns(width: 500, count: 1).map(\.width), [500])
    }
}
