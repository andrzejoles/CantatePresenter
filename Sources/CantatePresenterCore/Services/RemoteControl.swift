import Foundation

// MARK: - Remote Command

/// Polecenia z pilota w telefonie. Kody w JSON są stałe (nie tłumaczone).
public enum RemoteCommand: Equatable {
    case next
    case previous
    case nextSong
    case previousSong
    case black
    case clearText
    case stop
    case slide(Int)
    case planItem(Int)
    
    /// Treść POST: `{"command":"next"}` albo `{"command":"slide","index":2}`.
    public init?(json data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["command"] as? String else { return nil }
        let index = object["index"] as? Int
        switch name {
        case "next": self = .next
        case "previous": self = .previous
        case "nextSong": self = .nextSong
        case "previousSong": self = .previousSong
        case "black": self = .black
        case "clearText": self = .clearText
        case "stop": self = .stop
        case "slide":
            guard let index, index >= 0 else { return nil }
            self = .slide(index)
        case "planItem":
            guard let index, index >= 0 else { return nil }
            self = .planItem(index)
        default: return nil
        }
    }
}

// MARK: - Remote State

/// Stan prezentacji wysyłany do telefonu; teksty przycisków w języku interfejsu aplikacji.
public struct RemoteState: Codable, Equatable {
    public struct SlideInfo: Codable, Equatable {
        public var label: String
        public var preview: String
    }
    
    public struct PlanEntry: Codable, Equatable {
        public var title: String
        public var isCurrent: Bool
    }
    
    public var isLive: Bool
    public var isBlackScreen: Bool
    public var isClearText: Bool
    public var songTitle: String
    public var slideIndex: Int
    public var slideText: String
    public var slides: [SlideInfo]
    public var planName: String
    public var plan: [PlanEntry]
    public var labels: [String: String]
}

// MARK: - Remote Router

/// Obsługa żądań pilota: strona, stan i polecenia. Każde żądanie musi mieć token z kodu QR (`?t=`).
public struct RemoteRouter {
    public let token: String
    /// Token tylko do podglądu dla muzyków (`/stage`): bez sterowania prezentacją.
    public let stageToken: String?
    
    public init(token: String, stageToken: String? = nil) {
        self.token = token
        self.stageToken = stageToken
    }
    
    public func response(
        for request: RemoteHTTPRequest,
        page: () -> String,
        state: () -> RemoteState,
        perform: (RemoteCommand) -> Void,
        stagePage: () -> String = { "" },
        stageState: (Int) -> Data = { _ in Data("{}".utf8) }
    ) -> RemoteHTTPResponse {
        let given = request.query["t"] ?? ""
        let isController = Self.constantTimeEquals(given, token)
        let isMusician = stageToken.map { Self.constantTimeEquals(given, $0) } ?? false
        if (request.path == "/stage" || request.path == "/api/stage") && (isController || isMusician) {
            guard request.method == "GET" else { return .text("Method not allowed", status: 405) }
            if request.path == "/stage" {
                return RemoteHTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(stagePage().utf8))
            }
            let semitones = Int(request.query["transpose"] ?? "0").map { max(-11, min(11, $0)) } ?? 0
            return RemoteHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: stageState(semitones))
        }
        guard isController else {
            return .text(Lnow("Brak dostępu. Zeskanuj ponownie kod QR w aplikacji CantatePresenter."), status: 403)
        }
        switch (request.method, request.path) {
        case ("GET", "/"):
            return RemoteHTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(page().utf8))
        case ("GET", "/api/state"):
            return .json(state())
        case ("POST", "/api/command"):
            guard let command = RemoteCommand(json: request.body) else {
                return .text("Unknown command", status: 400)
            }
            perform(command)
            return .json(state())
        case (_, "/"), (_, "/api/state"), (_, "/api/command"):
            return .text("Method not allowed", status: 405)
        default:
            return .text("Not found", status: 404)
        }
    }
    
    /// Porównanie bez wczesnego wyjścia, żeby czas odpowiedzi nie zdradzał zgodnych znaków tokenu.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8), right = Array(b.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<left.count {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
    
    /// Losowy token (128 bitów) do adresu w kodzie QR.
    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
