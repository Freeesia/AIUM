import XCTest
@testable import AIUM

final class UsageStoreTests: XCTestCase {
    func testAppGroupIdentifierMatchesEntitlements() throws {
        let expectedIdentifier = "group.com.studiofreesia.aium"

        XCTAssertEqual(UsageStore.appGroupIdentifier, expectedIdentifier)
        XCTAssertEqual(
            try appGroups(in: repositoryRoot().appendingPathComponent("AIUM/AIUM.entitlements")),
            [expectedIdentifier]
        )
        XCTAssertEqual(
            try appGroups(in: repositoryRoot().appendingPathComponent("AIUMWidget/AIUMWidget.entitlements")),
            [expectedIdentifier]
        )
    }

    func testWidgetReadPathLoadsSnapshotsFromSharedAppGroup() throws {
        let containerURL = try XCTUnwrap(
            UsageStore.sharedContainerURL(),
            "App Group container is unavailable. Check Signing & Capabilities for AIUM."
        )
        let storeURL = containerURL.appendingPathComponent("usage_snapshots.json")
        let originalData = try? Data(contentsOf: storeURL)
        defer {
            if let originalData {
                try? originalData.write(to: storeURL, options: .atomicWrite)
            } else {
                try? FileManager.default.removeItem(at: storeURL)
            }
        }

        let expected = UsageSnapshot(
            provider: .githubCopilot,
            accountId: "test-account",
            displayName: "Widget Reader",
            planKind: .aiCredits,
            windowKind: .monthly,
            used: 42,
            limit: 100,
            unit: "AI credits",
            source: "test"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([expected]).write(to: storeURL, options: .atomicWrite)

        let loaded = UsageStore.loadSnapshotsFromSharedContainer()
        let actual = try XCTUnwrap(loaded.first { $0.id == expected.id })
        XCTAssertEqual(actual.provider, expected.provider)
        XCTAssertEqual(actual.accountId, expected.accountId)
        XCTAssertEqual(actual.displayName, expected.displayName)
        XCTAssertEqual(actual.used, expected.used, accuracy: 0.001)
        XCTAssertEqual(actual.limit, expected.limit, accuracy: 0.001)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func appGroups(in entitlementURL: URL) throws -> [String] {
        let data = try Data(contentsOf: entitlementURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        return try XCTUnwrap(plist["com.apple.security.application-groups"] as? [String])
    }
}
