import Foundation

enum UsageRefreshSetting: Int, CaseIterable, Identifiable, Sendable {
    case automatic = -1
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case sixHours = 360

    static let storageKey = "refresh_interval_minutes"
    static let defaultSetting: UsageRefreshSetting = .oneHour

    init(storedValue: Int?) {
        guard let storedValue,
              let setting = UsageRefreshSetting(rawValue: storedValue)
        else {
            self = Self.defaultSetting
            return
        }
        self = setting
    }

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return String(localized: "Auto")
        case .fifteenMinutes:
            return String(localized: "15 min")
        case .thirtyMinutes:
            return String(localized: "30 min")
        case .oneHour:
            return String(localized: "1 hour")
        case .twoHours:
            return String(localized: "2 hours")
        case .sixHours:
            return String(localized: "6 hours")
        }
    }

    var isAutomatic: Bool {
        self == .automatic
    }

    var fixedIntervalMinutes: Int? {
        isAutomatic ? nil : rawValue
    }
}

enum UsageRefreshSchedule {
    static let automaticIntervalStorageKey = "automatic_refresh_interval_minutes"
    static let minimumAutomaticIntervalMinutes = 5
    static let defaultAutomaticIntervalMinutes = 60

    static func refreshSetting(defaults: UserDefaults = .standard) -> UsageRefreshSetting {
        UsageRefreshSetting(
            storedValue: defaults.object(forKey: UsageRefreshSetting.storageKey) as? Int
        )
    }

    static func storedAutomaticIntervalMinutes(defaults: UserDefaults = .standard) -> Int {
        guard let interval = defaults.object(forKey: automaticIntervalStorageKey) as? Int else {
            return defaultAutomaticIntervalMinutes
        }

        return max(minimumAutomaticIntervalMinutes, interval)
    }

    static func storeAutomaticIntervalMinutes(
        _ interval: Int,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(max(minimumAutomaticIntervalMinutes, interval), forKey: automaticIntervalStorageKey)
    }

    static func scheduledIntervalMinutes(
        automaticIntervalMinutes: Int? = nil,
        defaults: UserDefaults = .standard
    ) -> Int {
        intervalMinutes(
            for: refreshSetting(defaults: defaults),
            automaticIntervalMinutes: automaticIntervalMinutes
                ?? storedAutomaticIntervalMinutes(defaults: defaults)
        )
    }

    static func intervalMinutes(
        for setting: UsageRefreshSetting,
        automaticIntervalMinutes: Int
    ) -> Int {
        guard setting.isAutomatic else {
            return setting.fixedIntervalMinutes ?? defaultAutomaticIntervalMinutes
        }

        return max(minimumAutomaticIntervalMinutes, automaticIntervalMinutes)
    }

    static func automaticIntervalMinutes(
        previous: [UsageSnapshot],
        current: [UsageSnapshot]
    ) -> Int {
        current.compactMap { snapshot -> Int? in
            intervalMinutes(for: snapshot, previous: previous)
        }.min() ?? defaultAutomaticIntervalMinutes
    }

    private static func intervalMinutes(
        for current: UsageSnapshot,
        previous snapshots: [UsageSnapshot]
    ) -> Int? {
        guard current.errorMessage == nil, current.limit > 0 else { return nil }
        guard let previousUsed = snapshots.first(where: { $0.id == current.id })?.used else { return nil }
        let increase = max(0, current.used - previousUsed)
        let increasePercent = min((increase / current.limit) * 100, 100)

        return intervalMinutes(forUsageIncreasePercent: increasePercent)
    }

    private static func intervalMinutes(forUsageIncreasePercent percent: Double) -> Int {
        switch percent {
        case 25...:
            return 5
        case 10..<25:
            return 15
        case 5..<10:
            return 30
        default:
            return defaultAutomaticIntervalMinutes
        }
    }
}
