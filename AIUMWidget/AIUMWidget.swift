import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Configuration

enum AIUMWidgetProviderOption: String, AppEnum {
    case githubCopilot
    case codex

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"

    static var caseDisplayRepresentations: [AIUMWidgetProviderOption: DisplayRepresentation] = [
        .githubCopilot: "GitHub Copilot",
        .codex: "OpenAI Codex",
    ]

    var provider: Provider {
        switch self {
        case .githubCopilot: .githubCopilot
        case .codex: .codex
        }
    }
}

struct AIUMWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage Provider"
    static var description = IntentDescription("Choose the provider whose highest usage is shown.")

    @Parameter(title: "Provider", default: .githubCopilot)
    var provider: AIUMWidgetProviderOption
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

// MARK: - Timeline Provider

struct AIUMWidgetProvider: AppIntentTimelineProvider {
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
                windowKind: .hourly,
                used: 30,
                limit: 50,
                resetAt: Calendar.current.date(byAdding: .hour, value: 1, to: Date()),
                unit: "requests",
                source: "placeholder"
            ),
        ],
        provider: .githubCopilot
    )
}

struct AIUMMediumWidgetProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> AIUMWidgetEntry {
        AIUMWidgetProvider.placeholderEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (AIUMWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIUMWidgetEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(date: now)
        let nextUpdate = now.addingTimeInterval(Self.refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry(date: Date = Date()) -> AIUMWidgetEntry {
        AIUMWidgetEntry(
            date: date,
            snapshots: UsageStore.loadSnapshotsFromSharedContainer(),
            provider: .githubCopilot
        )
    }
}

// MARK: - Small Widget (single provider)

struct AIUMSmallWidget: Widget {
    static let kind = "AIUMSmallWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: AIUMWidgetConfigurationIntent.self,
            provider: AIUMWidgetProvider()
        ) { entry in
            AIUMConfigurableWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Usage")
        .description("Shows your primary usage at a glance.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Medium Widget (both providers)

struct AIUMMediumWidget: Widget {
    static let kind = "AIUMMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AIUMMediumWidgetProvider()) { entry in
            AIUMMediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Copilot & Codex")
        .description("Shows GitHub Copilot and Codex usage side by side.")
        .supportedFamilies([.systemMedium])
    }
}
