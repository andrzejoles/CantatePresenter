import Foundation
import SwiftUI
import AppKit

public struct MainView: View {
    @ObservedObject var store = DataStore.shared
    @ObservedObject var screenManager = ScreenManager.shared
    
    @State private var selectedLeftTab: Int = 0 // 0: Library, 1: Plan
    @State private var isShowingEditor: Bool = false
    @State private var isShowingOnlineSearch: Bool = false
    @State private var isShowingImportExport: Bool = false
    @State private var isShowingAuthorTitleLookup: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var songToEdit: Song?
    @State private var lookupTargetSong: Song?
    
    public init() {}
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // MARK: - Top Global Toolbar
            HStack(spacing: 12) {
                // Title & Icon
                HStack(spacing: 8) {
                    Image(systemName: "music.quarternote.3")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                    Text(loc(.appTitle))
                        .font(.scaled(14, weight: .bold, scale: scale))
                }
                
                // Screen Status Badge
                if screenManager.isPresentationActive {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(loc(.projectorActive))
                            .font(.scaled(10, weight: .bold, scale: scale))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                } else if screenManager.isWindowedPreviewActive {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text(loc(.testWindowActive))
                            .font(.scaled(10, weight: .bold, scale: scale))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)
                }
                
                Spacer()
                
                // UI Scale Controls (Essential requirement)
                HStack(spacing: 4) {
                    Text("\(loc(.uiScale)):")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                    
                    Button(action: { store.zoomOutUI() }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Zmniejsz rozmiar interfejsu (Cmd -)")
                    
                    Button(action: { store.resetZoomUI() }) {
                        Text("\(Int(store.settings.uiScale * 100))%")
                            .font(.scaled(11, scale: scale, isMonospaced: true))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Przywróć 100% rozmiaru (Cmd 0)")
                    
                    Button(action: { store.zoomInUI() }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Zwiększ rozmiar interfejsu (Cmd +)")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                
                Divider()
                    .frame(height: 18)
                
                // Settings button
                Button(action: { isShowingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Ustawienia wyglądu i prezentacji")
                
                // User Manual button
                Button(action: {
                    NSApp.sendAction(#selector(AppDelegate.openUserManualAction), to: nil, from: nil)
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Instrukcja obsługi CantatePresenter (Cmd ?)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // MARK: - 3-Panel Resizable Layout (HSplitView)
            HSplitView {
                // PANEL 1: Left (Library / Plan switcher)
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("", selection: $selectedLeftTab) {
                        Text(loc(.libraryTab)).tag(0)
                        Text(loc(.planTab)).tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    Divider()
                    
                    if selectedLeftTab == 0 {
                        SongListView(
                            isShowingEditor: $isShowingEditor,
                            isShowingOnlineSearch: $isShowingOnlineSearch,
                            isShowingImportExport: $isShowingImportExport,
                            isShowingAuthorTitleLookup: $isShowingAuthorTitleLookup,
                            lookupTargetSong: $lookupTargetSong,
                            songToEdit: $songToEdit
                        )
                    } else {
                        PlanListView()
                    }
                }
                .frame(minWidth: 150, idealWidth: 280, maxWidth: .infinity)
                
                // PANEL 2: Middle (Current Song & Slide Cards)
                SongSlidesView(
                    isShowingEditor: $isShowingEditor,
                    songToEdit: $songToEdit
                )
                .frame(minWidth: 160, idealWidth: 500, maxWidth: .infinity)
                
                // PANEL 3: Right (Live Monitor & Controls)
                LiveOutputView()
                    .frame(minWidth: 160, idealWidth: 320, maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            
            // Draggable Divider with resize handle for bottom bar height
            ZStack {
                Divider()
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 44, height: 4)
            }
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newHeight = store.settings.bottomBarHeight - value.translation.height
                        store.settings.bottomBarHeight = min(160, max(52, newHeight))
                    }
                    .onEnded { _ in
                        store.saveSettings()
                    }
            )
            
            // Full-Width Visual Shortcuts Bar across the entire application with auto-scaled elements
            ShortcutLegendBarView(scale: scale)
        }
        .sheet(isPresented: $isShowingEditor) {
            SongEditorView(isPresented: $isShowingEditor, existingSong: songToEdit)
        }
        .sheet(isPresented: $isShowingOnlineSearch) {
            OnlineSearchSheet(isPresented: $isShowingOnlineSearch)
        }
        .sheet(isPresented: $isShowingAuthorTitleLookup) {
            AuthorTitleLookupSheet(isPresented: $isShowingAuthorTitleLookup, initialSong: lookupTargetSong)
        }
        .sheet(isPresented: $isShowingImportExport) {
            ImportExportSheet(isPresented: $isShowingImportExport)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(isPresented: $isShowingSettings)
        }
        .onAppear {
            setupGlobalKeyMonitor()
        }
    }
    
    private func setupGlobalKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept if user is typing in a text field
            if let firstResponder = NSApp.keyWindow?.firstResponder,
               firstResponder is NSTextView || firstResponder is NSTextField {
                return event
            }
            
            // Command key combos for zooming
            if event.modifierFlags.contains(.command) {
                if event.characters == "=" || event.characters == "+" {
                    store.zoomInUI()
                    return nil
                } else if event.characters == "-" {
                    store.zoomOutUI()
                    return nil
                } else if event.characters == "0" {
                    store.resetZoomUI()
                    return nil
                }
                return event
            }
            
            let shortcuts = store.settings.shortcuts
            let code = event.keyCode
            
            // Configurable presentation shortcuts
            if code == shortcuts.nextSlideKey || code == 124 || code == 125 {
                store.nextSlide()
                return nil
            } else if code == shortcuts.prevSlideKey || code == 123 || code == 126 {
                store.prevSlide()
                return nil
            } else if code == shortcuts.nextSongKey {
                store.nextSongInPlan()
                return nil
            } else if code == shortcuts.prevSongKey {
                store.prevSongInPlan()
                return nil
            } else if code == shortcuts.startPresentationKey {
                if let song = store.selectedSong {
                    store.present(song: song, slideIndex: 0)
                }
                return nil
            } else if code == shortcuts.stopPresentationKey {
                store.stopLive()
                return nil
            } else if code == shortcuts.blackScreenKey {
                store.toggleBlackScreen()
                return nil
            } else if code == shortcuts.clearTextKey {
                store.toggleClearText()
                return nil
            } else if code == 15 { // 'R' key (Refren)
                store.jumpToChorus()
                return nil
            } else if (18...29).contains(code) { // Number keys 1-9
                if let char = event.characters?.first, let num = Int(String(char)), num >= 1 && num <= 9 {
                    store.jumpToVerse(number: num)
                    return nil
                }
            }
            return event
        }
    }
}
