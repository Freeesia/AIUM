import WidgetKit
import SwiftUI

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
                if snapshot.isStale {
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
                        Text("\(Int(snapshot.usedPercent))%")
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

            if let resetAt = snapshot.resetAt {
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
        entry.snapshots.first { $0.provider == .githubCopilot }
    }
    private var codexSnapshot: UsageSnapshot? {
        entry.snapshots.first { $0.provider == .codex }
    }

    var body: some View {
        HStack(spacing: 0) {
            providerPane(
                provider: .githubCopilot,
                snapshot: githubSnapshot,
                icon: "person.crop.circle"
            )
            Divider()
            providerPane(
                provider: .codex,
                snapshot: codexSnapshot,
                icon: "cpu.fill"
            )
        }
        .padding(12)
    }

    @ViewBuilder
    private func providerPane(provider: Provider, snapshot: UsageSnapshot?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(provider.displayName, systemImage: icon)
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

                    Text("\(Int(snapshot.usedPercent))%")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(progressColor(for: snapshot.usedPercent))

                    ProgressView(value: snapshot.usedPercent / 100)
                        .tint(progressColor(for: snapshot.usedPercent))

                    Text("\(formatCount(snapshot.used)) / \(formatCount(snapshot.limit)) \(snapshot.unit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let resetAt = snapshot.resetAt {
                        resetInfo(resetAt: resetAt, style: .stacked)
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
            Gauge(value: snapshot.usedPercent / 100) {
                Image(systemName: "gauge.medium")
            } currentValueLabel: {
                Text("\(Int(snapshot.usedPercent))%")
                    .font(.system(size: 12, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Image(systemName: "person.crop.circle.badge.questionmark")
        }
    }
}

struct AIUMAccessoryRectangularView: View {
    var entry: AIUMWidgetEntry

    var body: some View {
        if let snapshot = entry.displaySnapshot {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.provider.displayName)
                    .font(.caption2.bold())
                    .lineLimit(1)
                Text("\(Int(snapshot.usedPercent))% used")
                    .font(.caption)
                    .fontWeight(.semibold)
                if let resetAt = snapshot.resetAt {
                    resetSummary(resetAt: resetAt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Not signed in")
                .font(.caption2)
        }
    }
}

// MARK: - Shared helper

private func progressColor(for percent: Double) -> Color {
    if percent >= 90 { return .red }
    if percent >= 70 { return .orange }
    return .blue
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
    "\(remainingTimeText(until: resetAt, from: referenceDate)) · \(resetTimeText(resetAt, relativeTo: referenceDate))"
}

private func remainingTimeText(until resetAt: Date, from referenceDate: Date) -> String {
    let seconds = resetAt.timeIntervalSince(referenceDate)
    guard seconds > 0 else { return "now" }

    let totalMinutes = max(1, Int(ceil(seconds / 60)))
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
        return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
    }
    if hours > 0 {
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
    return "\(minutes)m"
}

private func resetTimeText(_ resetAt: Date, relativeTo referenceDate: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = Calendar.current.isDate(resetAt, inSameDayAs: referenceDate) ? .none : .medium
    formatter.timeStyle = .short
    return formatter.string(from: resetAt)
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    AIUMSmallWidget()
} timeline: {
    AIUMWidgetEntry(
        date: Date(),
        snapshots: [
            UsageSnapshot(
                provider: .githubCopilot,
                displayName: "octocat",
                planKind: .aiCredits,
                windowKind: .monthly,
                used: 750,
                limit: 1000,
                resetAt: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
                unit: "AI credits",
                source: "preview"
            )
        ],
        provider: nil
    )
}

#Preview("Medium", as: .systemMedium) {
    AIUMMediumWidget()
} timeline: {
    AIUMWidgetEntry(
        date: Date(),
        snapshots: [
            UsageSnapshot(
                provider: .githubCopilot,
                displayName: "octocat",
                planKind: .aiCredits,
                windowKind: .monthly,
                used: 750,
                limit: 1000,
                resetAt: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
                unit: "AI credits",
                source: "preview"
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
                source: "preview"
            ),
        ],
        provider: nil
    )
}
