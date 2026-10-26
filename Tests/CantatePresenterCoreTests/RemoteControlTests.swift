import Foundation
import Network
import os
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
        #expect(RemoteCommand(json: Data(#"{"command":"start"}"#.utf8)) == .start)
        let id = UUID()
        #expect(RemoteCommand(json: Data(#"{"command":"song","id":"\#(id.uuidString)"}"#.utf8)) == .song(id))
        #expect(RemoteCommand(json: Data(#"{"command":"song","id":"nie-uuid"}"#.utf8)) == nil)
        #expect(RemoteCommand(json: Data(#"{"command":"song"}"#.utf8)) == nil)
    }

    @Test("Wyszukiwanie: tylko z tokenem sterowania, zapytanie zdekodowane z adresu")
    func searchRoute() throws {
        let router = RemoteRouter(token: "control", stageToken: "musician")
        let state = RemoteState(isLive: false, isBlackScreen: false, isClearText: false, songTitle: "", slideIndex: 0,
                                slideText: "", slides: [], planName: "", plan: [], labels: [:])
        var queries: [String] = []
        func respond(_ raw: String) throws -> RemoteHTTPResponse {
            router.response(for: try #require(request(raw)), page: { "" }, state: { state }, perform: { _ in },
                            search: { queries.append($0); return Data("[]".utf8) })
        }
        let found = try respond("GET /api/search?t=control&q=B%C3%B3g%20si%C4%99 HTTP/1.1\r\n\r\n")
        #expect(found.status == 200 && found.contentType.hasPrefix("application/json"))
        #expect(queries == ["Bóg się"])
        #expect(try respond("GET /api/search?t=musician&q=x HTTP/1.1\r\n\r\n").status == 403)
        #expect(try respond("POST /api/search?t=control&q=x HTTP/1.1\r\n\r\n").status == 405)
        #expect(queries.count == 1)
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

    @Test("Token muzyków: tylko podgląd /stage i /api/stage, bez sterowania")
    func stageToken() throws {
        let router = RemoteRouter(token: "control", stageToken: "musician")
        let state = RemoteState(isLive: true, isBlackScreen: false, isClearText: false, songTitle: "T", slideIndex: 0,
                                slideText: "A", slides: [], planName: "", plan: [], labels: [:])
        var performed: [RemoteCommand] = []
        var requestedSemitones: [Int] = []
        func respond(_ raw: String) throws -> RemoteHTTPResponse {
            router.response(for: try #require(request(raw)), page: { "control" }, state: { state }, perform: { performed.append($0) },
                            stagePage: { "stage" }, stageState: { requestedSemitones.append($0); return Data("{}".utf8) })
        }
        #expect(try respond("GET /stage?t=musician HTTP/1.1\r\n\r\n").body == Data("stage".utf8))
        #expect(try respond("GET /api/stage?t=musician&transpose=-3 HTTP/1.1\r\n\r\n").status == 200)
        #expect(try respond("GET /api/stage?t=musician&transpose=40 HTTP/1.1\r\n\r\n").status == 200)
        #expect(requestedSemitones == [-3, 11])
        #expect(try respond("GET /?t=musician HTTP/1.1\r\n\r\n").status == 403)
        #expect(try respond("GET /api/state?t=musician HTTP/1.1\r\n\r\n").status == 403)
        let body = #"{"command":"next"}"#
        #expect(try respond("POST /api/command?t=musician HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)").status == 403)
        #expect(performed.isEmpty)
        #expect(try respond("GET /stage?t=control HTTP/1.1\r\n\r\n").status == 200)
        #expect(try respond("GET /stage?t=wrong HTTP/1.1\r\n\r\n").status == 403)
    }

    @Test("Token: 128 bitów, bez znaków wymagających kodowania w adresie")
    func token() {
        let token = RemoteRouter.makeToken()
        #expect(token.count == 22)
        #expect(token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(RemoteRouter.makeToken() != token)
    }

    @Test("Strony pilota i muzyków z zasobów pakietu")
    func pagesComeFromResources() {
        let remote = RemoteControlPage.html(language: "en")
        #expect(remote.hasPrefix("<!doctype html>\n<html lang=\"en\">"))
        #expect(remote.contains("/api/state") && remote.contains("/api/search"))
        let stage = MusicianStagePage.html(language: "pl\"><script>")
        #expect(stage.hasPrefix("<!doctype html>\n<html lang=\"plscript\">"))
        #expect(stage.contains("/api/stage"))
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

    @Test("Po zatrzymaniu projekcję można wznowić z pilota w tym samym miejscu")
    func resumeAfterStop() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let song = Song(title: "Pierwsza", rawLyrics: "A1\n\nA2\n\nA3")
        store.songs = [song]

        RemoteControlBridge.perform(.song(song.id), on: store)
        RemoteControlBridge.perform(.next, on: store)
        RemoteControlBridge.perform(.stop, on: store)
        var state = RemoteControlBridge.state(of: store)
        #expect(!state.isLive && state.canStart)

        RemoteControlBridge.perform(.start, on: store)
        state = RemoteControlBridge.state(of: store)
        #expect(state.isLive && state.songTitle == "Pierwsza" && state.slideIndex == 1)

        // Dotknięcie slajdu przy zatrzymanej projekcji uruchamia ją od tego slajdu.
        RemoteControlBridge.perform(.stop, on: store)
        RemoteControlBridge.perform(.slide(2), on: store)
        state = RemoteControlBridge.state(of: store)
        #expect(state.isLive && state.slideIndex == 2)
    }

    @Test("Start bez wcześniejszej projekcji: zaznaczona pieśń albo pierwsza z planu; pusta biblioteka nic nie robi")
    func startWithoutActiveSong() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        store.songs = []
        store.plans = []
        #expect(!RemoteControlBridge.state(of: store).canStart)
        RemoteControlBridge.perform(.start, on: store)
        #expect(!store.isLive)

        let first = Song(title: "Pierwsza", rawLyrics: "A")
        let second = Song(title: "Druga", rawLyrics: "B")
        store.songs = [first, second]
        store.plans = [ServicePlan(name: "Plan", items: [PlanItem(songId: second.id)])]
        store.activePlanId = store.plans[0].id
        store.selectedSongId = nil
        RemoteControlBridge.perform(.start, on: store)
        #expect(store.isLive && store.activeSong?.id == second.id)
    }

    @Test("Wyszukiwanie z pilota: bez polskich znaków, najpierw trafienia w tytule, nieznane id ignorowane")
    func search() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        let inLyrics = Song(title: "Alleluja", author: "", rawLyrics: "Pan jest dobry\n\nŚwięty")
        let inTitle = Song(title: "Święty, Święty", author: "Autor", rawLyrics: "Hosanna")
        store.songs = [inLyrics, inTitle]

        let results = RemoteControlBridge.search("swiety", in: store)
        #expect(results.map(\.title) == ["Święty, Święty", "Alleluja"])
        #expect(results.first?.id == inTitle.id.uuidString)
        #expect(results.first?.firstLine == "Hosanna")
        #expect(RemoteControlBridge.search("  ", in: store).isEmpty)

        RemoteControlBridge.perform(.song(UUID()), on: store)
        #expect(!store.isLive)
        RemoteControlBridge.perform(.song(inLyrics.id), on: store)
        #expect(store.isLive && store.activeSong?.id == inLyrics.id && store.selectedSongId == inLyrics.id)
    }
}

@MainActor
@Suite("Pilot: serwer w sieci", .serialized)
struct RemoteServerTests {
    @Test("Serwer odpowiada przez prawdziwe połączenie TCP i liczy telefony")
    func serverRoundTrip() async throws {
        let server = RemoteControlServer(route: { request, token, _ in
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

    @Test("Ponad limit połączeń nowe są zamykane; po rozłączeniu serwer znów odpowiada")
    func connectionLimit() async throws {
        let server = RemoteControlServer(maxConnections: 2, route: { _, _, _ in .text("ok", status: 200) })
        server.start(port: 0)
        defer { server.stop() }
        for _ in 0..<100 where !server.isRunning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let port = try #require(server.port)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        // Dwa połączenia bez żądania zajmują limit.
        var idle: [NWConnection] = []
        for _ in 0..<2 { idle.append(try await Self.openIdleConnection(port: port)) }
        try await Task.sleep(nanoseconds: 200_000_000)
        await #expect(throws: (any Error).self) { _ = try await session.data(from: url) }

        idle.forEach { $0.cancel() }
        try await Task.sleep(nanoseconds: 300_000_000)
        let (data, _) = try await session.data(from: url)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
    }

    private static func openIdleConnection(port: UInt16) async throws -> NWConnection {
        let connection = NWConnection(host: "127.0.0.1", port: try #require(NWEndpoint.Port(rawValue: port)), using: .tcp)
        let opened = OSAllocatedUnfairLock(initialState: false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    guard opened.withLock({ done in defer { done = true }; return !done }) else { return }
                    if case .failed(let error) = state { continuation.resume(throwing: error) } else { continuation.resume() }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
        return connection
    }
}
