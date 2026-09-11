import SwiftUI
import WidgetKit

struct CodexUsageRingsView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshots: [UsageSnapshot]

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let lineWidth = size * 0.075
            let ringSpacing = size * 0.12

            ZStack {
                ForEach(CodexUsageLimit.allCases) { limit in
                    let snapshot = limit.snapshot(in: snapshots)
                    let diameter = size - lineWidth - CGFloat(limit.rawValue) * ringSpacing * 2

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

                if snapshots.contains(where: { $0.provider == .codex && $0.source == "demo" }) {
                    Text(verbatim: "D")
                        .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                } else {
                    ProviderIconView(provider: .codex, size: size * 0.24)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Provider.codex.displayName)
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let summary = CodexUsageLimit.allCases.map { limit in
            let usage = limit.snapshot(in: snapshots).map { snapshot in
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
            return "\(limit.accessibilityLabel): \(usage)"
        }.joined(separator: ", ")

        if snapshots.contains(where: { $0.provider == .codex && $0.source == "demo" }) {
            return String.localizedStringWithFormat(String(localized: "Demo: %@"), summary)
        }
        return summary
    }
}

struct CodexUsageRingsDetailView: View {
    let snapshots: [UsageSnapshot]
    let ringSize: CGFloat
    var showsResetTimes = false

    var body: some View {
        HStack(spacing: 8) {
            CodexUsageRingsView(snapshots: snapshots)
                .frame(width: ringSize, height: ringSize)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(CodexUsageLimit.allCases) { limit in
                    let snapshot = limit.snapshot(in: snapshots)

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

private extension CodexUsageLimit {
    var color: Color {
        switch self {
        case .fiveHour: .blue
        case .weekly: .purple
        case .lunaReserve: .teal
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveHour: String(localized: "5h")
        case .weekly: String(localized: "1w")
        case .lunaReserve: "Luna"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .fiveHour: String(localized: "Outer ring: 5 hours")
        case .weekly: String(localized: "Middle ring: 1 week")
        case .lunaReserve: String(localized: "Inner ring: Luna Reserve")
        }
    }
}
