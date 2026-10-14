import Foundation
import SwiftUI

public struct SongEditorView: View {
    @ObservedObject var store = DataStore.shared
    @Binding var isPresented: Bool
    
    var existingSong: Song?
    
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var key: String = ""
    @State private var tagsString: String = ""
    @State private var rawLyrics: String = ""
    @State private var chords: String = ""
    @State private var editorTab: Int = 0 // 0: Tekst & Slajdy, 1: Chwyty gitarowe
    @State private var isShowingChordsSearch: Bool = false
    
    public init(isPresented: Binding<Bool>, existingSong: Song? = nil) {
        self._isPresented = isPresented
        self.existingSong = existingSong
    }
    
    private var parsedSlides: [SongSlide] {
        return Song.parseLyrics(rawLyrics)
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingSong == nil ? loc(.newSong) : loc(.editSong))
                    .font(.scaled(16, weight: .bold, scale: scale))
                
                Spacer()
                
                Button(action: {
                    isShowingChordsSearch = true
                }) {
                    Label("Wyszukaj chwyty online...", systemImage: "guitars.fill")
                        .font(.scaled(11, weight: .semibold, scale: scale))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                
                Button(loc(.cancel)) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button(loc(.save)) {
                    saveSong()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Metadata Fields
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Tytuł pieśni *")
                                .font(.scaled(11, weight: .semibold, scale: scale))
                            Spacer()
                            DictationButtonView(text: $title, mode: .replace, size: 11)
                        }
                        TextField("Wpisz tytuł...", text: $title)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Autor / Źródło")
                                .font(.scaled(11, weight: .semibold, scale: scale))
                            Spacer()
                            DictationButtonView(text: $author, mode: .replace, size: 11)
                        }
                        TextField("np. Cesareo Gabarain", text: $author)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tonacja (Key)")
                            .font(.scaled(11, weight: .semibold, scale: scale))
                        TextField("np. D, G, Am", text: $key)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 90)
                    }
                }
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tagi / Kategorie (rozdzielone przecinkami)")
                            .font(.scaled(11, weight: .semibold, scale: scale))
                        TextField("np. Uwielbienie, Oazowe, Młodzieżowe, ŚDM", text: $tagsString)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    // Tab Picker for Editor View
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Widok edytora")
                            .font(.scaled(11, weight: .semibold, scale: scale))
                            .foregroundColor(.secondary)
                        Picker("", selection: $editorTab) {
                            Text("Tekst i Slajdy").tag(0)
                            Text("Chwyty gitarowe / Taby" + (chords.isEmpty ? "" : " (✓)")).tag(1)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 260)
                    }
                }
            }
            .padding(16)
            
            Divider()
            
            // Editor Body based on selected Tab
            if editorTab == 0 {
                // Side-by-side Editor & Live Slide Breakdown
                HSplitView {
                    // Left: Raw Text Editor
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Treść pieśni (dla rzutnika / zboru)")
                                .font(.scaled(12, weight: .semibold, scale: scale))
                            
                            DictationButtonView(
                                text: $rawLyrics,
                                mode: .appendNewline,
                                size: 12,
                                customPrompt: "Dyktuj tekst nowej zwrotki lub refrenu"
                            )
                            
                            Spacer()
                            Text(loc(.rawLyricsHint))
                                .font(.scaled(10, scale: scale))
                                .foregroundColor(.secondary)
                        }
                        
                        // Quick Section Insertion Toolbar
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("Wstaw sekcję:")
                                    .font(.scaled(10, weight: .semibold, scale: scale))
                                    .foregroundColor(.secondary)
                                
                                SectionInsertButton(title: "+ [Zwrotka]", tag: "[Zwrotka]\n", text: $rawLyrics)
                                SectionInsertButton(title: "+ [Refren]", tag: "[Refren]\n", text: $rawLyrics)
                                SectionInsertButton(title: "+ [Bridge / Mostek]", tag: "[Bridge]\n", text: $rawLyrics)
                                SectionInsertButton(title: "+ [Pre-Chorus]", tag: "[Pre-Chorus]\n", text: $rawLyrics)
                                SectionInsertButton(title: "+ [Coda / Koda]", tag: "[Coda]\n", text: $rawLyrics)
                                SectionInsertButton(title: "+ [Przejście / Solo]", tag: "[Przejście]\n", text: $rawLyrics)
                                SectionInsertButton(title: "+ [Zakończenie]", tag: "[Zakończenie]\n", text: $rawLyrics)
                            }
                            .padding(.vertical, 2)
                        }
                        
                        TextEditor(text: $rawLyrics)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                    .padding(14)
                    .frame(minWidth: 320)
                    
                    // Right: Live Parsed Slides Preview
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Podgląd wygenerowanych slajdów (\(parsedSlides.count))")
                                .font(.scaled(12, weight: .semibold, scale: scale))
                            Spacer()
                        }
                        
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(parsedSlides.enumerated()), id: \.element.id) { index, slide in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 5) {
                                            Text(slide.type.shortBadge)
                                                .font(.scaled(9, weight: .bold, scale: scale))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(badgeColorForType(slide.type))
                                                .foregroundColor(.white)
                                                .cornerRadius(3)
                                            
                                            Text(slide.label)
                                                .font(.scaled(11, weight: .bold, scale: scale))
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            Text("Slajd \(index + 1)")
                                                .font(.scaled(9, scale: scale))
                                                .foregroundColor(.secondary)
                                        }
                                        Text(slide.text)
                                            .font(.scaled(11, scale: scale))
                                            .lineSpacing(2)
                                    }
                                    .padding(8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(minWidth: 260)
                }
            } else {
                // MARK: - Chords & Tabs Editor Tab
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Opracowanie akordów i tabulatur (dla muzyków)")
                                .font(.scaled(12, weight: .bold, scale: scale))
                            Text("Chwyty są dostępne dla muzyków w aplikacji i nie wyświetlają się zborowi na ekranie projekcji.")
                                .font(.scaled(10.5, scale: scale))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Transpose helpers
                        HStack(spacing: 6) {
                            Button("Transpozycja ♭ -1") {
                                chords = GuitarChordsService.shared.transpose(chordsSheet: chords, semitones: -1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("Transpozycja ♯ +1") {
                                chords = GuitarChordsService.shared.transpose(chordsSheet: chords, semitones: 1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button(action: {
                                isShowingChordsSearch = true
                            }) {
                                Label("Szukaj w internecie...", systemImage: "globe")
                                    .font(.scaled(11, weight: .semibold, scale: scale))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        }
                    }
                    
                    TextEditor(text: $chords)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .lineSpacing(4)
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
                .padding(14)
            }
        }
        .frame(minWidth: 740, minHeight: 580)
        .onAppear {
            if let song = existingSong {
                self.title = song.title
                self.author = song.author
                self.key = song.key
                self.tagsString = song.tags.joined(separator: ", ")
                self.rawLyrics = song.rawLyrics
                self.chords = song.chords ?? ""
            }
        }
        .sheet(isPresented: $isShowingChordsSearch) {
            let tempSong = Song(title: title.isEmpty ? "Nowa pieśń" : title, author: author, rawLyrics: rawLyrics)
            ChordsSearchSheet(
                song: tempSong,
                isPresented: $isShowingChordsSearch,
                onApply: { chordsSheet, appliedKey in
                    self.chords = chordsSheet
                    if !appliedKey.isEmpty && key.isEmpty {
                        self.key = appliedKey
                    }
                    self.editorTab = 1 // Switch to chords tab to view
                }
            )
        }
    }
    
    private func saveSong() {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        guard !cleanTitle.isEmpty else { return }
        
        let tags = tagsString
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let finalChords = chords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : chords
        
        if let existing = existingSong {
            var updated = existing
            updated.title = cleanTitle
            updated.author = author.trimmingCharacters(in: .whitespaces)
            updated.key = key.trimmingCharacters(in: .whitespaces)
            updated.tags = tags
            updated.rawLyrics = rawLyrics
            updated.chords = finalChords
            updated.slides = Song.parseLyrics(rawLyrics)
            store.updateSong(updated)
        } else {
            let newSong = Song(
                title: cleanTitle,
                author: author.trimmingCharacters(in: .whitespaces),
                key: key.trimmingCharacters(in: .whitespaces),
                tags: tags,
                rawLyrics: rawLyrics,
                chords: finalChords
            )
            store.addSong(newSong)
        }
    }
    
    private func badgeColorForType(_ type: SlideType) -> Color {
        switch type {
        case .chorus: return .orange
        case .verse: return .blue
        case .bridge: return .purple
        case .preChorus: return .teal
        case .coda: return .pink
        case .interlude: return .mint
        case .ending: return .brown
        case .intro, .outro: return .gray
        case .tag: return .yellow
        default: return .indigo
        }
    }
}

// MARK: - Section Insert Button
private struct SectionInsertButton: View {
    let title: String
    let tag: String
    @Binding var text: String
    
    var body: some View {
        Button(action: {
            if text.isEmpty {
                text = tag
            } else if text.hasSuffix("\n\n") {
                text += tag
            } else if text.hasSuffix("\n") {
                text += "\n" + tag
            } else {
                text += "\n\n" + tag
            }
        }) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }
}

