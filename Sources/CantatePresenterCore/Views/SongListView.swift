import Foundation
import SwiftUI

public enum SongSortOrder: String, CaseIterable, Identifiable {
    case titleAsc = "Tytuł (A-Z)"
    case titleDesc = "Tytuł (Z-A)"
    case authorAsc = "Autor (A-Z)"
    case newest = "Najnowsze"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .titleAsc: return "arrow.up"
        case .titleDesc: return "arrow.down"
        case .authorAsc: return "person"
        case .newest: return "clock"
        }
    }
}

public struct SongListView: View {
    @Bindable var store = DataStore.shared
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var searchScope: Song.SearchScope = .all
    @State private var onlyWithChords = false
    @AppStorage("song_list_sort_order") private var sortOrder: SongSortOrder = .titleAsc
    /// Pieśń czekająca na potwierdzenie usunięcia (R4-17).
    @State private var songPendingDeletion: Song?
    @Binding var isShowingEditor: Bool
    @Binding var isShowingOnlineSearch: Bool
    @Binding var isShowingImportExport: Bool
    @Binding var isShowingAuthorTitleLookup: Bool
    @Binding var lookupTargetSong: Song?
    @Binding var songToEdit: Song?
    
    public init(
        isShowingEditor: Binding<Bool>,
        isShowingOnlineSearch: Binding<Bool>,
        isShowingImportExport: Binding<Bool>,
        isShowingAuthorTitleLookup: Binding<Bool>,
        lookupTargetSong: Binding<Song?>,
        songToEdit: Binding<Song?>
    ) {
        self._isShowingEditor = isShowingEditor
        self._isShowingOnlineSearch = isShowingOnlineSearch
        self._isShowingImportExport = isShowingImportExport
        self._isShowingAuthorTitleLookup = isShowingAuthorTitleLookup
        self._lookupTargetSong = lookupTargetSong
        self._songToEdit = songToEdit
    }
    
    private var filteredSongs: [Song] {
        let baseList: [Song]
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            baseList = store.songs
        } else {
            baseList = store.searchIndex.filter(store.songs, query: query, scope: searchScope)
        }
        let list = onlyWithChords ? baseList.filter(\.hasChords) : baseList
        return Self.sorted(list, by: sortOrder)
    }

    /// Sortowanie biblioteki (R4-13): tytuły i autorzy przycinani raz na pieśń, nie przy każdym porównaniu.
    /// `body` liczy listę raz (`let songs = filteredSongs`), a wcześniej sortował 900+ pieśni trzy razy.
    nonisolated static func sorted(_ songs: [Song], by order: SongSortOrder) -> [Song] {
        struct Keyed {
            let song: Song
            let title: String
            let author: String
        }
        let plLocale = Locale(identifier: "pl_PL")
        let options: String.CompareOptions = [.caseInsensitive, .numeric]
        let keyed = songs.map {
            Keyed(
                song: $0,
                title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: order == .authorAsc ? $0.author.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            )
        }
        return keyed.sorted { a, b in
            switch order {
            case .titleAsc:
                return a.title.compare(b.title, options: options, locale: plLocale) == .orderedAscending
            case .titleDesc:
                return a.title.compare(b.title, options: options, locale: plLocale) == .orderedDescending
            case .authorAsc:
                if a.author.isEmpty && !b.author.isEmpty { return false }
                if !a.author.isEmpty && b.author.isEmpty { return true }
                let comp = a.author.compare(b.author, options: options, locale: plLocale)
                if comp == .orderedSame {
                    return a.title.compare(b.title, options: options, locale: plLocale) == .orderedAscending
                }
                return comp == .orderedAscending
            case .newest:
                return a.song.createdAt > b.song.createdAt
            }
        }.map(\.song)
    }
    
    /// Cały tekst podpowiedzi tłumaczony osobno dla każdego zakresu; wstawiana nazwa zakresu pisana
    /// małą literą psuła m.in. niemieckie rzeczowniki („nur titel”, R8-07).
    private var searchPlaceholder: String {
        switch searchScope {
        case .all: return L("Szukaj w tytule, autorze i tekście...")
        case .titleAndAuthor: return L("Szukaj w tytule i autorze...")
        case .titleOnly: return L("Szukaj tylko w tytule...")
        case .authorOnly: return L("Szukaj tylko autora...")
        }
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        let songs = filteredSongs

        VStack(spacing: 0) {
            // Search Header: pole w osobnej linii, pod nim dyktowanie i zakres wyszukiwania
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(isSearchFocused ? .green : .secondary)
                    
                    TextField(searchPlaceholder, text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.scaled(12, scale: scale))
                        .focused($isSearchFocused)
                        .onReceive(NotificationCenter.default.publisher(for: .focusSongSearchField)) { _ in
                            isSearchFocused = true
                        }
                        .onChange(of: isSearchFocused) { _, focused in
                            // Po aktywacji cały tekst zaznaczony: pisanie od razu zastępuje poprzednie zapytanie.
                            guard focused else { return }
                            DispatchQueue.main.async {
                                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                            }
                        }
                        .onSubmit {
                            // Enter: zaznacz pierwszy wynik i wyjdź z pola, żeby klawisze znów sterowały slajdami.
                            if let first = songs.first {
                                store.selectedSongId = first.id
                            }
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(L("Wyczyść wyszukiwanie"))
                        .accessibilityLabel(L("Wyczyść wyszukiwanie"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                // Zielone: pole aktywne, można pisać. Czerwone: nieaktywne, klawisze sterują slajdami.
                .background((isSearchFocused ? Color.green : Color.red).opacity(0.07))
                .cardStyle(
                    cornerRadius: 8,
                    outline: (isSearchFocused ? Color.green : Color.red).opacity(isSearchFocused ? 0.7 : 0.35),
                    lineWidth: isSearchFocused ? 1.5 : 1
                )
                .contentShape(Rectangle())
                .onTapGesture { isSearchFocused = true }
                
                HStack(spacing: 6) {
                    // Voice dictation button for search
                    DictationButtonView(text: $searchText, mode: .replace, size: 12)
                    
                    Picker("", selection: $searchScope) {
                        ForEach(Song.SearchScope.allCases) { scope in
                            Text(L(scope.rawValue)).tag(scope)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .fixedSize()
                    
                    Toggle(isOn: $onlyWithChords) {
                        Label(L("Z chwytami"), systemImage: "guitars")
                            .font(.scaled(11, scale: scale))
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .tint(.orange)
                    .help(L("Pokaż tylko pieśni z chwytami"))
                    
                    Spacer()
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Sub-header: Count and Sort selector
            HStack {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty && !onlyWithChords {
                    Text(L("Pieśni: {0}", songs.count))
                        .font(.scaled(10.5, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                } else {
                    Text(L("{0} z {1} pieśni", songs.count, store.songs.count))
                        .font(.scaled(10.5, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Picker(L("Sortowanie"), selection: $sortOrder) {
                        ForEach(SongSortOrder.allCases) { order in
                            Label(L(order.rawValue), systemImage: order.icon).tag(order)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 9))
                        Text(L(sortOrder.rawValue))
                            .font(.scaled(10, scale: scale))
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .help(L("Zmień kolejność sortowania pieśni w bibliotece"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            
            Divider()
            
            // Songs List
            List(selection: $store.selectedSongId) {
                ForEach(songs) { song in
                    SongRowView(
                        song: song,
                        searchQuery: searchText,
                        isSelected: store.selectedSongId == song.id,
                        isLiveNow: store.activeSong?.id == song.id && store.isLive,
                        scale: scale
                    )
                    .tag(song.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        store.selectedSongId = song.id
                        songToEdit = song
                        isShowingEditor = true
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        store.selectedSongId = song.id
                    })
                    .contextMenu {
                        Button(L("Prezentuj teraz")) {
                            store.present(song: song, slideIndex: 0)
                        }
                        Button(L("Dodaj do aktywnego planu")) {
                            store.addSongToPlan(songId: song.id)
                        }
                        Button(L("Edytuj pieśń ✏️ (⌘E)")) {
                            songToEdit = song
                            isShowingEditor = true
                        }
                        Divider()
                        Button(L("Wyszukaj tytuł i autora online...")) {
                            lookupTargetSong = song
                            isShowingAuthorTitleLookup = true
                        }
                        Divider()
                        Button(L("Eksportuj jako plik tekstowy (.txt)...")) {
                            _ = SongExporter.exportSongAsTextFile(song)
                        }
                        Button(L("Eksportuj jako plik JSON (.json)...")) {
                            _ = SongExporter.exportSongsAsJSONFile([song], defaultName: song.title)
                        }
                        Divider()
                        Button(L("Usuń z bazy"), role: .destructive) {
                            songPendingDeletion = song
                        }
                    }
                }
            }
            .listStyle(InsetListStyle())
            // Usunięcie zabiera pieśń także ze wszystkich planów, więc jedno kliknięcie w menu nie wystarcza (R4-17).
            .confirmationDialog(
                L("Usunąć pieśń „{0}”?", songPendingDeletion?.title ?? ""),
                isPresented: Binding(
                    get: { songPendingDeletion != nil },
                    set: { if !$0 { songPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: songPendingDeletion
            ) { song in
                Button(L("Usuń"), role: .destructive) {
                    store.deleteSong(id: song.id)
                }
                Button(L("Anuluj"), role: .cancel) {}
            } message: { _ in
                Text(L("Pieśń zostanie usunięta z biblioteki i ze wszystkich planów."))
            }
            
            Divider()
            
            // Footer status
            HStack {
                Text(L("Pieśni w bibliotece: {0}", store.songs.count))
                    .font(.scaled(11, scale: scale))
                    .foregroundColor(.secondary)
                Spacer()
                Text(L("Podwójny klik / ⌘E: edycja"))
                    .font(.scaled(10, scale: scale))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

private struct SongRowView: View {
    let song: Song
    let searchQuery: String
    let isSelected: Bool
    let isLiveNow: Bool
    let scale: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if isLiveNow {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
                
                Text(song.title)
                    .font(.scaled(13, weight: .semibold, scale: scale))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Spacer()
                
                if song.hasChords {
                    Image(systemName: "guitars")
                        .font(.system(size: 10 * scale))
                        .foregroundColor(isSelected ? .white : .orange)
                        .help(L("Pieśń z chwytami"))
                }
                
                if !song.key.isEmpty {
                    Text(song.key)
                        .font(.scaled(10, weight: .bold, scale: scale))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                
                Text(L("{0} sl.", song.slides.count))
                    .font(.scaled(10, scale: scale))
                    .foregroundColor(.secondary)
            }
            
            if !song.author.isEmpty {
                Text(song.displayAuthor)
                    .font(.scaled(11, scale: scale))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // If search query matched inside lyrics, show snippet
            if let snippet = song.matchingSnippet(query: searchQuery) {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.scaled(9, scale: scale))
                        .foregroundColor(.orange)
                    Text(snippet)
                        .font(.scaled(10, scale: scale))
                        .foregroundColor(.orange)
                        .italic()
                        .lineLimit(1)
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 4)
    }
}
