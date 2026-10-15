import Foundation
import Security
import os

// MARK: - Keychain Store

/// Ogólne hasła w Pęku kluczy użytkownika dla jednej usługi.
public struct KeychainStore {
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

    public func data(for account: String) -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public func set(_ data: Data, for account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

public struct KeychainError: LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "kod \(status)"
        return "Błąd Pęku kluczy: \(message)"
    }
}

// MARK: - Google Credentials

/// Tokeny Google Drive użytkownika. Trzymane wyłącznie w Pęku kluczy, nigdy w `settings.json` ani w kopiach zapasowych (W4).
public struct GoogleCredentials: Codable, Equatable {
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
            throw NSError(domain: "GoogleDrive", code: 3, userInfo: [NSLocalizedDescriptionKey: "Brak access_token w odpowiedzi Google"])
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

public struct GoogleCredentialStore {
    public static let shared = GoogleCredentialStore(keychain: KeychainStore(service: "com.cantate.presenter.gdrive"))
    private static let account = "credentials"
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "gdrive")

    private let keychain: KeychainStore

    public init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    public func load() -> GoogleCredentials {
        guard let data = keychain.data(for: Self.account),
              let credentials = try? JSONDecoder().decode(GoogleCredentials.self, from: data) else {
            return GoogleCredentials()
        }
        return credentials
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
        var credentials = load()
        change(&credentials)
        try save(credentials)
    }

    public func clear() {
        keychain.delete(Self.account)
    }
}
