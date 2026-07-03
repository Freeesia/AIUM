import SwiftUI

enum UsageRelativeTimeText {
    static func reset(at resetAt: Date, relativeTo referenceDate: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let interval = resetAt.timeIntervalSince(referenceDate)
        let roundedMinutes = interval >= 0
            ? ceil(interval / 60)
            : floor(interval / 60)
        let roundedDate = referenceDate.addingTimeInterval(roundedMinutes * 60)
        return format(roundedDate, relativeTo: referenceDate, locale: locale)
    }

    static func fetched(at fetchedAt: Date, relativeTo referenceDate: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let elapsedMinutes = max(0, floor(referenceDate.timeIntervalSince(fetchedAt) / 60))
        let roundedDate = referenceDate.addingTimeInterval(-elapsedMinutes * 60)
        return format(roundedDate, relativeTo: referenceDate, locale: locale)
    }

    private static func format(_ date: Date, relativeTo referenceDate: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = date == referenceDate ? .named : .numeric
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

struct UsageCardView: View {
    let snapshot: UsageSnapshot

    private var progressColor: Color {
        let pct = snapshot.usedPercent
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        return .blue
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            cardContent(relativeTo: context.date)
        }
    }

    @ViewBuilder
    private func cardContent(relativeTo referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.provider.displayName)
                        .font(.headline)
                    if let displayName = snapshot.displayName {
                        Text(displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(planLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if referenceDate.timeIntervalSince(snapshot.fetchedAt) > 3600 {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .help("Data may be stale")
                }
            }

            // Error state
            if let error = snapshot.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(8)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else {
                // Progress ring + numbers
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.usedPercent / 100))
                            .stroke(progressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(verbatim: "\(Int(snapshot.usedPercent))%")
                            .font(.system(.body, design: .rounded, weight: .bold))
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        usageStat(label: "Used", value: formatCount(snapshot.used), color: progressColor)
                        if snapshot.limit > 0 {
                            usageStat(label: "Remaining", value: formatCount(max(0, snapshot.limit - snapshot.used)), color: .secondary)
                            usageStat(label: "Limit", value: formatCount(snapshot.limit), color: .secondary)
                        }
                    }
                }
            }

            // Footer
            HStack {
                Label {
                    if let resetAt = snapshot.resetAt {
                        Text(UsageRelativeTimeText.reset(at: resetAt, relativeTo: referenceDate))
                    } else {
                        Text(verbatim: "—")
                    }
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Spacer()
                Text("Updated \(UsageRelativeTimeText.fetched(at: snapshot.fetchedAt, relativeTo: referenceDate))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private var planLabel: LocalizedStringKey {
        switch snapshot.planKind {
        case .aiCredits: return "AI Credits"
        case .premiumRequests: return "Premium Requests"
        case .codexFree: return "Free Plan"
        case .codexPro: return "Pro Plan"
        case .unknown:
            switch snapshot.windowKind {
            case .monthly: return "Monthly"
            case .daily: return "Daily"
            case .hourly: return "Hourly"
            case .custom: return "Custom"
            }
        }
    }

    private func formatCount(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(Int(value))
    }

    @ViewBuilder
    private func usageStat(label: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            (Text(label) + Text(verbatim: ":"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Codex usage card

struct CodexUsageCardView: View {
    let snapshots: [UsageSnapshot]

    private let fiveHourWindowMinutes = 5 * 60
    private let weeklyWindowMinutes = 7 * 24 * 60

    private var fiveHourSnapshot: UsageSnapshot? {
        snapshots.first { $0.windowDurationMins == fiveHourWindowMinutes }
    }

    private var weeklySnapshot: UsageSnapshot? {
        snapshots.first { $0.windowDurationMins == weeklyWindowMinutes }
    }

    private var accountSnapshot: UsageSnapshot? {
        snapshots.first { $0.errorMessage == nil } ?? snapshots.first
    }

    private var errorMessages: [String] {
        Array(Set(snapshots.compactMap(\.errorMessage))).sorted()
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            cardContent(relativeTo: context.date)
        }
    }

    @ViewBuilder
    private func cardContent(relativeTo referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Provider.codex.displayName)
                        .font(.headline)
                    if let displayName = accountSnapshot?.displayName {
                        Text(displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if snapshots.contains(where: { referenceDate.timeIntervalSince($0.fetchedAt) > 3600 }) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .help("Data may be stale")
                }
            }

            ForEach(errorMessages, id: \.self) { message in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(alignment: .top, spacing: 12) {
                CodexUsageRingView(title: "5 hours", snapshot: fiveHourSnapshot, referenceDate: referenceDate)
                    .frame(maxWidth: .infinity)

                Divider()

                CodexUsageRingView(title: "1 week", snapshot: weeklySnapshot, referenceDate: referenceDate)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Spacer()
                if let fetchedAt = snapshots.map(\.fetchedAt).max() {
                    Text("Updated \(UsageRelativeTimeText.fetched(at: fetchedAt, relativeTo: referenceDate))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CodexUsageRingView: View {
    let title: LocalizedStringKey
    let snapshot: UsageSnapshot?
    let referenceDate: Date

    private var progressColor: Color {
        guard let snapshot else { return .secondary }
        if snapshot.usedPercent >= 90 { return .red }
        if snapshot.usedPercent >= 70 { return .orange }
        return .blue
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline.bold())

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)

                if let snapshot {
                    Circle()
                        .trim(from: 0, to: CGFloat(snapshot.usedPercent / 100))
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "\(Int(snapshot.usedPercent))%")
                        .font(.system(.body, design: .rounded, weight: .bold))
                } else {
                    Text(verbatim: "—")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 76)

            if let snapshot {
                Text(verbatim: usageText(for: snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Label(resetText(for: snapshot, relativeTo: referenceDate), systemImage: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func usageText(for snapshot: UsageSnapshot) -> String {
        guard snapshot.limit > 0 else { return "\(formatCount(snapshot.used)) used" }
        return "\(formatCount(snapshot.used)) / \(formatCount(snapshot.limit))"
    }

    private func resetText(for snapshot: UsageSnapshot, relativeTo referenceDate: Date) -> String {
        guard let resetAt = snapshot.resetAt else { return "—" }
        return UsageRelativeTimeText.reset(at: resetAt, relativeTo: referenceDate)
    }

    private func formatCount(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(Int(value))
    }
}

// MARK: - Not-signed-in card

struct NotSignedInCardView: View {
    let provider: Provider

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(provider.displayName)
                .font(.headline)
            Text("Not signed in")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Open Settings to sign in")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Preview

#Preview("Usage Card") {
    ScrollView {
        VStack(spacing: 12) {
            UsageCardView(snapshot: UsageSnapshot(
                provider: .githubCopilot,
                displayName: "octocat",
                planKind: .aiCredits,
                windowKind: .monthly,
                used: 750,
                limit: 1000,
                resetAt: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
                unit: "AI credits",
                source: "GitHub Billing API"
            ))
            CodexUsageCardView(snapshots: [
                UsageSnapshot(
                    provider: .codex,
                    displayName: "user@example.com",
                    planKind: .codexPro,
                    windowKind: .custom,
                    used: 45,
                    limit: 100,
                    resetAt: Calendar.current.date(byAdding: .hour, value: 1, to: Date()),
                    unit: "percent",
                    source: "Codex Private API",
                    windowDurationMins: 300
                ),
                UsageSnapshot(
                    provider: .codex,
                    displayName: "user@example.com",
                    planKind: .codexPro,
                    windowKind: .custom,
                    used: 22,
                    limit: 100,
                    resetAt: Calendar.current.date(byAdding: .day, value: 4, to: Date()),
                    unit: "percent",
                    source: "Codex Private API",
                    windowDurationMins: 10_080
                ),
            ])
            UsageCardView(snapshot: UsageSnapshot.error(provider: .codex, message: "Connection failed"))
            NotSignedInCardView(provider: .githubCopilot)
        }
        .padding()
    }
}
