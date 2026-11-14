import Foundation

/// Stable outer-to-inner order, independent of usage and response ordering.
enum CodexUsageLimit: Int, CaseIterable, Identifiable {
    case fiveHour
    case weekly

    var id: Self { self }

    func snapshot(in snapshots: [UsageSnapshot]) -> UsageSnapshot? {
        snapshots.filter { snapshot in
            guard snapshot.provider == .codex,
                  snapshot.errorMessage == nil,
                  snapshot.limit > 0,
                  snapshot.usedPercent.isFinite else { return false }

            switch self {
            case .fiveHour:
                return snapshot.windowDurationMins == 5 * 60
            case .weekly:
                return snapshot.windowDurationMins == 7 * 24 * 60
            }
        }
        .max { $0.fetchedAt < $1.fetchedAt }
    }
}
