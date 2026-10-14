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
    
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let driveFilesEndpoint = "https://www.googleapis.com/drive/v3/files"
    private let driveUploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
    private let userInfoEndpoint = "https://www.googleapis.com/oauth2/v2/userinfo"
    
    private init() {}
    
    // MARK: - OAuth URL Generator
    
    /// Generates standard Google OAuth 2.0 authorization URL for Desktop apps
    public func generateOAuthURL(clientId: String) -> URL? {
        guard !clientId.isEmpty else { return nil }
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: "urn:ietf:wg:oauth:2.0:oob"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/userinfo.email"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }
    
    // MARK: - Code to Tokens Exchange
    
    public func exchangeCodeForTokens(code: String, clientId: String, clientSecret: String) async throws -> (accessToken: String, refreshToken: String, email: String) {
        guard let url = URL(string: tokenEndpoint) else {
            throw NSError(domain: "GoogleDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowy adres tokenu"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "client_id": clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            "client_secret": clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
            "grant_type": "authorization_code"
        ]
        
        let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Błąd sieci"
            throw NSError(domain: "GoogleDrive", code: 2, userInfo: [NSLocalizedDescriptionKey: "Błąd wymiany kodu autoryzacji: \(errorText)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw NSError(domain: "GoogleDrive", code: 3, userInfo: [NSLocalizedDescriptionKey: "Brak access_token w odpowiedzi"])
        }
        
        let refreshToken = json["refresh_token"] as? String ?? ""
        
        // Fetch user email
        var userEmail = ""
        if let email = try? await fetchUserEmail(accessToken: accessToken) {
            userEmail = email
        }
        
        return (accessToken, refreshToken, userEmail)
    }
    
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
    
    // MARK: - Token Refresh
    
    public func getValidAccessToken() async throws -> String {
        let store = await MainActor.run { DataStore.shared }
        let settings = await MainActor.run { store.settings.googleDrive }
        
        // If access token is provided and non-empty, test or return it
        if !settings.accessToken.isEmpty {
            // If we have refreshToken, try refreshing if needed or return current
            return settings.accessToken
        }
        
        guard !settings.refreshToken.isEmpty, !settings.clientId.isEmpty, !settings.clientSecret.isEmpty else {
            throw NSError(domain: "GoogleDrive", code: 4, userInfo: [NSLocalizedDescriptionKey: "Brak poświadczeń Google Drive. Skonfiguruj Client ID, Client Secret lub Token w Ustawieniach."])
        }
        
        guard let url = URL(string: tokenEndpoint) else {
            throw NSError(domain: "GoogleDrive", code: 5, userInfo: [NSLocalizedDescriptionKey: "Nieprawidłowy adres tokenu"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "client_id": settings.clientId,
            "client_secret": settings.clientSecret,
            "refresh_token": settings.refreshToken,
            "grant_type": "refresh_token"
        ]
        let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            let errorText = String(data: data, encoding: .utf8) ?? "Błąd odświeżania"
            throw NSError(domain: "GoogleDrive", code: 6, userInfo: [NSLocalizedDescriptionKey: "Nie udało się odświeżyć tokenu Google: \(errorText)"])
        }
        
        // Save new access token
        await MainActor.run {
            store.settings.googleDrive.accessToken = newAccessToken
            store.saveSettings()
        }
        
        return newAccessToken
    }
    
    // MARK: - Folder Management
    
    public func getOrCreateBackupsFolder(accessToken: String, folderName: String = "HolyricsMac_Backups") async throws -> String {
        // 1. Search for existing folder
        let query = "name = '\(folderName)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(driveFilesEndpoint)?q=\(encodedQuery)&fields=files(id,name)") else {
            throw NSError(domain: "GoogleDrive", code: 7, userInfo: [NSLocalizedDescriptionKey: "Błąd zapytania folderu"])
        }
        
        var searchReq = URLRequest(url: searchURL)
        searchReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: searchReq)
        if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
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
        createReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let folderMeta: [String: Any] = [
            "name": folderName,
            "mimeType": "application/vnd.google-apps.folder",
            "description": "Kopie zapasowe bazy pieśni i ustawień aplikacji Holyrics Mac"
        ]
        createReq.httpBody = try JSONSerialization.data(withJSONObject: folderMeta)
        
        let (createData, createResp) = try await URLSession.shared.data(for: createReq)
        guard let createHttpResp = createResp as? HTTPURLResponse, (200...299).contains(createHttpResp.statusCode),
              let createJson = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let newId = createJson["id"] as? String else {
            throw NSError(domain: "GoogleDrive", code: 9, userInfo: [NSLocalizedDescriptionKey: "Nie udało się utworzyć folderu kopii zapasowych na Google Drive"])
        }
        
        return newId
    }
    
    // MARK: - Upload Backup to Google Drive
    
    public func uploadBackupToDrive(archiveURL: URL) async throws -> RemoteBackupItem {
        let token = try await getValidAccessToken()
        let store = await MainActor.run { DataStore.shared }
        let folderName = await MainActor.run { store.settings.googleDrive.targetFolder.isEmpty ? "HolyricsMac_Backups" : store.settings.googleDrive.targetFolder }
        let folderId = try await getOrCreateBackupsFolder(accessToken: token, folderName: folderName)
        
        guard let uploadURL = URL(string: driveUploadEndpoint) else {
            throw NSError(domain: "GoogleDrive", code: 10, userInfo: [NSLocalizedDescriptionKey: "Błąd URL wysyłki"])
        }
        
        let boundary = "-------HolyricsBackupBoundary\(UUID().uuidString)"
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Metadata Part
        let metadata: [String: Any] = [
            "name": archiveURL.lastPathComponent,
            "parents": [folderId],
            "mimeType": "application/zip",
            "description": "Holyrics Mac Pełny Backup (baza pieśni, chwyty, ustawienia, standby, języki, loga)"
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileId = json["id"] as? String else {
            let errorText = String(data: data, encoding: .utf8) ?? "Błąd wysyłania"
            throw NSError(domain: "GoogleDrive", code: 11, userInfo: [NSLocalizedDescriptionKey: "Błąd przesyłania do Google Drive: \(errorText)"])
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
        let token = try await getValidAccessToken()
        let store = await MainActor.run { DataStore.shared }
        let folderName = await MainActor.run { store.settings.googleDrive.targetFolder.isEmpty ? "HolyricsMac_Backups" : store.settings.googleDrive.targetFolder }
        let folderId = try await getOrCreateBackupsFolder(accessToken: token, folderName: folderName)
        
        let query = "'\(folderId)' in parents and trashed = false"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let listURL = URL(string: "\(driveFilesEndpoint)?q=\(encodedQuery)&fields=files(id,name,size,createdTime,modifiedTime)&orderBy=createdTime%20desc") else {
            throw NSError(domain: "GoogleDrive", code: 12, userInfo: [NSLocalizedDescriptionKey: "Błąd URL listy plików"])
        }
        
        var request = URLRequest(url: listURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            let errorText = String(data: data, encoding: .utf8) ?? "Błąd pobierania listy"
            throw NSError(domain: "GoogleDrive", code: 13, userInfo: [NSLocalizedDescriptionKey: "Błąd odczytu listy z Google Drive: \(errorText)"])
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
        let token = try await getValidAccessToken()
        guard let downloadURL = URL(string: "\(driveFilesEndpoint)/\(fileId)?alt=media") else {
            throw NSError(domain: "GoogleDrive", code: 14, userInfo: [NSLocalizedDescriptionKey: "Błąd URL pobierania"])
        }
        
        var request = URLRequest(url: downloadURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GoogleDrive", code: 15, userInfo: [NSLocalizedDescriptionKey: "Błąd pobierania pliku z Google Drive"])
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
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
