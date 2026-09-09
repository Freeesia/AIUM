import Foundation

struct CodexUsageResetConfirmation: Identifiable, Sendable {
    let id = UUID()
    let accountId: String
    let accountDisplayName: String?
    let remainingCount: Int
}

enum CodexUsageResetOutcome: String, Decodable, Sendable {
    case reset
    case alreadyRedeemed = "already_redeemed"
    case noCredit = "no_credit"
    case nothingToReset = "nothing_to_reset"

    var message: String {
        switch self {
        case .reset:
            return String(localized: "Codex usage has been reset.")
        case .alreadyRedeemed:
            return String(localized: "This reset request was already completed. No additional reset was used.")
        case .noCredit:
            return String(localized: "No reset credits are available.")
        case .nothingToReset:
            return String(localized: "Your usage does not need a reset right now.")
        }
    }
}

enum CodexUsageResetError: LocalizedError {
    case accountChanged

    var errorDescription: String? {
        String(localized: "The connected Codex account changed. Close this sheet and refresh before trying again.")
    }
}
