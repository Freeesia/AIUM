import Foundation

/// Keeps an uncertain reset attempt associated with its account, including
/// after the sheet closes or the app restarts. Retrying must reuse its ID.
@MainActor
final class CodexResetRequestStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func requestID(for accountId: String) -> UUID {
        let key = key(for: accountId)
        if let saved = defaults.string(forKey: key), let id = UUID(uuidString: saved) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }

    func clear(for accountId: String) {
        defaults.removeObject(forKey: key(for: accountId))
    }

    private func key(for accountId: String) -> String {
        "codex_pending_usage_reset.\(accountId)"
    }
}
