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
    @State private var searchScope: Song.SearchScope = .all
    @AppStorage("song_list_sort_order") private var sortOrder: SongSortOrder = .titleAsc
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
        
        let plLocale = Locale(identifier: "pl_PL")
        return baseList.sorted { a, b in
            let titleA = a.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleB = b.title.trimmingCharacters(in: .whitespacesAndNewlines)
            
            switch sortOrder {
            case .titleAsc:
                return titleA.compare(titleB, options: [.caseInsensitive, .numeric], locale: plLocale) == .orderedAscending
            case .titleDesc:
                return titleA.compare(titleB, options: [.caseInsensitive, .numeric], locale: plLocale) == .orderedDescending
            case .authorAsc:
                let authorA = a.author.trimmingCharacters(in: .whitespacesAndNewlines)
                let authorB = b.author.trimmingCharacters(in: .whitespacesAndNewlines)
                if authorA.isEmpty && !authorB.isEmpty { return false }
                if !authorA.isEmpty && authorB.isEmpty { return true }
                let comp = authorA.compare(authorB, options: [.caseInsensitive, .numeric], locale: plLocale)
                if comp == .orderedSame {
                    return titleA.compare(titleB, options: [.caseInsensitive, .numeric], locale: plLocale) == .orderedAscending
                }
                return comp == .orderedAscending
            case .newest:
                return a.createdAt > b.createdAt
            }
        }
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Search & Action Header
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField(searchScope == .all ? loc(.searchPlaceholder) : "Szukaj (\(searchScope.rawValue.lowercased()))...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.scaled(12, scale: scale))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Voice dictation button for search
                    DictationButtonView(text: $searchText, mode: .replace, size: 12)
                    
                    Picker("", selection: $searchScope) {
                        ForEach(Song.SearchScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 105)
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Quick Action Buttons
                HStack(spacing: 5) {
                    Button(action: {
                        songToEdit = nil
                        isShowingEditor = true
                    }) {
                        Label(loc(.newSong), systemImage: "plus")
                            .font(.scaled(11, weight: .medium, scale: scale))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button(action: {
                        if let selected = store.selectedSong {
                            songToEdit = selected
                            isShowingEditor = true
                        }
                    }) {
                        Label("Edytuj", systemImage: "pencil")
                            .font(.scaled(11, weight: .medium, scale: scale))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.selectedSong == nil)
                    .help("Edytuj wybraną pieśń (podwójny klik lub ⌘E)")
                    
                    Button(action: {
                        isShowingImportExport = true
                    }) {
                        Label(loc(.importExport), systemImage: "arrow.up.arrow.down")
                            .font(.scaled(11, scale: scale))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: {
                        lookupTargetSong = store.selectedSong
                        isShowingAuthorTitleLookup = true
                    }) {
                        Label(loc(.titleAuthor), systemImage: "person.text.rectangle")
                            .font(.scaled(11, scale: scale))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Wyszukiwarka tytułu i autora (dla zaznaczonej lub dla wszystkich)")
                    
                    Button(action: {
                        isShowingOnlineSearch = true
                    }) {
                        Label(loc(.online), systemImage: "globe")
                            .font(.scaled(11, scale: scale))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenQuickTextSheet"), object: nil)
                    }) {
                        Label("Szybki tekst", systemImage: "bolt.fill")
                            .font(.scaled(11, scale: scale))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Wyświetl natychmiast dowolny tekst lub ogłoszenie bez zapisywania w bazie (⌘T)")
                    
                    Spacer()
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Sub-header: Count and Sort selector
            HStack {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("\(filteredSongs.count) pieśni")
                        .font(.scaled(10.5, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                } else {
                    Text("\(filteredSongs.count) z \(store.songs.count) pieśni")
                        .font(.scaled(10.5, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Picker("Sortowanie", selection: $sortOrder) {
                        ForEach(SongSortOrder.allCases) { order in
                            Label(order.rawValue, systemImage: order.icon).tag(order)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 9))
                        Text(sortOrder.rawValue)
                            .font(.scaled(10, scale: scale))
                    }
                    .foregroundColor(.secondary)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .help("Zmień kolejność sortowania pieśni w bibliotece")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            
            Divider()
            
            // Songs List
            List(selection: $store.selectedSongId) {
                ForEach(filteredSongs) { song in
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
                        Button("Prezentuj teraz") {
                            store.present(song: song, slideIndex: 0)
                        }
                        Button("Dodaj do aktywnego planu") {
                            store.addSongToPlan(songId: song.id)
                        }
                        Button("Edytuj pieśń ✏️ (⌘E)") {
                            songToEdit = song
                            isShowingEditor = true
                        }
                        Divider()
                        Button("Wyszukaj tytuł i autora online...") {
                            lookupTargetSong = song
                            isShowingAuthorTitleLookup = true
                        }
                        Divider()
                        Button("Eksportuj jako plik tekstowy (.txt)...") {
                            _ = SongExporter.exportSongAsTextFile(song)
                        }
                        Button("Eksportuj jako plik JSON (.json)...") {
                            _ = SongExporter.exportSongsAsJSONFile([song], defaultName: song.title)
                        }
                        Divider()
                        Button("Usuń z bazy", role: .destructive) {
                            store.deleteSong(id: song.id)
                        }
                    }
                }
            }
            .listStyle(InsetListStyle())
            
            Divider()
            
            // Footer status
            HStack {
                Text("\(filteredSongs.count) \(loc(.songsInLibrary))")
                    .font(.scaled(11, scale: scale))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Podwójny klik / ⌘E: edycja")
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
                
                if !song.key.isEmpty {
                    Text(song.key)
                        .font(.scaled(10, weight: .bold, scale: scale))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                
                Text("\(song.slides.count) sl.")
                    .font(.scaled(10, scale: scale))
                    .foregroundColor(.secondary)
            }
            
            if !song.author.isEmpty {
                Text(song.author)
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
