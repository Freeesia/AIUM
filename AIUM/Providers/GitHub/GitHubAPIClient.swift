import Foundation

// MARK: - Response Models

struct GitHubUser: Decodable {
    let login: String
    let id: Int
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login, id, name
        case avatarUrl = "avatar_url"
    }
}

/// Response from `/users/{username}/settings/billing/ai_credit/usage`
struct GitHubAICreditUsageResponse: Decodable {
    let usedInCurrentPeriod: Double?
    let totalAllowance: Double?
    let currentPeriodEnd: Date?

    enum CodingKeys: String, CodingKey {
        case usedInCurrentPeriod = "used_in_current_period"
        case totalAllowance = "total_allowance"
        case currentPeriodEnd = "current_period_end"
    }
}

/// Response from `/users/{username}/settings/billing/premium_request/usage`
struct GitHubPremiumRequestUsageResponse: Decodable {
    let usedPremiumRequests: Double?
    let includedPremiumRequests: Double?
    let lastUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPremiumRequests = "used_premium_requests"
        case includedPremiumRequests = "included_premium_requests"
        case lastUpdatedAt = "last_updated_at"
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
    /// Endpoint: GET /users/{username}/settings/billing/ai_credit/usage
    func fetchAICreditUsage(username: String, token: String) async throws -> GitHubAICreditUsageResponse {
        let request = makeRequest(
            path: "/users/\(username)/settings/billing/ai_credit/usage",
            token: token
        )
        return try await fetch(request, endpointName: "AI Credits")
    }

    /// Fetches legacy Premium Request usage for the given username.
    /// Endpoint: GET /users/{username}/settings/billing/premium_request/usage
    func fetchPremiumRequestUsage(username: String, token: String) async throws -> GitHubPremiumRequestUsageResponse {
        let request = makeRequest(
            path: "/users/\(username)/settings/billing/premium_request/usage",
            token: token
        )
        return try await fetch(request, endpointName: "Premium Requests")
    }

    // MARK: - Private

    private func makeRequest(path: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func fetch<T: Decodable>(_ request: URLRequest, endpointName: String) async throws -> T {
        let (data, response) = try await session.data(for: request)
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
