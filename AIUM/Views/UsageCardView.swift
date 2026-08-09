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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        VStack(alignment: .leading, spacing: 10) {
            if let error = snapshot.errorMessage {
                cardHeader(relativeTo: referenceDate)
                errorBanner(error)
            } else if dynamicTypeSize.isAccessibilitySize {
                accessibilityUsageContent(relativeTo: referenceDate)
            } else {
                compactUsageContent(relativeTo: referenceDate)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Layout

    private func compactUsageContent(relativeTo referenceDate: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            progressRing(size: 64, lineWidth: 7)

            VStack(alignment: .leading, spacing: 2) {
                titleRow(relativeTo: referenceDate)

                if let displayName = snapshot.displayName {
                    Text(displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(planLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                resetInfo(relativeTo: referenceDate)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 3) {
                usageStats
                updatedInfo(relativeTo: referenceDate)
                    .padding(.top, 6)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func accessibilityUsageContent(relativeTo referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(relativeTo: referenceDate)

            HStack(alignment: .center, spacing: 16) {
                progressRing(size: 72, lineWidth: 8)
                usageStats
            }

            HStack {
                resetInfo(relativeTo: referenceDate)
                Spacer()
                updatedInfo(relativeTo: referenceDate)
            }
        }
    }

    private func cardHeader(relativeTo referenceDate: Date) -> some View {
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
            staleIndicator(relativeTo: referenceDate)
        }
    }

    private func titleRow(relativeTo referenceDate: Date) -> some View {
        HStack(spacing: 4) {
            Text(snapshot.provider.displayName)
                .font(.headline)
                .lineLimit(1)
            staleIndicator(relativeTo: referenceDate)
        }
    }

    private func progressRing(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(snapshot.usedPercent / 100))
                .stroke(progressColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(Int(snapshot.usedPercent))%")
                .font(.system(.body, design: .rounded, weight: .bold))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func staleIndicator(relativeTo referenceDate: Date) -> some View {
        if referenceDate.timeIntervalSince(snapshot.fetchedAt) > 3600 {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Data may be stale")
        }
    }

    private var usageStats: some View {
        VStack(alignment: .leading, spacing: 3) {
            usageStat(label: "Used", value: formatCount(snapshot.used), color: progressColor)
            if snapshot.limit > 0 {
                usageStat(
                    label: "Remaining",
                    value: formatCount(max(0, snapshot.limit - snapshot.used)),
                    color: .secondary
                )
                usageStat(label: "Limit", value: formatCount(snapshot.limit), color: .secondary)
            }
        }
    }

    private func resetInfo(relativeTo referenceDate: Date) -> some View {
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
        .lineLimit(1)
    }

    private func updatedInfo(relativeTo referenceDate: Date) -> some View {
        Label {
            Text("Updated \(UsageRelativeTimeText.fetched(at: snapshot.fetchedAt, relativeTo: referenceDate))")
        } icon: {
            Image(systemName: "clock")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
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
            UsageCardView(snapshot: UsageSnapshot(
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
            ))
            UsageCardView(snapshot: UsageSnapshot.error(provider: .codex, message: "Connection failed"))
            NotSignedInCardView(provider: .githubCopilot)
        }
        .padding()
    }
}
