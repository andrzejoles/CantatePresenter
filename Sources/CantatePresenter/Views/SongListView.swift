import Foundation
import SwiftUI

public struct SongListView: View {
    @ObservedObject var store = DataStore.shared
    @State private var searchText: String = ""
    @State private var searchScope: Song.SearchScope = .all
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
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return store.songs
        }
        return store.songs.filter { $0.matches(query: searchText, scope: searchScope) }
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
                    
                    Spacer()
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            
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
