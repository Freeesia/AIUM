import AppIntents
import SwiftUI
import WidgetKit

// SystemShortcut is available only on iOS 27. Gate the complete configuration
// type, including the storage synthesized by @Parameter, at that version.
@available(iOS 27.0, *)
struct AIUMShortcutWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage Provider & Action"
    static var description = IntentDescription(
        "Choose the usage provider and the app or shortcut to run when tapped."
    )

    @Parameter(title: "Provider", default: .githubCopilot)
    var provider: AIUMWidgetProviderOption

    @Parameter(title: "Action")
    var shortcut: SystemShortcut?
}

@available(iOS 27.0, *)
struct AIUMShortcutWidgetEntry: TimelineEntry {
    let usage: AIUMWidgetEntry
    let shortcut: SystemShortcut?

    var date: Date { usage.date }
}

@available(iOS 27.0, *)
struct AIUMShortcutWidgetProvider: AppIntentTimelineProvider {
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> AIUMShortcutWidgetEntry {
        AIUMShortcutWidgetEntry(
            usage: AIUMLockScreenWidgetProvider.placeholderEntry,
            shortcut: nil
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
        AIUMShortcutWidgetEntry(
            usage: AIUMWidgetEntry(
                date: Date(),
                snapshots: UsageStore.loadSnapshotsFromSharedContainer(),
                provider: configuration.provider.provider
            ),
            shortcut: configuration.shortcut
        )
    }
}

@available(iOS 27.0, *)
struct AIUMShortcutWidgetView: View {
    let entry: AIUMShortcutWidgetEntry

    @ViewBuilder
    var body: some View {
        if let shortcut = entry.shortcut {
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

@available(iOS 27.0, *)
struct AIUMShortcutLockScreenWidget: Widget {
    static let kind = AIUMLockScreenWidget.kind

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
