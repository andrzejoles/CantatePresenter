import Foundation
import SwiftUI

public struct OnlineSearchSheet: View {
    @Bindable var store = DataStore.shared
    @Binding var isPresented: Bool
    
    @State private var query: String = ""
    @State private var language: String = "pl"
    @State private var isSearching: Bool = false
    @State private var results: [OnlineSearchResult] = []
    @State private var selectedResultId: UUID?
    @State private var errorMessage: String?
    @State private var importAuthor: Bool = true
    @State private var editedTitle: String = ""
    @State private var editedAuthor: String = ""
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._language = State(initialValue: DataStore.shared.settings.onlineSearchLanguage)
    }
    
    private var selectedResult: OnlineSearchResult? {
        guard let id = selectedResultId else { return results.first }
        return results.first(where: { $0.id == id })
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Wyszukiwanie pieśni religijnych w internecie")
                    .font(.scaled(16, weight: .bold, scale: scale))
                Spacer()
                Button("Zamknij") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Search Bar & Language Picker
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    TextField("Wpisz tytuł lub słowa pieśni (np. Barka, Oceany, Dotknij Panie)...", text: $query)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.scaled(13, scale: scale))
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    DictationButtonView(text: $query, mode: .replace, size: 13)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                Picker("Język:", selection: $language) {
                    ForEach(LanguagePresets.searchLanguages) { choice in
                        Text(choice.name).tag(choice.code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 170)
                
                Button(action: performSearch) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 50)
                    } else {
                        Text("Szukaj")
                            .frame(width: 50)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
            .padding(14)
            
            Divider()
            
            // Content
            if isSearching {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Przeszukiwanie serwisów z pieśniami chrześcijańskimi...")
                        .font(.scaled(13, scale: scale))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if results.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(query.isEmpty ? "Wpisz tytuł lub fragment tekstu i kliknij 'Szukaj'" : "Nie znaleziono pieśni dla podanej frazy")
                        .font(.scaled(13, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                HSplitView {
                    // Left list of found results
                    List(selection: $selectedResultId) {
                        ForEach(results) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.title)
                                        .font(.scaled(13, weight: .semibold, scale: scale))
                                    Spacer()
                                    Text(item.source)
                                        .font(.scaled(9, scale: scale))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }
                                
                                if !item.artist.isEmpty {
                                    Text(item.artist)
                                        .font(.scaled(11, scale: scale))
                                        .foregroundColor(.secondary)
                                }
                                
                                if !item.snippet.isEmpty {
                                    Text(item.snippet)
                                        .font(.scaled(10, scale: scale))
                                        .foregroundColor(.secondary.opacity(0.8))
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                            .tag(item.id)
                        }
                    }
                    .listStyle(InsetListStyle())
                    .frame(minWidth: 300)
                    .onChange(of: selectedResultId) { _, newId in
                        if let found = results.first(where: { $0.id == newId }) {
                            editedTitle = found.title
                            editedAuthor = found.artist
                            importAuthor = !found.artist.isEmpty
                        }
                    }
                    
                    // Right preview pane
                    VStack(alignment: .leading, spacing: 10) {
                        if let selected = selectedResult {
                            // Review & Edit Before Import Box
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("Tytuł:")
                                        .font(.scaled(11, weight: .bold, scale: scale))
                                        .foregroundColor(.secondary)
                                        .frame(width: 45, alignment: .leading)
                                    
                                    TextField("Tytuł pieśni", text: $editedTitle)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.scaled(13, weight: .semibold, scale: scale))
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        importSong(selected)
                                    }) {
                                        Label("Importuj do programu", systemImage: "arrow.down.doc.fill")
                                            .font(.scaled(12, weight: .semibold, scale: scale))
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                
                                HStack(spacing: 8) {
                                    Text("Autor:")
                                        .font(.scaled(11, weight: .bold, scale: scale))
                                        .foregroundColor(.secondary)
                                        .frame(width: 45, alignment: .leading)
                                    
                                    Toggle("Importuj proponowanego autora:", isOn: $importAuthor)
                                        .font(.scaled(11, weight: .medium, scale: scale))
                                    
                                    if importAuthor {
                                        TextField("Autor / Wykonawca", text: $editedAuthor)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .font(.scaled(11, scale: scale))
                                    } else {
                                        HStack(spacing: 4) {
                                            Image(systemName: "person.crop.circle.badge.questionmark")
                                                .foregroundColor(.orange)
                                            Text("Zostanie zapisany jako:")
                                                .font(.scaled(11, scale: scale))
                                                .foregroundColor(.secondary)
                                            Text("\"Nieznany\"")
                                                .font(.scaled(11, weight: .bold, scale: scale))
                                                .foregroundColor(.orange)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.12))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            
                            Divider()
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    let slides = Song.parseLyrics(selected.lyrics)
                                    ForEach(Array(slides.enumerated()), id: \.element.id) { idx, slide in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(slide.label)
                                                .font(.scaled(10, weight: .bold, scale: scale))
                                                .foregroundColor(.orange)
                                            Text(slide.text)
                                                .font(.scaled(12, scale: scale))
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        } else {
                            Text("Wybierz pieśń z listy, aby zobaczyć podgląd")
                                .font(.scaled(12, scale: scale))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(minWidth: 340)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
    }
    
    private func performSearch() {
        let clean = query.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        Task {
            let found = await OnlineSearchService.shared.search(query: clean, language: language)
            await MainActor.run {
                self.results = found
                self.selectedResultId = found.first?.id
                if let first = found.first {
                    self.editedTitle = first.title
                    self.editedAuthor = first.artist
                    self.importAuthor = !first.artist.isEmpty
                }
                self.isSearching = false
            }
        }
    }
    
    private func importSong(_ result: OnlineSearchResult) {
        let finalTitle = editedTitle.trimmingCharacters(in: .whitespaces).isEmpty ? result.title : editedTitle.trimmingCharacters(in: .whitespaces)
        
        let finalAuthor: String
        if importAuthor {
            let trimmed = editedAuthor.trimmingCharacters(in: .whitespaces)
            finalAuthor = trimmed.isEmpty ? "Nieznany" : trimmed
        } else {
            finalAuthor = "Nieznany"
        }
        
        let newSong = Song(
            title: finalTitle,
            author: finalAuthor,
            tags: ["Import z sieci", result.source],
            rawLyrics: result.lyrics
        )
        store.addSong(newSong)
        isPresented = false
    }
}
