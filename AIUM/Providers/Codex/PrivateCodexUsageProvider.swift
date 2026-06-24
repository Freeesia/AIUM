import Foundation

// MARK: - Codex Usage Response

/// Normalized view of Codex's private usage response.
///
/// The Codex app-server currently exposes rate-limit data through the ChatGPT
/// backend (`/api/codex/usage`). Older builds and experiments have returned
/// snake_case window objects, so decoding stays tolerant while preserving one
/// strict output shape for the rest of the app.
struct CodexUsageResponse: Sendable {
    let windows: [CodexUsageWindow]
    let resetCredits: Double?
    let accountId: String?
    let email: String?

    static func decode(from data: Data, now: Date = Date()) throws -> CodexUsageResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.decodeError(
                endpoint: "Codex usage",
                body: String(data: data, encoding: .utf8),
                underlying: CodexUsageDecodeFailure()
            )
        }

        return CodexUsageParser(root: root, now: now).parse()
    }
}

struct CodexUsageWindow: Sendable {
    let planKind: PlanKind
    let windowKind: WindowKind
    let used: Double
    let limit: Double
    let resetAt: Date?
    let unit: String
    let source: String
    let windowDurationMins: Int?
}

// MARK: - Protocol

/// Abstraction for any Codex usage provider.
/// Switch implementation without changing ViewModels or Views.
protocol CodexUsageProvider: UsageProvider {}

// MARK: - Private Codex Usage Provider

/// Fetches Codex usage from the private Codex backend used by the Codex app.
///
/// This API is not an official public OpenAI API. Keep all endpoint and schema
/// assumptions isolated in this provider so changes do not leak into UI code.
actor PrivateCodexUsageProvider: CodexUsageProvider {
    let provider: Provider = .codex

    private let authProvider: any CodexAuthProviding
    private let session: URLSession
    private let backendBaseURL: URL
    private let usageEndpointPath: String
    private let profileEndpointPath: String

    init(
        authProvider: any CodexAuthProviding = CodexAuthProvider(),
        backendBaseURL: URL = CodexOAuthConfig.backendBaseURL,
        usageEndpointPath: String = CodexOAuthConfig.usageEndpointPath,
        profileEndpointPath: String = CodexOAuthConfig.profileEndpointPath,
        session: URLSession = .shared
    ) {
        self.authProvider = authProvider
        self.backendBaseURL = backendBaseURL
        self.usageEndpointPath = usageEndpointPath
        self.profileEndpointPath = profileEndpointPath
        self.session = session
    }

    // MARK: - UsageProvider

    var isAuthenticated: Bool {
        get async { await authProvider.isAuthenticated }
    }

    func fetchUsage() async throws -> [UsageSnapshot] {
        let token = try await authProvider.validAccessToken()
        var tokenBundle = await authProvider.tokenBundle

        if let identity = try? await fetchProfile(token: token, accountId: tokenBundle?.accountId) {
            try await authProvider.updateAccount(accountId: identity.accountId, email: identity.email)
            tokenBundle = await authProvider.tokenBundle
        }

        let request = makeBackendRequest(
            path: usageEndpointPath,
            token: token,
            accountId: tokenBundle?.accountId
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, endpointName: "Codex usage")

        let decoded = try decodeResponse(data)
        let snapshots = normalizeSnapshots(decoded, tokenBundle: tokenBundle)
        guard !snapshots.isEmpty else {
            throw CodexUsageError.noUsageData(body: String(data: data, encoding: .utf8))
        }

        return snapshots
    }

    // MARK: - Decoding and normalization

    nonisolated func decodeResponse(_ data: Data) throws -> CodexUsageResponse {
        try CodexUsageResponse.decode(from: data)
    }

    nonisolated func normalizeSnapshots(
        _ response: CodexUsageResponse,
        tokenBundle: CodexTokenBundle?
    ) -> [UsageSnapshot] {
        let accountId = response.accountId ?? tokenBundle?.accountId
        let displayName = response.email ?? tokenBundle?.email

        return response.windows.map { window in
            UsageSnapshot(
                provider: .codex,
                accountId: accountId,
                displayName: displayName,
                planKind: window.planKind,
                windowKind: window.windowKind,
                used: window.used,
                limit: window.limit,
                resetAt: window.resetAt,
                unit: window.unit,
                source: window.source,
                windowDurationMins: window.windowDurationMins
            )
        }
    }

    // MARK: - Private helpers

    private func fetchProfile(token: String, accountId: String?) async throws -> CodexAccountIdentity? {
        let request = makeBackendRequest(path: profileEndpointPath, token: token, accountId: accountId)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, endpointName: "Codex profile")
        return CodexAccountIdentity.extract(jsonData: data)
    }

    private func makeBackendRequest(path: String, token: String, accountId: String?) -> URLRequest {
        var request = URLRequest(url: backendBaseURL.appendingSlashPath(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIUM", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    private func validate(response: URLResponse, data: Data, endpointName: String) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              !(200..<300).contains(httpResponse.statusCode)
        else { return }

        throw CodexUsageError.httpError(
            endpoint: endpointName,
            statusCode: httpResponse.statusCode,
            body: String(data: data, encoding: .utf8)
        )
    }
}

// MARK: - Parser

private struct CodexUsageParser {
    private let root: [String: Any]
    private let now: Date

    init(root: [String: Any], now: Date) {
        self.root = root
        self.now = now
    }

    func parse() -> CodexUsageResponse {
        CodexUsageResponse(
            windows: parseWindows(),
            resetCredits: firstDouble(root, keys: [
                "rateLimitResetCredits",
                "rate_limit_reset_credits",
                "resetCredits",
                "reset_credits",
            ]),
            accountId: firstString(root, keys: [
                "account_id",
                "accountId",
                "chatgpt_account_id",
                "chatgptAccountId",
            ]),
            email: firstString(root, keys: ["email"])
        )
    }

    private func parseWindows() -> [CodexUsageWindow] {
        var windows: [CodexUsageWindow] = []

        windows.append(contentsOf: parseLegacyRootWindows())
        windows.append(contentsOf: parseRateLimits(root["rateLimits"]))
        windows.append(contentsOf: parseRateLimits(root["rate_limits"]))
        windows.append(contentsOf: parseRateLimitsById(root["rateLimitsByLimitId"]))
        windows.append(contentsOf: parseRateLimitsById(root["rate_limits_by_limit_id"]))

        if let data = root["data"] as? [String: Any] {
            windows.append(contentsOf: CodexUsageParser(root: data, now: now).parseWindows())
        }

        return deduplicate(windows)
    }

    private func parseLegacyRootWindows() -> [CodexUsageWindow] {
        var windows: [CodexUsageWindow] = []
        let metadata = WindowMetadata(
            limitId: nil,
            limitName: nil,
            individualLimit: nil,
            planName: nil
        )

        for key in ["primary_window", "primaryWindow", "primary"] {
            if let window = root[key] as? [String: Any],
               let parsed = parseWindow(window, label: "primary", metadata: metadata) {
                windows.append(parsed)
                break
            }
        }

        for key in ["secondary_window", "secondaryWindow", "secondary"] {
            if let window = root[key] as? [String: Any],
               let parsed = parseWindow(window, label: "secondary", metadata: metadata) {
                windows.append(parsed)
                break
            }
        }

        return windows
    }

    private func parseRateLimits(_ value: Any?) -> [CodexUsageWindow] {
        if let array = value as? [[String: Any]] {
            return array.flatMap { parseRateLimitContainer($0, fallbackLimitId: nil) }
        }

        if let dictionary = value as? [String: Any] {
            return parseRateLimitsById(dictionary)
        }

        return []
    }

    private func parseRateLimitsById(_ value: Any?) -> [CodexUsageWindow] {
        guard let dictionary = value as? [String: Any] else { return [] }

        return dictionary.flatMap { key, value -> [CodexUsageWindow] in
            if let container = value as? [String: Any] {
                return parseRateLimitContainer(container, fallbackLimitId: key)
            }
            return []
        }
    }

    private func parseRateLimitContainer(
        _ container: [String: Any],
        fallbackLimitId: String?
    ) -> [CodexUsageWindow] {
        let metadata = WindowMetadata(
            limitId: firstString(container, keys: ["limitId", "limit_id"]) ?? fallbackLimitId,
            limitName: firstString(container, keys: ["limitName", "limit_name", "name"]),
            individualLimit: firstDouble(container, keys: ["individualLimit", "individual_limit", "limit"]),
            planName: firstString(container, keys: ["planType", "plan_type", "plan"])
        )
        var windows: [CodexUsageWindow] = []

        let windowKeys = [
            "primary",
            "primaryWindow",
            "primary_window",
            "secondary",
            "secondaryWindow",
            "secondary_window",
            "credits",
            "credit",
        ]

        for key in windowKeys {
            guard let window = container[key] as? [String: Any],
                  let parsed = parseWindow(window, label: key, metadata: metadata)
            else { continue }

            windows.append(parsed)
        }

        if windows.isEmpty, looksLikeWindow(container),
           let parsed = parseWindow(container, label: metadata.limitName ?? "usage", metadata: metadata) {
            windows.append(parsed)
        }

        return windows
    }

    private func parseWindow(
        _ window: [String: Any],
        label: String,
        metadata: WindowMetadata
    ) -> CodexUsageWindow? {
        let rawLimit = firstDouble(window, keys: [
            "limit",
            "total",
            "totalAllowance",
            "total_allowance",
            "individualLimit",
            "individual_limit",
        ]) ?? metadata.individualLimit
        let rawRemaining = firstDouble(window, keys: [
            "remaining",
            "remainingRequests",
            "remaining_requests",
            "remainingCredits",
            "remaining_credits",
        ])
        let rawUsed = firstDouble(window, keys: [
            "used",
            "usedRequests",
            "used_requests",
            "usedInCurrentPeriod",
            "used_in_current_period",
            "currentUsage",
            "current_usage",
        ])
        let usedPercent = normalizedPercent(firstDouble(window, keys: [
            "usedPercent",
            "used_percent",
            "usagePercent",
            "usage_percent",
        ]))

        let limit: Double
        let used: Double
        let unit: String

        if let rawLimit {
            limit = rawLimit
            if let rawUsed {
                used = rawUsed
            } else if let rawRemaining {
                used = max(0, rawLimit - rawRemaining)
            } else if let usedPercent {
                used = rawLimit * (usedPercent / 100)
            } else {
                used = 0
            }
            unit = firstString(window, keys: ["unit"]) ?? "requests"
        } else if let usedPercent {
            limit = 100
            used = usedPercent
            unit = "percent"
        } else if let rawUsed {
            limit = 0
            used = rawUsed
            unit = firstString(window, keys: ["unit"]) ?? "requests"
        } else {
            return nil
        }

        let durationMins = windowDurationMins(window)
        let sourceName = [metadata.limitName, metadata.limitId, normalizedLabel(label)]
            .compactMap { $0 }
            .first

        return CodexUsageWindow(
            planKind: planKind(metadata: metadata),
            windowKind: windowKind(window, label: label, durationMins: durationMins),
            used: used,
            limit: limit,
            resetAt: resetDate(window),
            unit: unit,
            source: "Codex Backend Usage" + (sourceName.map { " (\($0))" } ?? ""),
            windowDurationMins: durationMins
        )
    }

    private func looksLikeWindow(_ dictionary: [String: Any]) -> Bool {
        firstDouble(dictionary, keys: [
            "limit",
            "remaining",
            "used",
            "usedPercent",
            "used_percent",
            "individualLimit",
            "individual_limit",
        ]) != nil
    }

    private func windowDurationMins(_ window: [String: Any]) -> Int? {
        if let mins = firstDouble(window, keys: ["windowDurationMins", "window_duration_mins"]) {
            return Int(mins)
        }

        if let seconds = firstDouble(window, keys: ["limitWindowSeconds", "limit_window_seconds"]) {
            return Int(seconds / 60)
        }

        return nil
    }

    private func windowKind(_ window: [String: Any], label: String, durationMins: Int?) -> WindowKind {
        let raw = [
            firstString(window, keys: ["window", "windowKind", "window_kind"]),
            label,
        ].compactMap { $0?.lowercased() }.joined(separator: " ")

        if raw.contains("month") { return .monthly }
        if raw.contains("day") || raw.contains("daily") { return .daily }
        if raw.contains("hour") || raw.contains("hourly") { return .hourly }

        switch durationMins {
        case 60:
            return .hourly
        case 1_440:
            return .daily
        case 43_200:
            return .monthly
        default:
            return durationMins == nil ? .custom : .custom
        }
    }

    private func planKind(metadata: WindowMetadata) -> PlanKind {
        let raw = [metadata.planName, metadata.limitName, metadata.limitId]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if raw.contains("free") {
            return .codexFree
        }

        return .codexPro
    }

    private func resetDate(_ window: [String: Any]) -> Date? {
        if let raw = firstValue(window, keys: ["resetsAt", "resets_at", "resetAt", "reset_at"]) {
            return parseDate(raw)
        }

        if let seconds = firstDouble(window, keys: ["resetAfterSeconds", "reset_after_seconds"]) {
            return now.addingTimeInterval(seconds)
        }

        return nil
    }

    private func parseDate(_ value: Any) -> Date? {
        if let date = value as? Date {
            return date
        }

        if let seconds = value as? TimeInterval {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }

        guard let string = value as? String else { return nil }

        if let seconds = TimeInterval(string) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        return ISO8601DateFormatter().date(from: string)
    }

    private func normalizedPercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        if value <= 1 {
            return value * 100
        }
        return value
    }

    private func normalizedLabel(_ value: String) -> String? {
        let normalized = value
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func deduplicate(_ windows: [CodexUsageWindow]) -> [CodexUsageWindow] {
        var seen = Set<String>()
        var result: [CodexUsageWindow] = []

        for window in windows {
            let key = [
                window.planKind.rawValue,
                window.windowKind.rawValue,
                String(window.windowDurationMins ?? 0),
                window.source,
            ].joined(separator: "|")

            if seen.insert(key).inserted {
                result.append(window)
            }
        }

        return result
    }

    private func firstValue(_ dictionary: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = dictionary[key], !(value is NSNull) {
                return value
            }
        }
        return nil
    }

    private func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = dictionary[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func firstDouble(_ dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            guard let value = dictionary[key], !(value is NSNull) else { continue }

            if let double = value as? Double {
                return double
            }
            if let int = value as? Int {
                return Double(int)
            }
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let string = value as? String, let double = Double(string) {
                return double
            }
            if let dictionary = value as? [String: Any] {
                if let nested = firstDouble(dictionary, keys: [
                    "value",
                    "remaining",
                    "available",
                    "credits",
                    "count",
                ]) {
                    return nested
                }
            }
        }

        return nil
    }
}

private struct WindowMetadata {
    let limitId: String?
    let limitName: String?
    let individualLimit: Double?
    let planName: String?
}

private struct CodexUsageDecodeFailure: LocalizedError {
    var errorDescription: String? {
        "Codex usage response was not a JSON object."
    }
}

private extension URL {
    func appendingSlashPath(_ path: String) -> URL {
        var url = self
        for component in path.split(separator: "/") {
            url.append(path: String(component))
        }
        return url
    }
}

// MARK: - Errors

enum CodexUsageError: LocalizedError {
    case httpError(endpoint: String, statusCode: Int, body: String?)
    case decodeError(endpoint: String, body: String?, underlying: Error)
    case noUsageData(body: String?)

    var errorDescription: String? {
        switch self {
        case .httpError(let endpoint, let code, let body):
            return "\(endpoint) HTTP \(code): \(Self.preview(body))"
        case .decodeError(let endpoint, let body, let underlying):
            return "\(endpoint) decode error: \(underlying.localizedDescription). Body: \(Self.preview(body))"
        case .noUsageData(let body):
            return "Codex usage response did not include rate-limit data. Body: \(Self.preview(body))"
        }
    }

    private static func preview(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return "no body" }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 300 { return singleLine }
        return String(singleLine.prefix(300)) + "..."
    }
}
