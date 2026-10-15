import Foundation
import SwiftUI
import AppKit

public struct PresentationContentView: View {
    @ObservedObject var store = DataStore.shared
    public var isPreviewWindow: Bool = false
    
    @State private var showEscHint: Bool = false
    
    public init(isPreviewWindow: Bool = false) {
        self.isPreviewWindow = isPreviewWindow
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let settings = store.settings
            let bgColor = Color(hex: settings.backgroundColorHex)
            let txtColor = Color(hex: settings.textColorHex)
            
            ZStack {
                // Background & Standby Screen
                if store.isBlackScreen {
                    Color.black
                        .ignoresSafeArea()
                } else if !store.isLive {
                    // Display configured HTML Standby Screen with dynamically injected active logo
                    StandbyWebView(htmlPath: settings.standbyHtmlPath, activeLogoId: settings.activeLogoId)
                        .ignoresSafeArea()
                } else {
                    bgColor
                        .ignoresSafeArea()
                }
                
                // Text layer (when presentation is live)
                if store.isLive && !store.isBlackScreen && !store.isClearText,
                   let slide = store.currentLiveSlide {
                    
                    let optimalSize = AutoFitEngine.calculateOptimalFontSize(
                        for: slide.text,
                        containerSize: size,
                        fontFamily: settings.fontFamily,
                        isBold: settings.isBold,
                        lineSpacingFactor: settings.lineSpacingFactor,
                        marginPercent: settings.marginPercent
                    )
                    
                    let horizontalPadding = size.width * CGFloat(settings.marginPercent)
                    let verticalPadding = size.height * CGFloat(settings.marginPercent)
                    
                    VStack(alignment: alignmentForString(settings.textAlignment)) {
                        if settings.verticalAlignment == "bottom" {
                            Spacer()
                        }
                        
                        Text(slide.text)
                            .font(customFont(name: settings.fontFamily, size: optimalSize, isBold: settings.isBold))
                            .foregroundColor(txtColor)
                            .multilineTextAlignment(textAlignmentForString(settings.textAlignment))
                            .lineSpacing(optimalSize * CGFloat(settings.lineSpacingFactor - 1.0))
                            .shadow(color: settings.hasShadow ? Color.black.opacity(0.85) : Color.clear, radius: 4, x: 2, y: 2)
                            .frame(maxWidth: .infinity, alignment: frameAlignmentForString(settings.textAlignment))
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, verticalPadding)
                        
                        if settings.verticalAlignment == "top" {
                            Spacer()
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
                
                // Subtle overlay banner for windowed preview
                if isPreviewWindow {
                    VStack {
                        HStack {
                            Text("OKNO PODGLĄDU PROJEKCJI")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white.opacity(0.7))
                                .cornerRadius(4)
                            Spacer()
                        }
                        .padding(8)
                        Spacer()
                    }
                }
                
                // Auto-fading ESC hint when running on single screen
                if !isPreviewWindow && showEscHint {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                // Zamknięcie po zakończeniu obsługi kliknięcia: przycisk leży w zamykanym oknie.
                                DispatchQueue.main.async {
                                    ScreenManager.shared.stopPresentation()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "keyboard")
                                    Text("Naciśnij ESC, aby wyjść z pełnego ekranu")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.black.opacity(0.75))
                                .foregroundColor(.white.opacity(0.9))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            Spacer()
                        }
                        .padding(.top, 18)
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            if !isPreviewWindow && NSScreen.screens.count == 1 {
                showEscHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showEscHint = false
                    }
                }
            }
        }
    }
    
    private func customFont(name: String, size: CGFloat, isBold: Bool) -> Font {
        if name == "System" || name == "SF Pro" {
            return .system(size: size, weight: isBold ? .bold : .regular)
        }
        return .custom(name, size: size).weight(isBold ? .bold : .regular)
    }
    
    private func alignmentForString(_ alignment: String) -> HorizontalAlignment {
        switch alignment.lowercased() {
        case "left", "lewo": return .leading
        case "right", "prawo": return .trailing
        default: return .center
        }
    }
    
    private func textAlignmentForString(_ alignment: String) -> TextAlignment {
        switch alignment.lowercased() {
        case "left", "lewo": return .leading
        case "right", "prawo": return .trailing
        default: return .center
        }
    }
    
    private func frameAlignmentForString(_ alignment: String) -> Alignment {
        switch alignment.lowercased() {
        case "left", "lewo": return .leading
        case "right", "prawo": return .trailing
        default: return .center
        }
    }
}
