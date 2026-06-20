import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct AIUMWidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [UsageSnapshot]
    let provider: Provider?
    var displaySnapshot: UsageSnapshot? {
        guard let provider else {
            return snapshots.first
        }
        return snapshots.first { $0.provider == provider }
    }
}

// MARK: - Timeline Provider

struct AIUMWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> AIUMWidgetEntry {
        AIUMWidgetEntry(
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
            provider: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AIUMWidgetEntry) -> Void) {
        let snapshots = UsageStore.loadSnapshotsFromSharedContainer()
        let entry = AIUMWidgetEntry(date: Date(), snapshots: snapshots, provider: nil)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIUMWidgetEntry>) -> Void) {
        let snapshots = UsageStore.loadSnapshotsFromSharedContainer()
        let entry = AIUMWidgetEntry(date: Date(), snapshots: snapshots, provider: nil)

        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Small Widget (single provider)

struct AIUMSmallWidget: Widget {
    static let kind = "AIUMSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AIUMWidgetProvider()) { entry in
            AIUMSmallWidgetView(entry: entry)
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
        StaticConfiguration(kind: Self.kind, provider: AIUMWidgetProvider()) { entry in
            AIUMMediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AIUM — Copilot & Codex")
        .description("Shows GitHub Copilot and Codex usage side by side.")
        .supportedFamilies([.systemMedium])
    }
}
