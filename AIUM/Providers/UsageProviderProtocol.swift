import Foundation

/// A type that can fetch current usage for a specific provider and return
/// normalized UsageSnapshot values.
protocol UsageProvider: Actor {
    var provider: Provider { get }

    /// Fetch the latest usage data.
    /// Throws on network / auth error.
    func fetchUsage() async throws -> [UsageSnapshot]

    /// Returns true if the user is authenticated with this provider.
    var isAuthenticated: Bool { get async }
}
