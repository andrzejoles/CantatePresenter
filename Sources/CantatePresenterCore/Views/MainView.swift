import Foundation
import SwiftUI
import AppKit

public struct MainView: View {
    @Bindable var store = DataStore.shared
    @ObservedObject var screenManager = ScreenManager.shared
    
    @State private var selectedLeftTab: Int = 0 // 0: Library, 1: Plan
    @State private var isShowingEditor: Bool = false
    @State private var isShowingOnlineSearch: Bool = false
    @State private var isShowingImportExport: Bool = false
    @State private var importExportStartsImport: Bool = false
    @State private var isShowingAuthorTitleLookup: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var isShowingQuickText: Bool = false
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
                
                // Quick Text Presentation Button (Ad-hoc)
                Button(action: { isShowingQuickText = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                        Text("Szybki tekst")
                            .font(.scaled(11, weight: .semibold, scale: scale))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .help("Wyświetl natychmiast dowolny tekst lub ogłoszenie bez zapisywania w bazie (⌘T)")
                .keyboardShortcut("t", modifiers: [.command])
                
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
        .sheet(isPresented: $isShowingImportExport, onDismiss: { importExportStartsImport = false }) {
            ImportExportSheet(isPresented: $isShowingImportExport, startsImportOnAppear: importExportStartsImport)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(isPresented: $isShowingSettings)
        }
        .sheet(isPresented: $isShowingQuickText) {
            QuickTextSheet(isPresented: $isShowingQuickText)
        }
        .alert(
            store.persistenceIssues.first?.title ?? "",
            isPresented: Binding(
                get: { !store.persistenceIssues.isEmpty },
                set: { isPresented in
                    if !isPresented, let issue = store.persistenceIssues.first {
                        store.dismissPersistenceIssue(issue)
                    }
                }
            ),
            presenting: store.persistenceIssues.first
        ) { issue in
            if let copy = issue.quarantinedCopy {
                Button("Pokaż w Finderze") {
                    NSWorkspace.shared.activateFileViewerSelecting([copy])
                }
            }
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(issue.message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openImportFlow)) { _ in
            guard !isShowingImportExport else { return }
            importExportStartsImport = true
            isShowingImportExport = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenQuickTextSheet"))) { _ in
            isShowingQuickText = true
        }
    }
}

extension Notification.Name {
    /// Plik → Importuj pieśni: ten sam przepływ co w oknie Import/Eksport (S3).
    static let openImportFlow = Notification.Name("OpenImportFlow")
}
