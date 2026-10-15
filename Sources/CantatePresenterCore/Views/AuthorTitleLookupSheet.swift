import Foundation
import SwiftUI

public enum LookupScope: String, CaseIterable, Identifiable {
    case selectedSong = "Dla zaznaczonej pieśni"
    case allSongs = "Dla wszystkich pieśni"
    
    public var id: String { rawValue }
}

public struct AuthorTitleLookupSheet: View {
    @Bindable var store = DataStore.shared
    @Binding var isPresented: Bool
    
    // Initial song passed if triggered for a specific song
    public var initialSong: Song?
    
    @State private var scope: LookupScope = .selectedSong
    
    // Single song mode state
    @State private var selectedSongId: UUID?
    @State private var singleQuery: String = ""
    @State private var isSingleSearching: Bool = false
    @State private var singleResults: [OnlineSearchResult] = []
    @State private var selectedCandidateId: UUID?
    @State private var singleSuccessMessage: String?
    
    // Batch mode state
    @State private var onlyMissingAuthor: Bool = true
    @State private var onlyFillEmptyFields: Bool = true
    @State private var updateTitleAlso: Bool = false
    @State private var isBatchRunning: Bool = false
    @State private var batchProgress: Double = 0.0
    @State private var batchStatusText: String = ""
    @State private var batchProposals: [SongMatchProposal] = []
    @State private var batchSuccessMessage: String?
    
    public init(isPresented: Binding<Bool>, initialSong: Song? = nil) {
        self._isPresented = isPresented
        self.initialSong = initialSong
    }
    
    private var targetSingleSong: Song? {
        if let id = selectedSongId {
            return store.songs.first(where: { $0.id == id })
        }
        return initialSong ?? store.selectedSong ?? store.songs.first
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // MARK: - Header
            HStack(spacing: 12) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wyszukiwarka tytułu i autora pieśni")
                        .font(.scaled(16, weight: .bold, scale: scale))
                    Text("Wyszukuje i automatycznie uzupełnia brakujące dane utworów w oparciu o bazę hymnów i sieć internetową")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Zamknij") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // MARK: - Scope Selector (Dla aktualnie zaznaczonej / Dla wszystkich)
            HStack {
                Text("Zakres operacji:")
                    .font(.scaled(12, weight: .semibold, scale: scale))
                
                Picker("", selection: $scope) {
                    ForEach(LookupScope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 320)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // MARK: - Content by Scope
            if scope == .selectedSong {
                singleSongView(scale: scale)
            } else {
                batchSongsView(scale: scale)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            if let song = targetSingleSong {
                selectedSongId = song.id
                singleQuery = AuthorTitleLookupService.shared.suggestedQuery(for: song)
                performSingleSearch()
            }
        }
    }
    
    // MARK: - Single Song Mode View
    @ViewBuilder
    private func singleSongView(scale: Double) -> some View {
        VStack(spacing: 0) {
            // Selected song header & Query editor
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    // Song Picker / Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aktualna pieśń:")
                            .font(.scaled(11, weight: .bold, scale: scale))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: Binding(
                            get: { targetSingleSong?.id ?? UUID() },
                            set: { newId in
                                selectedSongId = newId
                                if let s = store.songs.first(where: { $0.id == newId }) {
                                    singleQuery = AuthorTitleLookupService.shared.suggestedQuery(for: s)
                                    performSingleSearch()
                                }
                            }
                        )) {
                            ForEach(store.songs) { s in
                                Text(s.title + (s.author.isEmpty ? " (brak autora)" : " — \(s.author)"))
                                    .tag(s.id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    .frame(maxWidth: 320)
                    
                    // Search Query Box
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fraza wyszukiwania (tytuł lub fragment tekstu):")
                            .font(.scaled(11, weight: .bold, scale: scale))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("Wpisz fragment tekstu lub tytuł...", text: $singleQuery)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.scaled(12, scale: scale))
                                .onSubmit {
                                    performSingleSearch()
                                }
                            
                            DictationButtonView(text: $singleQuery, mode: .replace, size: 12)
                            
                            Button(action: performSingleSearch) {
                                if isSingleSearching {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 50)
                                } else {
                                    Text("Szukaj")
                                        .frame(width: 50)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(singleQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSingleSearching)
                        }
                    }
                }
                
                if let msg = singleSuccessMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.scaled(11, weight: .medium, scale: scale))
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Candidates list & actions
            if isSingleSearching {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Wyszukiwanie tytułu i autora w bazie hymnów i sieci...")
                        .font(.scaled(12, scale: scale))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if singleResults.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Nie znaleziono propozycji dla podanej frazy.")
                        .font(.scaled(13, scale: scale))
                        .foregroundColor(.secondary)
                    Text("Spróbuj wpisać inny fragment tekstu lub pierwsze słowa zwrotki.")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }
            } else {
                List(selection: $selectedCandidateId) {
                    ForEach(singleResults) { item in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(item.title)
                                        .font(.scaled(13, weight: .bold, scale: scale))
                                    
                                    if !item.source.isEmpty {
                                        Text(item.source)
                                            .font(.scaled(9, weight: .medium, scale: scale))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                    }
                                }
                                
                                HStack(spacing: 6) {
                                    Text("Autor / Wykonawca:")
                                        .font(.scaled(11, weight: .medium, scale: scale))
                                        .foregroundColor(.secondary)
                                    Text(item.artist.isEmpty ? "(brak informacji)" : item.artist)
                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                        .foregroundColor(item.artist.isEmpty ? .secondary : .primary)
                                }
                                
                                if !item.snippet.isEmpty {
                                    Text(item.snippet)
                                        .font(.scaled(10, scale: scale))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            // Apply Buttons
                            VStack(alignment: .trailing, spacing: 4) {
                                Button(action: {
                                    applySingleCandidate(item, updateTitle: true, setUnknownAuthor: false)
                                }) {
                                    Label("Zastosuj tytuł i autora", systemImage: "checkmark")
                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                HStack(spacing: 4) {
                                    Button(action: {
                                        applySingleCandidate(item, updateTitle: true, setUnknownAuthor: true)
                                    }) {
                                        Text("Tytuł + autor: 'Nieznany'")
                                            .font(.scaled(10, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help("Zastosuj tytuł, a autora oznacz jako 'Nieznany' (np. gdy proponowany autor budzi wątpliwości)")
                                    
                                    Button(action: {
                                        applySingleCandidate(item, updateTitle: false, setUnknownAuthor: true)
                                    }) {
                                        Text("Autor -> 'Nieznany'")
                                            .font(.scaled(10, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    
                                    if !item.artist.isEmpty {
                                        Button(action: {
                                            applySingleCandidate(item, updateTitle: false, setUnknownAuthor: false)
                                        }) {
                                            Text("Tylko autora")
                                                .font(.scaled(10, scale: scale))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .tag(item.id)
                    }
                }
                .listStyle(InsetListStyle())
            }
        }
    }
    
    // MARK: - Batch Songs Mode View
    @ViewBuilder
    private func batchSongsView(scale: Double) -> some View {
        VStack(spacing: 0) {
            // Options Bar
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 20) {
                    Toggle("Tylko pieśni z brakującym autorem", isOn: $onlyMissingAuthor)
                        .font(.scaled(11, scale: scale))
                    
                    Toggle("Uzupełniaj tylko puste pola", isOn: $onlyFillEmptyFields)
                        .font(.scaled(11, scale: scale))
                    
                    Toggle("Aktualizuj również tytuły", isOn: $updateTitleAlso)
                        .font(.scaled(11, scale: scale))
                    
                    Spacer()
                    
                    Button(action: startBatchLookup) {
                        if isBatchRunning {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 140)
                        } else {
                            Label("Rozpocznij przeszukiwanie", systemImage: "sparkles.magnifyingglass")
                                .font(.scaled(11, weight: .semibold, scale: scale))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBatchRunning)
                }
                
                if isBatchRunning {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: batchProgress, total: 1.0)
                        Text(batchStatusText)
                            .font(.scaled(10, scale: scale))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let msg = batchSuccessMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.scaled(11, weight: .medium, scale: scale))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Proposals List
            if batchProposals.isEmpty && !isBatchRunning {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "rectangle.stack.badge.person.crop")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Kliknij 'Rozpocznij przeszukiwanie', aby przeanalizować utwory w bibliotece.")
                        .font(.scaled(13, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                    Text("System dopasuje pieśni na podstawie słów zwrotek oraz tytułów i zaproponuje autorów.")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Selection action bar
                    HStack {
                        Button("Zaznacz wszystkie") {
                            for i in 0..<batchProposals.count {
                                batchProposals[i].isSelected = true
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        Button("Odznacz wszystkie") {
                            for i in 0..<batchProposals.count {
                                batchProposals[i].isSelected = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        Divider()
                            .frame(height: 16)
                        
                        Button("Wszyscy autorzy") {
                            for i in 0..<batchProposals.count {
                                batchProposals[i].acceptAuthor = true
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        Button("Autorzy -> 'Nieznany'") {
                            for i in 0..<batchProposals.count {
                                batchProposals[i].acceptAuthor = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Oznacza proponowanych autorów jako 'Nieznany' (np. gdy nazwy budzą wątpliwości)")
                        
                        Spacer()
                        
                        let selectedCount = batchProposals.filter { $0.isSelected && !$0.isApplied }.count
                        Button(action: applyBatchProposals) {
                            Label("Zastosuj do zaznaczonych (\(selectedCount))", systemImage: "checkmark.circle")
                                .font(.scaled(11, weight: .semibold, scale: scale))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(selectedCount == 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    List {
                        ForEach($batchProposals) { $proposal in
                            HStack(alignment: .center, spacing: 12) {
                                Toggle("", isOn: $proposal.isSelected)
                                    .labelsHidden()
                                    .disabled(proposal.isApplied)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(proposal.currentTitle)
                                            .font(.scaled(13, weight: .semibold, scale: scale))
                                        
                                        if updateTitleAlso && proposal.proposedTitle != proposal.currentTitle {
                                            Image(systemName: "arrow.right")
                                                .font(.scaled(10, scale: scale))
                                                .foregroundColor(.secondary)
                                            Text(proposal.proposedTitle)
                                                .font(.scaled(13, weight: .bold, scale: scale))
                                                .foregroundColor(.blue)
                                        }
                                        
                                        Spacer()
                                        
                                        Text("\(proposal.confidence)% zgodności")
                                            .font(.scaled(9, weight: .bold, scale: scale))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(proposal.confidence > 70 ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                            .foregroundColor(proposal.confidence > 70 ? .green : .orange)
                                            .cornerRadius(4)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Text("Autor:")
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                        Text(proposal.currentAuthor.isEmpty ? "(brak)" : proposal.currentAuthor)
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                        Image(systemName: "arrow.right")
                                            .font(.scaled(10, scale: scale))
                                            .foregroundColor(.secondary)
                                        
                                        Toggle(isOn: $proposal.acceptAuthor) {
                                            if proposal.acceptAuthor {
                                                HStack(spacing: 4) {
                                                    Text(proposal.proposedAuthor.isEmpty ? "(nie znaleziono)" : proposal.proposedAuthor)
                                                        .font(.scaled(11, weight: .bold, scale: scale))
                                                        .foregroundColor(proposal.proposedAuthor.isEmpty ? .secondary : .primary)
                                                    Text("(zastosuj)")
                                                        .font(.scaled(9, scale: scale))
                                                        .foregroundColor(.secondary)
                                                }
                                            } else {
                                                HStack(spacing: 4) {
                                                    Text("Zapisz jako:")
                                                        .font(.scaled(11, scale: scale))
                                                        .foregroundColor(.secondary)
                                                    Text("\"Nieznany\"")
                                                        .font(.scaled(11, weight: .bold, scale: scale))
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                        }
                                        .toggleStyle(.checkbox)
                                        .disabled(proposal.isApplied)
                                    }
                                }
                                
                                if proposal.isApplied {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 16))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(InsetListStyle())
                }
            }
        }
    }
    
    // MARK: - Actions
    private func performSingleSearch() {
        guard let song = targetSingleSong else { return }
        let clean = singleQuery.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        
        isSingleSearching = true
        singleSuccessMessage = nil
        
        Task {
            let (_, results) = await AuthorTitleLookupService.shared.lookup(for: song, customQuery: clean)
            await MainActor.run {
                self.singleResults = results
                self.selectedCandidateId = results.first?.id
                self.isSingleSearching = false
            }
        }
    }
    
    private func applySingleCandidate(_ candidate: OnlineSearchResult, updateTitle: Bool, setUnknownAuthor: Bool = false) {
        guard var song = targetSingleSong else { return }
        
        var updatedTitle = song.title
        var updatedAuthor = song.author
        
        if updateTitle && !candidate.title.isEmpty {
            updatedTitle = candidate.title
        }
        if setUnknownAuthor {
            updatedAuthor = "Nieznany"
        } else if !candidate.artist.isEmpty {
            updatedAuthor = candidate.artist
        }
        
        song.title = updatedTitle
        song.author = updatedAuthor
        store.updateSong(song)
        
        singleSuccessMessage = "Zaktualizowano dane utworu: \(updatedTitle) (Autor: \(updatedAuthor))"
    }
    
    private func startBatchLookup() {
        let candidateSongs = store.songs.filter { song in
            if onlyMissingAuthor && !song.author.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
            return true
        }
        
        guard !candidateSongs.isEmpty else {
            batchSuccessMessage = "Brak pieśni spełniających wybrane kryteria (wszystkie mają już autora)."
            return
        }
        
        isBatchRunning = true
        batchProgress = 0.0
        batchProposals = []
        batchSuccessMessage = nil
        
        Task {
            var proposals: [SongMatchProposal] = []
            let total = candidateSongs.count
            
            for (index, song) in candidateSongs.enumerated() {
                await MainActor.run {
                    self.batchProgress = Double(index) / Double(total)
                    self.batchStatusText = "Przeszukiwanie \(index + 1) z \(total): \(song.title)..."
                }
                
                let (bestMatch, _) = await AuthorTitleLookupService.shared.lookup(for: song)
                if let match = bestMatch, !match.proposedAuthor.isEmpty || !match.proposedTitle.isEmpty {
                    proposals.append(match)
                }
            }
            
            await MainActor.run {
                self.batchProposals = proposals
                self.batchProgress = 1.0
                self.isBatchRunning = false
                self.batchStatusText = "Ukończono! Znaleziono propozycje dla \(proposals.count) z \(total) pieśni."
            }
        }
    }
    
    private func applyBatchProposals() {
        var appliedCount = 0
        for i in 0..<batchProposals.count {
            guard batchProposals[i].isSelected && !batchProposals[i].isApplied else { continue }
            let prop = batchProposals[i]
            
            if let idx = store.songs.firstIndex(where: { $0.id == prop.songId }) {
                var song = store.songs[idx]
                
                // Update author
                if prop.acceptAuthor {
                    if !prop.proposedAuthor.isEmpty {
                        if !onlyFillEmptyFields || song.author.trimmingCharacters(in: .whitespaces).isEmpty {
                            song.author = prop.proposedAuthor
                        }
                    }
                } else {
                    song.author = "Nieznany"
                }
                
                // Update title if enabled
                if updateTitleAlso && !prop.proposedTitle.isEmpty {
                    song.title = prop.proposedTitle
                }
                
                store.updateSong(song)
                batchProposals[i].isApplied = true
                appliedCount += 1
            }
        }
        
        batchSuccessMessage = "Pomyślnie zaktualizowano dane dla \(appliedCount) pieśni!"
    }
}
