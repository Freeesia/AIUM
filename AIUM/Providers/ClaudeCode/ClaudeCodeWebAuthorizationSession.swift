import AuthenticationServices
import Foundation
import Network
import UIKit

// MARK: - Web Authorization Session

/// Runs the browser leg of the Claude Code sign-in with `ASWebAuthenticationSession`.
///
/// The Claude Code OAuth client only accepts `http://localhost:<port>/callback`
/// as an automatic redirect. While the authentication sheet is open, AIUM
/// listens on the loopback interface, receives that redirect, and answers it
/// with a redirect to `aium-claude-code://`, which closes the sheet.
@MainActor
final class ClaudeCodeWebAuthorizationSession: NSObject, ClaudeCodeAuthorizationSession {
    private var webSession: ASWebAuthenticationSession?

    nonisolated func authorize(
        buildAuthorizationURL: @escaping @Sendable (URL) -> URL
    ) async throws -> ClaudeCodeAuthorizationCallback {
        let server = ClaudeCodeLoopbackServer()
        defer { server.stop() }

        let port = try await server.start()
        let redirectURI = ClaudeCodeOAuthConfig.loopbackRedirectURI(port: port)
        let authorizationURL = buildAuthorizationURL(redirectURI)

        let callbackURL = try await withTaskCancellationHandler {
            try await waitForCallback(authorizationURL: authorizationURL, server: server)
        } onCancel: {
            server.stop()
            Task { @MainActor [weak self] in self?.webSession?.cancel() }
        }
        return ClaudeCodeAuthorizationCallback(url: callbackURL, redirectURI: redirectURI)
    }

    private func waitForCallback(authorizationURL: URL, server: ClaudeCodeLoopbackServer) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let completion = ClaudeCodeCallbackCompletion(continuation)

            // The loopback request is authoritative: it arrives even when the
            // browser does not follow the custom-scheme redirect.
            server.onCallback = { [weak self] url in
                completion.resume(with: .success(url))
                Task { @MainActor in self?.finishWebSession() }
            }
            server.onFailure = { [weak self] error in
                completion.resume(with: .failure(error))
                Task { @MainActor in self?.finishWebSession() }
            }

            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callback: .customScheme(ClaudeCodeOAuthConfig.callbackScheme)
            ) { [weak self] url, error in
                if let url {
                    completion.resume(with: .success(url))
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    completion.resume(with: .failure(ClaudeCodeAuthError.cancelled))
                } else {
                    completion.resume(with: .failure(error ?? ClaudeCodeAuthError.cancelled))
                }
                Task { @MainActor in self?.webSession = nil }
            }
            session.presentationContextProvider = self
            // Reuse an existing claude.ai browser sign-in when available.
            session.prefersEphemeralWebBrowserSession = false
            webSession = session

            if !session.start() {
                webSession = nil
                completion.resume(with: .failure(ClaudeCodeAuthError.callbackListenerUnavailable(
                    String(localized: "The sign-in browser could not be opened.")
                )))
            }
        }
    }

    private func finishWebSession() {
        webSession?.cancel()
        webSession = nil
    }
}

extension ClaudeCodeWebAuthorizationSession: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
                return window
            }
            return ASPresentationAnchor()
        }
    }
}

/// Resumes a continuation at most once; the loopback listener and the web
/// session can both report a result.
private final class ClaudeCodeCallbackCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<URL, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

// MARK: - Loopback Server

/// Minimal HTTP listener bound to the loopback interface that accepts the
/// OAuth redirect once and forwards the browser to the app's callback scheme.
final class ClaudeCodeLoopbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.studiofreesia.aium.claude-code-loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var hasDeliveredCallback = false
    private var _onCallback: (@Sendable (URL) -> Void)?
    private var _onFailure: (@Sendable (Error) -> Void)?

    var onCallback: (@Sendable (URL) -> Void)? {
        get { lock.withLock { _onCallback } }
        set { lock.withLock { _onCallback = newValue } }
    }

    var onFailure: (@Sendable (Error) -> Void)? {
        get { lock.withLock { _onFailure } }
        set { lock.withLock { _onFailure = newValue } }
    }

    /// Starts listening on an ephemeral loopback port and returns it.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw ClaudeCodeAuthError.callbackListenerUnavailable(error.localizedDescription)
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.listener = listener
                startContinuation = continuation
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = listener?.port?.rawValue {
                        self.resumeStart(with: .success(port))
                    } else {
                        self.resumeStart(with: .failure(ClaudeCodeAuthError.callbackListenerUnavailable("no port")))
                    }
                case .failed(let error):
                    let failure = ClaudeCodeAuthError.callbackListenerUnavailable(error.localizedDescription)
                    self.resumeStart(with: .failure(failure))
                    self.onFailure?(failure)
                case .cancelled:
                    self.resumeStart(with: .failure(ClaudeCodeAuthError.cancelled))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        let listener = lock.withLock { () -> NWListener? in
            let listener = self.listener
            self.listener = nil
            _onCallback = nil
            _onFailure = nil
            return listener
        }
        listener?.cancel()
    }

    // MARK: - Request handling

    private func resumeStart(with result: Result<UInt16, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<UInt16, Error>? in
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let response = Self.response(for: buffer) {
                if let callbackURL = response.callbackURL {
                    self.deliverCallback(callbackURL)
                }
                connection.send(content: response.data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else if isComplete || error != nil || buffer.count > 16_384 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func deliverCallback(_ url: URL) {
        let handler = lock.withLock { () -> (@Sendable (URL) -> Void)? in
            guard !hasDeliveredCallback else { return nil }
            hasDeliveredCallback = true
            return _onCallback
        }
        handler?(url)
    }

    struct Response {
        let data: Data
        /// Set when the request was the OAuth redirect.
        let callbackURL: URL?
    }

    /// Builds the HTTP response for a buffered request, or nil while the
    /// request headers are still incomplete.
    static func response(for request: Data) -> Response? {
        guard let headerEnd = request.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: request[..<headerEnd.lowerBound], encoding: .utf8)
        else { return nil }

        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let target = URLComponents(string: String(parts[1])),
              target.path == ClaudeCodeOAuthConfig.loopbackCallbackPath
        else {
            return Response(data: httpResponse(status: "404 Not Found", headers: [:]), callbackURL: nil)
        }

        var callback = URLComponents()
        callback.scheme = ClaudeCodeOAuthConfig.callbackScheme
        callback.host = "oauth"
        callback.path = ClaudeCodeOAuthConfig.loopbackCallbackPath
        callback.percentEncodedQuery = target.percentEncodedQuery
        guard let callbackURL = callback.url else {
            return Response(data: httpResponse(status: "400 Bad Request", headers: [:]), callbackURL: nil)
        }

        return Response(
            data: httpResponse(
                status: "302 Found",
                headers: ["Location": callbackURL.absoluteString, "Cache-Control": "no-store"]
            ),
            callbackURL: callbackURL
        )
    }

    private static func httpResponse(status: String, headers: [String: String]) -> Data {
        var lines = ["HTTP/1.1 \(status)"]
        lines += headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        lines += ["Content-Length: 0", "Connection: close", "", ""]
        return Data(lines.joined(separator: "\r\n").utf8)
    }
}
