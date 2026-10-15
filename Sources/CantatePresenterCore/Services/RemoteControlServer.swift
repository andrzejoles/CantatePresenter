import Foundation
import Network
import Observation
import os

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
    public private(set) var token = RemoteRouter.makeToken()
    public private(set) var errorMessage: String?
    public private(set) var lastSeen: [String: Date] = [:]
    
    /// Obsługa żądania z bieżącym tokenem; w testach podmieniana, żeby nie dotykać `DataStore.shared`.
    var route: @MainActor (RemoteHTTPRequest, String) -> RemoteHTTPResponse
    
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.cantate.presenter.remote")
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "remote")
    
    init(route: (@MainActor (RemoteHTTPRequest, String) -> RemoteHTTPResponse)? = nil) {
        self.route = route ?? { request, token in
            RemoteControlBridge.response(for: request, token: token, store: DataStore.shared)
        }
    }
    
    // MARK: - Lifecycle
    
    public func start(port requestedPort: UInt16 = RemoteControlServer.preferredPort) {
        guard listener == nil else { return }
        errorMessage = nil
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let nwPort = NWEndpoint.Port(rawValue: requestedPort) ?? .any
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state, requestedPort: requestedPort) }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            fail(error, requestedPort: requestedPort)
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = nil
        lastSeen = [:]
    }
    
    /// Nowy token: dotychczasowe telefony tracą dostęp i muszą zeskanować nowy kod.
    public func regenerateToken() {
        token = RemoteRouter.makeToken()
        lastSeen = [:]
    }
    
    private func listenerChanged(_ state: NWListener.State, requestedPort: UInt16) {
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
    
    // MARK: - Connections
    
    nonisolated private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Połączenie, które nie przyśle żądania w 10 s, jest zamykane.
        queue.asyncAfter(deadline: .now() + 10) { connection.cancel() }
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
                let host = Self.host(of: connection.endpoint)
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    let response = self.route(request, self.token)
                    if response.status == 200 { self.lastSeen[host] = Date() }
                    Self.send(response, on: connection)
                }
            default:
                Self.send(.text("Bad request", status: 400), on: connection)
            }
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
            let host = String(cString: hostBuffer)
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
    static func response(for request: RemoteHTTPRequest, token: String, store: DataStore) -> RemoteHTTPResponse {
        RemoteRouter(token: token).response(
            for: request,
            page: { RemoteControlPage.html(language: store.settings.appLanguage) },
            state: { state(of: store) },
            perform: { perform($0, on: store) }
        )
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
            labels: labels()
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
        case .slide(let index): store.jumpToSlide(index: index)
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
            "notLive": L("Projekcja nie jest uruchomiona. Wybierz pieśń z planu."),
            "offline": L("Brak połączenia z komputerem. Sprawdź, czy telefon jest w tej samej sieci Wi-Fi."),
            "title": L("Pilot CantatePresenter")
        ]
    }
}
