import Foundation
import AppKit

public struct RemoteBackupItem: Identifiable, Codable {
    public let id: String
    public let name: String
    public let size: Int64?
    public let createdTime: Date?
    public let modifiedTime: Date?
    
    public var formattedSize: String {
        guard let size = size else { return "Nieznany" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    public var formattedDate: String {
        guard let date = createdTime ?? modifiedTime else { return "Nieznana data" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

public final class GoogleDriveService {
    public static let shared = GoogleDriveService()
    
    private let driveFilesEndpoint = "https://www.googleapis.com/drive/v3/files"
    private let driveUploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
    private let userInfoEndpoint = "https://www.googleapis.com/oauth2/v2/userinfo"
    
    private init() {}
    
    private let credentialStore = GoogleCredentialStore.shared
    
    // MARK: - Sign In (W3: loopback + PKCE)
    
    /// Czy ta kompilacja ma wbudowanego klienta OAuth (patrz `build_app.sh`).
    public var isSignInAvailable: Bool { GoogleOAuth.Client.bundled != nil }
    
    private func bundledClient() throws -> GoogleOAuth.Client {
        guard let client = GoogleOAuth.Client.bundled else {
            throw NSError(domain: "GoogleDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ta wersja aplikacji nie ma skonfigurowanego logowania Google."])
        }
        return client
    }
    
    /// Otwiera logowanie Google w przeglądarce, odbiera kod na lokalnym porcie i zapisuje tokeny w Pęku kluczy.
    /// Użytkownik loguje się własnym kontem; kopie trafiają na jego Dysk. Zwraca adres e-mail konta.
    public func signIn() async throws -> String {
        let client = try bundledClient()
        
        let pkce = GoogleOAuth.PKCE()
        let state = GoogleOAuth.randomState()
        let server = GoogleOAuth.LoopbackServer()
        let port = try await server.start()
        defer { server.stop() }
        let redirectURI = "http://127.0.0.1:\(port)"
        
        guard let authURL = GoogleOAuth.authorizationURL(clientId: client.id, redirectURI: redirectURI, codeChallenge: pkce.challenge, state: state) else {
            throw NSError(domain: "GoogleDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nie można zbudować adresu logowania Google."])
        }
        await MainActor.run { _ = NSWorkspace.shared.open(authURL) }
        
        let callback = try await server.waitForCallback(timeout: .seconds(300))
        guard callback.state == state else { throw GoogleOAuth.OAuthError.stateMismatch }
        
        let request = GoogleOAuth.tokenRequest([
            "code": callback.code,
            "client_id": client.id,
            "client_secret": client.secret,
            "code_verifier": pkce.verifier,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Błąd sieci"
            throw NSError(domain: "GoogleDrive", code: 2, userInfo: [NSLocalizedDescriptionKey: "Błąd wymiany kodu autoryzacji: \(errorText)"])
        }
        // Google pozwala odznaczyć poszczególne uprawnienia na ekranie zgody; bez Dysku kopie nie zadziałają.
        let grantedScopes = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["scope"] as? String) ?? ""
        guard grantedScopes.isEmpty || grantedScopes.contains("https://www.googleapis.com/auth/drive.file") else {
            throw NSError(domain: "GoogleDrive", code: 17, userInfo: [NSLocalizedDescriptionKey: "Nie udzielono dostępu do Dysku Google. Połącz ponownie i na ekranie zgody zaznacz dostęp do plików na Dysku."])
        }
        var credentials = credentialStore.load()
        try credentials.apply(tokenResponse: data)
        try credentialStore.save(credentials)
        
        return (try? await fetchUserEmail(accessToken: credentials.accessToken)) ?? ""
    }
    
    /// Usuwa tokeny użytkownika z Pęku kluczy.
    public func signOut() {
        credentialStore.clear()
    }
    
    public var isSignedIn: Bool { credentialStore.load().isSignedIn }
    
    public func fetchUserEmail(accessToken: String) async throws -> String {
        guard let url = URL(string: userInfoEndpoint) else { return "" }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return ""
        }
        return email
    }
    
    // MARK: - Token Refresh (W3)
    
    /// Zwraca ważny token; odświeża go przed wygaśnięciem albo na żądanie (po 401).
    public func getValidAccessToken(forceRefresh: Bool = false) async throws -> String {
        var credentials = credentialStore.load()
        if !forceRefresh && !credentials.needsRefresh() {
            return credentials.accessToken
        }
        guard !credentials.refreshToken.isEmpty else {
            throw NSError(domain: "GoogleDrive", code: 4, userInfo: [NSLocalizedDescriptionKey: "Brak połączenia z kontem Google. Połącz konto w Ustawieniach → Dysk Google."])
        }
        let client = try bundledClient()
        
        let request = GoogleOAuth.tokenRequest([
            "client_id": client.id,
            "client_secret": client.secret,
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Błąd odświeżania"
            throw NSError(domain: "GoogleDrive", code: 6, userInfo: [NSLocalizedDescriptionKey: "Nie udało się odświeżyć tokenu Google: \(errorText)"])
        }
        try credentials.apply(tokenResponse: data)
        try credentialStore.save(credentials)
        return credentials.accessToken
    }
    
    private var requester: GoogleOAuth.AuthorizedRequester {
        GoogleOAuth.AuthorizedRequester(
            token: { [unowned self] forceRefresh in try await self.getValidAccessToken(forceRefresh: forceRefresh) },
            send: { request in
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "GoogleDrive", code: 16, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowa odpowiedź serwera Google"])
                }
                return (data, httpResponse)
            }
        )
    }
    
    /// Błąd API Dysku z powodem podanym przez Google i wskazówką dla typowych przyczyn.
    static func apiError(code: Int, _ summary: String, status: Int, data: Data) -> NSError {
        var reason = ""
        var message = String(data: data, encoding: .utf8) ?? ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any] {
            message = error["message"] as? String ?? message
            let errors = error["errors"] as? [[String: Any]]
            let details = error["details"] as? [[String: Any]]
            reason = (errors?.first?["reason"] as? String) ?? (details?.compactMap { $0["reason"] as? String }.first) ?? ""
        }
        let hint: String
        switch reason {
        case "accessNotConfigured", "SERVICE_DISABLED":
            hint = "Google Drive API nie jest włączone w projekcie Google Cloud aplikacji."
        case "insufficientPermissions", "ACCESS_TOKEN_SCOPE_INSUFFICIENT":
            hint = "Brak zgody na dostęp do Dysku. Rozłącz konto, połącz ponownie i zaznacz dostęp do plików na Dysku."
        case "authError", "UNAUTHENTICATED":
            hint = "Sesja Google wygasła. Rozłącz konto i połącz ponownie."
        default:
            hint = ""
        }
        let text = [summary + " (HTTP \(status)).", hint, message.isEmpty ? "" : "Odpowiedź Google: \(message)"]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return NSError(domain: "GoogleDrive", code: code, userInfo: [NSLocalizedDescriptionKey: text])
    }
    
    /// Wartość w zapytaniu `q` Dysku Google: escapowanie `\` i `'` (W3).
    public static func escapeQueryValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
    
    // MARK: - Folder Management
    
    public func getOrCreateBackupsFolder(folderName: String = "CantatePresenter_Backups") async throws -> String {
        // 1. Search for existing folder
        let query = "name = '\(Self.escapeQueryValue(folderName))' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(driveFilesEndpoint)?q=\(encodedQuery)&fields=files(id,name)") else {
            throw NSError(domain: "GoogleDrive", code: 7, userInfo: [NSLocalizedDescriptionKey: "Błąd zapytania folderu"])
        }
        
        let searchReq = URLRequest(url: searchURL)
        
        let (data, httpResponse) = try await requester.data(for: searchReq)
        if (200...299).contains(httpResponse.statusCode),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = json["files"] as? [[String: Any]], let first = files.first,
           let id = first["id"] as? String {
            return id
        }
        
        // 2. Folder not found — create it
        guard let createURL = URL(string: driveFilesEndpoint) else {
            throw NSError(domain: "GoogleDrive", code: 8, userInfo: [NSLocalizedDescriptionKey: "Błąd URL tworzenia folderu"])
        }
        
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let folderMeta: [String: Any] = [
            "name": folderName,
            "mimeType": "application/vnd.google-apps.folder",
            "description": "Kopie zapasowe bazy pieśni i ustawień aplikacji CantatePresenter"
        ]
        createReq.httpBody = try JSONSerialization.data(withJSONObject: folderMeta)
        
        let (createData, createHttpResp) = try await requester.data(for: createReq)
        guard (200...299).contains(createHttpResp.statusCode),
              let createJson = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let newId = createJson["id"] as? String else {
            throw Self.apiError(code: 9, "Nie udało się utworzyć folderu kopii zapasowych na Dysku Google", status: createHttpResp.statusCode, data: createData)
        }
        
        return newId
    }
    
    // MARK: - Upload Backup to Google Drive
    
    public func uploadBackupToDrive(archiveURL: URL) async throws -> RemoteBackupItem {
        let store = await MainActor.run { DataStore.shared }
        let folderName = await MainActor.run { store.settings.googleDrive.targetFolder.isEmpty ? "CantatePresenter_Backups" : store.settings.googleDrive.targetFolder }
        let folderId = try await getOrCreateBackupsFolder(folderName: folderName)
        
        guard let uploadURL = URL(string: driveUploadEndpoint) else {
            throw NSError(domain: "GoogleDrive", code: 10, userInfo: [NSLocalizedDescriptionKey: "Błąd URL wysyłki"])
        }
        
        let boundary = "-------CantateBackupBoundary\(UUID().uuidString)"
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Metadata Part
        let metadata: [String: Any] = [
            "name": archiveURL.lastPathComponent,
            "parents": [folderId],
            "mimeType": "application/zip",
            "description": "CantatePresenter Pełny Backup (baza pieśni, chwyty, ustawienia, standby, języki, loga)"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        
        // File Content Part
        let fileData = try Data(contentsOf: archiveURL)
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, httpResponse) = try await requester.data(for: request)
        guard (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileId = json["id"] as? String else {
            throw Self.apiError(code: 11, "Błąd przesyłania kopii na Dysk Google", status: httpResponse.statusCode, data: data)
        }
        
        let name = json["name"] as? String ?? archiveURL.lastPathComponent
        let size = (json["size"] as? String).flatMap { Int64($0) } ?? Int64(fileData.count)
        
        // Update last backup date in settings
        await MainActor.run {
            store.settings.googleDrive.lastBackupDate = Date()
            store.saveSettings()
        }
        
        return RemoteBackupItem(
            id: fileId,
            name: name,
            size: size,
            createdTime: Date(),
            modifiedTime: Date()
        )
    }
    
    // MARK: - List Remote Backups
    
    public func listBackupsFromDrive() async throws -> [RemoteBackupItem] {
        let store = await MainActor.run { DataStore.shared }
        let folderName = await MainActor.run { store.settings.googleDrive.targetFolder.isEmpty ? "CantatePresenter_Backups" : store.settings.googleDrive.targetFolder }
        let folderId = try await getOrCreateBackupsFolder(folderName: folderName)
        
        let query = "'\(Self.escapeQueryValue(folderId))' in parents and trashed = false"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let listURL = URL(string: "\(driveFilesEndpoint)?q=\(encodedQuery)&fields=files(id,name,size,createdTime,modifiedTime)&orderBy=createdTime%20desc") else {
            throw NSError(domain: "GoogleDrive", code: 12, userInfo: [NSLocalizedDescriptionKey: "Błąd URL listy plików"])
        }
        
        let request = URLRequest(url: listURL)
        
        let (data, httpResponse) = try await requester.data(for: request)
        guard (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            throw Self.apiError(code: 13, "Błąd odczytu listy kopii z Dysku Google", status: httpResponse.statusCode, data: data)
        }
        
        let isoFormatter = ISO8601DateFormatter()
        return files.compactMap { dict -> RemoteBackupItem? in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String else { return nil }
            let size = (dict["size"] as? String).flatMap { Int64($0) }
            let createdTime = (dict["createdTime"] as? String).flatMap { isoFormatter.date(from: $0) }
            let modifiedTime = (dict["modifiedTime"] as? String).flatMap { isoFormatter.date(from: $0) }
            return RemoteBackupItem(id: id, name: name, size: size, createdTime: createdTime, modifiedTime: modifiedTime)
        }
    }
    
    // MARK: - Download & Restore from Google Drive
    
    public func downloadBackupFromDrive(fileId: String, fileName: String) async throws -> URL {
        guard let encodedId = fileId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let downloadURL = URL(string: "\(driveFilesEndpoint)/\(encodedId)?alt=media") else {
            throw NSError(domain: "GoogleDrive", code: 14, userInfo: [NSLocalizedDescriptionKey: "Błąd URL pobierania"])
        }
        
        let request = URLRequest(url: downloadURL)
        
        let (data, httpResponse) = try await requester.data(for: request)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Self.apiError(code: 15, "Błąd pobierania kopii z Dysku Google", status: httpResponse.statusCode, data: data)
        }
        
        // Nazwa z Dysku nie trafia do ścieżki (W3): mogłaby zawierać "/" lub "..".
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CantateDriveBackup_\(UUID().uuidString).cantatebackup")
        try data.write(to: tempURL)
        return tempURL
    }
    
    public func restoreFromDrive(fileId: String, fileName: String) async throws -> BackupManifest {
        let tempURL = try await downloadBackupFromDrive(fileId: fileId, fileName: fileName)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        return try await BackupService.shared.restoreBackup(from: tempURL)
    }
}
