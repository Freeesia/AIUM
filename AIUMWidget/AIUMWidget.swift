import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Configuration

enum AIUMWidgetProviderOption: String, AppEnum {
    case githubCopilot
    case codex
    case claudeCode

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"

    static var caseDisplayRepresentations: [AIUMWidgetProviderOption: DisplayRepresentation] = [
        .githubCopilot: "GitHub Copilot",
        .codex: "OpenAI Codex",
        .claudeCode: "Claude Code",
    ]

    var provider: Provider {
        switch self {
        case .githubCopilot: .githubCopilot
        case .codex: .codex
        case .claudeCode: .claudeCode
        }
    }
}

struct AIUMWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage Provider"
    static var description = IntentDescription("Choose the provider whose usage is shown.")

    @Parameter(title: "Provider", default: .githubCopilot)
    var provider: AIUMWidgetProviderOption

    static var parameterSummary: some ParameterSummary {
        Summary("Provider: \(\.$provider)")
    }
}

struct AIUMMediumWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage Providers"
    static var description = IntentDescription("Choose the two providers whose usage is shown side by side.")

    @Parameter(title: "Left Provider", default: .githubCopilot)
    var leadingProvider: AIUMWidgetProviderOption

    @Parameter(title: "Right Provider", default: .codex)
    var trailingProvider: AIUMWidgetProviderOption

    static var parameterSummary: some ParameterSummary {
        Summary("Left: \(\.$leadingProvider), Right: \(\.$trailingProvider)")
    }
}

// MARK: - Timeline Entry

struct AIUMWidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [UsageSnapshot]
    let provider: Provider

    var displaySnapshot: UsageSnapshot? {
        UsageSnapshot.displaySnapshot(from: snapshots, for: provider)
    }
}

struct AIUMMediumWidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [UsageSnapshot]
    let leadingProvider: Provider
    let trailingProvider: Provider
}

// MARK: - Timeline Providers

/// Shared by the small and Lock Screen widgets, which show one selected provider.
struct AIUMUsageWidgetProvider: AppIntentTimelineProvider {
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> AIUMWidgetEntry {
        Self.placeholderEntry
    }

    func snapshot(
        for configuration: AIUMWidgetConfigurationIntent,
        in context: Context
    ) async -> AIUMWidgetEntry {
        let snapshots = UsageStore.loadSnapshotsFromSharedContainer()
        return AIUMWidgetEntry(
            date: Date(),
            snapshots: snapshots,
            provider: configuration.provider.provider
        )
    }

    func timeline(
        for configuration: AIUMWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<AIUMWidgetEntry> {
        let now = Date()
        let snapshots = UsageStore.loadSnapshotsFromSharedContainer()
        let entry = AIUMWidgetEntry(
            date: now,
            snapshots: snapshots,
            provider: configuration.provider.provider
        )

        // Re-read cached snapshots every 5 minutes. WidgetKit may coalesce updates.
        let nextUpdate = now.addingTimeInterval(Self.refreshInterval)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    static let placeholderEntry = AIUMWidgetEntry(
        date: Date(),
        snapshots: [
            UsageSnapshot(
                provider: .githubCopilot,
                displayName: "octocat",
                planKind: .aiCredits,
                windowKind: .monthly,
                used: 600,
                limit: 1000,
                resetAt: Calendar.current.date(byAdding: .day, value: 12, to: Date()),
                unit: "AI credits",
                source: "placeholder"
            ),
            UsageSnapshot(
                provider: .codex,
                displayName: "user@example.com",
                planKind: .codexPro,
                windowKind: .custom,
                used: 72,
                limit: 100,
                resetAt: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
                unit: "percent",
                source: "placeholder",
                windowDurationMins: 5 * 60
            ),
            UsageSnapshot(
                provider: .codex,
                displayName: "user@example.com",
                planKind: .codexPro,
                windowKind: .custom,
                used: 42,
                limit: 100,
                resetAt: Calendar.current.date(byAdding: .day, value: 4, to: Date()),
                unit: "percent",
                source: "placeholder",
                windowDurationMins: 7 * 24 * 60
            ),
            UsageSnapshot(
                provider: .codex,
                displayName: "user@example.com",
                planKind: .codexLunaReserve,
                windowKind: .custom,
                used: 8,
                limit: 100,
                resetAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                unit: "percent",
                source: "placeholder",
                windowDurationMins: 7 * 24 * 60
            ),
            UsageSnapshot(
                provider: .claudeCode,
                windowKind: .custom,
                used: 54,
                limit: 100,
                resetAt: Calendar.current.date(byAdding: .hour, value: 3, to: Date()),
                unit: "percent",
                source: "placeholder",
                windowDurationMins: 5 * 60
            ),
            UsageSnapshot(
                provider: .claudeCode,
                windowKind: .custom,
                used: 31,
                limit: 100,
                resetAt: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
                unit: "percent",
                source: "placeholder",
                windowDurationMins: 7 * 24 * 60
            ),
        ],
        provider: .githubCopilot
    )
}

struct AIUMMediumWidgetProvider: AppIntentTimelineProvider {
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> AIUMMediumWidgetEntry {
        AIUMMediumWidgetEntry(
            date: Date(),
            snapshots: AIUMUsageWidgetProvider.placeholderEntry.snapshots,
            leadingProvider: .githubCopilot,
            trailingProvider: .codex
        )
    }

    func snapshot(
        for configuration: AIUMMediumWidgetConfigurationIntent,
        in context: Context
    ) async -> AIUMMediumWidgetEntry {
        makeEntry(for: configuration)
    }

    func timeline(
        for configuration: AIUMMediumWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<AIUMMediumWidgetEntry> {
        let entry = makeEntry(for: configuration)
        // Re-read cached snapshots every 5 minutes. WidgetKit may coalesce updates.
        let nextUpdate = entry.date.addingTimeInterval(Self.refreshInterval)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func makeEntry(for configuration: AIUMMediumWidgetConfigurationIntent) -> AIUMMediumWidgetEntry {
        AIUMMediumWidgetEntry(
            date: Date(),
            snapshots: UsageStore.loadSnapshotsFromSharedContainer(),
            leadingProvider: configuration.leadingProvider.provider,
            trailingProvider: configuration.trailingProvider.provider
        )
    }
}

// MARK: - Small Widget (selected provider)

struct AIUMSmallWidget: Widget {
    static let kind = "AIUMSmallWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: AIUMWidgetConfigurationIntent.self,
            provider: AIUMUsageWidgetProvider()
        ) { entry in
            AIUMSmallWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Usage")
        .description("Shows usage for your selected provider at a glance.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Lock Screen Widget (configurable provider)

struct AIUMLockScreenWidget: Widget {
    static let kind = "AIUMLockScreenUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: AIUMWidgetConfigurationIntent.self,
            provider: AIUMUsageWidgetProvider()
        ) { entry in
            AIUMConfigurableWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Lock Screen Usage")
        .description("Shows usage for your selected provider, with rings for Codex and Claude Code limits.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        .promptsForUserConfiguration()
    }
}

// MARK: - Medium Widget (two selected providers)

struct AIUMMediumWidget: Widget {
    static let kind = "AIUMMediumWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: AIUMMediumWidgetConfigurationIntent.self,
            provider: AIUMMediumWidgetProvider()
        ) { entry in
            AIUMMediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Usage Comparison")
        .description("Shows usage for two selected providers side by side.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
