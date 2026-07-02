import XCTest
@testable import AIUM

final class DemoUsageProviderTests: XCTestCase {
    func testIsAuthenticatedAlwaysTrue() async {
        let provider = DemoUsageProvider(provider: .githubCopilot)
        let result = await provider.isAuthenticated
        XCTAssertTrue(result)
    }

    func testFetchUsageReturnsGithubDemoSnapshots() async throws {
        let provider = DemoUsageProvider(provider: .githubCopilot)
        let snapshots = try await provider.fetchUsage()
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertTrue(snapshots.allSatisfy { $0.source == "demo" })
        XCTAssertTrue(snapshots.allSatisfy { $0.provider == .githubCopilot })
    }

    func testFetchUsageReturnsCodexDemoSnapshots() async throws {
        let provider = DemoUsageProvider(provider: .codex)
        let snapshots = try await provider.fetchUsage()
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertTrue(snapshots.allSatisfy { $0.source == "demo" })
        XCTAssertTrue(snapshots.allSatisfy { $0.provider == .codex })
    }

    func testProviderPropertyMatchesInit() async {
        let github = DemoUsageProvider(provider: .githubCopilot)
        let codex = DemoUsageProvider(provider: .codex)
        let githubProvider = await github.provider
        let codexProvider = await codex.provider
        XCTAssertEqual(githubProvider, .githubCopilot)
        XCTAssertEqual(codexProvider, .codex)
    }
}
