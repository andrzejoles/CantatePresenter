import Foundation
import SwiftUI
import WebKit
import AppKit

final class PresentationWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC
            Task { @MainActor in
                ScreenManager.shared.stopPresentation()
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            Task { @MainActor in
                ScreenManager.shared.stopPresentation()
            }
            return
        }
        super.keyDown(with: event)
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
        loadHTML(into: webView)
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedPath != htmlPath || context.coordinator.lastLogoId != activeLogoId {
            context.coordinator.lastLoadedPath = htmlPath
            context.coordinator.lastLogoId = activeLogoId
            loadHTML(into: nsView)
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public class Coordinator {
        var lastLoadedPath: String = ""
        var lastLogoId: String = ""
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
                webView.loadHTMLString("""
                <!DOCTYPE html><html><body style="background:#0a0e1a;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;font-family:-apple-system,sans-serif;">
                <div style="width:140px;height:140px;margin-bottom:18px;">\(logoPreset.svgContent)</div>
                <h1 style="font-size:42px;margin:0;font-weight:700;">CantatePresenter</h1>
                <p style="color:#94a3b8;font-size:18px;margin-top:8px;">Wersja 1.0.0</p>
                </body></html>
                """, baseURL: nil)
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
            
            webView.loadHTMLString(htmlContent, baseURL: targetURL.deletingLastPathComponent())
        } else {
            webView.loadFileURL(targetURL, allowingReadAccessTo: targetURL.deletingLastPathComponent())
        }
    }
}
