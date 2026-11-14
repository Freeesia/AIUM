import Foundation

/// Keeps an uncertain reset attempt associated with its account, including
/// after the sheet closes or the app restarts. Retrying must reuse its ID.
@MainActor
final class UsageResetRequestStore {
    static let codexKeyPrefix = "codex_pending_usage_reset"
    static let claudeCodeKeyPrefix = "claude_code_pending_usage_reset"

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    static func codex(defaults: UserDefaults = .standard) -> UsageResetRequestStore {
        UsageResetRequestStore(defaults: defaults, keyPrefix: codexKeyPrefix)
    }

    static func claudeCode(defaults: UserDefaults = .standard) -> UsageResetRequestStore {
        UsageResetRequestStore(defaults: defaults, keyPrefix: claudeCodeKeyPrefix)
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
        "\(keyPrefix).\(accountId)"
    }
}
