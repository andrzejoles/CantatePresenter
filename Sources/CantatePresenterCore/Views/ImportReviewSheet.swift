import Foundation
import SwiftUI
import AppKit

public struct ImportReviewSheet: View {
    @Bindable var store = DataStore.shared
    public let report: ImportProcessingResult
    public let onCommit: ([Song]) -> Void
    public let onCancel: () -> Void
    
    @State private var selectedTab: Int = 0 // 0: Wzbogacone, 1: Duplikaty, 2: Kolizje, 3: Wszystkie, 4: Chwyty
    @State private var searchQuery: String = ""
    @State private var duplicateSkipMap: [UUID: Bool] = [:]
    @State private var collisionSkipMap: [UUID: Bool] = [:]
    @State private var songForChordsSearch: Song?
    @State private var isShowingChordsModal: Bool = false
    @State private var workingSongs: [Song] = []
    
    public init(report: ImportProcessingResult, onCommit: @escaping ([Song]) -> Void, onCancel: @escaping () -> Void) {
        self.report = report
        self.onCommit = onCommit
        self.onCancel = onCancel
        
        var map: [UUID: Bool] = [:]
        for d in report.duplicateRecords {
            map[d.id] = d.shouldSkipDuplicate
        }
        _duplicateSkipMap = State(initialValue: map)
        _workingSongs = State(initialValue: report.uniqueSongs)
    }
    
    private var songsWithChords: [Song] {
        return workingSongs.filter { $0.chords != nil && !$0.chords!.isEmpty }
    }
    
    private var filteredEnrichments: [EnrichmentRecord] {
        if searchQuery.isEmpty { return report.enrichmentRecords }
        let q = Song.foldString(searchQuery)
        return report.enrichmentRecords.filter {
            Song.foldString($0.enrichedTitle).contains(q) ||
            Song.foldString($0.enrichedAuthor).contains(q) ||
            Song.foldString($0.details).contains(q)
        }
    }
    
    private var filteredDuplicates: [DuplicateRecord] {
        if searchQuery.isEmpty { return report.duplicateRecords }
        let q = Song.foldString(searchQuery)
        return report.duplicateRecords.filter {
            Song.foldString($0.primarySong.title).contains(q) ||
            Song.foldString($0.duplicateSong.title).contains(q) ||
            Song.foldString($0.reason).contains(q)
        }
    }
    
    private var filteredSongsWithChords: [Song] {
        if searchQuery.isEmpty { return songsWithChords }
        let q = Song.foldString(searchQuery)
        return songsWithChords.filter {
            Song.foldString($0.title).contains(q) ||
            Song.foldString($0.author).contains(q) ||
            Song.foldString($0.key).contains(q)
        }
    }
    
    private var songsToCommit: [Song] {
        report.songsToCommit(workingSongs: workingSongs, duplicateSkips: duplicateSkipMap, collisionSkips: collisionSkipMap)
    }
    
    private var songsToImportCount: Int {
        songsToCommit.count
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Podsumowanie importu i deduplikacji pieśni"))
                        .font(.scaled(17, weight: .bold, scale: scale))
                    Text(L("Wykryto duplikaty, naprawiono polskie litery, oczyszczono formatowanie i dołączono chwyty gitarowe."))
                        .font(.scaled(12, scale: scale))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(L("Anuluj")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Pliki uszkodzone lub wczytane częściowo (R2-04)
            if !report.fileProblems.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label(L("Nie wszystkie pliki udało się wczytać:"), systemImage: "exclamationmark.triangle.fill")
                        .font(.scaled(12, weight: .semibold, scale: scale))
                        .foregroundColor(.orange)
                    ForEach(Array(report.fileProblems.prefix(5).enumerated()), id: \.offset) { _, problem in
                        Text("\(problem.fileName): \(problem.message)")
                            .font(.scaled(11, scale: scale))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    if report.fileProblems.count > 5 {
                        Text(L("… i {0} więcej", report.fileProblems.count - 5))
                            .font(.scaled(11, scale: scale))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
                
                Divider()
            }
            
            // 4 Summary Metrics Badges
            HStack(spacing: 12) {
                MetricCard(
                    title: L("Wczytano z pliku"),
                    value: "\(report.totalScanned)",
                    subtitle: L("utworów"),
                    icon: "doc.text.magnifyingglass",
                    color: .blue,
                    scale: scale
                )
                
                MetricCard(
                    title: L("Wykryte duplikaty"),
                    value: "\(report.duplicateRecords.count)",
                    subtitle: L("pominięte"),
                    icon: "doc.on.doc.fill",
                    color: .orange,
                    scale: scale
                )
                
                MetricCard(
                    title: L("Autorzy i polskie litery"),
                    value: "\(report.enrichmentRecords.count)",
                    subtitle: L("wzbogacone"),
                    icon: "sparkles",
                    color: .purple,
                    scale: scale
                )
                
                MetricCard(
                    title: L("Chwyty gitarowe"),
                    value: "\(songsWithChords.count)",
                    subtitle: L("z akordami"),
                    icon: "guitars.fill",
                    color: .yellow,
                    scale: scale
                )
                
                MetricCard(
                    title: L("Do zaimportowania"),
                    value: "\(songsToImportCount)",
                    subtitle: L("unikalnych pieśni"),
                    icon: "checkmark.circle.fill",
                    color: .green,
                    scale: scale
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Tab Selector & Search Bar
            HStack {
                Picker("", selection: $selectedTab) {
                    Text(L("Autorzy & Polskie litery ({0})", report.enrichmentRecords.count)).tag(0)
                    Text(L("Wykryte duplikaty ({0})", report.duplicateRecords.count)).tag(1)
                    Text(L("Chwyty gitarowe ({0})", songsWithChords.count)).tag(4)
                    if !report.existingCollisions.isEmpty {
                        Text(L("Kolizje z bazą ({0})", report.existingCollisions.count)).tag(2)
                    }
                    Text(L("Wszystkie do dodania ({0})", workingSongs.count)).tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(L("Filtruj listę..."), text: $searchQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.scaled(11, scale: scale))
                        .frame(width: 160)
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .helpLabel(L("Wyczyść wyszukiwanie"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()
            
            // Tab Contents
            Group {
                if selectedTab == 0 {
                    // MARK: - Enriched Songs List
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if filteredEnrichments.isEmpty {
                                Text(L("Brak elementów do wyświetlenia"))
                                    .foregroundColor(.secondary)
                                    .padding(40)
                            } else {
                                ForEach(filteredEnrichments) { item in
                                    EnrichmentRowView(item: item, scale: scale)
                                }
                            }
                        }
                        .padding(16)
                    }
                } else if selectedTab == 1 {
                    // MARK: - Duplicates List
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if filteredDuplicates.isEmpty {
                                Text(L("Brak wykrytych duplikatów"))
                                    .foregroundColor(.secondary)
                                    .padding(40)
                            } else {
                                ForEach(filteredDuplicates) { item in
                                    DuplicateRowView(
                                        record: item,
                                        isSkipped: Binding(
                                            get: { duplicateSkipMap[item.id] ?? true },
                                            set: { duplicateSkipMap[item.id] = $0 }
                                        ),
                                        scale: scale
                                    )
                                }
                            }
                        }
                        .padding(16)
                    }
                } else if selectedTab == 4 {
                    // MARK: - Chords & Tabs List
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if filteredSongsWithChords.isEmpty {
                                VStack(spacing: 8) {
                                    Text(L("Brak opracowań chwytów spełniających filtr."))
                                        .foregroundColor(.secondary)
                                }
                                .padding(40)
                            } else {
                                ForEach(filteredSongsWithChords) { song in
                                    ChordsSummaryRowView(
                                        song: song,
                                        scale: scale,
                                        onSearchChords: {
                                            self.songForChordsSearch = song
                                            self.isShowingChordsModal = true
                                        }
                                    )
                                }
                            }
                        }
                        .padding(16)
                    }
                } else if selectedTab == 2 {
                    // MARK: - Collisions with Existing Library
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(report.existingCollisions) { item in
                                CollisionRowView(
                                    record: item,
                                    isSkipped: Binding(
                                        get: { collisionSkipMap[item.id] ?? item.shouldSkipDuplicate },
                                        set: { collisionSkipMap[item.id] = $0 }
                                    ),
                                    scale: scale
                                )
                            }
                        }
                        .padding(16)
                    }
                } else {
                    // MARK: - All Unique Songs List
                    List(workingSongs) { song in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(song.title)
                                        .font(.scaled(12, weight: .semibold, scale: scale))
                                    if song.chords != nil {
                                        Text("🎸")
                                            .font(.scaled(10, scale: scale))
                                    }
                                    if !song.key.isEmpty {
                                        Text(song.key)
                                            .font(.scaled(9, weight: .bold, scale: scale))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.15))
                                            .foregroundColor(.orange)
                                            .cornerRadius(3)
                                    }
                                }
                                Text(song.author.isEmpty ? L("Autor nieznany") : song.displayAuthor)
                                    .font(.scaled(10, scale: scale))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(L("{0} slajdów", song.slides.count))
                                .font(.scaled(10, scale: scale))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Bottom Action Bar
            HStack {
                Text(L("Gotowych do dodania: {0} pieśni ({1} z chwytami gitarowymi)", songsToImportCount, songsWithChords.count))
                    .font(.scaled(12, weight: .medium, scale: scale))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(L("Anuluj")) {
                    onCancel()
                }
                .font(.scaled(12, scale: scale))
                
                Button(action: {
                    commitImport()
                }) {
                    Label(L("Zaimportuj {0} pieśni", songsToImportCount), systemImage: "arrow.down.doc.fill")
                        .font(.scaled(12, weight: .bold, scale: scale))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.regular)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 580)
        .sheet(isPresented: $isShowingChordsModal) {
            if let targetSong = songForChordsSearch {
                ChordsSearchSheet(
                    song: targetSong,
                    isPresented: $isShowingChordsModal,
                    onApply: { newChords, newKey in
                        if let idx = workingSongs.firstIndex(where: { $0.id == targetSong.id }) {
                            workingSongs[idx].chords = newChords
                            if !newKey.isEmpty {
                                workingSongs[idx].key = newKey
                            }
                        }
                    }
                )
            }
        }
    }
    
    private func commitImport() {
        onCommit(songsToCommit)
    }
}

// MARK: - Subviews
private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let scale: CGFloat
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.scaled(20, scale: scale))
                .foregroundColor(color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.scaled(17, weight: .bold, scale: scale))
                    .foregroundColor(.primary)
                Text(title)
                    .font(.scaled(9.5, weight: .medium, scale: scale))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct EnrichmentRowView: View {
    let item: EnrichmentRecord
    let scale: CGFloat
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkle")
                .foregroundColor(.purple)
                .font(.scaled(14, scale: scale))
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.enrichedTitle)
                        .font(.scaled(12, weight: .bold, scale: scale))
                    if item.enrichedTitle != item.originalTitle {
                        Text(L("(z: „{0}”)", item.originalTitle))
                            .font(.scaled(10, scale: scale))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 6) {
                    Text(L("Autor:"))
                        .font(.scaled(10, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                    Text(item.enrichedAuthor.isEmpty ? L("brak") : item.enrichedAuthor)
                        .font(.scaled(11, weight: .semibold, scale: scale))
                        .foregroundColor(.primary)
                    if !item.originalAuthor.isEmpty && item.originalAuthor != item.enrichedAuthor {
                        Text(L("(wcześniej: {0})", item.originalAuthor))
                            .font(.scaled(10, scale: scale))
                            .foregroundColor(.secondary)
                    }
                }
                
                if !item.details.isEmpty {
                    Text(item.details)
                        .font(.scaled(9.5, scale: scale))
                        .foregroundColor(.purple.opacity(0.8))
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

private struct ChordsSummaryRowView: View {
    let song: Song
    let scale: CGFloat
    let onSearchChords: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "guitars.fill")
                        .foregroundColor(.orange)
                    Text(song.title)
                        .font(.scaled(12, weight: .bold, scale: scale))
                }
                
                if !song.key.isEmpty {
                    Text(L("Tonacja: {0}", song.key))
                        .font(.scaled(10, weight: .bold, scale: scale))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Button(action: onSearchChords) {
                    Label(L("Zmień / Szukaj chwytów"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.scaled(10, scale: scale))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if let chords = song.chords {
                let previewLines = chords.components(separatedBy: .newlines).prefix(4).joined(separator: "\n")
                Text(previewLines)
                    .font(.system(size: 11 * scale, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.7))
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct DuplicateRowView: View {
    let record: DuplicateRecord
    @Binding var isSkipped: Bool
    let scale: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundColor(.orange)
                    Text(L("Zgodność: {0}%", record.similarityScore))
                        .font(.scaled(11, weight: .bold, scale: scale))
                        .foregroundColor(.orange)
                }
                
                Text("•  \(record.reason)")
                    .font(.scaled(10.5, scale: scale))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Toggle(L("Pomiń ten duplikat"), isOn: $isSkipped)
                    .font(.scaled(11, scale: scale))
                    .toggleStyle(CheckboxToggleStyle())
            }
            
            HStack(spacing: 12) {
                // Primary version
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.scaled(10, scale: scale))
                        Text(L("Wersja główna (zachowywana):"))
                            .font(.scaled(9.5, weight: .bold, scale: scale))
                            .foregroundColor(.green)
                    }
                    Text(record.primarySong.title)
                        .font(.scaled(11, weight: .semibold, scale: scale))
                    Text(record.primarySong.author.isEmpty ? L("Autor nieznany") : record.primarySong.displayAuthor)
                        .font(.scaled(10, scale: scale))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.06))
                .cornerRadius(6)
                
                // Duplicate version
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(isSkipped ? .red : .orange)
                            .font(.scaled(10, scale: scale))
                        Text(isSkipped ? L("Wersja zduplikowana (pomijana):") : L("Wersja zduplikowana (zostanie dodana):"))
                            .font(.scaled(9.5, weight: .bold, scale: scale))
                            .foregroundColor(isSkipped ? .red : .orange)
                    }
                    Text(record.duplicateSong.title)
                        .font(.scaled(11, weight: .semibold, scale: scale))
                    Text(record.duplicateSong.author.isEmpty ? L("Autor nieznany") : record.duplicateSong.displayAuthor)
                        .font(.scaled(10, scale: scale))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSkipped ? Color.red.opacity(0.06) : Color.orange.opacity(0.06))
                .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct CollisionRowView: View {
    let record: DuplicateRecord
    @Binding var isSkipped: Bool
    let scale: CGFloat
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.primarySong.title)
                    .font(.scaled(11, weight: .bold, scale: scale))
                Text(record.reason)
                    .font(.scaled(10, scale: scale))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle(L("Pomiń (jest w bibliotece)"), isOn: $isSkipped)
                .toggleStyle(.checkbox)
                .font(.scaled(10, scale: scale))
        }
        .padding(10)
        .background(Color.yellow.opacity(0.08))
        .cornerRadius(6)
    }
}
