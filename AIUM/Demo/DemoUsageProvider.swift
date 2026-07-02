import Foundation

/// A demo implementation of `UsageProvider` that returns pre-generated
/// snapshot data without making any network requests.
actor DemoUsageProvider: UsageProvider {
    let provider: Provider

    init(provider: Provider) {
        self.provider = provider
    }

    var isAuthenticated: Bool {
        true
    }

    func fetchUsage() async throws -> [UsageSnapshot] {
        DemoUsageDataFactory.snapshots(for: provider)
    }
}
