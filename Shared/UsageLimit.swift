import Foundation

/// Rate-limit windows drawn as concentric rings. The order returned by
/// `limits(for:)` is the stable outer-to-inner ring order, independent of
/// usage and response ordering.
enum UsageLimit: Int, CaseIterable, Identifiable {
    case fiveHour
    case weekly
    case lunaReserve

    var id: Self { self }

    /// Limits shown as rings for a provider. Empty when the provider reports a
    /// single quota instead of rate-limit windows.
    static func limits(for provider: Provider) -> [UsageLimit] {
        switch provider {
        case .githubCopilot: []
        case .codex: [.fiveHour, .weekly, .lunaReserve]
        case .claudeCode: [.fiveHour, .weekly]
        }
    }

    func snapshot(in snapshots: [UsageSnapshot], for provider: Provider) -> UsageSnapshot? {
        snapshots.filter { snapshot in
            guard snapshot.provider == provider,
                  snapshot.errorMessage == nil,
                  snapshot.limit > 0,
                  snapshot.usedPercent.isFinite else { return false }

            switch self {
            case .fiveHour:
                return snapshot.planKind != .codexLunaReserve
                    && snapshot.windowDurationMins == 5 * 60
            case .weekly:
                return snapshot.planKind != .codexLunaReserve
                    && snapshot.windowDurationMins == 7 * 24 * 60
            case .lunaReserve:
                return snapshot.planKind == .codexLunaReserve
            }
        }
        .max { $0.fetchedAt < $1.fetchedAt }
    }
}

extension Provider {
    /// Whether usage is shown as concentric rings, one per rate-limit window.
    var usesUsageRings: Bool {
        !UsageLimit.limits(for: self).isEmpty
    }
}
