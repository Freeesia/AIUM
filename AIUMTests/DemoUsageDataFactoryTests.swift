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

    func testCodexSnapshotsContainOnlyWeeklyWindow() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .codex, now: now)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.windowDurationMins, 7 * 24 * 60)
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

    func testCodexWeeklyValues() {
        let snapshots = DemoUsageDataFactory.snapshots(for: .codex, now: now)
        let weekly = snapshots.first
        XCTAssertEqual(weekly?.used, 42)
        XCTAssertEqual(weekly?.limit, 100)
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
