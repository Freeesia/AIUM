import XCTest
@testable import AIUM

final class DemoUsageDataFactoryTests: XCTestCase {
    private let now = Date()

    func testGithubSnapshotsHaveDemoSource() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
        XCTAssertTrue(snapshots.allSatisfy { $0.source == "demo" })
    }

    func testCodexSnapshotsHaveDemoSource() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .codex, now: now)
        XCTAssertTrue(snapshots.allSatisfy { $0.source == "demo" })
    }

    func testGithubSnapshotsAccountId() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
        XCTAssertTrue(snapshots.allSatisfy { $0.accountId == "demo-github" })
    }

    func testCodexSnapshotsAccountId() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .codex, now: now)
        XCTAssertTrue(snapshots.allSatisfy { $0.accountId == "demo-codex" })
    }

    func testGithubSnapshotsContainAICreditsAndPremiumRequests() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
        XCTAssertTrue(snapshots.contains { $0.planKind == .aiCredits })
        XCTAssertTrue(snapshots.contains { $0.planKind == .premiumRequests })
    }

    func testCodexSnapshotsContainHourlyAndDaily() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .codex, now: now)
        XCTAssertTrue(snapshots.contains { $0.windowKind == .hourly })
        XCTAssertTrue(snapshots.contains { $0.windowKind == .daily })
    }

    func testGithubAICreditsValues() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
        let aiCredits = snapshots.first { $0.planKind == .aiCredits }
        XCTAssertEqual(aiCredits?.used, 620)
        XCTAssertEqual(aiCredits?.limit, 1000)
    }

    func testGithubPremiumRequestsValues() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
        let premiumRequests = snapshots.first { $0.planKind == .premiumRequests }
        XCTAssertEqual(premiumRequests?.used, 184)
        XCTAssertEqual(premiumRequests?.limit, 300)
    }

    func testCodexHourlyValues() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .codex, now: now)
        let hourly = snapshots.first { $0.windowKind == .hourly }
        XCTAssertEqual(hourly?.used, 37)
        XCTAssertEqual(hourly?.limit, 50)
    }

    func testCodexDailyValues() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .codex, now: now)
        let daily = snapshots.first { $0.windowKind == .daily }
        XCTAssertEqual(daily?.used, 210)
        XCTAssertEqual(daily?.limit, 300)
    }

    func testFetchedAtIsBasedOnNow() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
        for snapshot in snapshots {
            XCTAssertEqual(snapshot.fetchedAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        }
    }

    func testErrorMessageIsNil() {
        let allSnapshots = DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
            + DemoUsageDataFactory.snapshots(for: .codex, now: now)
        XCTAssertTrue(allSnapshots.allSatisfy { $0.errorMessage == nil })
    }

    func testGithubSnapshotsProvider() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .githubCopilot, now: now)
        XCTAssertTrue(snapshots.allSatisfy { $0.provider == .githubCopilot })
    }

    func testCodexSnapshotsProvider() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .codex, now: now)
        XCTAssertTrue(snapshots.allSatisfy { $0.provider == .codex })
    }
}
