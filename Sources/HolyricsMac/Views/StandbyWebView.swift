import Foundation
import SwiftUI
import WebKit
import AppKit

public struct StandbyWebView: NSViewRepresentable {
    public let htmlPath: String
    
    public init(htmlPath: String) {
        self.htmlPath = htmlPath
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        
        loadHTML(into: webView)
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedPath != htmlPath {
            context.coordinator.lastLoadedPath = htmlPath
            loadHTML(into: nsView)
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public class Coordinator {
        var lastLoadedPath: String = ""
    }
    
    private func loadHTML(into webView: WKWebView) {
        let targetURL: URL
        let fileManager = FileManager.default
        
        // 1. Try specified path
        if !htmlPath.isEmpty && fileManager.fileExists(atPath: htmlPath) {
            targetURL = URL(fileURLWithPath: htmlPath)
        } else {
            // 2. Try default path in data directory
            let bundleURL = Bundle.main.bundleURL
            let projectFolder = bundleURL.pathExtension == "app"
                ? bundleURL.deletingLastPathComponent()
                : URL(fileURLWithPath: fileManager.currentDirectoryPath)
            
            let defaultURL = projectFolder.appendingPathComponent("data/standby.html")
            if fileManager.fileExists(atPath: defaultURL.path) {
                targetURL = defaultURL
            } else {
                // Fallback inline basic HTML
                webView.loadHTMLString("""
                <!DOCTYPE html><html><body style="background:#0a0e1a;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;font-family:-apple-system,sans-serif;">
                <h1 style="font-size:42px;margin:0;">Holyrics Mac</h1>
                <p style="color:#38bdf8;font-size:18px;">Wersja 1.0.0 — Gotowy do projekcji</p>
                </body></html>
                """, baseURL: nil)
                return
            }
        }
        
        webView.loadFileURL(targetURL, allowingReadAccessTo: targetURL.deletingLastPathComponent())
    }
}
