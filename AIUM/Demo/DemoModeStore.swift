import Foundation

/// Reads the demo mode flag from the app's preferences.
final class DemoModeStore {
    static let enabledKey = "demo_mode_enabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }
}
