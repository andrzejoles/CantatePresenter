import Foundation
import SwiftUI
import WebKit

public struct LogoGallerySheet: View {
    @ObservedObject var store = DataStore.shared
    @Binding var isPresented: Bool
    
    @State private var selectedLogoId: String = ""
    @State private var successNotice: String?
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Galeria propozycji logo aplikacji")
                        .font(.scaled(16, weight: .bold, scale: scale))
                    Text("Wybierz logo, które będzie reprezentować program na planszy czuwania (standby) i w materiałach")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Gotowe") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Notice banner if chosen
            if let notice = successNotice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(notice)
                        .font(.scaled(12, weight: .medium, scale: scale))
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
            }
            
            // Grid of 16 logos
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(LogoCatalog.all) { logo in
                        LogoCardView(
                            logo: logo,
                            isSelected: store.settings.activeLogoId == logo.id,
                            scale: scale,
                            onSelect: {
                                store.updateActiveLogo(id: logo.id)
                                successNotice = "Ustawiono aktywne logo: \(logo.name)"
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 780, minHeight: 600)
    }
}

public struct LogoCardView: View {
    public let logo: LogoPreset
    public let isSelected: Bool
    public let scale: Double
    public let onSelect: () -> Void
    
    public init(logo: LogoPreset, isSelected: Bool, scale: Double, onSelect: @escaping () -> Void) {
        self.logo = logo
        self.isSelected = isSelected
        self.scale = scale
        self.onSelect = onSelect
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                SVGThumbnailView(svgString: logo.svgContent)
                    .frame(height: 140)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                
                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Aktywne")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .padding(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(logo.name)
                        .font(.scaled(12, weight: .bold, scale: scale))
                    Spacer()
                    Text(logo.category)
                        .font(.scaled(8, weight: .semibold, scale: scale))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                
                Text(logo.subtitle)
                    .font(.scaled(10, scale: scale))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Button(action: onSelect) {
                Text(isSelected ? "Wybrane jako główne" : "Wybierz to logo")
                    .font(.scaled(11, weight: .medium, scale: scale))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.green : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2.5 : 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0.05), radius: 4, x: 0, y: 2)
    }
}

public struct SVGThumbnailView: NSViewRepresentable {
    public let svgString: String
    
    public init(svgString: String) {
        self.svgString = svgString
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { margin: 0; padding: 0; background: transparent; display: flex; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
        svg { width: 90%; height: 90%; }
        </style></head><body>\(svgString)</body></html>
        """
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
