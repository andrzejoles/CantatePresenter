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

    private static func admit(_ counter: inout RemoteConnectionCounter, _ host: String, total: Int = 32, anonymous: Int = 16,
                              perHost: Int = 8) -> RemoteConnectionCounter.Admission? {
        counter.admit(host: host, maxTotal: total, maxAnonymous: anonymous, maxPerHost: perHost)
    }

    @Test("Licznik połączeń: limit łączny i na adres, zwolnienie miejsca (R3-05)")
    func connectionCounter() throws {
        var counter = RemoteConnectionCounter()
        let admitted = ["a", "a", "a", "b"].map { counter.admit(host: $0, maxTotal: 3, maxAnonymous: 3, maxPerHost: 2) }
        #expect(admitted.map { $0 != nil } == [true, true, false, true])
        let ids = admitted.compactMap { $0?.id }
        #expect(Set(ids).count == 3)
        // Wszystkie miejsca zajęte przez połączenia z żądaniem w toku: nowe jest odrzucane.
        ids.forEach { counter.requestReceived(id: $0) }
        #expect(counter.admit(host: "c", maxTotal: 3, maxAnonymous: 3, maxPerHost: 2) == nil)
        counter.release(id: ids[0])
        #expect(counter.total == 2 && counter.perHost["a"] == 1)
        let afterRelease = try #require(Self.admit(&counter, "c", total: 3, anonymous: 3, perHost: 2))
        #expect(afterRelease.pool == .anonymous && afterRelease.evicted == nil)
        // Podwójne zwolnienie (np. po wyrzuceniu) niczego nie psuje.
        counter.release(id: ids[0])
        [afterRelease.id, ids[1], ids[2]].forEach { counter.release(id: $0) }
        #expect(counter.total == 0 && counter.anonymous == 0 && counter.perHost.isEmpty)
    }

    @Test("Kilka adresów bez tokenu nie zajmie miejsc telefonu z tokenem (R7-05); zaufanie do nowego kodu (R11-02)")
    func authorizedHostKeepsCapacity() {
        var counter = RemoteConnectionCounter()
        counter.markAuthorized(host: "192.168.1.20")
        // Atakujący z 4 adresów po 8 połączeń; połączenia wysłały żądanie, więc nie można ich wyrzucić.
        var attacker = 0
        for host in ["192.168.1.66", "192.168.1.67", "192.168.1.68", "192.168.1.69"] {
            for _ in 0..<8 {
                guard let admission = counter.admit(host: host, maxTotal: 32, maxAnonymous: 16, maxPerHost: 8) else { continue }
                counter.requestReceived(id: admission.id)
                attacker += 1
            }
        }
        #expect(attacker == 16)
        let phone = (0..<8).map { _ in counter.admit(host: "192.168.1.20", maxTotal: 32, maxAnonymous: 16, maxPerHost: 8) }
        #expect(phone.allSatisfy { $0?.pool == .trusted })
        // Nowy adres bez tokenu: pula anonimowa pełna, nikogo bezczynnego do wyrzucenia.
        #expect(counter.admit(host: "192.168.1.70", maxTotal: 32, maxAnonymous: 16, maxPerHost: 8) == nil)
        // Zaufanie nie wygasa z czasem (telefon zablokowany na czas kazania), tylko po „Nowy kod”.
        phone.compactMap { $0?.id }.forEach { counter.release(id: $0) }
        #expect(counter.admit(host: "192.168.1.20", maxTotal: 32, maxAnonymous: 16, maxPerHost: 8)?.pool == .trusted)
        counter.revokeTrust()
        #expect(counter.admit(host: "192.168.1.20", maxTotal: 32, maxAnonymous: 16, maxPerHost: 8) == nil)
    }

    @Test("Pełna pula anonimowa: nowe połączenie wyrzuca najstarsze bezczynne, a nie jest odrzucane (R11-02)")
    func evictsOldestIdleAnonymous() throws {
        var counter = RemoteConnectionCounter()
        // Atakujący z IPv4 i jednej sieci IPv6 trzyma 16 bezczynnych połączeń.
        var idle: [UInt64] = []
        for host in ["192.168.1.66", "fe80:0:0:0::/64"] {
            for _ in 0..<8 {
                idle.append(try #require(Self.admit(&counter, host)).id)
            }
        }
        // Telefon (jeszcze bez zaufania) dostaje miejsce kosztem najstarszego bezczynnego połączenia.
        let phone = try #require(Self.admit(&counter, "192.168.1.20"))
        #expect(phone.pool == .anonymous && phone.evicted == idle[0])
        #expect(counter.anonymous == 16 && counter.total == 16 && counter.perHost["192.168.1.66"] == 7)
        counter.release(id: idle[0]) // zamknięcie wyrzuconego połączenia nie zwalnia drugi raz
        #expect(counter.anonymous == 16 && counter.total == 16)
        // Żądanie z tokenem: odtąd telefon korzysta z puli zaufanej.
        counter.requestReceived(id: phone.id)
        counter.markAuthorized(host: "192.168.1.20")
        let next = try #require(Self.admit(&counter, "192.168.1.20"))
        #expect(next.pool == .trusted && next.evicted == nil)
        // Połączenie telefonu z żądaniem w toku nie jest wyrzucane: kolejne nowe biorą miejsca atakującego.
        for expected in idle[1...] {
            #expect(counter.admit(host: "192.168.1.71", maxTotal: 32, maxAnonymous: 16, maxPerHost: 32)?.evicted == expected)
        }
        // Teraz bezczynne są tylko połączenia z 192.168.1.71 (najstarsze pierwsze).
        let more = try #require(Self.admit(&counter, "192.168.1.72"))
        #expect(more.evicted != phone.id && more.evicted != nil)
    }

    @Test("Limit łączny zajęty: zaufany telefon też wyrzuca bezczynne połączenie anonimowe (R11-02)")
    func trustedHostEvictsWhenTotalIsFull() throws {
        var counter = RemoteConnectionCounter()
        counter.markAuthorized(host: "phone")
        let anonymous = try #require(Self.admit(&counter, "a", total: 2, anonymous: 2, perHost: 2))
        let trusted = try #require(Self.admit(&counter, "phone", total: 2, anonymous: 2, perHost: 2))
        counter.requestReceived(id: trusted.id)
        let second = try #require(Self.admit(&counter, "phone", total: 2, anonymous: 2, perHost: 2))
        #expect(second.pool == .trusted && second.evicted == anonymous.id)
        // Same zaufane połączenia: brak kogo wyrzucić.
        #expect(counter.admit(host: "b", maxTotal: 2, maxAnonymous: 2, maxPerHost: 2) == nil)
    }

    @Test("Tabela zaufanych adresów ograniczona: usuwany najdawniej używany (R11-02)")
    func trustedHostsAreBoundedLRU() {
        var counter = RemoteConnectionCounter()
        let limit = RemoteConnectionCounter.maxTrustedHosts
        for index in 0..<limit { counter.markAuthorized(host: "host\(index)") }
        counter.markAuthorized(host: "host0") // znów używany
        counter.markAuthorized(host: "nowy")
        #expect(counter.trustedHostCount == limit)
        #expect(counter.isTrusted(host: "host0") && counter.isTrusted(host: "nowy"))
        #expect(!counter.isTrusted(host: "host1"))
    }

    @Test("Adresy IPv6 liczone po prefiksie /64, IPv4 zapisane jako IPv6 jak IPv4 (R7-05)")
    func connectionBuckets() {
        #expect(RemoteConnectionCounter.bucket(forHost: "192.168.1.5") == "192.168.1.5")
        #expect(RemoteConnectionCounter.bucket(forHost: "::ffff:192.168.1.5") == "192.168.1.5")
        #expect(RemoteConnectionCounter.bucket(forHost: "fe80::1%en0") == RemoteConnectionCounter.bucket(forHost: "fe80::abcd:2%en0"))
        #expect(RemoteConnectionCounter.bucket(forHost: "2001:db8:1:2::5") == "2001:db8:1:2::/64")
        #expect(RemoteConnectionCounter.bucket(forHost: "2001:db8:1:2:aaaa:bbbb:cccc:dddd") == "2001:db8:1:2::/64")
        #expect(RemoteConnectionCounter.bucket(forHost: "2001:db8:1:3::5") != "2001:db8:1:2::/64")
        #expect(RemoteConnectionCounter.bucket(forHost: "not an address") == "not an address")
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
    @Test("Teksty pilota i ekranu muzyków w języku podanego DataStore, bez DataStore.shared (R5-01)")
    func labelsFollowStoreLanguage() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        store.settings.appLanguage = "de"
        let song = Song(title: "Pierwsza", rawLyrics: "[Refren]\nA1")
        store.songs = [song]
        RemoteControlBridge.perform(.song(song.id), on: store)

        let state = RemoteControlBridge.state(of: store)
        #expect(state.labels["next"] == "Weiter")
        #expect(state.slides.first?.label == "Refrain")
        #expect(RemoteControlBridge.stageLabels(language: "en")["title"] == "Musicians' screen")
        #expect(RemoteControlBridge.labels(language: "pl")["next"] == "Dalej")
        #expect(MusicianStage.make(store: store, semitones: 0).current?.label == "Refrain")
    }

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

    @Test("Zastępczy autor w wynikach pilota i na stronie muzyków jest w języku aplikacji (R12-04)")
    func searchTranslatesUnknownAuthor() throws {
        let dir = try TestDirectory()
        defer { dir.remove() }
        let store = DataStore(dataDirectory: dir.url)
        store.settings.appLanguage = "en"
        defer { Localization.currentLanguage = Localization.sourceLanguage }
        let song = Song(title: "Gloria", author: SongEnrichmentService.unknownAuthorPlaceholder, rawLyrics: "Gloria in excelsis")
        store.songs = [song]

        #expect(RemoteControlBridge.search("gloria", in: store).first?.author == "Unknown")
        store.present(song: song)
        #expect(MusicianStage.make(store: store, semitones: 0).author == "Unknown")
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

    @Test("Limit połączeń zajęty przez bezczynne: nowe wyrzuca najstarsze i dostaje odpowiedź (R11-02)")
    func connectionLimit() async throws {
        let server = RemoteControlServer(maxConnections: 2, route: { _, _, _ in .text("ok", status: 200) })
        server.start(port: 0)
        defer { server.stop() }
        for _ in 0..<100 where !server.isRunning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let port = try #require(server.port)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/?t=\(server.token)"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        // Dwa połączenia bez żądania zajmują limit; przed R11-02 telefon był wtedy odrzucany.
        var idle: [NWConnection] = []
        for _ in 0..<2 { idle.append(try await Self.openIdleConnection(port: port)) }
        defer { idle.forEach { $0.cancel() } }
        try await Task.sleep(nanoseconds: 200_000_000)
        let (data, _) = try await session.data(from: url)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
    }

    @Test("Limit na adres: bezczynne połączenia z jednego adresu nie blokują innych (R3-05)")
    func perHostLimit() async throws {
        let server = RemoteControlServer(maxConnections: 8, maxConnectionsPerHost: 2, route: { _, _, _ in .text("ok", status: 200) })
        server.start(port: 0)
        defer { server.stop() }
        try await Self.waitUntilRunning(server)
        let port = try #require(server.port)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        // Dwa bezczynne połączenia z 127.0.0.1 wyczerpują limit tego adresu...
        var idle: [NWConnection] = []
        for _ in 0..<2 { idle.append(try await Self.openIdleConnection(port: port)) }
        defer { idle.forEach { $0.cancel() } }
        try await Task.sleep(nanoseconds: 200_000_000)
        let sameHost = try #require(URL(string: "http://127.0.0.1:\(port)/?t=\(server.token)"))
        await #expect(throws: (any Error).self) { _ = try await session.data(from: sameHost) }

        // ...ale telefon z innego adresu (tu ::1) dalej dostaje odpowiedź.
        let otherHost = try #require(URL(string: "http://[::1]:\(port)/?t=\(server.token)"))
        let (data, _) = try await session.data(from: otherHost)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
    }

    @Test("Zły token: 403 bez przechodzenia przez wątek główny i DataStore (R3-05)")
    func wrongTokenAnsweredOffMain() async throws {
        let routed = OSAllocatedUnfairLock(initialState: 0)
        let server = RemoteControlServer(route: { _, _, _ in
            routed.withLock { $0 += 1 }
            return .text("ok", status: 200)
        })
        server.start(port: 0)
        defer { server.stop() }
        try await Self.waitUntilRunning(server)
        let port = try #require(server.port)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        for path in ["/api/state?t=zly", "/", "/stage?t=", "/api/command"] {
            let (_, response) = try await session.data(from: try #require(URL(string: "http://127.0.0.1:\(port)\(path)")))
            #expect((response as? HTTPURLResponse)?.statusCode == 403, "\(path)")
        }
        let routedBefore = routed.withLock { $0 }
        #expect(routedBefore == 0)

        let (_, ok) = try await session.data(from: try #require(URL(string: "http://127.0.0.1:\(port)/stage?t=\(server.stageToken)")))
        #expect((ok as? HTTPURLResponse)?.statusCode == 200)
        server.regenerateToken()
        let (_, old) = try await session.data(from: try #require(URL(string: "http://127.0.0.1:\(port)/?t=\(server.token.dropLast())x")))
        #expect((old as? HTTPURLResponse)?.statusCode == 403)
        let routedAfter = routed.withLock { $0 }
        #expect(routedAfter == 1)
    }

    @Test("Spóźnione zdarzenie starego odbiornika nie wyłącza działającego serwera (R3-06)")
    func staleListenerEventIgnored() async throws {
        let server = RemoteControlServer(route: { _, _, _ in .text("ok", status: 200) })
        server.start(port: 0)
        try await Self.waitUntilRunning(server)
        let first = server.listenerGeneration
        server.stop()
        server.start(port: 0)
        defer { server.stop() }
        try await Self.waitUntilRunning(server)
        #expect(server.listenerGeneration != first)

        // `.cancelled` i `.failed` starego odbiornika docierają po `.ready` nowego.
        server.listenerChanged(.cancelled, generation: first, requestedPort: 0)
        server.listenerChanged(.failed(.posix(.EADDRINUSE)), generation: first, requestedPort: 0)
        #expect(server.isRunning)
        #expect(server.port != nil && server.errorMessage == nil)
    }

    @Test("Drugi odbiornik na tym samym porcie się nie uruchamia (R3-07: bez SO_REUSEPORT)")
    func portIsNotShared() async throws {
        let server = RemoteControlServer(route: { _, _, _ in .text("ok", status: 200) })
        server.start(port: 0)
        defer { server.stop() }
        try await Self.waitUntilRunning(server)
        let rawPort = try #require(server.port)
        let port = try #require(NWEndpoint.Port(rawValue: rawPort))

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let second = try NWListener(using: parameters, on: port)
        second.newConnectionHandler = { $0.cancel() }
        let failed = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let done = OSAllocatedUnfairLock(initialState: false)
            second.stateUpdateHandler = { state in
                let result: Bool?
                switch state {
                case .ready: result = false
                case .failed, .cancelled: result = true
                default: result = nil
                }
                guard let result, done.withLock({ finished in defer { finished = true }; return !finished }) else { return }
                continuation.resume(returning: result)
            }
            second.start(queue: .global())
        }
        second.cancel()
        #expect(failed)
    }

    private static func waitUntilRunning(_ server: RemoteControlServer) async throws {
        for _ in 0..<100 where !server.isRunning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(server.isRunning)
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
