import SwiftUI
import WidgetKit

/// Concentric rings, one per rate-limit window of a provider (Codex, Claude Code).
struct UsageRingsView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let provider: Provider
    let snapshots: [UsageSnapshot]

    private var limits: [UsageLimit] { UsageLimit.limits(for: provider) }

    private var isDemoData: Bool {
        snapshots.contains { $0.provider == provider && $0.source == "demo" }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let lineWidth = size * 0.075
            let ringSpacing = size * 0.12

            ZStack {
                ForEach(Array(limits.enumerated()), id: \.element) { index, limit in
                    let snapshot = limit.snapshot(in: snapshots, for: provider)
                    let diameter = size - lineWidth - CGFloat(index) * ringSpacing * 2

                    ZStack {
                        Circle()
                            .stroke(
                                Color.secondary.opacity(0.2),
                                style: StrokeStyle(
                                    lineWidth: lineWidth,
                                    dash: snapshot == nil ? [lineWidth, lineWidth] : []
                                )
                            )

                        if let snapshot, snapshot.usedPercent > 0 {
                            Circle()
                                .trim(from: 0, to: CGFloat(min(max(snapshot.usedPercent / 100, 0), 1)))
                                .stroke(
                                    renderingMode == .fullColor ? limit.color : .primary,
                                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .widgetAccentable()
                        }
                    }
                    .frame(width: diameter, height: diameter)
                }

                if isDemoData {
                    Text(verbatim: "D")
                        .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                } else {
                    ProviderIconView(provider: provider, size: size * 0.24)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.displayName)
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let summary = limits.enumerated().map { index, limit in
            let usage = limit.snapshot(in: snapshots, for: provider).map { snapshot in
                let percent = String.localizedStringWithFormat(
                    String(localized: "%lld percent used"),
                    Int64(max(0, snapshot.usedPercent))
                )
                if let resetAt = snapshot.resetAt {
                    let reset = String.localizedStringWithFormat(
                        String(localized: "Resets at %@"),
                        resetAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    return "\(percent), \(reset)"
                }
                return percent
            } ?? String(localized: "Usage unavailable")
            return "\(limit.accessibilityLabel(index: index)): \(usage)"
        }.joined(separator: ", ")

        if isDemoData {
            return String.localizedStringWithFormat(String(localized: "Demo: %@"), summary)
        }
        return summary
    }
}

struct UsageRingsDetailView: View {
    let provider: Provider
    let snapshots: [UsageSnapshot]
    let ringSize: CGFloat
    var showsResetTimes = false

    var body: some View {
        HStack(spacing: 8) {
            UsageRingsView(provider: provider, snapshots: snapshots)
                .frame(width: ringSize, height: ringSize)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(UsageLimit.limits(for: provider)) { limit in
                    let snapshot = limit.snapshot(in: snapshots, for: provider)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(limit.color)
                                .frame(width: 4, height: 4)
                                .widgetAccentable()
                            Text(limit.shortLabel)
                            Spacer(minLength: 0)
                            Text(verbatim: snapshot.map { "\(Int(max(0, $0.usedPercent)))%" } ?? "—")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .font(.system(size: 10))

                        if showsResetTimes, let resetAt = snapshot?.resetAt {
                            TimelineView(.everyMinute) { context in
                                Label {
                                    Text(remainingTimeText(until: resetAt, from: context.date))
                                } icon: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

private extension UsageLimit {
    var color: Color {
        switch self {
        case .fiveHour: .blue
        case .weekly: .purple
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveHour: String(localized: "5h")
        case .weekly: String(localized: "1w")
        }
    }

    /// Describes the ring by its position (5 hours outside, 1 week inside).
    func accessibilityLabel(index: Int) -> String {
        switch (self, index == 0) {
        case (.fiveHour, true): return String(localized: "Outer ring: 5 hours")
        case (.fiveHour, false): return String(localized: "5h")
        case (.weekly, _): return String(localized: "Inner ring: 1 week")
        }
    }
}
