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
                    Text(L("CantatePresenter"))
                        .font(.scaled(14, weight: .bold, scale: scale))
                }
                
                // Screen Status Badge
                if screenManager.isWaitingForDisplay {
                    // S1: projektor zniknął; okno projekcji ukryte, wróci po ponownym podłączeniu.
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(L("Projektor odłączony – projekcja wróci po podłączeniu"))
                            .font(.scaled(10, weight: .bold, scale: scale))
                            .foregroundColor(.orange)
                        Button(L("Zakończ projekcję")) {
                            screenManager.stopPresentation()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.14))
                    .cornerRadius(6)
                } else if screenManager.isPresentationActive {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(L("Projektor: Aktywny"))
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
                        Text(L("Okno testowe"))
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
                        Text(L("Szybki tekst"))
                            .font(.scaled(11, weight: .semibold, scale: scale))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .help(L("Wyświetl natychmiast dowolny tekst lub ogłoszenie bez zapisywania w bazie (⌘T)"))
                .keyboardShortcut("t", modifiers: [.command])
                
                // Akcje biblioteki (wcześniej ciasno pod wyszukiwarką). Przy wąskim oknie same ikony z podpowiedzią.
                ViewThatFits(in: .horizontal) {
                    libraryActions(scale: scale, showTitles: true)
                    libraryActions(scale: scale, showTitles: false)
                }
                
                Spacer()
                
                // UI Scale Controls (Essential requirement)
                HStack(spacing: 4) {
                    Text("\(L("Rozmiar UI")):")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                    
                    Button(action: { store.zoomOutUI() }) {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L("Zmniejsz rozmiar interfejsu (Cmd -)"))
                    
                    Button(action: { store.resetZoomUI() }) {
                        Text("\(Int(store.settings.uiScale * 100))%")
                            .font(.scaled(11, scale: scale, isMonospaced: true))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L("Przywróć 100% rozmiaru (Cmd 0)"))
                    
                    Button(action: { store.zoomInUI() }) {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L("Zwiększ rozmiar interfejsu (Cmd +)"))
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
                .help(L("Ustawienia wyglądu i prezentacji"))
                
                // User Manual button
                Button(action: {
                    NSApp.sendAction(#selector(AppDelegate.openUserManualAction), to: nil, from: nil)
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L("Instrukcja obsługi CantatePresenter (Cmd ?)"))
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
                        Text(L("Biblioteka pieśni")).tag(0)
                        Text(L("Plan nabożeństwa")).tag(1)
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
                Button(L("Pokaż w Finderze")) {
                    NSWorkspace.shared.activateFileViewerSelecting([copy])
                }
            }
            Button(L("OK"), role: .cancel) {}
        } message: { issue in
            Text(issue.message)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSongSearch)) { _ in
            selectedLeftTab = 0
            // Lista pieśni może dopiero się pojawić po przełączeniu zakładki.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .focusSongSearchField, object: nil)
            }
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

    @ViewBuilder
    private func libraryActions(scale: CGFloat, showTitles: Bool) -> some View {
        HStack(spacing: 5) {
            Button(action: {
                songToEdit = nil
                isShowingEditor = true
            }) {
                Label(L("Nowa pieśń"), systemImage: "plus")
                    .labelStyle(LibraryActionLabelStyle(showTitle: showTitles))
                    .font(.scaled(11, weight: .medium, scale: scale))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help(L("Nowa pieśń"))
            
            Button(action: {
                if let selected = store.selectedSong {
                    songToEdit = selected
                    isShowingEditor = true
                }
            }) {
                Label(L("Edytuj"), systemImage: "pencil")
                    .labelStyle(LibraryActionLabelStyle(showTitle: showTitles))
                    .font(.scaled(11, weight: .medium, scale: scale))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.selectedSong == nil)
            .help(L("Edytuj wybraną pieśń (podwójny klik lub ⌘E)"))
            
            Button(action: { isShowingImportExport = true }) {
                Label(L("Import/Eksport"), systemImage: "arrow.up.arrow.down")
                    .labelStyle(LibraryActionLabelStyle(showTitle: showTitles))
                    .font(.scaled(11, scale: scale))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L("Import/Eksport"))
            
            Button(action: {
                lookupTargetSong = store.selectedSong
                isShowingAuthorTitleLookup = true
            }) {
                Label(L("Tytuł/Autor"), systemImage: "person.text.rectangle")
                    .labelStyle(LibraryActionLabelStyle(showTitle: showTitles))
                    .font(.scaled(11, scale: scale))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L("Wyszukiwarka tytułu i autora (dla zaznaczonej lub dla wszystkich)"))
            
            Button(action: { isShowingOnlineSearch = true }) {
                Label(L("Online"), systemImage: "globe")
                    .labelStyle(LibraryActionLabelStyle(showTitle: showTitles))
                    .font(.scaled(11, scale: scale))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L("Wyszukiwanie pieśni religijnych w internecie"))
                }
        .fixedSize()
    }

}

extension Notification.Name {
    /// Plik → Importuj pieśni: ten sam przepływ co w oknie Import/Eksport (S3).
    static let openImportFlow = Notification.Name("OpenImportFlow")
    /// Edycja → Szukaj pieśni (⌘F): przełącza na Bibliotekę i aktywuje pole wyszukiwania.
    static let focusSongSearch = Notification.Name("FocusSongSearch")
    static let focusSongSearchField = Notification.Name("FocusSongSearchField")
}

/// Etykieta przycisku z napisem albo sama ikona (wąskie okno); napis zostaje jako podpowiedź.
struct LibraryActionLabelStyle: LabelStyle {
    let showTitle: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        if showTitle {
            HStack(spacing: 4) {
                configuration.icon
                configuration.title
            }
        } else {
            configuration.icon
        }
    }
}
