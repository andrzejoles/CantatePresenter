import Foundation
import SwiftUI
import AppKit

public struct LiveOutputView: View {
    @ObservedObject var store = DataStore.shared
    @ObservedObject var screenManager = ScreenManager.shared
    
    public init() {}
    
    private var nextSlide: SongSlide? {
        guard let song = store.activeSong, store.isLive else { return nil }
        let nextIndex = store.activeSlideIndex + 1
        if nextIndex < song.slides.count {
            return song.slides[nextIndex]
        }
        return nil
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - Section 1: Live Monitor (What's on screen)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Ekran na żywo", systemImage: "display")
                            .font(.scaled(13, weight: .bold, scale: scale))
                        
                        Spacer()
                        
                        if store.isLive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("LIVE")
                                    .font(.scaled(10, weight: .bold, scale: scale))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(4)
                        } else {
                            Text("OFF AIR")
                                .font(.scaled(10, weight: .bold, scale: scale))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    
                    // 16:9 Aspect Ratio Mini Screen
                    ZStack {
                        let bgColor = Color(hex: store.settings.backgroundColorHex)
                        let txtColor = Color(hex: store.settings.textColorHex)
                        
                        if store.isBlackScreen {
                            Color.black
                            Text("CZARNY EKRAN")
                                .font(.scaled(11, weight: .bold, scale: scale))
                                .foregroundColor(.white.opacity(0.5))
                        } else if !store.isLive {
                            Color(hex: "#0e111d")
                            VStack(spacing: 6) {
                                Image(systemName: "sparkles.tv")
                                    .font(.system(size: 24))
                                    .foregroundColor(.cyan)
                                Text("PLANSZA STARTOWA")
                                    .font(.scaled(11, weight: .bold, scale: scale))
                                    .foregroundColor(.white)
                                Text("CantatePresenter v1.0.0 • Standby")
                                    .font(.scaled(9, scale: scale))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        } else if store.isClearText {
                            bgColor
                            Text("TEKST UKRYTY")
                                .font(.scaled(11, weight: .bold, scale: scale))
                                .foregroundColor(txtColor.opacity(0.4))
                        } else if let slide = store.currentLiveSlide {
                            bgColor
                            Text(slide.text)
                                .font(customFont(name: store.settings.fontFamily, size: 14 * CGFloat(scale), isBold: store.settings.isBold))
                                .foregroundColor(txtColor)
                                .multilineTextAlignment(alignmentForString(store.settings.textAlignment))
                                .shadow(color: store.settings.hasShadow ? Color.black.opacity(0.8) : Color.clear, radius: 2, x: 1, y: 1)
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(height: 155)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(store.isLive ? Color.red.opacity(0.8) : Color.secondary.opacity(0.3), lineWidth: store.isLive ? 2 : 1)
                    )
                    
                    if let song = store.activeSong, store.isLive {
                        HStack {
                            Text(song.title)
                                .font(.scaled(11, weight: .medium, scale: scale))
                                .lineLimit(1)
                            Spacer()
                            Text("Slajd \(store.activeSlideIndex + 1)/\(song.slides.count)")
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - Section 2: Live Navigation Controls
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: { store.prevSlide() }) {
                            Label("Poprzedni", systemImage: "arrow.left")
                                .frame(maxWidth: .infinity)
                                .font(.scaled(12, weight: .semibold, scale: scale))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(!store.isLive)
                        
                        Button(action: { store.nextSlide() }) {
                            Label("Następny", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                                .font(.scaled(12, weight: .semibold, scale: scale))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(!store.isLive)
                    }
                    
                    HStack(spacing: 8) {
                        Button(action: { store.toggleBlackScreen() }) {
                            HStack {
                                Circle()
                                    .fill(store.isBlackScreen ? Color.red : Color.secondary.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                Text("Czarny (B)")
                                    .font(.scaled(11, scale: scale))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.isBlackScreen ? .red : .primary)
                        
                        Button(action: { store.toggleClearText() }) {
                            HStack {
                                Circle()
                                    .fill(store.isClearText ? Color.orange : Color.secondary.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                Text("Czysty (C)")
                                    .font(.scaled(11, scale: scale))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.isClearText ? .orange : .primary)
                        
                        if store.isLive {
                            Button(action: { store.stopLive() }) {
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .help("Zatrzymaj prezentację")
                        }
                    }
                }
                
                Divider()
                
                // MARK: - Section 3: Next Slide Preview (Styled like Live Monitor, but grayed out)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Podgląd następnego slajdu", systemImage: "arrow.forward.square")
                            .font(.scaled(13, weight: .bold, scale: scale))
                        
                        Spacer()
                        
                        if nextSlide != nil {
                            Text("NASTĘPNY")
                                .font(.scaled(10, weight: .bold, scale: scale))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(4)
                        } else {
                            Text("KONIEC")
                                .font(.scaled(10, weight: .bold, scale: scale))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    
                    // 16:9 Aspect Ratio Mini Screen for NEXT slide (grayed out preview)
                    ZStack {
                        let bgColor = Color(hex: store.settings.backgroundColorHex)
                        let txtColor = Color(hex: store.settings.textColorHex)
                        
                        if let next = nextSlide {
                            bgColor
                            
                            // Dimmed overlay to give a clean grayed-out effect
                            Color.black.opacity(0.2)
                            
                            VStack {
                                HStack {
                                    Text(next.label)
                                        .font(.scaled(9, weight: .bold, scale: scale))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.6))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(8)
                            
                            Text(next.text)
                                .font(customFont(name: store.settings.fontFamily, size: 13 * CGFloat(scale), isBold: store.settings.isBold))
                                .foregroundColor(txtColor.opacity(0.55))
                                .multilineTextAlignment(alignmentForString(store.settings.textAlignment))
                                .shadow(color: store.settings.hasShadow ? Color.black.opacity(0.4) : Color.clear, radius: 2, x: 1, y: 1)
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Color(NSColor.controlBackgroundColor)
                            VStack(spacing: 6) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 20))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text(store.isLive ? "Brak kolejnego slajdu (Koniec pieśni)" : "Brak aktywnej prezentacji")
                                    .font(.scaled(11, scale: scale))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(height: 135)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    
                    if let next = nextSlide {
                        HStack {
                            Text("Następny: \(next.label)")
                                .font(.scaled(11, weight: .medium, scale: scale))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(next.lines.count) linie")
                                .font(.scaled(10, scale: scale))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // MARK: - Section 4: Multi-screen Selection & Display Controller
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Ekrany i Projektor", systemImage: "sparkles.tv")
                            .font(.scaled(13, weight: .bold, scale: scale))
                        Spacer()
                        Button(action: { screenManager.refreshScreens() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Odśwież listę monitorów")
                    }
                    
                    Picker("Docelowy ekran:", selection: Binding(
                        get: { store.settings.selectedScreenIndex },
                        set: {
                            store.settings.selectedScreenIndex = $0
                            store.saveSettings()
                        }
                    )) {
                        ForEach(screenManager.availableScreens) { screen in
                            Text(screen.name).tag(screen.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .font(.scaled(11, scale: scale))
                    
                    // Launch buttons
                    VStack(spacing: 6) {
                        Button(action: {
                            screenManager.togglePresentation(on: store.settings.selectedScreenIndex)
                        }) {
                            HStack {
                                Image(systemName: screenManager.isPresentationActive ? "stop.circle.fill" : "play.rectangle.fill")
                                Text(screenManager.isPresentationActive ? "Zatrzymaj pełny ekran" : "Prezentuj na pełnym ekranie")
                                    .font(.scaled(12, weight: .semibold, scale: scale))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(screenManager.isPresentationActive ? .red : .blue)
                        
                        Button(action: {
                            screenManager.toggleWindowedPreview()
                        }) {
                            HStack {
                                Image(systemName: screenManager.isWindowedPreviewActive ? "xmark.circle" : "macwindow.badge.plus")
                                Text(screenManager.isWindowedPreviewActive ? "Zamknij okno testowe" : "Otwórz okno testowe")
                                    .font(.scaled(11, scale: scale))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func customFont(name: String, size: CGFloat, isBold: Bool) -> Font {
        if name == "System" || name == "SF Pro" {
            return .system(size: size, weight: isBold ? .bold : .regular)
        }
        return .custom(name, size: size).weight(isBold ? .bold : .regular)
    }
    
    private func alignmentForString(_ alignment: String) -> TextAlignment {
        switch alignment.lowercased() {
        case "left", "lewo": return .leading
        case "right", "prawo": return .trailing
        default: return .center
        }
    }
}
