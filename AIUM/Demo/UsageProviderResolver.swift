import Foundation

// MARK: - Protocol

/// Resolves the correct `UsageProvider` for a given `Provider` at runtime.
/// When demo mode is enabled, returns `DemoUsageProvider` instead of the
/// real network-backed provider.
protocol UsageProviderResolving {
    func provider(for provider: Provider) -> any UsageProvider
}

// MARK: - App Resolver

/// Production resolver that checks `DemoModeStore` on every resolution.
final class AppUsageProviderResolver: UsageProviderResolving {
    private let demoModeStore: DemoModeStore
    private let githubProvider: any UsageProvider
    private let codexProvider: any UsageProvider

    init(
        demoModeStore: DemoModeStore = DemoModeStore(),
        githubProvider: any UsageProvider = GitHubUsageProvider(),
        codexProvider: any UsageProvider = PrivateCodexUsageProvider()
    ) {
        self.demoModeStore = demoModeStore
        self.githubProvider = githubProvider
        self.codexProvider = codexProvider
    }

    func provider(for provider: Provider) -> any UsageProvider {
        if demoModeStore.isEnabled {
            return DemoUsageProvider(provider: provider)
        }
        switch provider {
        case .githubCopilot: return githubProvider
        case .codex: return codexProvider
        }
    }
}
