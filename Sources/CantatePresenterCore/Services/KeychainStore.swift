import Foundation
import Security
import os

// MARK: - Secret Store

/// Miejsce na sekrety (Pęk kluczy; w testach zastępowane).
public protocol SecretStore: Sendable {
    /// `nil` tylko wtedy, gdy wpisu nie ma. Odmowa dostępu albo zablokowany pęk kluczy to błąd,
    /// a nie „brak danych” (R3-04).
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func delete(_ account: String) throws
}

// MARK: - Keychain Store

/// Ogólne hasła w Pęku kluczy użytkownika dla jednej usługi.
public struct KeychainStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func data(for account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status, service: service)
        }
    }

    public func set(_ data: Data, for account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus, service: service) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status, service: service)
        }
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, service: service)
        }
    }
}

public struct KeychainError: LocalizedError {
    public let status: OSStatus
    public var service: String = ""

    /// Pęk kluczy nie dał dostępu: użytkownik odmówił, pęk jest zablokowany albo wpis należy do innego podpisu
    /// aplikacji (podpis ad-hoc zmienia się z każdą wersją, docs/RELEASE.md).
    public var isAccessDenied: Bool {
        [errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed, errSecNoAccessForItem].contains(status)
    }

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "kod \(status)"
        if isAccessDenied {
            return Lnow("Pęk kluczy nie udostępnił danych logowania ({0}). Pozwól na dostęp, gdy macOS o to zapyta, albo usuń wpis „{1}” w aplikacji Dostęp do pęku kluczy i połącz konto Google ponownie.", message, service)
        }
        return Lnow("Błąd Pęku kluczy: {0}", message)
    }
}

// MARK: - Google Credentials

/// Tokeny Google Drive użytkownika. Trzymane wyłącznie w Pęku kluczy, nigdy w `settings.json` ani w kopiach zapasowych (W4).
public struct GoogleCredentials: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date?

    public init(accessToken: String = "", refreshToken: String = "", expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isSignedIn: Bool { !refreshToken.isEmpty || !accessToken.isEmpty }

    /// Odświeżamy minutę przed wygaśnięciem; token bez znanego terminu też odświeżamy (W3).
    public func needsRefresh(now: Date = Date()) -> Bool {
        guard !accessToken.isEmpty, let expiresAt else { return true }
        return expiresAt.timeIntervalSince(now) < 60
    }

    /// Zapisuje odpowiedź z endpointu tokenu. Google przy odświeżeniu zwykle nie zwraca nowego refresh tokenu.
    public mutating func apply(tokenResponse data: Data, now: Date = Date()) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            throw NSError(domain: "GoogleDrive", code: 3, userInfo: [NSLocalizedDescriptionKey: Lnow("Brak access_token w odpowiedzi Google")])
        }
        accessToken = access
        if let refresh = json["refresh_token"] as? String, !refresh.isEmpty {
            refreshToken = refresh
        }
        if let seconds = json["expires_in"] as? Double {
            expiresAt = now.addingTimeInterval(seconds)
        } else {
            expiresAt = nil
        }
    }
}

// MARK: - Google Credential Store

public struct GoogleCredentialStore: Sendable {
    public static let shared = GoogleCredentialStore(keychain: KeychainStore(service: "com.cantate.presenter.gdrive"))
    private static let account = "credentials"
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "gdrive")

    private let keychain: any SecretStore

    public init(keychain: any SecretStore) {
        self.keychain = keychain
    }

    /// Puste dane, gdy wpisu nie ma albo jest nieczytelny; błąd Pęku kluczy (np. odmowa dostępu) jest zgłaszany,
    /// żeby nie udawać „niepołączonego konta” (R3-04).
    public func load() throws -> GoogleCredentials {
        let data: Data?
        do {
            data = try keychain.data(for: Self.account)
        } catch {
            Self.logger.error("Nie można odczytać danych Google z Pęku kluczy: \(String(describing: error), privacy: .public)")
            throw error
        }
        guard let data else { return GoogleCredentials() }
        do {
            return try JSONDecoder().decode(GoogleCredentials.self, from: data)
        } catch {
            Self.logger.error("Nieczytelne dane Google w Pęku kluczy: \(String(describing: error), privacy: .public)")
            return GoogleCredentials()
        }
    }

    public func save(_ credentials: GoogleCredentials) throws {
        do {
            try keychain.set(try JSONEncoder().encode(credentials), for: Self.account)
        } catch {
            Self.logger.error("Nie można zapisać danych Google w Pęku kluczy: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public func update(_ change: (inout GoogleCredentials) -> Void) throws {
        var credentials = try load()
        change(&credentials)
        try save(credentials)
    }

    public func clear() throws {
        do {
            try keychain.delete(Self.account)
        } catch {
            Self.logger.error("Nie można usunąć danych Google z Pęku kluczy: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
