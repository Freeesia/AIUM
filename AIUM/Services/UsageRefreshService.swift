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
    private let githubProvider: GitHubUsageProvider
    private let codexProvider: PrivateCodexUsageProvider

    init(
        usageStore: UsageStore? = nil,
        githubProvider: GitHubUsageProvider = GitHubUsageProvider(),
        codexProvider: PrivateCodexUsageProvider = PrivateCodexUsageProvider()
    ) {
        self.usageStore = usageStore ?? .shared
        self.githubProvider = githubProvider
        self.codexProvider = codexProvider
    }

    func refreshUsage() async -> UsageRefreshResult {
        let previousSnapshots = usageStore.snapshots
        let errors = [
            await refreshGitHub(),
            await refreshCodex(),
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

    private func refreshGitHub() async -> String? {
        do {
            guard await githubProvider.isAuthenticated else { return nil }
            let snapshots = try await githubProvider.fetchUsage()
            usageStore.replace(provider: .githubCopilot, with: snapshots)
            return nil
        } catch {
            let errSnapshot = UsageSnapshot.error(provider: .githubCopilot, message: error.localizedDescription)
            usageStore.upsert(errSnapshot)
            return error.localizedDescription
        }
    }

    private func refreshCodex() async -> String? {
        do {
            guard await codexProvider.isAuthenticated else { return nil }
            let snapshots = try await codexProvider.fetchUsage()
            usageStore.replace(provider: .codex, with: snapshots)
            return nil
        } catch {
            let errSnapshot = UsageSnapshot.error(provider: .codex, message: error.localizedDescription)
            usageStore.upsert(errSnapshot)
            return error.localizedDescription
        }
    }
}
