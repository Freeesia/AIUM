import Security
import XCTest
@testable import AIUM

@MainActor
final class UsageRefreshServiceTests: XCTestCase {
    func testKeychainTokensUseBackgroundAccessibleDeviceOnlyProtection() {
        XCTAssertTrue(
            CFEqual(
                KeychainHelper.tokenAccessibility,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            )
        )
    }

    func testKeychainSaveUsesBackgroundAccessibleProtection() throws {
        let service = "com.studiofreesia.aium.tests.\(UUID().uuidString)"
        let account = "save-accessibility"
        defer { try? KeychainHelper.delete(service: service, account: account) }

        try KeychainHelper.save("token", service: service, account: account)

        XCTAssertTrue(try keychainAccessibility(service: service, account: account))
    }

    func testCachedProviderReportsCredentialLoadFailure() async throws {
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let store = UsageStore(testingStoreURL: storeURL)
        store.upsert(snapshot(provider: .githubCopilot))
        let service = UsageRefreshService(
            usageStore: store,
            githubProvider: StubUsageProvider(
                provider: .githubCopilot,
                isAuthenticated: false,
                error: StubRefreshError.credentialsUnavailable
            ),
            codexProvider: StubUsageProvider(provider: .codex, isAuthenticated: false)
        )

        let result = await service.refreshUsage()

        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errorMessage?.contains("credentials unavailable") == true)
        XCTAssertEqual(store.snapshots(for: .githubCopilot).last?.errorMessage, "credentials unavailable")
    }

    func testSignedOutProviderWithoutCacheIsSkipped() async {
        let storeURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let store = UsageStore(testingStoreURL: storeURL)
        let githubProvider = StubUsageProvider(
            provider: .githubCopilot,
            isAuthenticated: false,
            error: StubRefreshError.credentialsUnavailable
        )
        let service = UsageRefreshService(
            usageStore: store,
            githubProvider: githubProvider,
            codexProvider: StubUsageProvider(provider: .codex, isAuthenticated: false)
        )

        let result = await service.refreshUsage()
        let fetchCount = await githubProvider.fetchCount

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(fetchCount, 0)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUM-UsageRefreshServiceTests-\(UUID().uuidString).json")
    }

    private func keychainAccessibility(service: String, account: String) throws -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess)
        let attributes = try XCTUnwrap(result as? [CFString: Any])
        let accessibility = try XCTUnwrap(attributes[kSecAttrAccessible] as? String)
        return accessibility == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    private func snapshot(provider: Provider) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            accountId: "test-account",
            planKind: .aiCredits,
            windowKind: .monthly,
            used: 1,
            limit: 10,
            source: "test"
        )
    }
}

private actor StubUsageProvider: UsageProvider {
    let provider: Provider
    let authenticated: Bool
    let snapshots: [UsageSnapshot]
    let error: Error?
    private(set) var fetchCount = 0

    init(
        provider: Provider,
        isAuthenticated: Bool,
        snapshots: [UsageSnapshot] = [],
        error: Error? = nil
    ) {
        self.provider = provider
        authenticated = isAuthenticated
        self.snapshots = snapshots
        self.error = error
    }

    var isAuthenticated: Bool {
        get async { authenticated }
    }

    func fetchUsage() async throws -> [UsageSnapshot] {
        fetchCount += 1
        if let error { throw error }
        return snapshots
    }
}

private enum StubRefreshError: LocalizedError {
    case credentialsUnavailable

    var errorDescription: String? {
        "credentials unavailable"
    }
}
