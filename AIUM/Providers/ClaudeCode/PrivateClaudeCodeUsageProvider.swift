import Foundation

// MARK: - Claude Code Usage Response

/// Normalized view of the private Claude Code usage response
/// (`GET /api/oauth/usage`), which reports plan rate-limit windows as
/// `{ "five_hour": { "utilization": 37.0, "resets_at": "..." }, "seven_day": ... }`.
struct ClaudeCodeUsageResponse: Sendable {
    static let fiveHourWindowMins = 5 * 60
    static let sevenDayWindowMins = 7 * 24 * 60

    let fiveHour: ClaudeCodeUsageWindow?
    let sevenDay: ClaudeCodeUsageWindow?

    var windows: [ClaudeCodeUsageWindow] {
        [fiveHour, sevenDay].compactMap { $0 }
    }

    static func decode(from data: Data) throws -> ClaudeCodeUsageResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeCodeUsageError.decodeError(
                endpoint: "Claude Code usage",
                body: String(data: data, encoding: .utf8),
                underlying: ClaudeCodeUsageDecodeFailure()
            )
        }

        return ClaudeCodeUsageResponse(
            fiveHour: window(root, keys: ["five_hour", "fiveHour"], durationMins: fiveHourWindowMins),
            sevenDay: window(root, keys: ["seven_day", "sevenDay"], durationMins: sevenDayWindowMins)
        )
    }

    private static func window(
        _ root: [String: Any],
        keys: [String],
        durationMins: Int
    ) -> ClaudeCodeUsageWindow? {
        guard let window = keys.lazy.compactMap({ root[$0] as? [String: Any] }).first,
              let utilization = number(window["utilization"]) ?? number(window["percent"]),
              utilization.isFinite
        else { return nil }

        let resetValue = ["resets_at", "resetsAt", "reset_at", "resetAt"]
            .lazy
            .compactMap { window[$0] }
            .first { !($0 is NSNull) }

        return ClaudeCodeUsageWindow(
            usedPercent: max(0, utilization),
            resetAt: resetValue.flatMap(parseDate),
            windowDurationMins: durationMins
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    /// Accepts Unix epoch seconds, Unix epoch milliseconds, and ISO 8601 strings
    /// with or without fractional seconds.
    static func parseDate(_ value: Any) -> Date? {
        if let number = value as? NSNumber {
            return epochDate(number.doubleValue)
        }
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }

        if let seconds = Double(string) {
            return epochDate(seconds)
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: string) {
            return date
        }

        // The API may return microsecond precision, which ISO8601DateFormatter
        // rejects. Trim the fraction to milliseconds and retry.
        if let range = string.range(of: #"\.\d+"#, options: .regularExpression) {
            let fraction = string[range].prefix(4)
            let trimmed = string.replacingCharacters(in: range, with: fraction)
            return fractional.date(from: trimmed)
        }
        return nil
    }

    private static func epochDate(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }
}

struct ClaudeCodeUsageWindow: Sendable {
    /// Percentage of the window used (0...100, may exceed 100).
    let usedPercent: Double
    let resetAt: Date?
    let windowDurationMins: Int
}

// MARK: - Protocol

/// Abstraction for any Claude Code usage provider.
/// Switch implementation without changing ViewModels or Views.
protocol ClaudeCodeUsageProvider: UsageProvider {}

// MARK: - Private Claude Code Usage Provider

/// Fetches Claude Code plan usage from the private endpoint used by the
/// Claude Code CLI's `/usage` command.
///
/// This API is not an official public Anthropic API. Keep all endpoint and
/// schema assumptions isolated in this provider so changes do not leak into UI code.
actor PrivateClaudeCodeUsageProvider: ClaudeCodeUsageProvider {
    static let source = "claude-code-private-api"

    let provider: Provider = .claudeCode

    private let authProvider: any ClaudeCodeAuthProviding
    private let session: URLSession
    private let apiBaseURL: URL
    private let usageEndpointPath: String

    init(
        authProvider: any ClaudeCodeAuthProviding = ClaudeCodeAuthProvider(),
        apiBaseURL: URL = ClaudeCodeOAuthConfig.apiBaseURL,
        usageEndpointPath: String = ClaudeCodeOAuthConfig.usageEndpointPath,
        session: URLSession = .shared
    ) {
        self.authProvider = authProvider
        self.apiBaseURL = apiBaseURL
        self.usageEndpointPath = usageEndpointPath
        self.session = session
    }

    // MARK: - UsageProvider

    var isAuthenticated: Bool {
        get async { await authProvider.isAuthenticated }
    }

    func fetchUsage() async throws -> [UsageSnapshot] {
        let token = try await authProvider.validAccessToken()
        let tokenBundle = await authProvider.tokenBundle

        var request = URLRequest(url: apiBaseURL.appending(path: usageEndpointPath), timeoutInterval: 15)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(ClaudeCodeOAuthConfig.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIUM", forHTTPHeaderField: "User-Agent")

        debugLog("Requesting Claude Code usage: \(request.url?.absoluteString ?? "unknown URL")")
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            debugLog("Claude Code usage response: HTTP \(httpResponse.statusCode)")
        }
        try validate(response: response, data: data, endpointName: "Claude Code usage")

        let decoded = try ClaudeCodeUsageResponse.decode(from: data)
        guard !decoded.windows.isEmpty else {
            throw ClaudeCodeUsageError.noUsageData(body: String(data: data, encoding: .utf8))
        }

        let snapshots = Self.normalizeSnapshots(decoded, tokenBundle: tokenBundle)
        debugLog("Decoded \(snapshots.count) Claude Code usage snapshot(s).")
        return snapshots
    }

    // MARK: - Normalization

    static func normalizeSnapshots(
        _ response: ClaudeCodeUsageResponse,
        tokenBundle: ClaudeCodeTokenBundle?,
        now: Date = Date()
    ) -> [UsageSnapshot] {
        response.windows.map { window in
            UsageSnapshot(
                provider: .claudeCode,
                accountId: tokenBundle?.accountId,
                displayName: tokenBundle?.accountDisplayName,
                planKind: .unknown,
                windowKind: .custom,
                used: window.usedPercent,
                limit: 100,
                resetAt: window.resetAt,
                unit: "percent",
                source: source,
                fetchedAt: now,
                windowDurationMins: window.windowDurationMins
            )
        }
    }

    // MARK: - Private helpers

    private func validate(response: URLResponse, data: Data, endpointName: String) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200..<300).contains(httpResponse.statusCode)
        else { return }

        debugLog(
            "\(endpointName) HTTP \(httpResponse.statusCode) at \(httpResponse.url?.absoluteString ?? "unknown URL")"
        )
        throw ClaudeCodeUsageError.httpError(
            endpoint: endpointName,
            statusCode: httpResponse.statusCode,
            body: String(data: data, encoding: .utf8)
        )
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[AIUM][ClaudeCodeUsage] \(message())")
        #endif
    }
}

private struct ClaudeCodeUsageDecodeFailure: LocalizedError {
    var errorDescription: String? {
        String(localized: "Claude Code usage response was not a JSON object.")
    }
}

// MARK: - Errors

enum ClaudeCodeUsageError: LocalizedError {
    case httpError(endpoint: String, statusCode: Int, body: String?)
    case decodeError(endpoint: String, body: String?, underlying: Error)
    case noUsageData(body: String?)

    var errorDescription: String? {
        switch self {
        case .httpError(let endpoint, let code, let body):
            return String.localizedStringWithFormat(
                String(localized: "%@ HTTP %lld: %@"),
                endpoint,
                Int64(code),
                Self.preview(body)
            )
        case .decodeError(let endpoint, let body, let underlying):
            return String.localizedStringWithFormat(
                String(localized: "%@ decode error: %@. Body: %@"),
                endpoint,
                underlying.localizedDescription,
                Self.preview(body)
            )
        case .noUsageData(let body):
            return String.localizedStringWithFormat(
                String(localized: "Claude Code usage response did not include rate-limit data. Body: %@"),
                Self.preview(body)
            )
        }
    }

    private static func preview(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return String(localized: "no body") }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 300 { return singleLine }
        return String(singleLine.prefix(300)) + "..."
    }
}
