import Foundation
import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers
import os

final class PresentationWKWebView: WKWebView {
    // Nie przejmuje fokusu, więc klawisze trafiają do `KeyboardMonitor` jako okno projekcji.
    override var acceptsFirstResponder: Bool { false }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let zoom = StandbyZoom.factor(forWidth: newSize.width)
        if abs(pageZoom - zoom) > 0.01 {
            pageZoom = zoom
        }
    }
}

/// Kontener planszy. `WKWebView` powstaje w nim dopiero wtedy, gdy lista reguł blokady sieci jest gotowa,
/// i dostaje ją w konfiguracji (R11-01): lista dodana do już utworzonego widoku dawała pustą planszę.
public final class StandbyContainerView: NSView {
    override public var acceptsFirstResponder: Bool { false }

    var webView: WKWebView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let webView else { return }
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
    }
}

// MARK: - Standby Zoom

/// Plansza ma rozmiary w px i rem dobrane do ok. 960 px szerokości; na projektorze były za małe.
/// Cała strona jest powiększana proporcjonalnie do szerokości (1920 px → ×2), także we własnych plikach.
public enum StandbyZoom {
    public static let designWidth: CGFloat = 960
    
    /// Dolna granica 0.1, a nie 0.3: podgląd w wąskim prawym panelu (poniżej ok. 290 px) ucinał planszę,
    /// bo strona przestawała się mieścić (R8-11).
    public static func factor(forWidth width: CGFloat) -> CGFloat {
        min(4.0, max(0.1, width / designWidth))
    }
}

// MARK: - Standby Credits

/// Autor na planszy startowej. Dopisywany w pamięci przy wczytywaniu, więc plik planszy
/// (także własny plik użytkownika) nie jest zmieniany.
public enum StandbyCredits {
    @MainActor
    public static var text: String {
        L("Autor: Andrzej Oles · we współpracy z Claude (Anthropic)")
    }
    
    public static func inject(into html: String, credits: String) -> String {
        guard !html.contains("Andrzej Oles") else { return html }
        let escaped = credits
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let element = """
        <div class="cantate-credits" style="position:fixed;left:0;right:0;bottom:10px;text-align:center;\
        font-family:-apple-system,sans-serif;font-size:1rem;letter-spacing:0.04em;color:rgba(255,255,255,0.6);">\
        \(escaped)</div>
        """
        if let body = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            return html.replacingCharacters(in: body, with: element + "\n</body>")
        }
        return html + element
    }
}

// MARK: - Standby Renderer

/// Składa planszę startową w pamięci (S8): logo, wersja, tekst gotowości i autor w wybranym języku.
/// Plik planszy (także własny plik użytkownika) nigdy nie jest zapisywany. Podmiany są zwykłymi
/// operacjami na napisach, więc znaki `$` i `\` w SVG logo niczego nie psują.
public enum StandbyRenderer {
    public static let logoMarker = "<!--LOGO-->"
    static let defaultReadyText = "GOTOWY DO PROJEKCJI • OCZEKIWANIE NA PREZENTACJĘ"
    
    public struct Texts {
        public var version: String
        public var ready: String
        public var credits: String
        
        public init(version: String, ready: String, credits: String) {
            self.version = version
            self.ready = ready
            self.credits = credits
        }
        
        @MainActor
        public static var current: Texts {
            Texts(
                version: L("Wersja {0}", AppVersion.current),
                ready: L(StandbyRenderer.defaultReadyText),
                credits: StandbyCredits.text
            )
        }
    }
    
    public static func render(html: String, logoSVG: String, texts: Texts) -> String {
        var result = html
        if let marker = result.range(of: logoMarker) {
            result.replaceSubrange(marker, with: logoSVG)
        } else if let open = result.range(of: "<div class=\"logo-wrapper\">"),
                  let close = result.range(of: "</div>", range: open.upperBound..<result.endIndex) {
            // Plansze sprzed znacznika: logo było wpisane w treść `logo-wrapper`.
            result.replaceSubrange(open.upperBound..<close.lowerBound, with: "\n" + logoSVG + "\n")
        }
        if let version = result.range(of: #"Wersja \d+(\.\d+)*"#, options: .regularExpression) {
            result.replaceSubrange(version, with: texts.version)
        }
        result = result.replacingOccurrences(of: defaultReadyText, with: texts.ready)
        return injectContentSecurityPolicy(into: StandbyCredits.inject(into: result, credits: texts.credits))
    }

    // MARK: Content Security Policy

    /// Szablon planszy może pochodzić z cudzej kopii zapasowej albo z pliku z internetu (R7-02):
    /// skrypty działają (zegar), ale nie mogą pobierać ani wysyłać niczego przez sieć. Obrazy, style i czcionki
    /// tylko z plików obok szablonu i z `data:` (logo END). CSP nie obejmuje `<link rel="preconnect">`,
    /// więc połączenia blokuje też lista reguł `StandbyNetworkBlock` (R11-01).
    public static let contentSecurityPolicy = "default-src 'none'; img-src file: data:; style-src 'unsafe-inline' file:; "
        + "font-src file: data:; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"

    /// Wstawia CSP na samym początku dokumentu (zaraz po `<!DOCTYPE>`), przed jakimkolwiek skryptem szablonu.
    /// Parser HTML umieszcza taki `<meta>` w niejawnym `<head>`, więc obejmuje całą stronę.
    static func injectContentSecurityPolicy(into html: String) -> String {
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"
        let body = html.drop { $0.isWhitespace || $0 == "\u{FEFF}" }
        if body.prefix(9).lowercased() == "<!doctype", let end = body.firstIndex(of: ">") {
            let doctype = body[...end]
            var rest = body[body.index(after: end)...]
            var separator = ""
            if rest.first == "\n" {
                separator = "\n"
                rest = rest.dropFirst()
            }
            return String(doctype) + separator + meta + "\n" + String(rest)
        }
        return meta + "\n" + String(body)
    }
}

// MARK: - Standby Network Block

/// Druga warstwa obok CSP (R11-01). CSP nie zatrzymuje `<link rel="preconnect">` ani `prerender`, więc skrypt
/// szablonu mógł otworzyć połączenie (DNS i TCP) z dowolnym hostem i w ten sposób wysyłać dane. Lista reguł
/// WebKit blokuje każde wczytanie `http(s)` i `ws(s)`. Kompilowana raz na uruchomienie; plansza wczytuje się
/// dopiero, gdy lista jest dodana do widoku, a bez niej tylko szablon z pakietu aplikacji.
@MainActor
public enum StandbyNetworkBlock {
    public static let identifier = "com.cantate.presenter.standby-network-block"
    /// Wyrażenia reguł WebKit nie mają `|`, więc dwie reguły.
    public static let encodedRules = """
    [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},\
    {"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}]
    """

    private static var ruleList: WKContentRuleList?
    private static var failed = false
    private static var waiting: [(WKContentRuleList?) -> Void] = []

    /// Wywołuje `completion` z listą reguł (od razu, jeśli jest już skompilowana) albo z `nil`, gdy kompilacja się
    /// nie udała.
    static func withRuleList(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let ruleList { return completion(ruleList) }
        if failed { return completion(nil) }
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        compile(in: WKContentRuleListStore.default()) { list in
            ruleList = list
            failed = list == nil
            let callbacks = waiting
            waiting = []
            callbacks.forEach { $0(list) }
        }
    }

    /// Kompiluje listę w podanym magazynie; `nil` przy błędzie (zapisanym w dzienniku).
    static func compile(in store: WKContentRuleListStore?, completion: @escaping @MainActor (WKContentRuleList?) -> Void) {
        guard let store else {
            logger.error("Plansza: brak magazynu reguł WebKit")
            return completion(nil)
        }
        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encodedRules) { list, error in
            if let error {
                logger.error("Plansza: nie udało się skompilować blokady sieci: \(String(describing: error), privacy: .public)")
            }
            MainActor.assumeIsolated { completion(list) }
        }
    }

    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "standby")
}

// MARK: - Standby Navigation Policy

/// Plansza wyświetla tylko to, co wczytała aplikacja (R7-02): każde wczytanie zlecone przez
/// `loadHTMLString` przepuszcza dokładnie jedną nawigację głównej ramki pod adres bazowy;
/// przekierowania, linki, `location = …` i `<meta http-equiv="refresh">` są odrzucane.
public struct StandbyNavigationPolicy: Sendable {
    private var expected: String?

    public init() {}

    public mutating func expectLoad(baseURL: URL?) {
        expected = (baseURL ?? URL(string: "about:blank"))?.absoluteString
    }

    public mutating func allow(url: URL?, isMainFrame: Bool) -> Bool {
        guard isMainFrame, let expected, url?.absoluteString == expected else { return false }
        self.expected = nil
        return true
    }
}

// MARK: - Standby Template

/// Skąd brana jest plansza startowa (R4-37): własny plik z Ustawień, `standby.html` w katalogu danych
/// (przeniesiony ze starszych wersji), a na świeżej instalacji szablon z pakietu aplikacji
/// (`Resources/standby.html`: logo, wersja, zegar, tekst gotowości).
public enum StandbyTemplate {
    public static var bundledURL: URL? {
        Localization.resourceBundle?.url(forResource: "standby", withExtension: "html")
    }

    /// Zwykły plik `.html`/`.htm` (także przez dowiązanie). Ścieżka z ustawień może pochodzić z cudzej kopii
    /// zapasowej, więc program, pakiet `.app` ani katalog nie są brane za planszę (R11-03).
    public static func isHTMLFile(atPath path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard ["html", "htm"].contains(url.pathExtension.lowercased()) else { return false }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    public static func url(customPath: String, dataFile: URL = AppPaths.shared.standbyFile) -> URL? {
        if isHTMLFile(atPath: customPath) {
            return URL(fileURLWithPath: customPath)
        }
        if isHTMLFile(atPath: dataFile.path) {
            return dataFile
        }
        return bundledURL
    }

    /// „Otwórz plik planszy”: zawsze w domyślnej aplikacji dla HTML, nigdy przez `NSWorkspace.open` samego pliku,
    /// który dla programu albo `.command` by go uruchomił (R11-03). Bez takiej aplikacji: pokazanie w Finderze.
    @MainActor
    public static func openInHTMLViewer(_ url: URL) {
        let workspace = NSWorkspace.shared
        guard isHTMLFile(atPath: url.path), let viewer = workspace.urlForApplication(toOpen: .html) else {
            workspace.activateFileViewerSelecting([url])
            return
        }
        workspace.open([url], withApplicationAt: viewer, configuration: NSWorkspace.OpenConfiguration())
    }
}

public struct StandbyWebView: NSViewRepresentable {
    public let htmlPath: String
    public let activeLogoId: String
    
    public init(htmlPath: String = "", activeLogoId: String = "") {
        self.htmlPath = htmlPath
        self.activeLogoId = activeLogoId
    }
    
    /// Bez `allowFileAccessFromFileURLs` (R7-02): skrypt szablonu nie odczyta plików z dysku. Obrazy i style
    /// obok szablonu nadal się wczytują jako zwykłe zasoby strony.
    static func makeConfiguration(ruleList: WKContentRuleList? = nil) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        if let ruleList {
            config.userContentController.add(ruleList)
        }
        return config
    }

    public func makeNSView(context: Context) -> StandbyContainerView {
        let container = StandbyContainerView()
        context.coordinator.lastLoadedPath = htmlPath
        context.coordinator.lastLogoId = activeLogoId
        context.coordinator.lastCredits = StandbyCredits.text
        loadHTML(into: container, coordinator: context.coordinator)
        return container
    }
    
    public func updateNSView(_ nsView: StandbyContainerView, context: Context) {
        // Napis z autorem zależy od języka, więc jego zmiana też przeładowuje planszę.
        let credits = StandbyCredits.text
        if context.coordinator.lastLoadedPath != htmlPath || context.coordinator.lastLogoId != activeLogoId
            || context.coordinator.lastCredits != credits {
            context.coordinator.lastLoadedPath = htmlPath
            context.coordinator.lastLogoId = activeLogoId
            context.coordinator.lastCredits = credits
            loadHTML(into: nsView, coordinator: context.coordinator)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedPath: String = ""
        var lastLogoId: String = ""
        var lastCredits: String = ""
        var navigationPolicy = StandbyNavigationPolicy()
        /// Numer ostatniego zlecenia wczytania: po kompilacji reguł wczytywane jest tylko najnowsze.
        var loadRequest = 0
        var networkBlockInstalled = false

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
            decisionHandler(navigationPolicy.allow(url: navigationAction.request.url, isMainFrame: isMainFrame) ? .allow : .cancel)
        }
    }

    /// Wczytanie dopiero z blokadą sieci (R11-01). Gdy listy reguł nie da się skompilować, plansza jest tylko
    /// z szablonu w pakiecie aplikacji: własny plik albo `standby.html` z cudzej kopii mógłby się wtedy łączyć.
    private func loadHTML(into container: StandbyContainerView, coordinator: Coordinator) {
        coordinator.loadRequest += 1
        let request = coordinator.loadRequest
        StandbyNetworkBlock.withRuleList { [weak container] ruleList in
            guard let container, request == coordinator.loadRequest else { return }
            let webView = container.webView ?? makeWebView(in: container, ruleList: ruleList, coordinator: coordinator)
            render(into: webView, coordinator: coordinator, networkBlocked: coordinator.networkBlockInstalled)
        }
    }

    private func makeWebView(in container: StandbyContainerView, ruleList: WKContentRuleList?, coordinator: Coordinator) -> WKWebView {
        let webView = PresentationWKWebView(frame: container.bounds, configuration: Self.makeConfiguration(ruleList: ruleList))
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = coordinator
        coordinator.networkBlockInstalled = ruleList != nil
        container.webView = webView
        return webView
    }

    private func render(into webView: WKWebView, coordinator: Coordinator, networkBlocked: Bool) {
        let fileManager = FileManager.default
        let resolvedLogoId = !activeLogoId.isEmpty ? activeLogoId : DataStore.shared.settings.activeLogoId
        let logoSVG = LogoCatalog.getById(resolvedLogoId).svgContent

        let targetURL = networkBlocked ? StandbyTemplate.url(customPath: htmlPath) : StandbyTemplate.bundledURL
        let template = targetURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? Self.fallbackTemplate
        let baseURL = targetURL.flatMap { fileManager.fileExists(atPath: $0.path) ? $0.deletingLastPathComponent() : nil }
        coordinator.navigationPolicy.expectLoad(baseURL: baseURL)
        webView.loadHTMLString(StandbyRenderer.render(html: template, logoSVG: logoSVG, texts: .current), baseURL: baseURL)
    }

    /// Plansza awaryjna, gdy nie da się odczytać żadnego szablonu (np. brak paczki zasobów).
    static let fallbackTemplate = """
    <!DOCTYPE html><html><head><meta charset="utf-8"></head>\
    <body style="background:#0a0e1a;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;font-family:-apple-system,sans-serif;">
    <div class="logo-wrapper" style="width:140px;height:140px;margin-bottom:18px;">\(StandbyRenderer.logoMarker)</div>
    <h1 style="font-size:42px;margin:0;font-weight:700;">CantatePresenter</h1>
    <p style="color:#94a3b8;font-size:18px;margin-top:8px;">Wersja 1.0.0</p>
    </body></html>
    """
}
