import Foundation

// MARK: - Codex Rate-Limit Response

/// Raw decoded response from the Codex private usage / rate-limit endpoint.
///
/// ⚠️ This model reflects a private API that may change at any time.
/// All endpoint details are isolated here so they can be updated without touching the UI.
///
/// TODO: Verify field names against the actual endpoint before use.
struct CodexRateLimitResponse: Decodable {
    /// Primary rate-limit window (e.g. per-minute or per-hour).
    let primaryWindow: WindowDetail?
    /// Secondary rate-limit window (e.g. per-day).
    let secondaryWindow: WindowDetail?
    /// Reset credits returned by the server, if any.
    let resetCredits: Double?

    init(primaryWindow: WindowDetail?, secondaryWindow: WindowDetail?, resetCredits: Double?) {
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
        self.resetCredits = resetCredits
    }

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
        case resetCredits = "reset_credits"
    }

    struct WindowDetail: Decodable {
        let limit: Double?
        let remaining: Double?
        let resetAt: Date?
        let windowDurationMins: Int?
        let usedPercent: Double?

        init(limit: Double?, remaining: Double?, resetAt: Date?,
             windowDurationMins: Int?, usedPercent: Double?) {
            self.limit = limit
            self.remaining = remaining
            self.resetAt = resetAt
            self.windowDurationMins = windowDurationMins
            self.usedPercent = usedPercent
        }

        enum CodingKeys: String, CodingKey {
            case limit
            case remaining
            case resetAt = "reset_at"
            case windowDurationMins = "window_duration_mins"
            case usedPercent = "used_percent"
        }
    }
}

// MARK: - Protocol

/// Abstraction for any Codex usage provider.
/// Switch implementation without changing ViewModels or Views.
protocol CodexUsageProvider: UsageProvider {}

// MARK: - Private Codex Usage Provider

/// Fetches Codex usage from a private (undocumented) rate-limit endpoint.
///
/// ⚠️ WARNING: This uses private OpenAI API endpoints that are NOT officially supported.
/// - They may change or disappear without notice.
/// - Do NOT submit an app using this to the public App Store until official APIs are available.
/// - Endpoint path and response schema may need adjustment.
///
/// TODO: Replace or augment this provider once official usage APIs are available.
actor PrivateCodexUsageProvider: CodexUsageProvider {
    let provider: Provider = .codex

    private let authProvider: CodexAuthProvider
    private let session: URLSession

    // TODO: Confirm the correct endpoint path for the private usage API.
    private let endpointPath: String

    init(
        authProvider: CodexAuthProvider = CodexAuthProvider(),
        endpointPath: String = "/v1/usage/rate_limits",  // TODO: Verify this path
        session: URLSession = .shared
    ) {
        self.authProvider = authProvider
        self.endpointPath = endpointPath
        self.session = session
    }

    // MARK: - UsageProvider

    var isAuthenticated: Bool {
        get async { await authProvider.isAuthenticated }
    }

    func fetchUsage() async throws -> [UsageSnapshot] {
        let token = try await authProvider.validAccessToken()
        let tokenBundle = await authProvider.tokenBundle

        let url = URL(string: "https://api.openai.com")!.appending(path: endpointPath)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw CodexUsageError.httpError(httpResponse.statusCode,
                                             String(data: data, encoding: .utf8))
        }

        let decoded = try decodeResponse(data)
        return normalizeSnapshots(decoded, tokenBundle: tokenBundle)
    }

    // MARK: - Normalization

    nonisolated func normalizeSnapshots(
        _ response: CodexRateLimitResponse,
        tokenBundle: CodexTokenBundle?
    ) -> [UsageSnapshot] {
        var snapshots: [UsageSnapshot] = []
        let accountId = tokenBundle?.accountId
        let displayName = tokenBundle?.email

        if let primary = response.primaryWindow {
            snapshots.append(normalizeWindow(
                primary,
                planKind: .codexPro,
                windowKind: primary.windowDurationMins.map { _ in .custom } ?? .hourly,
                accountId: accountId,
                displayName: displayName,
                source: "Codex Private API (primary)"
            ))
        }

        if let secondary = response.secondaryWindow {
            snapshots.append(normalizeWindow(
                secondary,
                planKind: .codexPro,
                windowKind: .daily,
                accountId: accountId,
                displayName: displayName,
                source: "Codex Private API (secondary)"
            ))
        }

        return snapshots
    }

    nonisolated func decodeResponse(_ data: Data) throws -> CodexRateLimitResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodexRateLimitResponse.self, from: data)
    }

    private nonisolated func normalizeWindow(
        _ window: CodexRateLimitResponse.WindowDetail,
        planKind: PlanKind,
        windowKind: WindowKind,
        accountId: String?,
        displayName: String?,
        source: String
    ) -> UsageSnapshot {
        let limit = window.limit ?? 0
        let remaining = window.remaining ?? 0
        let used: Double

        if let usedPercent = window.usedPercent {
            // Server provides used% directly
            used = limit * (usedPercent / 100)
        } else {
            used = max(0, limit - remaining)
        }

        return UsageSnapshot(
            provider: .codex,
            accountId: accountId,
            displayName: displayName,
            planKind: planKind,
            windowKind: windowKind,
            used: used,
            limit: limit,
            resetAt: window.resetAt,
            unit: "requests",
            source: source,
            windowDurationMins: window.windowDurationMins
        )
    }
}

// MARK: - Errors

enum CodexUsageError: LocalizedError {
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "Codex API error \(code): \(body ?? "no body")"
        }
    }
}
