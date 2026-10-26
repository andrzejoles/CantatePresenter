import Foundation
import SwiftUI
import WebKit
import AppKit

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
        return StandbyCredits.inject(into: result, credits: texts.credits)
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

    public static func url(customPath: String, dataFile: URL = AppPaths.shared.standbyFile) -> URL? {
        let fileManager = FileManager.default
        if !customPath.isEmpty && fileManager.fileExists(atPath: customPath) {
            return URL(fileURLWithPath: customPath)
        }
        if fileManager.fileExists(atPath: dataFile.path) {
            return dataFile
        }
        return bundledURL
    }
}

public struct StandbyWebView: NSViewRepresentable {
    public let htmlPath: String
    public let activeLogoId: String
    
    public init(htmlPath: String = "", activeLogoId: String = "") {
        self.htmlPath = htmlPath
        self.activeLogoId = activeLogoId
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = PresentationWKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        
        context.coordinator.lastLoadedPath = htmlPath
        context.coordinator.lastLogoId = activeLogoId
        context.coordinator.lastCredits = StandbyCredits.text
        loadHTML(into: webView)
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // Napis z autorem zależy od języka, więc jego zmiana też przeładowuje planszę.
        let credits = StandbyCredits.text
        if context.coordinator.lastLoadedPath != htmlPath || context.coordinator.lastLogoId != activeLogoId
            || context.coordinator.lastCredits != credits {
            context.coordinator.lastLoadedPath = htmlPath
            context.coordinator.lastLogoId = activeLogoId
            context.coordinator.lastCredits = credits
            loadHTML(into: nsView)
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public class Coordinator {
        var lastLoadedPath: String = ""
        var lastLogoId: String = ""
        var lastCredits: String = ""
    }
    
    private func loadHTML(into webView: WKWebView) {
        let fileManager = FileManager.default
        let resolvedLogoId = !activeLogoId.isEmpty ? activeLogoId : DataStore.shared.settings.activeLogoId
        let logoSVG = LogoCatalog.getById(resolvedLogoId).svgContent
        
        let targetURL = StandbyTemplate.url(customPath: htmlPath)
        let template = targetURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? Self.fallbackTemplate
        let baseURL = targetURL.flatMap { fileManager.fileExists(atPath: $0.path) ? $0.deletingLastPathComponent() : nil }
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
