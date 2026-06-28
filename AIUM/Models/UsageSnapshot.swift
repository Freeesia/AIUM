import Foundation

// MARK: - Provider

public enum Provider: String, Codable, CaseIterable, Sendable {
    case githubCopilot
    case codex

    public var displayName: String {
        switch self {
        case .githubCopilot: return "GitHub Copilot"
        case .codex: return "OpenAI Codex"
        }
    }

    var iconAssetName: String {
        switch self {
        case .githubCopilot: return "GitHubCopilot"
        case .codex: return "Codex"
        }
    }
}

// MARK: - WindowKind

public enum WindowKind: String, Codable, Sendable {
    case monthly
    case daily
    case hourly
    case custom
}

// MARK: - PlanKind

public enum PlanKind: String, Codable, Sendable {
    case aiCredits
    case premiumRequests
    case codexFree
    case codexPro
    case unknown
}

// MARK: - UsageSnapshot

/// Normalized snapshot of a provider's usage at a point in time.
public struct UsageSnapshot: Codable, Identifiable, Sendable {
    public let provider: Provider
    public let accountId: String?
    public let displayName: String?
    public let planKind: PlanKind
    public let windowKind: WindowKind
    /// Number of units consumed in the current window.
    public let used: Double
    /// Total allowed units in the current window (0 = unknown).
    public let limit: Double
    /// Reset date/time for the current window.
    public let resetAt: Date?
    /// Human-readable unit label (e.g. "requests", "tokens").
    public let unit: String
    /// String describing where the data came from.
    public let source: String
    /// When this snapshot was fetched.
    public let fetchedAt: Date
    /// Non-nil when the last refresh returned an error.
    public let errorMessage: String?
    /// Duration of the rate-limit window in minutes (nil for monthly).
    public let windowDurationMins: Int?

    // MARK: Computed

    public var id: String {
        [
            provider.rawValue,
            accountId ?? "default",
            planKind.rawValue,
            windowKind.rawValue,
            windowDurationMins.map { "\($0)m" } ?? "window",
            source,
        ].joined(separator: "-")
    }

    public var usedPercent: Double {
        guard limit > 0 else { return 0 }
        return min((used / limit) * 100, 100)
    }

    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }

    // MARK: Init

    public init(
        provider: Provider,
        accountId: String? = nil,
        displayName: String? = nil,
        planKind: PlanKind = .unknown,
        windowKind: WindowKind = .monthly,
        used: Double,
        limit: Double,
        resetAt: Date? = nil,
        unit: String = "requests",
        source: String,
        fetchedAt: Date = Date(),
        errorMessage: String? = nil,
        windowDurationMins: Int? = nil
    ) {
        self.provider = provider
        self.accountId = accountId
        self.displayName = displayName
        self.planKind = planKind
        self.windowKind = windowKind
        self.used = used
        self.limit = limit
        self.resetAt = resetAt
        self.unit = unit
        self.source = source
        self.fetchedAt = fetchedAt
        self.errorMessage = errorMessage
        self.windowDurationMins = windowDurationMins
    }
}

// MARK: - Helpers

extension UsageSnapshot {
    /// Returns a placeholder snapshot used before data is fetched.
    static func placeholder(provider: Provider) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            used: 0,
            limit: 0,
            source: "placeholder"
        )
    }

    /// Returns an error snapshot.
    static func error(
        provider: Provider,
        accountId: String? = nil,
        displayName: String? = nil,
        planKind: PlanKind = .unknown,
        windowKind: WindowKind = .monthly,
        unit: String = "requests",
        source: String = "error",
        message: String
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            accountId: accountId,
            displayName: displayName,
            planKind: planKind,
            windowKind: windowKind,
            used: 0,
            limit: 0,
            unit: unit,
            source: source,
            errorMessage: message
        )
    }

    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > 3600
    }
}
