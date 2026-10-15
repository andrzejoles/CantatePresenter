import Foundation
import CryptoKit
import Network

// MARK: - Google OAuth

/// Logowanie Google dla aplikacji desktopowej (W3): przekierowanie na loopback `http://127.0.0.1:<port>`
/// z PKCE i `state`, zgodnie z zaleceniem Google po wyłączeniu przepływu „oob”.
public enum GoogleOAuth {
    public static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    public static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    public static let scopes = "https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/userinfo.email"

    // MARK: - Client
    
    /// Klient OAuth aplikacji („Aplikacja komputerowa”), wbudowany przez `build_app.sh` w Info.plist.
    /// To identyfikator aplikacji wobec Google, nie konto: każdy użytkownik loguje się własnym kontem.
    /// Google nie traktuje sekretu klienta desktopowego jako tajemnicy, ale nie trzymamy go w repozytorium.
    public struct Client: Equatable {
        public let id: String
        public let secret: String
        
        public init(id: String, secret: String) {
            self.id = id
            self.secret = secret
        }
        
        public init?(infoDictionary: [String: Any]?) {
            guard let id = infoDictionary?["CantateGoogleClientID"] as? String, !id.isEmpty else { return nil }
            self.init(id: id, secret: infoDictionary?["CantateGoogleClientSecret"] as? String ?? "")
        }
        
        public static let bundled = Client(infoDictionary: Bundle.main.infoDictionary)
    }
    
    // MARK: - PKCE

    public struct PKCE {
        public let verifier: String
        public var challenge: String { Self.challenge(for: verifier) }

        private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        public init() {
            var generator = SystemRandomNumberGenerator()
            verifier = String((0..<64).map { _ in Self.alphabet.randomElement(using: &generator)! })
        }

        /// `BASE64URL(SHA256(verifier))` bez dopełnienia (RFC 7636, metoda S256).
        public static func challenge(for verifier: String) -> String {
            base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        }
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    // MARK: - URLs and Requests

    public static func authorizationURL(clientId: String, redirectURI: String, codeChallenge: String, state: String) -> URL? {
        var components = URLComponents(string: authorizationEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }

    /// Żądanie `application/x-www-form-urlencoded` do endpointu tokenu.
    public static func tokenRequest(_ parameters: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = parameters
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    // MARK: - Callback

    public struct Callback: Equatable {
        public let code: String
        public let state: String
    }

    public enum OAuthError: LocalizedError {
        case denied(String)
        case missingCode
        case stateMismatch
        case timedOut
        case listenerFailed(String)

        public var errorDescription: String? {
            switch self {
            case .denied(let reason): return "Google odmówił dostępu: \(reason)."
            case .missingCode: return "Przekierowanie z Google nie zawiera kodu autoryzacji."
            case .stateMismatch: return "Odpowiedź logowania nie pasuje do tego żądania (parametr state). Spróbuj ponownie."
            case .timedOut: return "Logowanie nie zostało dokończone w przeglądarce w wyznaczonym czasie."
            case .listenerFailed(let reason): return "Nie można uruchomić lokalnego odbiornika logowania: \(reason)."
            }
        }
    }

    /// Odczytuje pierwszą linię żądania HTTP, np. `GET /?code=…&state=… HTTP/1.1`.
    public static func parseCallback(requestLine: String) throws -> Callback {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, let components = URLComponents(string: "http://127.0.0.1" + parts[1]) else {
            throw OAuthError.missingCode
        }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        if let error = items["error"] {
            throw OAuthError.denied(error)
        }
        guard let code = items["code"], !code.isEmpty else {
            throw OAuthError.missingCode
        }
        return Callback(code: code, state: items["state"] ?? "")
    }

    // MARK: - Loopback Server

    /// Jednorazowy serwer HTTP na `127.0.0.1` z losowym portem, który odbiera przekierowanie z przeglądarki.
    public final class LoopbackServer: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.cantate.presenter.oauth-loopback")
        private var listener: NWListener?
        private var result: Result<Callback, Error>?
        private var waiter: CheckedContinuation<Callback, Error>?
        private var startContinuation: CheckedContinuation<UInt16, Error>?

        public init() {}

        public func start() async throws -> UInt16 {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            let listener: NWListener
            do {
                listener = try NWListener(using: parameters)
            } catch {
                throw OAuthError.listenerFailed(error.localizedDescription)
            }
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: OAuthError.listenerFailed("odbiornik zwolniony"))
                        return
                    }
                    self.startContinuation = continuation
                    listener.stateUpdateHandler = { [weak self] state in
                        self?.listenerStateChanged(state)
                    }
                    listener.start(queue: self.queue)
                }
            }
        }
        
        /// Wywoływane na `queue`.
        private func listenerStateChanged(_ state: NWListener.State) {
            guard let continuation = startContinuation else { return }
            switch state {
            case .ready:
                startContinuation = nil
                continuation.resume(returning: listener?.port?.rawValue ?? 0)
            case .failed(let error):
                startContinuation = nil
                continuation.resume(throwing: OAuthError.listenerFailed(error.localizedDescription))
            default:
                break
            }
        }

        public func waitForCallback(timeout: Duration) async throws -> Callback {
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.queue.async { self?.finish(.failure(OAuthError.timedOut)) }
            }
            defer { timeoutTask.cancel() }
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let result = self.result {
                        continuation.resume(with: result)
                    } else {
                        self.waiter = continuation
                    }
                }
            }
        }

        public func stop() {
            queue.async {
                self.listener?.cancel()
                self.listener = nil
            }
        }

        private func finish(_ outcome: Result<Callback, Error>) {
            guard result == nil else { return }
            result = outcome
            listener?.cancel()
            listener = nil
            if let waiter {
                self.waiter = nil
                waiter.resume(with: outcome)
            }
        }

        private func handle(_ connection: NWConnection) {
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
                guard let self else { return }
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let requestLine = request.components(separatedBy: "\r\n").first ?? ""
                let outcome: Result<Callback, Error>?
                do {
                    outcome = .success(try GoogleOAuth.parseCallback(requestLine: requestLine))
                } catch OAuthError.missingCode {
                    // Np. /favicon.ico: czekamy dalej na właściwe przekierowanie.
                    outcome = nil
                } catch {
                    outcome = .failure(error)
                }
                let body: String
                switch outcome {
                case .success: body = "Zalogowano. Możesz zamknąć tę kartę i wrócić do CantatePresenter."
                case .failure(let error): body = "Logowanie nie powiodło się: \(error.localizedDescription)"
                case nil: body = ""
                }
                let html = "<!doctype html><meta charset=\"utf-8\"><title>CantatePresenter</title><body style=\"font-family:-apple-system;padding:40px\"><h2>CantatePresenter</h2><p>\(body)</p></body>"
                let status = outcome == nil ? "404 Not Found" : "200 OK"
                let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                if let outcome {
                    self.finish(outcome)
                }
            }
        }
    }

    // MARK: - Authorized Requests

    /// Wysyła żądanie z tokenem; po 401 wymusza odświeżenie tokenu i ponawia raz (W3).
    public struct AuthorizedRequester {
        public var token: (_ forceRefresh: Bool) async throws -> String
        public var send: (URLRequest) async throws -> (Data, HTTPURLResponse)

        public init(
            token: @escaping (_ forceRefresh: Bool) async throws -> String,
            send: @escaping (URLRequest) async throws -> (Data, HTTPURLResponse)
        ) {
            self.token = token
            self.send = send
        }

        public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            var authorized = request
            authorized.setValue("Bearer \(try await token(false))", forHTTPHeaderField: "Authorization")
            let (data, response) = try await send(authorized)
            guard response.statusCode == 401 else { return (data, response) }
            authorized.setValue("Bearer \(try await token(true))", forHTTPHeaderField: "Authorization")
            return try await send(authorized)
        }
    }
}
