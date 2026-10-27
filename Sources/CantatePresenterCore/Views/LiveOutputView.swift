import Foundation
import SwiftUI
import AppKit

public struct LiveOutputView: View {
    @Bindable var store = DataStore.shared
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
    
    private var presentationAspectRatio: CGFloat {
        screenManager.selectedScreenAspectRatio
    }
    
    private var presentationScreenSize: CGSize {
        screenManager.selectedScreenSize
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - Section 1: Live Monitor (What's on screen)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Label(L("Ekran na żywo"), systemImage: "display")
                                .font(.scaled(13, weight: .bold, scale: scale))
                            
                            Text(ScreenManager.formattedAspectRatio(for: presentationAspectRatio))
                                .font(.scaled(9, weight: .semibold, scale: scale))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        if store.isLive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text(L("LIVE"))
                                    .font(.scaled(10, weight: .bold, scale: scale))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(4)
                        } else {
                            Text(L("OFF AIR"))
                                .font(.scaled(10, weight: .bold, scale: scale))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    
                    // Presentation Screen Aspect Ratio Mini Screen
                    ZStack {
                        let bgColor = Color(hex: store.settings.backgroundColorHex)
                        let txtColor = Color(hex: store.settings.textColorHex)
                        
                        if store.isBlackScreen {
                            Color.black
                            Text(L("CZARNY EKRAN"))
                                .font(.scaled(11, weight: .bold, scale: scale))
                                .foregroundColor(.white.opacity(0.5))
                        } else if !store.isLive {
                            // Ta sama plansza co na projektorze (własny plik, zegar, napis gotowości), pomniejszona (R4-15).
                            // Strona jest składana w rozmiarze projektowym i pomniejszana jako obraz: przy pageZoom
                            // poniżej ok. 0.5 WebKit nie zmniejsza tekstu poniżej minimum i napisy nachodziły na siebie.
                            GeometryReader { geo in
                                let width = StandbyZoom.designWidth
                                StandbyWebView(htmlPath: store.settings.standbyHtmlPath, activeLogoId: store.settings.activeLogoId)
                                    .frame(width: width, height: width / presentationAspectRatio)
                                    .scaleEffect(geo.size.width / width, anchor: .topLeading)
                                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                            }
                            .allowsHitTesting(false)
                        } else if store.isClearText {
                            bgColor
                            Text(L("TEKST UKRYTY"))
                                .font(.scaled(11, weight: .bold, scale: scale))
                                .foregroundColor(txtColor.opacity(0.4))
                        } else if let slide = store.currentLiveSlide {
                            PresentationSlidePreviewCanvas(
                                text: slide.text,
                                targetScreenSize: presentationScreenSize,
                                settings: store.settings,
                                footer: store.currentLiveCopyrightNotice
                            )
                        }
                    }
                    .aspectRatio(presentationAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                            Text(L("Slajd {0}/{1}", store.activeSlideIndex + 1, song.slides.count))
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // MARK: - Section 2: Live Navigation Controls
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: { store.prevSlide() }) {
                            Label(L("Poprzedni"), systemImage: "arrow.left")
                                .frame(maxWidth: .infinity)
                                .font(.scaled(12, weight: .semibold, scale: scale))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(!store.isLive)
                        
                        Button(action: { store.nextSlide() }) {
                            Label(L("Następny"), systemImage: "arrow.right")
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
                                Text(L("Czarny ({0})", KeyboardRouter.shortKeyName(for: store.settings.shortcuts.blackScreenKey)))
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
                                Text(L("Czysty ({0})", KeyboardRouter.shortKeyName(for: store.settings.shortcuts.clearTextKey)))
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
                            .helpLabel(L("Zatrzymaj prezentację"))
                        }
                    }
                }
                
                Divider()
                
                // MARK: - Section 3: Next Slide Preview (Styled like Live Monitor, but grayed out)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Label(L("Podgląd następnego slajdu"), systemImage: "arrow.forward.square")
                                .font(.scaled(13, weight: .bold, scale: scale))
                            
                            Text(ScreenManager.formattedAspectRatio(for: presentationAspectRatio))
                                .font(.scaled(9, weight: .semibold, scale: scale))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        if nextSlide != nil {
                            Text(L("NASTĘPNY"))
                                .font(.scaled(10, weight: .bold, scale: scale))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(4)
                        } else {
                            Text(L("KONIEC"))
                                .font(.scaled(10, weight: .bold, scale: scale))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    
                    // Presentation Screen Aspect Ratio Mini Screen for NEXT slide (grayed out preview)
                    ZStack {
                        if let next = nextSlide {
                            PresentationSlidePreviewCanvas(
                                text: next.text,
                                targetScreenSize: presentationScreenSize,
                                settings: store.settings,
                                isDimmed: true,
                                label: next.displayLabel
                            )
                        } else {
                            Color(NSColor.controlBackgroundColor)
                            VStack(spacing: 6) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 20))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text(store.isLive ? L("Brak kolejnego slajdu (Koniec pieśni)") : L("Brak aktywnej prezentacji"))
                                    .font(.scaled(11, scale: scale))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .aspectRatio(presentationAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    
                    if let next = nextSlide {
                        HStack {
                            Text(L("Następny: {0}", next.displayLabel))
                                .font(.scaled(11, weight: .medium, scale: scale))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(L("Linie: {0}", next.lines.count))
                                .font(.scaled(10, scale: scale))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // MARK: - Section 4: Multi-screen Selection & Display Controller
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(L("Ekrany i Projektor"), systemImage: "sparkles.tv")
                            .font(.scaled(13, weight: .bold, scale: scale))
                        Spacer()
                        Button(action: { screenManager.refreshScreens() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(PlainButtonStyle())
                        .helpLabel(L("Odśwież listę monitorów"))
                    }
                    
                    Picker(L("Docelowy ekran:"), selection: Binding(
                        get: { _ = store.settings.selectedScreenID; return screenManager.selectedScreenItemID ?? 0 },
                        set: { index in
                            if let item = screenManager.availableScreens.first(where: { $0.id == index }) {
                                screenManager.selectScreen(item)
                            }
                        }
                    )) {
                        ForEach(screenManager.availableScreens) { screen in
                            Text(screen.isPrimary ? "\(screen.name) [\(L("główny"))]" : screen.name).tag(screen.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .font(.scaled(11, scale: scale))
                    
                    // Launch buttons
                    VStack(spacing: 6) {
                        Button(action: {
                            screenManager.togglePresentation()
                        }) {
                            HStack {
                                Image(systemName: screenManager.isPresentationActive ? "stop.circle.fill" : "play.rectangle.fill")
                                Text(screenManager.isPresentationActive ? L("Zatrzymaj pełny ekran") : L("Prezentuj na pełnym ekranie"))
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
                                Text(screenManager.isWindowedPreviewActive ? L("Zamknij okno testowe") : L("Otwórz okno testowe"))
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
}

