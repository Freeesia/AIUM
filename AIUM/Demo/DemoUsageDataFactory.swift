import Foundation

/// Creates demo usage snapshots for App Review and testing purposes.
enum DemoUsageDataFactory {
    /// Returns demo snapshots for both GitHub Copilot and OpenAI Codex.
    /// All snapshots use `source = "demo"` and time values based on `now`.
    static func snapshots(for provider: Provider, now: Date = Date()) -> [UsageSnapshot] {
        switch provider {
        case .githubCopilot:
            return githubSnapshots(now: now)
        case .codex:
            return codexSnapshots(now: now)
        }
    }

    // MARK: - GitHub Copilot

    private static func githubSnapshots(now: Date) -> [UsageSnapshot] {
        let monthlyReset = Calendar.current.date(
            byAdding: .month, value: 1,
            to: Calendar.current.startOfMonth(for: now)
        ) ?? now.addingTimeInterval(30 * 24 * 3600)

        return [
            UsageSnapshot(
                provider: .githubCopilot,
                accountId: "demo-github",
                displayName: "Demo GitHub Account",
                planKind: .aiCredits,
                windowKind: .monthly,
                used: 620,
                limit: 1000,
                resetAt: monthlyReset,
                unit: "AI credits",
                source: "demo",
                fetchedAt: now
            ),
            UsageSnapshot(
                provider: .githubCopilot,
                accountId: "demo-github",
                displayName: "Demo GitHub Account",
                planKind: .premiumRequests,
                windowKind: .monthly,
                used: 184,
                limit: 300,
                resetAt: monthlyReset,
                unit: "premium requests",
                source: "demo",
                fetchedAt: now
            ),
        ]
    }

    // MARK: - OpenAI Codex

    private static func codexSnapshots(now: Date) -> [UsageSnapshot] {
        let hourlyReset = now.addingTimeInterval(3600)
        let dailyReset = Calendar.current.startOfDay(
            for: now.addingTimeInterval(24 * 3600)
        )

        return [
            UsageSnapshot(
                provider: .codex,
                accountId: "demo-codex",
                displayName: "demo@example.com",
                planKind: .codexPro,
                windowKind: .hourly,
                used: 37,
                limit: 50,
                resetAt: hourlyReset,
                unit: "requests",
                source: "demo",
                fetchedAt: now,
                windowDurationMins: 60
            ),
            UsageSnapshot(
                provider: .codex,
                accountId: "demo-codex",
                displayName: "demo@example.com",
                planKind: .codexPro,
                windowKind: .daily,
                used: 210,
                limit: 300,
                resetAt: dailyReset,
                unit: "requests",
                source: "demo",
                fetchedAt: now,
                windowDurationMins: 24 * 60
            ),
        ]
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
