import Foundation
import SwiftUI
import AppKit

public struct PresentationContentView: View {
    @Bindable var store = DataStore.shared
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
                    
                    SlideTextView(text: slide.text, settings: settings, fontSize: optimalSize, containerSize: size,
                                  footer: store.currentLiveCopyrightNotice)
                }
                
                // Subtle overlay banner for windowed preview
                if isPreviewWindow {
                    VStack {
                        HStack {
                            Text(L("OKNO PODGLĄDU PROJEKCJI"))
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
                                    Text(L("Naciśnij ESC, aby wyjść z pełnego ekranu"))
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
}

