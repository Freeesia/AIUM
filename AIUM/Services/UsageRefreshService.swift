import Foundation

struct UsageRefreshResult {
    let previousSnapshots: [UsageSnapshot]
    let currentSnapshots: [UsageSnapshot]
    let errorMessage: String?
    let automaticIntervalMinutes: Int

    var isSuccess: Bool {
        errorMessage == nil
    }
}

@MainActor
final class UsageRefreshService {
    private let usageStore: UsageStore
    private let resolver: any UsageProviderResolving

    init(
        usageStore: UsageStore? = nil,
        resolver: any UsageProviderResolving = AppUsageProviderResolver()
    ) {
        self.usageStore = usageStore ?? .shared
        self.resolver = resolver
    }

    func refreshUsage() async -> UsageRefreshResult {
        let previousSnapshots = usageStore.snapshots
        let errors = [
            await refreshProvider(.githubCopilot),
            await refreshProvider(.codex),
        ].compactMap { $0 }

        let currentSnapshots = usageStore.snapshots
        let automaticIntervalMinutes = UsageRefreshSchedule.automaticIntervalMinutes(
            previous: previousSnapshots,
            current: currentSnapshots
        )
        UsageRefreshSchedule.storeAutomaticIntervalMinutes(automaticIntervalMinutes)

        return UsageRefreshResult(
            previousSnapshots: previousSnapshots,
            currentSnapshots: currentSnapshots,
            errorMessage: errors.isEmpty ? nil : errors.joined(separator: "\n"),
            automaticIntervalMinutes: automaticIntervalMinutes
        )
    }

    private func refreshProvider(_ providerKind: Provider) async -> String? {
        let usageProvider = resolver.provider(for: providerKind)
        let hasCachedUsage = !usageStore.snapshots(for: providerKind).isEmpty
        guard await usageProvider.isAuthenticated || hasCachedUsage else { return nil }

        do {
            let snapshots = try await usageProvider.fetchUsage()
            usageStore.replace(provider: providerKind, with: snapshots)
            return nil
        } catch {
            let errSnapshot = UsageSnapshot.error(provider: providerKind, message: error.localizedDescription)
            usageStore.upsert(errSnapshot)
            return error.localizedDescription
        }
    }
}
