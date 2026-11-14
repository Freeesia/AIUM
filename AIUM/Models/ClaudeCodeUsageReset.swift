import Foundation

struct ClaudeCodeUsageResetConfirmation: Identifiable, Sendable {
    let id = UUID()
    let accountId: String
    let organizationId: String
    let accountDisplayName: String?
    let remainingCount: Int
}

/// Limit resets the Claude account can use (the `cedar_ember` block of the
/// private usage response).
struct ClaudeCodeResetStatus: Sendable, Equatable {
    let eligible: Bool
    let grants: [ClaudeCodeResetGrant]
    /// The grant the backend expects the next reset to use, when it names one.
    let nextGrantId: String?
    let cooldownUntil: Date?

    /// Resets left in grants that are neither paused nor expired.
    func availableCount(now: Date = Date()) -> Int {
        guard eligible else { return 0 }
        return activeGrants(now: now).reduce(0) { $0 + $1.resetsLeft }
    }

    /// Grants that still hold resets, earliest expiration first.
    func activeGrants(now: Date = Date()) -> [ClaudeCodeResetGrant] {
        grants
            .filter { $0.resetsLeft > 0 && !$0.paused && ($0.endsAt.map { $0 > now } ?? true) }
            .sorted {
                let lhs = $0.endsAt ?? .distantFuture
                let rhs = $1.endsAt ?? .distantFuture
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
    }

    /// The grant a reset will use: the backend's next grant when it can be
    /// used now, otherwise the usable grant that expires first.
    func grantToUse(now: Date = Date()) -> ClaudeCodeResetGrant? {
        guard eligible else { return nil }
        let usable = activeGrants(now: now).filter(\.usableNow)
        if let nextGrantId, let next = usable.first(where: { $0.id == nextGrantId }) {
            return next
        }
        return usable.first
    }
}

struct ClaudeCodeResetGrant: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable {
        case session
        case weekly
        case full
    }

    let id: String
    let label: String?
    let resetsLeft: Int
    let endsAt: Date?
    let paused: Bool
    let usableNow: Bool
    let useRequiresLimit: Bool
    let kind: Kind?

    var displayTitle: String {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return String(localized: "Usage reset") }
        return label
    }

    var kindDescription: String? {
        switch kind {
        case .session: return String(localized: "Resets the 5-hour limit")
        case .weekly: return String(localized: "Resets the weekly limit")
        case .full: return String(localized: "Resets all usage limits")
        case nil: return nil
        }
    }
}

enum ClaudeCodeUsageResetOutcome: String, Sendable {
    case reset
    case alreadyUsed = "already_used"
    case notLimited = "not_limited"
    case cooldown
    case ineligible

    var message: String {
        switch self {
        case .reset:
            return String(localized: "Claude Code usage has been reset.")
        case .alreadyUsed:
            return String(localized: "This reset request was already completed. No additional reset was used.")
        case .notLimited:
            return String(localized: "Your usage does not need a reset right now.")
        case .cooldown:
            return String(localized: "A reset was used recently. Try again later.")
        case .ineligible:
            return String(localized: "This account can't use a usage reset right now.")
        }
    }
}

enum ClaudeCodeUsageResetError: LocalizedError {
    case accountChanged
    case noUsableReset
    /// The backend could not confirm whether the reset was applied.
    case unconfirmed

    var errorDescription: String? {
        switch self {
        case .accountChanged:
            return String(localized: "The connected Claude account changed. Close this sheet and refresh before trying again.")
        case .noUsableReset:
            return String(localized: "No reset can be used right now.")
        case .unconfirmed:
            return String(localized: "Could not confirm the reset. Retry to check the same request without using an additional reset.")
        }
    }
}
