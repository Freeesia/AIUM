import WidgetKit
import SwiftUI

// MARK: - Configurable Widget View

struct AIUMConfigurableWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    var entry: AIUMWidgetEntry

    @ViewBuilder
    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            AIUMAccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AIUMAccessoryRectangularView(entry: entry)
        default:
            AIUMSmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget View

struct AIUMSmallWidgetView: View {
    var entry: AIUMWidgetEntry

    var body: some View {
        if let snapshot = entry.displaySnapshot {
            smallUsageView(snapshot: snapshot)
        } else {
            notSignedInView
        }
    }

    @ViewBuilder
    private func smallUsageView(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.provider.displayName)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if snapshot.source == "demo" {
                    Text(verbatim: "DEMO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                } else if snapshot.isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if let error = snapshot.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if snapshot.provider == .codex {
                CodexUsageRingsDetailView(
                    snapshots: entry.snapshots,
                    ringSize: 48,
                    showsResetTimes: true
                )
                .frame(maxWidth: .infinity)
            } else {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(snapshot.usedPercent / 100))
                        .stroke(progressColor(for: snapshot.usedPercent),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(verbatim: "\(Int(snapshot.usedPercent))%")
                            .font(.system(.callout, design: .rounded, weight: .bold))
                        Text("used")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 60, height: 60)
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            if snapshot.provider != .codex, let resetAt = snapshot.resetAt {
                resetInfo(resetAt: resetAt, style: .compact)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var notSignedInView: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Not signed in")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium Widget View

struct AIUMMediumWidgetView: View {
    var entry: AIUMWidgetEntry

    private var githubSnapshot: UsageSnapshot? {
        UsageSnapshot.displaySnapshot(from: entry.snapshots, for: .githubCopilot)
    }
    private var codexSnapshot: UsageSnapshot? {
        UsageSnapshot.displaySnapshot(from: entry.snapshots, for: .codex)
    }
    private var isDemoData: Bool {
        entry.snapshots.contains { $0.source == "demo" }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                providerPane(
                    provider: .githubCopilot,
                    snapshot: githubSnapshot
                )
                Divider()
                providerPane(
                    provider: .codex,
                    snapshot: codexSnapshot
                )
            }
            .padding(12)

            if isDemoData {
                Text(verbatim: "DEMO")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    .padding(6)
            }
        }
    }

    @ViewBuilder
    private func providerPane(provider: Provider, snapshot: UsageSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(provider.displayName)
            } icon: {
                ProviderIconView(provider: provider, size: 28)
            }
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let snapshot {
                if let error = snapshot.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Spacer(minLength: 0)

                    if provider == .codex {
                        CodexUsageRingsDetailView(
                            snapshots: entry.snapshots,
                            ringSize: 60,
                            showsResetTimes: true
                        )
                        Spacer(minLength: 0)
                    } else {
                        Text(verbatim: "\(Int(snapshot.usedPercent))%")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(progressColor(for: snapshot.usedPercent))

                        ProgressView(value: snapshot.usedPercent / 100)
                            .tint(progressColor(for: snapshot.usedPercent))

                        Text(verbatim: "\(formatCount(snapshot.used)) / \(formatCount(snapshot.limit)) \(snapshot.localizedUnit)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let resetAt = snapshot.resetAt {
                            resetInfo(resetAt: resetAt, style: .stacked)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text("Not signed in")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func formatCount(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1fk", value / 1000) : String(Int(value))
    }
}

// MARK: - Accessory Views

struct AIUMAccessoryCircularView: View {
    var entry: AIUMWidgetEntry

    var body: some View {
        if let snapshot = entry.displaySnapshot {
            if let errorMessage = snapshot.errorMessage {
                unavailableGauge(
                    systemImage: "exclamationmark.triangle.fill",
                    accessibilityValue: errorMessage
                )
            } else if snapshot.provider == .codex {
                CodexUsageRingsView(snapshots: entry.snapshots)
            } else if snapshot.source == "demo" {
                Gauge(value: snapshot.usedPercent / 100) {
                    ProviderIconView(provider: snapshot.provider, size: 20)
                } currentValueLabel: {
                    Text(verbatim: "D")
                        .font(.system(size: 12, weight: .bold))
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel(snapshot.provider.displayName)
                .accessibilityValue(
                    String.localizedStringWithFormat(
                        String(localized: "Demo: %lld percent used"),
                        Int64(snapshot.usedPercent)
                    )
                )
            } else {
                Gauge(value: snapshot.usedPercent / 100) {
                    ProviderIconView(provider: snapshot.provider, size: 20)
                } currentValueLabel: {
                    Text(verbatim: "\(Int(snapshot.usedPercent))%")
                        .font(.system(size: 12, weight: .bold))
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel(snapshot.provider.displayName)
                .accessibilityValue(
                    String.localizedStringWithFormat(
                        String(localized: "%lld percent used"),
                        Int64(snapshot.usedPercent)
                    )
                )
            }
        } else {
            unavailableGauge(
                systemImage: "person.crop.circle.badge.exclamationmark",
                accessibilityValue: String(localized: "Not signed in")
            )
        }
    }

    private func unavailableGauge(systemImage: String, accessibilityValue: String) -> some View {
        Gauge(value: 0) {
            ProviderIconView(provider: entry.provider, size: 20)
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text(providerAbbreviation(entry.provider))
                    .font(.system(size: 9, weight: .bold))
                Image(systemName: systemImage)
                    .font(.system(size: 9))
            }
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(entry.provider.displayName)
        .accessibilityValue(accessibilityValue)
    }
}

struct AIUMAccessoryRectangularView: View {
    var entry: AIUMWidgetEntry

    var body: some View {
        if let snapshot = entry.displaySnapshot {
            if snapshot.errorMessage != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.provider.displayName)
                        .font(.caption2.bold())
                    Label("Usage unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                }
            } else if snapshot.provider == .codex {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(snapshot.provider.displayName)
                            .font(.caption2.bold())
                        if snapshot.source == "demo" {
                            Text(verbatim: "DEMO")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .lineLimit(1)

                    CodexUsageRingsDetailView(snapshots: entry.snapshots, ringSize: 46)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.provider.displayName)
                        .font(.caption2.bold())
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "%lld%% used"),
                                Int64(snapshot.usedPercent)
                            )
                        )
                            .font(.caption)
                            .fontWeight(.semibold)
                        if snapshot.source == "demo" {
                            Text(verbatim: "DEMO")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    if let resetAt = snapshot.resetAt {
                        resetSummary(resetAt: resetAt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.provider.displayName)
                    .font(.caption2.bold())
                Label("Not signed in", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Shared helper

private func progressColor(for percent: Double) -> Color {
    if percent >= 90 { return .red }
    if percent >= 70 { return .orange }
    return .blue
}

private func providerAbbreviation(_ provider: Provider) -> String {
    switch provider {
    case .githubCopilot: "GH"
    case .codex: "CX"
    }
}

private enum ResetInfoStyle {
    case compact
    case stacked
}

@ViewBuilder
private func resetInfo(resetAt: Date, style: ResetInfoStyle) -> some View {
    TimelineView(.everyMinute) { context in
        HStack(alignment: style == .compact ? .center : .top, spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.caption2)
                .foregroundStyle(.secondary)

            switch style {
            case .compact:
                Text(resetSummaryText(resetAt: resetAt, referenceDate: context.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .stacked:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Resets in \(remainingTimeText(until: resetAt, from: context.date))")
                    Text("At \(resetTimeText(resetAt, relativeTo: context.date))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }
}

@ViewBuilder
private func resetSummary(resetAt: Date) -> some View {
    TimelineView(.everyMinute) { context in
        Text(resetSummaryText(resetAt: resetAt, referenceDate: context.date))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private func resetSummaryText(resetAt: Date, referenceDate: Date) -> String {
    String.localizedStringWithFormat(
        String(localized: "%@ · %@"),
        remainingTimeText(until: resetAt, from: referenceDate),
        resetTimeText(resetAt, relativeTo: referenceDate)
    )
}

func remainingTimeText(until resetAt: Date, from referenceDate: Date) -> String {
    let seconds = resetAt.timeIntervalSince(referenceDate)
    guard seconds > 0 else { return String(localized: "now") }

    let totalMinutes = max(1, Int(ceil(seconds / 60)))
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
        if hours > 0 {
            return String.localizedStringWithFormat(
                String(localized: "%lldd %lldh"),
                Int64(days),
                Int64(hours)
            )
        }
        return String.localizedStringWithFormat(String(localized: "%lldd"), Int64(days))
    }
    if hours > 0 {
        if minutes > 0 {
            return String.localizedStringWithFormat(
                String(localized: "%lldh %lldm"),
                Int64(hours),
                Int64(minutes)
            )
        }
        return String.localizedStringWithFormat(String(localized: "%lldh"), Int64(hours))
    }
    return String.localizedStringWithFormat(String(localized: "%lldm"), Int64(minutes))
}

private func resetTimeText(_ resetAt: Date, relativeTo referenceDate: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = Calendar.current.isDate(resetAt, inSameDayAs: referenceDate) ? .none : .medium
    formatter.timeStyle = .short
    return formatter.string(from: resetAt)
}

// MARK: - Previews

private enum WidgetPreviewData {
    static let date = Date(timeIntervalSince1970: 1_789_171_200)
    static let snapshots = [
        UsageSnapshot(
            provider: .githubCopilot, displayName: "octocat", planKind: .aiCredits,
            windowKind: .monthly, used: 750, limit: 1000,
            resetAt: date.addingTimeInterval(10 * 24 * 3600),
            unit: "AI credits", source: "preview", fetchedAt: date
        ),
        codexSnapshot(plan: .codexPro, used: 72, minutes: 5 * 60, resetHours: 2),
        codexSnapshot(plan: .codexPro, used: 42, minutes: 7 * 24 * 60, resetHours: 96),
        codexSnapshot(plan: .codexLunaReserve, used: 8, minutes: 7 * 24 * 60, resetHours: 168),
    ]

    static func entry(provider: Provider, snapshots: [UsageSnapshot] = snapshots) -> AIUMWidgetEntry {
        AIUMWidgetEntry(date: date, snapshots: snapshots, provider: provider)
    }

    private static func codexSnapshot(
        plan: PlanKind, used: Double, minutes: Int, resetHours: Double
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex, planKind: plan, windowKind: .custom, used: used, limit: 100,
            resetAt: date.addingTimeInterval(resetHours * 3600), unit: "percent",
            source: "preview", fetchedAt: date, windowDurationMins: minutes
        )
    }
}

#Preview("Small", as: .systemSmall) {
    AIUMSmallWidget()
} timeline: {
    WidgetPreviewData.entry(provider: .githubCopilot)
}

#Preview("Codex Circular", as: .accessoryCircular) {
    AIUMLockScreenWidget()
} timeline: {
    WidgetPreviewData.entry(provider: .codex)
}

#Preview("Codex Rectangular", as: .accessoryRectangular) {
    AIUMLockScreenWidget()
} timeline: {
    WidgetPreviewData.entry(provider: .codex)
}

#Preview("Codex Missing Reserve", as: .accessoryCircular) {
    AIUMLockScreenWidget()
} timeline: {
    WidgetPreviewData.entry(
        provider: .codex,
        snapshots: WidgetPreviewData.snapshots.filter { $0.planKind != .codexLunaReserve }
    )
}

#Preview("Codex Error", as: .accessoryCircular) {
    AIUMLockScreenWidget()
} timeline: {
    WidgetPreviewData.entry(
        provider: .codex,
        snapshots: [.error(provider: .codex, message: "Connection failed")]
    )
}

#Preview("Copilot Rectangular", as: .accessoryRectangular) {
    AIUMLockScreenWidget()
} timeline: {
    WidgetPreviewData.entry(provider: .githubCopilot)
}

#Preview("Medium", as: .systemMedium) {
    AIUMMediumWidget()
} timeline: {
    WidgetPreviewData.entry(provider: .githubCopilot)
}
