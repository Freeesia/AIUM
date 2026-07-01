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
                        Text("\(Int(snapshot.usedPercent))%")
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
                        Text("—")
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

    private var planLabel: String {
        switch snapshot.planKind {
        case .aiCredits: return "AI Credits"
        case .premiumRequests: return "Premium Requests"
        case .codexFree: return "Free Plan"
        case .codexPro: return "Pro Plan"
        case .unknown: return snapshot.windowKind.rawValue.capitalized
        }
    }

    private func formatCount(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(Int(value))
    }

    @ViewBuilder
    private func usageStat(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
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
                windowKind: .hourly,
                used: 45,
                limit: 50,
                resetAt: Calendar.current.date(byAdding: .hour, value: 1, to: Date()),
                unit: "requests",
                source: "Codex Private API"
            ))
            UsageCardView(snapshot: UsageSnapshot.error(provider: .codex, message: "Connection failed"))
            NotSignedInCardView(provider: .githubCopilot)
        }
        .padding()
    }
}
