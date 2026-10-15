import Foundation

// MARK: - Remote HTTP Request

/// Minimalne żądanie HTTP/1.1 dla pilota ze smartfona: tylko to, czego potrzebuje strona pilota (GET/POST, zapytanie, treść).
public struct RemoteHTTPRequest: Equatable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data
    
    /// Największe przyjmowane żądanie; pilot wysyła krótkie polecenia JSON.
    public static let maxSize = 64 * 1024
    
    public enum ParseResult: Equatable {
        case incomplete
        case invalid
        case complete(RemoteHTTPRequest)
    }
    
    /// Parsuje bufor odebrany z połączenia; `incomplete`, gdy brakuje jeszcze nagłówków albo treści.
    public static func parse(_ data: Data) -> ParseResult {
        guard data.count <= maxSize else { return .invalid }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return .incomplete }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }
        
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }
        
        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        
        return .complete(RemoteHTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: data[bodyStart..<(bodyStart + length)]
        ))
    }
}

// MARK: - Remote HTTP Response

public struct RemoteHTTPResponse: Equatable {
    public var status: Int
    public var contentType: String
    public var body: Data
    
    public init(status: Int, contentType: String, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }
    
    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> RemoteHTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return RemoteHTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }
    
    public static func text(_ text: String, status: Int) -> RemoteHTTPResponse {
        RemoteHTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }
    
    /// Odpowiedź z nagłówkami: bez pamięci podręcznej (stan zmienia się co chwilę) i z zamknięciem połączenia.
    public var serialized: Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        default: reason = "Error"
        }
        let head = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "Referrer-Policy: no-referrer",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
        return Data(head.utf8) + body
    }
}
