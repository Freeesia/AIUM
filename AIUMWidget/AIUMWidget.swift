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
    static var description = IntentDescription("Choose the provider whose usage is shown.")

    @Parameter(title: "Provider", default: .githubCopilot)
    var provider: AIUMWidgetProviderOption

    static var parameterSummary: some ParameterSummary {
        Summary("Provider: \(\.$provider)")
    }
}

// iOS 27 lets a widget button run an action selected by the user. Keep this
// separate from the iOS 18 configuration so the app retains its deployment target.
@available(iOS 27.0, *)
struct AIUMShortcutWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage Provider & Action"
    static var description = IntentDescription(
        "Choose the usage provider and the app or shortcut to run when tapped."
    )

    @Parameter(title: "Provider", default: .githubCopilot)
    var provider: AIUMWidgetProviderOption

    // Optional so placeholders and widgets awaiting configuration still render.
    @Parameter(title: "Action")
    var shortcut: SystemShortcut?
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

struct AIUMLockScreenWidgetProvider: AppIntentTimelineProvider {
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
        ],
        provider: .githubCopilot
    )
}

// The iOS 27 shortcut is supplied by WidgetKit, not resolved by the provider.
// The provider continues to read usage exclusively from the App Group cache.
@available(iOS 27.0, *)
struct AIUMShortcutWidgetEntry: TimelineEntry {
    let usage: AIUMWidgetEntry
    let configuration: AIUMShortcutWidgetConfigurationIntent

    var date: Date { usage.date }
}

@available(iOS 27.0, *)
struct AIUMShortcutWidgetProvider: AppIntentTimelineProvider {
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> AIUMShortcutWidgetEntry {
        AIUMShortcutWidgetEntry(
            usage: AIUMLockScreenWidgetProvider.placeholderEntry,
            configuration: AIUMShortcutWidgetConfigurationIntent()
        )
    }

    func snapshot(
        for configuration: AIUMShortcutWidgetConfigurationIntent,
        in context: Context
    ) async -> AIUMShortcutWidgetEntry {
        makeEntry(for: configuration)
    }

    func timeline(
        for configuration: AIUMShortcutWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<AIUMShortcutWidgetEntry> {
        let entry = makeEntry(for: configuration)
        return Timeline(
            entries: [entry],
            policy: .after(entry.date.addingTimeInterval(Self.refreshInterval))
        )
    }

    private func makeEntry(
        for configuration: AIUMShortcutWidgetConfigurationIntent
    ) -> AIUMShortcutWidgetEntry {
        let usage = AIUMWidgetEntry(
            date: Date(),
            snapshots: UsageStore.loadSnapshotsFromSharedContainer(),
            provider: configuration.provider.provider
        )
        return AIUMShortcutWidgetEntry(usage: usage, configuration: configuration)
    }
}

struct AIUMStaticWidgetProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> AIUMWidgetEntry {
        AIUMLockScreenWidgetProvider.placeholderEntry
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

// A system-shortcut button is the only interaction on iOS 27+. There is
// deliberately no URL Scheme or network call in this widget extension.
@available(iOS 27.0, *)
struct AIUMShortcutWidgetView: View {
    let entry: AIUMShortcutWidgetEntry

    @ViewBuilder
    var body: some View {
        if let shortcut = entry.configuration.shortcut {
            Button(intent: RunSystemShortcutIntent(shortcut: shortcut)) {
                usageView
            }
            .buttonStyle(.plain)
        } else {
            usageView
        }
    }

    private var usageView: some View {
        AIUMConfigurableWidgetView(entry: entry.usage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}

// MARK: - Small Widget (single provider)

struct AIUMSmallWidget: Widget {
    static let kind = "AIUMSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AIUMStaticWidgetProvider()) { entry in
            AIUMSmallWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Usage")
        .description("Shows your primary usage at a glance.")
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
            provider: AIUMLockScreenWidgetProvider()
        ) { entry in
            AIUMConfigurableWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Lock Screen Usage")
        .description("Shows usage for your selected provider, with three rings for Codex limits.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        .promptsForUserConfiguration()
    }
}

@available(iOS 27.0, *)
struct AIUMShortcutLockScreenWidget: Widget {
    static let kind = "AIUMLockScreenUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: AIUMShortcutWidgetConfigurationIntent.self,
            provider: AIUMShortcutWidgetProvider()
        ) { entry in
            AIUMShortcutWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Lock Screen Usage")
        .description("Shows usage and runs your configured app or shortcut when tapped.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        .promptsForUserConfiguration()
    }
}

// MARK: - Medium Widget (both providers)

struct AIUMMediumWidget: Widget {
    static let kind = "AIUMMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AIUMStaticWidgetProvider()) { entry in
            AIUMMediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Copilot & Codex")
        .description("Shows GitHub Copilot and Codex usage side by side.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
