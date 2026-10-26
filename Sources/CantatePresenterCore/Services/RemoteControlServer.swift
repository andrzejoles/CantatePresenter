import Foundation
import Network
import Observation
import os

// MARK: - Connection Counter

/// Otwarte połączenia pilota: łącznie i na adres telefonu (R3-05). Jedno urządzenie w sieci nie może zająć
/// wszystkich miejsc bezczynnymi połączeniami.
struct RemoteConnectionCounter: Sendable {
    private(set) var total = 0
    private(set) var perHost: [String: Int] = [:]
    
    mutating func admit(host: String, maxTotal: Int, maxPerHost: Int) -> Bool {
        guard total < maxTotal, perHost[host, default: 0] < maxPerHost else { return false }
        total += 1
        perHost[host, default: 0] += 1
        return true
    }
    
    mutating func release(host: String) {
        total = max(0, total - 1)
        let remaining = perHost[host, default: 0] - 1
        perHost[host] = remaining > 0 ? remaining : nil
    }
}

// MARK: - Remote Control Server

/// Serwer pilota w sieci lokalnej: strona dla telefonu i proste API (HTTP, bez zależności zewnętrznych).
/// Dostęp tylko z tokenem z kodu QR; nowy token rozłącza wszystkie telefony.
@MainActor
@Observable
public final class RemoteControlServer {
    public static let shared = RemoteControlServer()
    nonisolated public static let preferredPort: UInt16 = 8765
    /// Telefon liczy się jako połączony, jeśli pytał o stan w tym czasie (strona pyta co sekundę).
    nonisolated static let connectedWindow: TimeInterval = 5
    
    public private(set) var isRunning = false
    public private(set) var port: UInt16?
    public private(set) var token: String
    /// Token dla muzyków: tylko podgląd slajdu z chwytami.
    public private(set) var stageToken: String
    public private(set) var errorMessage: String?
    public private(set) var lastSeen: [String: Date] = [:]
    
    /// Obsługa żądania z bieżącym tokenem; w testach podmieniana, żeby nie dotykać `DataStore.shared`.
    var route: @MainActor (RemoteHTTPRequest, String, String) -> RemoteHTTPResponse
    
    @ObservationIgnored private var listener: NWListener?
    /// Numer bieżącego odbiornika: zdarzenia starszych (po zatrzymaniu albo ponownym starcie) są pomijane (R3-06).
    @ObservationIgnored private(set) var listenerGeneration = 0
    @ObservationIgnored private let queue = DispatchQueue(label: "com.cantate.presenter.remote")
    /// Otwarte połączenia; ponad limit nowe są od razu zamykane (telefony i tablety pytają co sekundę i rozłączają się).
    @ObservationIgnored nonisolated private let openConnections = OSAllocatedUnfairLock(initialState: RemoteConnectionCounter())
    /// Kopia tokenów dla kolejki sieci: zły token dostaje 403 bez przechodzenia na wątek główny (R3-05).
    @ObservationIgnored nonisolated private let acceptedTokens: OSAllocatedUnfairLock<(control: String, stage: String)>
    nonisolated private let maxConnections: Int
    nonisolated private let maxConnectionsPerHost: Int
    /// Telefon wysyła żądanie (ok. 300 B) zaraz po połączeniu; dłużej czekające połączenie jest zamykane.
    nonisolated static let requestDeadline: TimeInterval = 3
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "remote")
    
    init(maxConnections: Int = 32, maxConnectionsPerHost: Int = 8,
         route: (@MainActor (RemoteHTTPRequest, String, String) -> RemoteHTTPResponse)? = nil) {
        let control = RemoteRouter.makeToken()
        let stage = RemoteRouter.makeToken()
        self.token = control
        self.stageToken = stage
        self.acceptedTokens = OSAllocatedUnfairLock(initialState: (control: control, stage: stage))
        self.maxConnections = maxConnections
        self.maxConnectionsPerHost = maxConnectionsPerHost
        self.route = route ?? { request, token, stageToken in
            RemoteControlBridge.response(for: request, token: token, stageToken: stageToken, store: DataStore.shared)
        }
    }
    
    // MARK: - Lifecycle
    
    public func start(port requestedPort: UInt16 = RemoteControlServer.preferredPort) {
        guard listener == nil else { return }
        errorMessage = nil
        listenerGeneration += 1
        let generation = listenerGeneration
        do {
            let parameters = NWParameters.tcp
            // Tylko SO_REUSEADDR (ponowny start na tym samym porcie), nie SO_REUSEPORT: drugi odbiornik na tym
            // porcie się nie uruchomi, co sprawdza test (R3-07).
            parameters.allowLocalEndpointReuse = true
            let nwPort = NWEndpoint.Port(rawValue: requestedPort) ?? .any
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state, generation: generation, requestedPort: requestedPort) }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            fail(error, requestedPort: requestedPort)
        }
    }
    
    public func stop() {
        listenerGeneration += 1
        listener?.cancel()
        listener = nil
        isRunning = false
        port = nil
        lastSeen = [:]
    }
    
    /// Nowy token: dotychczasowe telefony tracą dostęp i muszą zeskanować nowy kod.
    public func regenerateToken() {
        token = RemoteRouter.makeToken()
        stageToken = RemoteRouter.makeToken()
        let tokens = (control: token, stage: stageToken)
        acceptedTokens.withLock { $0 = tokens }
        lastSeen = [:]
    }
    
    func listenerChanged(_ state: NWListener.State, generation: Int, requestedPort: UInt16) {
        // Spóźnione `.cancelled`/`.failed` poprzedniego odbiornika nie może wyłączyć ani zrestartować obecnego.
        guard generation == listenerGeneration else { return }
        switch state {
        case .ready:
            isRunning = true
            port = listener?.port?.rawValue
            Self.logger.info("Pilot: serwer na porcie \(self.port ?? 0)")
        case .failed(let error):
            fail(error, requestedPort: requestedPort)
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }
    
    private func fail(_ error: Error, requestedPort: UInt16) {
        Self.logger.error("Pilot: \(String(describing: error), privacy: .public)")
        listener?.cancel()
        listener = nil
        isRunning = false
        // Zajęty port: drugi raz na dowolnym wolnym porcie (adres w kodzie QR i tak go zawiera).
        if requestedPort != 0 {
            start(port: 0)
        } else {
            errorMessage = Lnow("Nie udało się uruchomić pilota: {0}", error.localizedDescription)
        }
    }
    
    // MARK: - Status
    
    public func connectedDevices(now: Date = Date()) -> Int {
        lastSeen.values.filter { now.timeIntervalSince($0) < Self.connectedWindow }.count
    }
    
    /// Adres do kodu QR: adres Maca w sieci lokalnej, port i token.
    public var address: URL? {
        guard isRunning, let port, let host = Self.localIPv4Address() else { return nil }
        return URL(string: "http://\(host):\(port)/?t=\(token)")
    }

    /// Adres podglądu dla muzyków (tylko odczyt).
    public var stageAddress: URL? {
        guard isRunning, let port, let host = Self.localIPv4Address() else { return nil }
        return URL(string: "http://\(host):\(port)/stage?t=\(stageToken)")
    }
    
    // MARK: - Connections
    
    nonisolated private func accept(_ connection: NWConnection) {
        let host = Self.host(of: connection.endpoint)
        let accepted = openConnections.withLock {
            $0.admit(host: host, maxTotal: maxConnections, maxPerHost: maxConnectionsPerHost)
        }
        guard accepted else {
            connection.cancel()
            return
        }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed:
                connection.cancel()
            case .cancelled:
                self?.openConnections.withLock { $0.release(host: host) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        // Połączenie, które nie przyśle żądania w porę, jest zamykane (R3-05).
        queue.asyncAfter(deadline: .now() + Self.requestDeadline) { connection.cancel() }
        receive(on: connection, buffer: Data())
    }
    
    nonisolated private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch RemoteHTTPRequest.parse(buffer) {
            case .incomplete where error == nil && !isComplete:
                self?.receive(on: connection, buffer: buffer)
            case .complete(let request):
                // Każda ścieżka wymaga tokenu sterowania albo muzyków: bez niego 403 od razu, na kolejce sieci.
                guard let self, self.isAuthorized(request) else {
                    Self.send(RemoteRouter.forbidden(), on: connection)
                    return
                }
                let host = Self.host(of: connection.endpoint)
                Task { @MainActor [weak self] in
                    guard let self else { connection.cancel(); return }
                    let response = self.route(request, self.token, self.stageToken)
                    if response.status == 200 { self.lastSeen[host] = Date() }
                    Self.send(response, on: connection)
                }
            default:
                Self.send(.text("Bad request", status: 400), on: connection)
            }
        }
    }
    
    nonisolated private func isAuthorized(_ request: RemoteHTTPRequest) -> Bool {
        let given = request.query["t"] ?? ""
        return acceptedTokens.withLock {
            RemoteRouter.constantTimeEquals(given, $0.control) || RemoteRouter.constantTimeEquals(given, $0.stage)
        }
    }
    
    nonisolated private static func send(_ response: RemoteHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { _ in connection.cancel() })
    }
    
    nonisolated private static func host(of endpoint: NWEndpoint) -> String {
        if case .hostPort(let host, _) = endpoint { return "\(host)" }
        return "\(endpoint)"
    }
    
    // MARK: - Network Address
    
    /// Adres IPv4 Maca w sieci lokalnej (Wi-Fi albo Ethernet), bez pętli zwrotnej i adresów 169.254.x.x.
    nonisolated static func localIPv4Address() -> String? {
        var addresses: [(name: String, address: String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0, (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let host = String(decoding: hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard !host.hasPrefix("169.254.") else { continue }
            addresses.append((String(cString: interface.ifa_name), host))
        }
        // Najpierw en0/en1 (Wi-Fi, Ethernet), potem pozostałe (np. mostek, VPN).
        return addresses.sorted { lhs, rhs in
            let rank: (String) -> Int = { $0.hasPrefix("en") ? 0 : 1 }
            return (rank(lhs.name), lhs.name) < (rank(rhs.name), rhs.name)
        }.first?.address
    }
}

// MARK: - Remote Control Bridge

/// Połączenie pilota z `DataStore`: stan do wysłania i wykonanie poleceń.
@MainActor
enum RemoteControlBridge {
    static func response(for request: RemoteHTTPRequest, token: String, stageToken: String, store: DataStore) -> RemoteHTTPResponse {
        RemoteRouter(token: token, stageToken: stageToken).response(
            for: request,
            page: { RemoteControlPage.html(language: store.settings.appLanguage) },
            state: { state(of: store) },
            perform: { perform($0, on: store) },
            stagePage: { MusicianStagePage.html(language: store.settings.appLanguage) },
            stageState: { semitones in
                let payload = StagePayload(stage: MusicianStage.make(store: store, semitones: semitones), labels: stageLabels())
                return (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
            },
            search: { query in (try? JSONEncoder().encode(search(query, in: store))) ?? Data("[]".utf8) }
        )
    }
    
    /// Pieśni pasujące do zapytania (jak lista w aplikacji): najpierw trafienia w tytule lub autorze.
    static func search(_ query: String, in store: DataStore, limit: Int = 40) -> [RemoteSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let all = store.searchIndex.filter(store.songs, query: query, scope: .all)
        let titled = Set(store.searchIndex.filter(all, query: query, scope: .titleAndAuthor).map(\.id))
        let ordered = all.filter { titled.contains($0.id) } + all.filter { !titled.contains($0.id) }
        return ordered.prefix(limit).map { song in
            RemoteSearchResult(
                id: song.id.uuidString,
                title: song.title,
                author: song.author,
                firstLine: song.slides.first?.text.components(separatedBy: "\n").first ?? ""
            )
        }
    }
    
    /// Pieśń, którą uruchomi „Start”: ostatnio wyświetlana, zaznaczona w aplikacji albo pierwsza z planu.
    static func startCandidate(in store: DataStore) -> Song? {
        if let active = store.activeSong { return active }
        if store.selectedSongId != nil, let selected = store.selectedSong { return selected }
        if let firstId = store.activePlan?.items.first?.songId, let song = store.songs.first(where: { $0.id == firstId }) {
            return song
        }
        return store.selectedSong
    }

    struct StagePayload: Encodable {
        let stage: MusicianStage
        let labels: [String: String]
    }

    /// Teksty strony dla muzyków w języku interfejsu aplikacji.
    static func stageLabels() -> [String: String] {
        [
            "title": L("Ekran dla muzyków"),
            "key": L("Tonacja: {0}"),
            "next": L("Następny slajd"),
            "nextSong": L("Następnie: {0}"),
            "borrowed": L("Chwyty jak w: {0}"),
            "noChords": L("Brak chwytów dla tej pieśni"),
            "notLive": L("Brak aktywnej prezentacji"),
            "black": L("CZARNY EKRAN"),
            "clear": L("TEKST UKRYTY"),
            "transpose": L("Transpozycja"),
            "font": L("Czcionka"),
            "offline": L("Brak połączenia z komputerem. Sprawdź, czy telefon jest w tej samej sieci Wi-Fi."),
        ]
    }
    
    static func state(of store: DataStore) -> RemoteState {
        let song = store.activeSong
        let plan = store.activePlan
        let titles = Dictionary(store.songs.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return RemoteState(
            isLive: store.isLive,
            isBlackScreen: store.isBlackScreen,
            isClearText: store.isClearText,
            songTitle: song?.title ?? "",
            slideIndex: store.activeSlideIndex,
            slideText: store.currentLiveSlide?.text ?? "",
            slides: (song?.slides ?? []).map { slide in
                RemoteState.SlideInfo(label: slide.displayLabel, preview: slide.text.components(separatedBy: "\n").first ?? "")
            },
            planName: plan?.name ?? "",
            plan: (plan?.items ?? []).map { item in
                RemoteState.PlanEntry(title: titles[item.songId] ?? "?", isCurrent: item.songId == song?.id)
            },
            labels: labels(),
            canStart: !store.isLive && startCandidate(in: store) != nil,
            startTitle: store.isLive ? "" : (startCandidate(in: store)?.title ?? "")
        )
    }
    
    static func perform(_ command: RemoteCommand, on store: DataStore) {
        switch command {
        case .next: store.nextSlide()
        case .previous: store.prevSlide()
        case .nextSong: store.nextSongInPlan()
        case .previousSong: store.prevSongInPlan()
        case .black: store.toggleBlackScreen()
        case .clearText: store.toggleClearText()
        case .stop: store.stopLive()
        case .start:
            guard !store.isLive, let song = startCandidate(in: store) else { return }
            // Wznowienie w tym samym miejscu, w którym projekcję zatrzymano.
            let index = song.id == store.activeSong?.id ? store.activeSlideIndex : 0
            store.present(song: song, slideIndex: index)
        case .slide(let index):
            if !store.isLive, let song = store.activeSong, index < song.slides.count {
                store.present(song: song, slideIndex: index)
            } else {
                store.jumpToSlide(index: index)
            }
        case .song(let id):
            guard let song = store.songs.first(where: { $0.id == id }) else { return }
            store.present(song: song)
            store.selectedSongId = song.id
        case .planItem(let index):
            guard let items = store.activePlan?.items, index < items.count,
                  let song = store.songs.first(where: { $0.id == items[index].songId }) else { return }
            store.present(song: song)
            store.selectedSongId = song.id
        }
    }
    
    /// Teksty strony telefonu w języku interfejsu aplikacji.
    static func labels() -> [String: String] {
        [
            "next": L("Dalej"),
            "previous": L("Wstecz"),
            "nextSong": L("Następna pieśń"),
            "previousSong": L("Poprzednia pieśń"),
            "black": L("Czarny ekran"),
            "clearText": L("Ukryj tekst"),
            "stop": L("Zakończ projekcję"),
            "slides": L("Slajdy"),
            "plan": L("Plan"),
            "notLive": L("Projekcja nie jest uruchomiona. Wybierz pieśń z planu lub wyszukaj ją."),
            "start": L("Rozpocznij projekcję"),
            "resume": L("Wznów projekcję"),
            "search": L("Szukaj pieśni"),
            "searchPlaceholder": L("Tytuł, autor lub fragment tekstu"),
            "noResults": L("Nie znaleziono pieśni"),
            "offline": L("Brak połączenia z komputerem. Sprawdź, czy telefon jest w tej samej sieci Wi-Fi."),
            "title": L("Pilot CantatePresenter")
        ]
    }
}
