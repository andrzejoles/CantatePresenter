import Foundation
import SwiftUI
import WebKit
import AppKit

final class PresentationWKWebView: WKWebView {
    // Nie przejmuje fokusu, więc klawisze trafiają do `KeyboardMonitor` jako okno projekcji.
    override var acceptsFirstResponder: Bool { false }
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
        font-family:-apple-system,sans-serif;font-size:0.8rem;letter-spacing:0.04em;color:rgba(255,255,255,0.38);">\
        \(escaped)</div>
        """
        if let body = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            return html.replacingCharacters(in: body, with: element + "\n</body>")
        }
        return html + element
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
        
        let targetURL: URL
        if !htmlPath.isEmpty && fileManager.fileExists(atPath: htmlPath) {
            targetURL = URL(fileURLWithPath: htmlPath)
        } else {
            let defaultURL = AppPaths.shared.standbyFile
            if fileManager.fileExists(atPath: defaultURL.path) {
                targetURL = defaultURL
            } else {
                let resolvedLogoId = !activeLogoId.isEmpty ? activeLogoId : DataStore.shared.settings.activeLogoId
                let logoPreset = LogoCatalog.getById(resolvedLogoId)
                webView.loadHTMLString(StandbyCredits.inject(into: """
                <!DOCTYPE html><html><body style="background:#0a0e1a;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;font-family:-apple-system,sans-serif;">
                <div style="width:140px;height:140px;margin-bottom:18px;">\(logoPreset.svgContent)</div>
                <h1 style="font-size:42px;margin:0;font-weight:700;">CantatePresenter</h1>
                <p style="color:#94a3b8;font-size:18px;margin-top:8px;">Wersja 1.0.0</p>
                </body></html>
                """, credits: StandbyCredits.text), baseURL: nil)
                return
            }
        }
        
        // Read HTML and dynamically inject current active logo
        if var htmlContent = try? String(contentsOf: targetURL, encoding: .utf8) {
            let resolvedLogoId = !activeLogoId.isEmpty ? activeLogoId : DataStore.shared.settings.activeLogoId
            let logoPreset = LogoCatalog.getById(resolvedLogoId)
            
            let regexPattern = "(<div class=\"logo-wrapper\">)[\\s\\S]*?(</div>)"
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
                let range = NSRange(location: 0, length: (htmlContent as NSString).length)
                let safeSvg = logoPreset.svgContent.replacingOccurrences(of: "$", with: "\\$")
                let replacement = "$1\n            " + safeSvg + "\n        $2"
                htmlContent = regex.stringByReplacingMatches(in: htmlContent, options: [], range: range, withTemplate: replacement)
            }
            
            webView.loadHTMLString(StandbyCredits.inject(into: htmlContent, credits: StandbyCredits.text), baseURL: targetURL.deletingLastPathComponent())
        } else {
            webView.loadFileURL(targetURL, allowingReadAccessTo: targetURL.deletingLastPathComponent())
        }
    }
}
