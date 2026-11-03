import Foundation
import SwiftUI
import WebKit
import AppKit

// MARK: - Insert Mode

/// Co wstawić do edytora z otwartej strony pieśni.
public enum WywrotaInsertMode: Sendable {
    case lyrics
    case chords
    case lyricsAndChords
}

// MARK: - Browser Model

/// Przeglądarka Śpiewnika Wywroty w aplikacji. Strony otwiera i przegląda użytkownik, jak w Safari; aplikacja
/// odczytuje tylko stronę na ekranie i tylko po kliknięciu „Wstaw…” (regulamin serwisu §7.1: bez automatycznego
/// i masowego pobierania). Logowanie zostaje w danych WebKit aplikacji, więc serwis pokazuje całe opracowania.
@MainActor
final class WywrotaBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum PageState: Equatable {
        case loading
        /// Strona bez opracowania (wyszukiwanie, lista, logowanie).
        case noSong
        /// Serwis pokazuje tylko początek opracowania (niezalogowany użytkownik).
        case truncated
        case song(WywrotaSong)
    }

    @Published private(set) var state: PageState = .loading
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    let webView: WKWebView
    /// Numer wczytanej strony: odczyt poprzedniej strony, który skończył się po przejściu dalej, jest pomijany.
    private var pageGeneration = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Serwis rozpoznaje Safari; bez tego dopisku WebKit przedstawia się jako nieznana przeglądarka.
        configuration.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func open(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = WywrotaParser.searchURL(for: trimmed) else { return }
        open(url)
    }

    private func updateNavigation() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    /// Odczyt strony na ekranie (`WywrotaParser.pageScript`) po jej wczytaniu.
    private func readPage() {
        pageGeneration += 1
        let generation = pageGeneration
        let url = webView.url
        webView.evaluateJavaScript(WywrotaParser.pageScript) { [weak self] result, _ in
            let json = result as? String
            MainActor.assumeIsolated {
                guard let self, generation == self.pageGeneration else { return }
                self.state = Self.state(json: json, url: url)
            }
        }
    }

    nonisolated static func state(json: String?, url: URL?) -> PageState {
        guard let json, let url, WywrotaParser.isWywrotaHost(url.host),
              let page = try? JSONDecoder().decode(WywrotaParser.Page.self, from: Data(json.utf8)) else { return .noSong }
        if page.truncated { return .truncated }
        let song = WywrotaParser.song(page: page, url: url.absoluteString)
        return song.lyrics.isEmpty && song.chords == nil ? .noSong : .song(song)
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard isMainFrame, let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.allow)
            return
        }
        if WywrotaParser.isWywrotaHost(url.host) {
            decisionHandler(.allow)
        } else {
            // Strony spoza serwisu (sklepy z aplikacjami, linki w opisach) w zwykłej przeglądarce.
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pageGeneration += 1
        state = .loading
        updateNavigation()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigation()
        readPage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigation()
        state = .noSong
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavigation()
        state = .noSong
    }

    // MARK: WKUIDelegate

    /// Link otwierany w nowym oknie: strona serwisu w tym samym widoku, inne w zwykłej przeglądarce.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if WywrotaParser.isWywrotaHost(url.host) {
                webView.load(URLRequest(url: url))
            } else if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }
}

// MARK: - Web View

private struct WywrotaWebView: NSViewRepresentable {
    let model: WywrotaBrowserModel

    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Browser Sheet

/// Okno ze Śpiewnikiem Wywroty: wyszukanie pieśni na stronie serwisu i wstawienie do edytora jej tekstu,
/// chwytów albo obu naraz (decyzja właściciela 2026-11-03).
struct WywrotaBrowserSheet: View {
    @Binding var isPresented: Bool
    let initialQuery: String
    let onInsert: (WywrotaSong, WywrotaInsertMode) -> Void

    @StateObject private var model = WywrotaBrowserModel()
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: { model.webView.goBack() }) { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack)
                    .helpLabel(L("Wstecz"))
                Button(action: { model.webView.goForward() }) { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                    .helpLabel(L("Dalej"))
                Button(action: { model.open(WywrotaParser.homeURL) }) { Image(systemName: "house") }
                    .helpLabel(L("Piosenki religijne w Śpiewniku Wywroty"))
                TextField(L("Tytuł lub fragment tekstu"), text: $query)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 220)
                    .onSubmit { model.search(query) }
                Button(L("Szukaj")) { model.search(query) }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button(L("Zamknij")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.bordered)
            .padding(10)

            Divider()

            WywrotaWebView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isTruncated ? .orange : .primary)
                        .lineLimit(2)
                    Spacer()
                    Button(L("Wstaw tekst")) { insert(.lyrics) }
                        .disabled(currentSong?.lyrics.isEmpty ?? true)
                    Button(L("Wstaw chwyty")) { insert(.chords) }
                        .disabled(currentSong?.chords == nil)
                    Button(L("Wstaw tekst i chwyty")) { insert(.lyricsAndChords) }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentSong == nil || currentSong?.chords == nil || currentSong?.lyrics.isEmpty == true)
                }
                Text(L("Wstawiana jest tylko pieśń otwarta na tej stronie. Teksty i opracowania należą do ich autorów i mogą być chronione prawem autorskim."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.bordered)
            .padding(10)
        }
        // Arkusz nad arkuszem edytora (min. 740 × 580): nie może wymuszać większego rozmiaru niż on.
        .frame(minWidth: 720, idealWidth: 940, minHeight: 540, idealHeight: 680)
        .onAppear {
            query = initialQuery
            let trimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                model.open(WywrotaParser.homeURL)
            } else {
                model.search(trimmed)
            }
        }
    }

    private var currentSong: WywrotaSong? {
        if case .song(let song) = model.state { return song }
        return nil
    }

    private var isTruncated: Bool { model.state == .truncated }

    private var statusText: String {
        switch model.state {
        case .loading: return L("Wczytywanie...")
        case .noSong: return L("Otwórz stronę pieśni, aby wstawić jej tekst lub chwyty.")
        case .truncated: return L("Strona pokazuje tylko początek opracowania. Zaloguj się w Śpiewniku Wywroty (u góry strony), aby wstawić całość.")
        case .song(let song): return song.title.isEmpty ? L("Pieśń gotowa do wstawienia") : L("Pieśń: {0}", song.title)
        }
    }

    private func insert(_ mode: WywrotaInsertMode) {
        guard let song = currentSong else { return }
        onInsert(song, mode)
        isPresented = false
    }
}
