import Foundation
import SwiftUI
import AppKit

public struct ChordsSearchSheet: View {
    @Bindable var store = DataStore.shared
    public let song: Song
    public let onApply: (String, String) -> Void // (chordsSheet, key)
    @Binding var isPresented: Bool
    
    @State private var searchQuery: String = ""
    @State private var results: [GuitarChordResult] = []
    @State private var selectedResult: GuitarChordResult?
    @State private var previewChords: String = ""
    @State private var transpositionSteps: Int = 0
    
    public init(song: Song, isPresented: Binding<Bool>, onApply: @escaping (String, String) -> Void) {
        self.song = song
        self._isPresented = isPresented
        self.onApply = onApply
        self._searchQuery = State(initialValue: song.title)
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "guitars.fill")
                            .font(.scaled(18, scale: scale))
                            .foregroundColor(.orange)
                        Text(L("Wyszukiwarka chwytów gitarowych i tabulatur"))
                            .font(.scaled(16, weight: .bold, scale: scale))
                    }
                    Text(L("Szukanie akordów dla: „{0}” we wbudowanej bazie chwytów", song.title))
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(L("Zamknij")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Search Bar with Voice Dictation
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(L("Wpisz tytuł pieśni lub słowa..."), text: $searchQuery, onCommit: {
                        triggerSearch()
                    })
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.scaled(13, scale: scale))
                    
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .helpLabel(L("Wyczyść wyszukiwanie"))
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                DictationButtonView(text: $searchQuery, mode: .replace, size: 13, customPrompt: L("Powiedz tytuł pieśni..."))
                
                Button(action: triggerSearch) {
                    Text(L("Szukaj"))
                        .font(.scaled(12, weight: .semibold, scale: scale))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
            
            Divider()
            
            // Main Content: Split Master-Detail
            HSplitView {
                // Left: Results list
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(L("Znalezione opracowania ({0})", results.count))
                            .font(.scaled(11, weight: .semibold, scale: scale))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    
                    Divider()
                    
                    if results.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.scaled(32, scale: scale))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(L("Wpisz tytuł i kliknij „Szukaj”, aby znaleźć chwyty we wbudowanej bazie. Program nie pobiera chwytów z internetu."))
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(results, selection: Binding(
                            get: { selectedResult?.id },
                            set: { newId in
                                if let match = results.first(where: { $0.id == newId }) {
                                    selectResult(match)
                                }
                            }
                        )) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title)
                                        .font(.scaled(12, weight: .bold, scale: scale))
                                    Spacer()
                                    if !item.key.isEmpty {
                                        Text(item.key)
                                            .font(.scaled(10, weight: .bold, scale: scale))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15))
                                            .foregroundColor(.orange)
                                            .cornerRadius(4)
                                    }
                                }
                                
                                HStack {
                                    Text(item.artist)
                                        .font(.scaled(10, scale: scale))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(item.source)
                                        .font(.scaled(9.5, scale: scale))
                                        .foregroundColor(.secondary.opacity(0.8))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(minWidth: 260, maxWidth: 360)
                
                // Right: Chords Preview & Transposition
                VStack(alignment: .leading, spacing: 0) {
                    if let sel = selectedResult {
                        // Transposition Toolbar
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Text(L("Transpozycja:"))
                                    .font(.scaled(11, weight: .semibold, scale: scale))
                                    .foregroundColor(.secondary)
                                
                                Button(action: { transposeChords(by: -1) }) {
                                    Label("♭ -1", systemImage: "minus")
                                        .font(.scaled(10.5, scale: scale))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Text(transpositionSteps == 0 ? "0" : (transpositionSteps > 0 ? "+\(transpositionSteps)" : "\(transpositionSteps)"))
                                    .font(.scaled(11, weight: .bold, scale: scale))
                                    .frame(minWidth: 28)
                                
                                Button(action: { transposeChords(by: 1) }) {
                                    Label("♯ +1", systemImage: "plus")
                                        .font(.scaled(10.5, scale: scale))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                if transpositionSteps != 0 {
                                    Button(L("Reset")) {
                                        resetTransposition()
                                    }
                                    .buttonStyle(.plain)
                                    .font(.scaled(10.5, scale: scale))
                                    .foregroundColor(.blue)
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                onApply(previewChords, sel.key)
                                isPresented = false
                            }) {
                                Label(L("Zastosuj chwyty do pieśni"), systemImage: "checkmark.circle.fill")
                                    .font(.scaled(11, weight: .bold, scale: scale))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.regular)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        
                        Divider()
                        
                        // Chords sheet view in clean monospace font
                        ScrollView {
                            Text(previewChords)
                                .font(.system(size: 13 * scale, weight: .regular, design: .monospaced))
                                .lineSpacing(4)
                                .foregroundColor(.primary)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        
                    } else {
                        VStack(spacing: 8) {
                            Text(L("Wybierz opracowanie z listy po lewej stronie, aby podejrzeć chwyty i dokonać transpozycji."))
                                .font(.scaled(12, scale: scale))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 400)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 560)
        .onAppear {
            triggerSearch()
        }
    }
    
    private func triggerSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        results = GuitarChordsService.shared.searchChords(for: searchQuery)
        if let first = results.first {
            selectResult(first)
        } else {
            selectedResult = nil
        }
    }
    
    private func selectResult(_ item: GuitarChordResult) {
        self.selectedResult = item
        self.transpositionSteps = 0
        self.previewChords = item.chordsSheet
    }
    
    private func transposeChords(by step: Int) {
        guard let sel = selectedResult else { return }
        transpositionSteps += step
        previewChords = GuitarChordsService.shared.transpose(chordsSheet: sel.chordsSheet, semitones: transpositionSteps)
    }
    
    private func resetTransposition() {
        guard let sel = selectedResult else { return }
        transpositionSteps = 0
        previewChords = sel.chordsSheet
    }
}
