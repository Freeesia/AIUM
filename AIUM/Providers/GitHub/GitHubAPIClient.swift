import Foundation

// MARK: - Response Models

struct GitHubUser: Decodable, Sendable {
    let login: String
    let id: Int
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login, id, name
        case avatarUrl = "avatar_url"
    }
}

struct GitHubBillingTimePeriod: Decodable, Sendable {
    let year: Int?
    let month: Int?
    let day: Int?

    func periodEndDate() -> Date? {
        guard let year else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month ?? 1
        components.day = day ?? 1

        guard let start = calendar.date(from: components) else { return nil }
        if day != nil {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        if month != nil {
            return calendar.date(byAdding: .month, value: 1, to: start)
        }
        return nil
    }
}

struct GitHubBillingUsageItem: Decodable, Sendable {
    let product: String?
    let sku: String?
    let model: String?
    let unitType: String?
    let quantity: Double?
    let grossQuantity: Double?
    let netQuantity: Double?

    var consumedQuantity: Double {
        grossQuantity ?? quantity ?? netQuantity ?? 0
    }
}

struct GitHubAICreditUsageResponse: Decodable, Sendable {
    let timePeriod: GitHubBillingTimePeriod?
    let usageItems: [GitHubBillingUsageItem]

    init(
        timePeriod: GitHubBillingTimePeriod? = nil,
        usageItems: [GitHubBillingUsageItem] = []
    ) {
        self.timePeriod = timePeriod
        self.usageItems = usageItems
    }

    var usedQuantity: Double {
        usageItems.reduce(0) { $0 + $1.consumedQuantity }
    }

    enum CodingKeys: String, CodingKey {
        case timePeriod
        case usageItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timePeriod = try container.decodeIfPresent(GitHubBillingTimePeriod.self, forKey: .timePeriod)
        usageItems = try container.decodeIfPresent([GitHubBillingUsageItem].self, forKey: .usageItems) ?? []
    }
}

struct GitHubPremiumRequestUsageResponse: Decodable, Sendable {
    let timePeriod: GitHubBillingTimePeriod?
    let usageItems: [GitHubBillingUsageItem]

    init(
        timePeriod: GitHubBillingTimePeriod? = nil,
        usageItems: [GitHubBillingUsageItem] = []
    ) {
        self.timePeriod = timePeriod
        self.usageItems = usageItems
    }

    var usedQuantity: Double {
        usageItems.reduce(0) { $0 + $1.consumedQuantity }
    }

    enum CodingKeys: String, CodingKey {
        case timePeriod
        case usageItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timePeriod = try container.decodeIfPresent(GitHubBillingTimePeriod.self, forKey: .timePeriod)
        usageItems = try container.decodeIfPresent([GitHubBillingUsageItem].self, forKey: .usageItems) ?? []
    }
}

// MARK: - API Client

protocol GitHubAPIProviding: Actor {
    func fetchUser(token: String) async throws -> GitHubUser
    func fetchAICreditUsage(username: String, token: String) async throws -> GitHubAICreditUsageResponse
    func fetchPremiumRequestUsage(username: String, token: String) async throws -> GitHubPremiumRequestUsageResponse
}

/// Low-level GitHub REST API client.
/// All methods require a valid access token.
actor GitHubAPIClient: GitHubAPIProviding {
    private let baseURL = URL(string: "https://api.github.com")!
    private let apiVersion = "2026-03-10"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Endpoints

    /// Fetches the authenticated user's profile.
    func fetchUser(token: String) async throws -> GitHubUser {
        let request = makeRequest(path: "/user", token: token)
        return try await fetch(request, endpointName: "Authenticated User")
    }

    /// Fetches AI Credit usage for the given username.
    /// Endpoint:
    ///  - GET /users/{username}/settings/billing/ai_credit/usage
    func fetchAICreditUsage(username: String, token: String) async throws -> GitHubAICreditUsageResponse {
        let request = makeRequest(
            path: "/users/\(username)/settings/billing/ai_credit/usage",
            queryItems: currentMonthQueryItems(),
            token: token
        )
        return try await fetch(request, endpointName: "AI Credits")
    }

    /// Fetches Premium Request usage for the given username.
    /// Endpoint:
    ///  - GET /users/{username}/settings/billing/premium_request/usage
    func fetchPremiumRequestUsage(username: String, token: String) async throws -> GitHubPremiumRequestUsageResponse {
        let request = makeRequest(
            path: "/users/\(username)/settings/billing/premium_request/usage",
            queryItems: currentMonthQueryItems(),
            token: token
        )
        return try await fetch(request, endpointName: "Premium Requests")
    }

    // MARK: - Private

    private func makeRequest(path: String, queryItems: [URLQueryItem] = [], token: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func currentMonthQueryItems(now: Date = Date()) -> [URLQueryItem] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let year = components.year, let month = components.month else { return [] }
        return [
            URLQueryItem(name: "year", value: String(year)),
            URLQueryItem(name: "month", value: String(month)),
        ]
    }

    private func fetch<T: Decodable>(_ request: URLRequest, endpointName: String) async throws -> T {
        debugLog("Requesting \(endpointName): \(request.url?.absoluteString ?? "unknown URL")")
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            debugLog("Response \(endpointName): HTTP \(httpResponse.statusCode). Body: \(Self.previewBody(data))")
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8)
            switch httpResponse.statusCode {
            case 401:
                throw GitHubAPIError.authenticationFailed(statusCode: httpResponse.statusCode, body: body)
            default:
                throw GitHubAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubAPIError.decodeError(endpoint: endpointName, body: String(data: data, encoding: .utf8), underlying: error)
        }
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-AIUMDebugGitHubUsage") else { return }
        print("[AIUM][GitHubAPI] \(message())")
        #endif
    }

    private static func previewBody(_ data: Data) -> String {
        guard let body = String(data: data, encoding: .utf8), !body.isEmpty else { return "empty" }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 500 { return singleLine }
        return String(singleLine.prefix(500)) + "..."
    }
}

// MARK: - Errors

enum GitHubAPIError: LocalizedError {
    case authenticationFailed(statusCode: Int, body: String?)
    case httpError(statusCode: Int, body: String?)
    case decodeError(endpoint: String, body: String?, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let code, let body):
            return "GitHub API auth error \(code): \(Self.preview(body))"
        case .httpError(let code, let body):
            return "GitHub API HTTP \(code): \(Self.preview(body))"
        case .decodeError(let endpoint, let body, let underlying):
            return "GitHub API decode error for \(endpoint): \(underlying.localizedDescription). Body: \(Self.preview(body))"
        }
    }

    private static func preview(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return "no body" }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= 300 { return singleLine }
        return String(singleLine.prefix(300)) + "..."
    }
}
