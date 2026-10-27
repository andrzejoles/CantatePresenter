import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - W3: logowanie Google (loopback + PKCE) i odświeżanie tokenu

@Suite("Google OAuth (W3)")
struct GoogleOAuthTests {
    @Test("PKCE: wektor testowy z RFC 7636")
    func pkceChallengeMatchesRFC() {
        #expect(GoogleOAuth.PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("PKCE: losowy weryfikator ma 64 dozwolone znaki")
    func pkceVerifier() {
        let pkce = GoogleOAuth.PKCE()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(pkce.verifier.count == 64)
        #expect(pkce.verifier.unicodeScalars.allSatisfy(allowed.contains))
        #expect(GoogleOAuth.PKCE().verifier != pkce.verifier)
    }

    @Test("state: 24 losowe bajty w base64url, za każdym razem inne")
    func randomState() {
        let states = (0..<50).map { _ in GoogleOAuth.randomState() }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(states.allSatisfy { $0.count == 32 && $0.unicodeScalars.allSatisfy(allowed.contains) })
        #expect(Set(states).count == states.count)
        #expect(!states.contains(GoogleOAuth.base64URL(Data(count: 24))))
    }

    @Test("Adres logowania: loopback, PKCE S256, state, bez zablokowanego oob")
    func authorizationURL() throws {
        let url = try #require(GoogleOAuth.authorizationURL(
            clientId: "abc.apps.googleusercontent.com",
            redirectURI: "http://127.0.0.1:53682",
            codeChallenge: "wyzwanie",
            state: "stan"
        ))
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(items["redirect_uri"] == "http://127.0.0.1:53682")
        #expect(items["code_challenge"] == "wyzwanie")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["state"] == "stan")
        #expect(items["access_type"] == "offline")
        #expect(!url.absoluteString.contains("oob"))
    }

    @Test("Odczyt przekierowania z kodem")
    func parsesCallback() throws {
        let callback = try GoogleOAuth.parseCallback(requestLine: "GET /?state=xyz&code=4%2F0AbCd&scope=drive HTTP/1.1")
        #expect(callback.code == "4/0AbCd")
        #expect(callback.state == "xyz")
    }

    @Test("Odmowa dostępu w przekierowaniu to błąd")
    func callbackWithError() {
        #expect(throws: (any Error).self) {
            try GoogleOAuth.parseCallback(requestLine: "GET /?error=access_denied&state=xyz HTTP/1.1")
        }
    }

    @Test("Serwer loopback odbiera przekierowanie z przeglądarki; obce żądania bez state nie kończą logowania (R3-03)")
    func loopbackServerReceivesCode() async throws {
        let server = GoogleOAuth.LoopbackServer(expectedState: "stan")
        let port = try await server.start()
        #expect(port > 0)

        async let callback = server.waitForCallback(timeout: .seconds(5))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        // Inna strona albo proces skanuje porty: błąd bez właściwego state nie przerywa logowania.
        let foreign = try #require(URL(string: "http://127.0.0.1:\(port)/?error=%3Cimg%20src%3Dx%3E&state=obcy"))
        let (_, rejected) = try await session.data(from: foreign)
        #expect((rejected as? HTTPURLResponse)?.statusCode == 404)

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/?code=kod123&state=stan"))
        let (data, response) = try await session.data(from: url)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("default-src 'none'") == true)
        #expect(String(decoding: data, as: UTF8.self).contains("CantatePresenter"))
        let received = try await callback
        #expect(received.code == "kod123")
        #expect(received.state == "stan")
    }

    @Test("Przekierowanie: tylko z oczekiwanym state; treść błędu nie trafia do HTML bez escapowania (R3-03)")
    func callbackRequiresStateAndEscapes() throws {
        #expect(GoogleOAuth.callbackOutcome(requestLine: "GET /?code=k&state=inny HTTP/1.1", expectedState: "stan") == nil)
        #expect(GoogleOAuth.callbackOutcome(requestLine: "GET /?code=k HTTP/1.1", expectedState: "stan") == nil)
        #expect(GoogleOAuth.callbackOutcome(requestLine: "GET /favicon.ico HTTP/1.1", expectedState: "stan") == nil)
        #expect(GoogleOAuth.callbackOutcome(requestLine: "GET /?state=stan HTTP/1.1", expectedState: "stan") == nil)
        let success = try #require(GoogleOAuth.callbackOutcome(requestLine: "GET /?code=k&state=stan HTTP/1.1", expectedState: "stan"))
        #expect(try success.get() == GoogleOAuth.Callback(code: "k", state: "stan"))

        let denied = try #require(GoogleOAuth.callbackOutcome(
            requestLine: "GET /?error=%3Cb%3Ex%22%26%3C%2Fb%3E&state=stan HTTP/1.1", expectedState: "stan"))
        #expect(throws: (any Error).self) { try denied.get() }
        let page = String(decoding: GoogleOAuth.loopbackHTTPResponse(for: denied), as: UTF8.self)
        #expect(page.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(!page.contains("<b>") && page.contains("&lt;b&gt;x&quot;&amp;&lt;/b&gt;"))
        #expect(page.contains("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\n"))
        #expect(String(decoding: GoogleOAuth.loopbackHTTPResponse(for: nil), as: UTF8.self).hasPrefix("HTTP/1.1 404 Not Found\r\n"))
    }

    @Test("Odpowiedź z tokenem: czas wygaśnięcia i zachowanie starego refresh tokenu")
    func tokenResponse() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let json = Data(#"{"access_token":"nowy","expires_in":3599,"token_type":"Bearer"}"#.utf8)
        var credentials = GoogleCredentials(accessToken: "stary", refreshToken: "odśwież", expiresAt: nil)

        try credentials.apply(tokenResponse: json, now: now)

        #expect(credentials.accessToken == "nowy")
        #expect(credentials.refreshToken == "odśwież")
        #expect(credentials.expiresAt == now.addingTimeInterval(3599))
    }

    @Test("Token jest odświeżany minutę przed wygaśnięciem")
    func refreshWindow() {
        let now = Date()
        func credentials(expiresIn seconds: TimeInterval?) -> GoogleCredentials {
            GoogleCredentials(accessToken: "t", refreshToken: "r", expiresAt: seconds.map { now.addingTimeInterval($0) })
        }
        #expect(!credentials(expiresIn: 600).needsRefresh(now: now))
        #expect(credentials(expiresIn: 30).needsRefresh(now: now))
        #expect(credentials(expiresIn: nil).needsRefresh(now: now))
        #expect(GoogleCredentials(accessToken: "", refreshToken: "r", expiresAt: nil).needsRefresh(now: now))
    }

    @Test("Po 401 token jest odświeżany i żądanie ponawiane raz")
    func retriesOnceAfterUnauthorized() async throws {
        var tokens: [Bool] = []
        var statuses = [401, 200]
        let requester = GoogleOAuth.AuthorizedRequester(
            token: { forceRefresh in tokens.append(forceRefresh); return forceRefresh ? "świeży" : "stary" },
            send: { request in
                let status = statuses.removeFirst()
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (Data(request.value(forHTTPHeaderField: "Authorization")!.utf8), response)
            }
        )

        let (data, response) = try await requester.data(for: URLRequest(url: URL(string: "https://example.com")!))

        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "Bearer świeży")
        #expect(tokens == [false, true])
    }

    @Test("Apostrof w nazwie folderu jest escapowany w zapytaniu Dysku")
    func escapesDriveQuery() {
        #expect(GoogleDriveService.escapeQueryValue("Kopie O'Neil") == #"Kopie O\'Neil"#)
        #expect(GoogleDriveService.escapeQueryValue(#"a\b"#) == #"a\\b"#)
    }
}

// MARK: - W4: sekrety w Pęku kluczy, nie w settings.json

@Suite("Dane logowania Google w Pęku kluczy (W4)", .serialized)
struct GoogleCredentialStoreTests {
    private func makeStore() -> GoogleCredentialStore {
        GoogleCredentialStore(keychain: KeychainStore(service: "com.cantate.presenter.tests.\(UUID().uuidString)"))
    }

    @Test("Zapis, odczyt i usunięcie w Pęku kluczy")
    func keychainRoundTrip() throws {
        let store = makeStore()
        defer { try? store.clear() }
        let credentials = GoogleCredentials(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 5))

        try store.save(credentials)
        #expect(try store.load() == credentials)

        try store.clear()
        #expect(try store.load() == GoogleCredentials())
        try store.clear()
    }

    @Test("Stary settings.json z tokenami: sekrety trafiają do Pęku kluczy i znikają z JSON")
    func migratesLegacySecrets() throws {
        let store = makeStore()
        defer { try? store.clear() }
        let legacy = Data(#"""
        {"isEnabled": true, "accountEmail": "ktos@example.com", "clientId": "id", "clientSecret": "sekret",
         "accessToken": "dostęp", "refreshToken": "odśwież", "targetFolder": "Kopie", "autoBackupOnExit": true}
        """#.utf8)

        var settings = try JSONDecoder().decode(GoogleDriveSettings.self, from: legacy)
        #expect(settings.hasLegacySecrets)
        try settings.migrateLegacySecrets(into: store)

        #expect(!settings.hasLegacySecrets)
        #expect(try store.load().refreshToken == "odśwież")
        let encoded = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        #expect(!encoded.contains("sekret"))
        #expect(!encoded.contains("odśwież"))
        #expect(!encoded.contains("accessToken"))
        #expect(encoded.contains("Kopie"))
    }

    @Test("Klient OAuth wbudowany w Info.plist; brak klienta wyłącza logowanie")
    func bundledClient() {
        #expect(GoogleOAuth.Client(infoDictionary: ["CantateGoogleClientID": "id.apps", "CantateGoogleClientSecret": "s"]) == GoogleOAuth.Client(id: "id.apps", secret: "s"))
        #expect(GoogleOAuth.Client(infoDictionary: ["CantateGoogleClientID": ""]) == nil)
        #expect(GoogleOAuth.Client(infoDictionary: nil) == nil)
    }

    @Test("Domyślny e-mail konta jest pusty")
    func defaultEmailIsEmpty() {
        #expect(GoogleDriveSettings().accountEmail.isEmpty)
    }
}

// MARK: - Komunikaty błędów Dysku

@Suite("Błędy API Dysku Google")
struct GoogleDriveErrorTests {
    @Test("Wyłączone Drive API: wskazówka i komunikat Google")
    func apiDisabled() {
        let body = Data(#"{"error":{"code":403,"message":"Google Drive API has not been used in project 742 before or it is disabled.","errors":[{"reason":"accessNotConfigured"}]}}"#.utf8)
        let text = GoogleDriveService.apiError(code: 9, "Nie udało się utworzyć folderu", status: 403, data: body).localizedDescription

        #expect(text.contains("HTTP 403"))
        #expect(text.contains("Drive API nie jest włączone"))
        #expect(text.contains("has not been used"))
    }

    @Test("Brak uprawnienia do Dysku: wskazówka o ponownym połączeniu")
    func insufficientScope() {
        let body = Data(#"{"error":{"code":403,"message":"Request had insufficient authentication scopes.","details":[{"reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#.utf8)
        #expect(GoogleDriveService.apiError(code: 9, "x", status: 403, data: body).localizedDescription.contains("Brak zgody na dostęp do Dysku"))
    }
}

// MARK: - Dysk Google bez sieci i bez prawdziwego Pęku kluczy (R3-02, R3-04, R3-12)

/// Sekrety w pamięci; `failure` udaje odmowę dostępu Pęku kluczy.
final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    var failure: OSStatus? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }
    private var _failure: OSStatus?

    func data(for account: String) throws -> Data? {
        try lock.withLock {
            if let status = _failure { throw KeychainError(status: status, service: "test") }
            return items[account]
        }
    }

    func set(_ data: Data, for account: String) throws {
        try lock.withLock {
            if let status = _failure { throw KeychainError(status: status, service: "test") }
            items[account] = data
        }
    }

    func delete(_ account: String) throws {
        try lock.withLock {
            if let status = _failure { throw KeychainError(status: status, service: "test") }
            items[account] = nil
        }
    }
}

/// Podstawione HTTP: zapisuje żądania i odpowiada kolejno z listy (albo rzuca błąd sieci).
final class FakeHTTP: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)]) {
        self.responses = responses
    }

    var sent: [URLRequest] { lock.withLock { requests } }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        try lock.withLock {
            requests.append(request)
            guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
            let (status, body) = responses.removeFirst()
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

@Suite("Dysk Google: folder kopii, odwołanie dostępu, błędy Pęku kluczy")
struct GoogleDriveServiceTests {
    private func makeService(_ http: FakeHTTP, secrets: MemorySecretStore = MemorySecretStore()) throws -> (GoogleDriveService, GoogleCredentialStore) {
        let store = GoogleCredentialStore(keychain: secrets)
        try store.save(GoogleCredentials(accessToken: "dostęp", refreshToken: "odśwież", expiresAt: Date().addingTimeInterval(3600)))
        return (GoogleDriveService(credentialStore: store, send: { try http.send($0) }), store)
    }

    @Test("Błąd wyszukiwania folderu nie tworzy drugiego folderu (R3-02)")
    func searchErrorDoesNotCreateFolder() async throws {
        let http = FakeHTTP([(500, #"{"error":{"message":"Backend Error"}}"#)])
        let (service, _) = try makeService(http)
        await #expect(throws: (any Error).self) { _ = try await service.getOrCreateBackupsFolder(folderName: "Kopie") }
        #expect(http.sent.count == 1)
        #expect(http.sent.allSatisfy { ($0.httpMethod ?? "GET") == "GET" })
    }

    @Test("Nazwa folderu z & i + jest zakodowana w całości; brak folderu: jeden POST (R3-02)")
    func folderNameIsEncoded() async throws {
        let http = FakeHTTP([(200, #"{"files":[]}"#), (200, #"{"id":"nowy"}"#)])
        let (service, _) = try makeService(http)
        let id = try await service.getOrCreateBackupsFolder(folderName: "a&b+c ł")
        #expect(id == "nowy")
        let search = try #require(http.sent.first?.url?.absoluteString)
        #expect(search.contains("a%26b%2Bc%20%C5%82"))
        #expect(!search.contains("&b+c"))
        let query = try #require(URLComponents(string: search)?.queryItems?.first { $0.name == "q" }?.value)
        #expect(query.hasPrefix("name = 'a&b+c ł' and"))
        #expect(http.sent.count == 2 && http.sent[1].httpMethod == "POST")
    }

    @Test("Istniejący folder: bez tworzenia nowego")
    func existingFolder() async throws {
        let http = FakeHTTP([(200, #"{"files":[{"id":"stary","name":"Kopie"}]}"#)])
        let (service, _) = try makeService(http)
        #expect(try await service.getOrCreateBackupsFolder(folderName: "Kopie") == "stary")
        #expect(http.sent.count == 1)
    }

    @Test("Rozłączenie odwołuje refresh token w Google i usuwa tokeny (R3-12)")
    func signOutRevokes() async throws {
        let http = FakeHTTP([(200, "")])
        let (service, store) = try makeService(http)
        #expect(try await service.signOut())
        let revoke = try #require(http.sent.first)
        #expect(revoke.url?.absoluteString == "https://oauth2.googleapis.com/revoke" && revoke.httpMethod == "POST")
        #expect(String(decoding: revoke.httpBody ?? Data(), as: UTF8.self) == "token=od%C5%9Bwie%C5%BC")
        #expect(try store.load() == GoogleCredentials())
        #expect(try !service.signInState())
    }

    @Test("Bez internetu tokeny i tak znikają z Pęku kluczy, a wynik mówi o braku odwołania (R3-12)")
    func signOutOffline() async throws {
        let http = FakeHTTP([])
        let (service, store) = try makeService(http)
        #expect(try await !service.signOut())
        #expect(http.sent.count == 1)
        #expect(try store.load() == GoogleCredentials())
    }

    @Test("Odmowa dostępu Pęku kluczy to błąd Pęku kluczy, a nie „brak połączenia z kontem” (R3-04)")
    func keychainDenied() async throws {
        let secrets = MemorySecretStore()
        let (service, store) = try makeService(FakeHTTP([]), secrets: secrets)
        secrets.failure = errSecUserCanceled

        #expect(throws: KeychainError.self) { try store.load() }
        #expect(throws: KeychainError.self) { try service.signInState() }
        do {
            _ = try await service.getValidAccessToken()
            Issue.record("Oczekiwany błąd Pęku kluczy")
        } catch let error as KeychainError {
            #expect(error.isAccessDenied)
            #expect(error.localizedDescription.contains("test"))
        } catch {
            Issue.record("Inny błąd: \(error)")
        }
        await #expect(throws: KeychainError.self) { try await service.signOut() }
    }
}
