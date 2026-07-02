import XCTest
@testable import AIUM

final class DemoModeStoreTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "DemoModeStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    func testIsEnabledDefaultsToFalse() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DemoModeStore(defaults: defaults)
        XCTAssertFalse(store.isEnabled)
    }

    func testIsEnabledReturnsTrueWhenKeyIsSet() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: DemoModeStore.enabledKey)
        let store = DemoModeStore(defaults: defaults)
        XCTAssertTrue(store.isEnabled)
    }

    func testIsEnabledReturnsFalseWhenKeyIsExplicitlyFalse() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: DemoModeStore.enabledKey)
        let store = DemoModeStore(defaults: defaults)
        XCTAssertFalse(store.isEnabled)
    }

    func testEnabledKeyValue() {
        XCTAssertEqual(DemoModeStore.enabledKey, "demo_mode_enabled")
    }
}
