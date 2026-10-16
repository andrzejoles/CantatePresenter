import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - Pilot ze smartfona

@Suite("Pilot: HTTP i router")
struct RemoteHTTPTests {
    private func request(_ raw: String) -> RemoteHTTPRequest? {
        if case .complete(let request) = RemoteHTTPRequest.parse(Data(raw.utf8)) { return request }
        return nil
    }

    @Test("Żądanie GET z zapytaniem i POST z treścią")
    func parsesRequests() throws {
        let get = try #require(request("GET /api/state?t=abc HTTP/1.1\r\nHost: x\r\n\r\n"))
        #expect(get.method == "GET" && get.path == "/api/state" && get.query["t"] == "abc")

        let body = #"{"command":"next"}"#
        let post = try #require(request("POST /api/command?t=abc HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"))
        #expect(String(data: post.body, encoding: .utf8) == body)
    }

    @Test("Niepełne i błędne żądania")
    func incompleteAndInvalid() {
        #expect(RemoteHTTPRequest.parse(Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)) == .incomplete)
        #expect(RemoteHTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc".utf8)) == .incomplete)
        #expect(RemoteHTTPRequest.parse(Data("nonsense\r\n\r\n".utf8)) == .invalid)
        #expect(RemoteHTTPRequest.parse(Data(repeating: 65, count: RemoteHTTPRequest.maxSize + 1)) == .invalid)
    }

    @Test("Polecenia z JSON; nieznane i ujemne indeksy odrzucone")
    func commands() {
        #expect(RemoteCommand(json: Data(#"{"command":"next"}"#.utf8)) == .next)
        #expect(RemoteCommand(json: Data(#"{"command":"slide","index":2}"#.utf8)) == .slide(2))
        #expect(RemoteCommand(json: Data(#"{"command":"planItem","index":-1}"#.utf8)) == nil)
        #expect(RemoteCommand(json: Data(#"{"command":"shutdown"}"#.utf8)) == nil)
    }

    @Test("Bez poprawnego tokenu: 403; z tokenem: strona, stan, polecenie")
    func router() throws {
        let router = RemoteRouter(token: "secret")
        let state = RemoteState(isLive: true, isBlackScreen: false, isClearText: false, songTitle: "T", slideIndex: 0,
                                slideText: "A", slides: [], planName: "", plan: [], labels: [:])
        var performed: [RemoteCommand] = []
        func respond(_ raw: String) throws -> RemoteHTTPResponse {
            router.response(for: try #require(request(raw)), page: { "<html>" }, state: { state }, perform: { performed.append($0) })
        }

        #expect(try respond("GET /api/state HTTP/1.1\r\n\r\n").status == 403)
        #expect(try respond("GET /api/state?t=secreT HTTP/1.1\r\n\r\n").status == 403)
        #expect(try respond("GET /?t=secret HTTP/1.1\r\n\r\n").contentType.hasPrefix("text/html"))
        #expect(try respond("GET /api/state?t=secret HTTP/1.1\r\n\r\n").status == 200)
        #expect(try respond("GET /api/command?t=secret HTTP/1.1\r\n\r\n").status == 405)
        #expect(try respond("GET /etc/passwd?t=secret HTTP/1.1\r\n\r\n").status == 404)
        let body = #"{"command":"black"}"#
        #expect(try respond("POST /api/command?t=secret HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)").status == 200)
        #expect(performed == [.black])
    }

    @Test("Token: 128 bitów, bez znaków wymagających kodowania w adresie")
    func token() {
        let token = RemoteRouter.makeToken()
        #expect(token.count == 22)
        #expect(token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(RemoteRouter.makeToken() != token)
    }

    @Test("Odpowiedź bez pamięci podręcznej i z zamknięciem połączenia")
    func responseHeaders() {
        let text = String(decoding: RemoteHTTPResponse.text("ok", status: 200).serialized, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Cache-Control: no-store\r\n") && text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\nok"))
    }
}

@MainActor
@Suite("Pilot: sterowanie prezentacją")
struct RemoteBridgeTests {
    @Test("Stan i polecenia działają na DataStore: slajdy, czarny ekran, pozycja planu")
    func bridge() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let first = Song(title: "Pierwsza", rawLyrics: "A1\n\nA2")
        let second = Song(title: "Druga", rawLyrics: "B1")
        store.songs = [first, second]
        store.plans = [ServicePlan(name: "Niedziela", items: [PlanItem(songId: first.id), PlanItem(songId: second.id)])]
        store.activePlanId = store.plans[0].id

        RemoteControlBridge.perform(.planItem(0), on: store)
        RemoteControlBridge.perform(.next, on: store)
        var state = RemoteControlBridge.state(of: store)
        #expect(state.isLive && state.songTitle == "Pierwsza" && state.slideIndex == 1 && state.slideText == "A2")
        #expect(state.plan.map(\.isCurrent) == [true, false])
        #expect(state.slides.count == 2)

        RemoteControlBridge.perform(.black, on: store)
        #expect(RemoteControlBridge.state(of: store).isBlackScreen)

        RemoteControlBridge.perform(.nextSong, on: store)
        state = RemoteControlBridge.state(of: store)
        #expect(state.songTitle == "Druga" && state.planName == "Niedziela")

        RemoteControlBridge.perform(.planItem(9), on: store)
        #expect(RemoteControlBridge.state(of: store).songTitle == "Druga")

        RemoteControlBridge.perform(.stop, on: store)
        #expect(!RemoteControlBridge.state(of: store).isLive)
    }
}

@MainActor
@Suite("Pilot: serwer w sieci", .serialized)
struct RemoteServerTests {
    @Test("Serwer odpowiada przez prawdziwe połączenie TCP i liczy telefony")
    func serverRoundTrip() async throws {
        let server = RemoteControlServer(route: { request, token in
            RemoteRouter(token: token).response(for: request, page: { "page" }, state: {
                RemoteState(isLive: false, isBlackScreen: false, isClearText: false, songTitle: "Test", slideIndex: 0,
                            slideText: "", slides: [], planName: "", plan: [], labels: [:])
            }, perform: { _ in })
        })
        server.start(port: 0)
        defer { server.stop() }
        for _ in 0..<100 where !server.isRunning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let port = try #require(server.port)

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/api/state?t=\(server.token)"))
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(try JSONDecoder().decode(RemoteState.self, from: data).songTitle == "Test")
        #expect(server.connectedDevices() == 1)

        let wrong = try #require(URL(string: "http://127.0.0.1:\(port)/api/state?t=wrong"))
        let (_, denied) = try await URLSession.shared.data(from: wrong)
        #expect((denied as? HTTPURLResponse)?.statusCode == 403)

        server.regenerateToken()
        let (_, old) = try await URLSession.shared.data(from: url)
        #expect((old as? HTTPURLResponse)?.statusCode == 403)
        #expect(server.connectedDevices() == 0)
    }
}
