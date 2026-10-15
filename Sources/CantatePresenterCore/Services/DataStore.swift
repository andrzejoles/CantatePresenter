import Foundation
import Combine
import SwiftUI
import os

// MARK: - Persistence Issue

/// Problem z plikiem danych pokazywany użytkownikowi w oknie głównym (K1).
public struct PersistenceIssue: Identifiable, Equatable {
    public enum Kind: Equatable {
        /// Pliku nie da się odczytać; zapis do niego jest zablokowany do czasu udanego wczytania.
        case unreadable
        case saveFailed
        /// Nie udało się przenieść danych do Application Support (K2); `fileName` to stary katalog.
        case migrationFailed
    }
    
    public let id = UUID()
    public let kind: Kind
    public let fileName: String
    public let quarantinedCopy: URL?
    public let errorDescription: String
    
    public var title: String {
        switch kind {
        case .unreadable: return "Nie można odczytać pliku \(fileName)"
        case .saveFailed: return "Nie można zapisać pliku \(fileName)"
        case .migrationFailed: return "Nie udało się przenieść danych"
        }
    }
    
    public var message: String {
        switch kind {
        case .unreadable:
            let copy = quarantinedCopy.map { "Kopia pliku: \($0.lastPathComponent).\n\n" } ?? ""
            return "Plik jest uszkodzony albo ma nieznany format. Aplikacja go nie nadpisze: zmiany w tej części danych nie będą zapisywane do czasu przywrócenia kopii lub ponownego uruchomienia.\n\n\(copy)Szczegóły: \(errorDescription)"
        case .saveFailed:
            return "Ostatnie zmiany mogą nie zostać zachowane.\n\nSzczegóły: \(errorDescription)"
        case .migrationFailed:
            return "Biblioteka nie została skopiowana do folderu Application Support. W tej sesji aplikacja używa dotychczasowego katalogu:\n\(fileName)\n\nSzczegóły: \(errorDescription)"
        }
    }
}

@MainActor
public final class DataStore: ObservableObject {
    public static let shared = DataStore()
    
    @Published public var songs: [Song] = []
    @Published public var plans: [ServicePlan] = []
    @Published public var activePlanId: UUID?
    @Published public var selectedSongId: UUID?
    
    // Live Presentation State
    @Published public var activeSong: Song?
    @Published public var activeSlideIndex: Int = 0
    @Published public var isLive: Bool = false
    @Published public var isBlackScreen: Bool = false
    @Published public var isClearText: Bool = false
    
    @Published public var settings: AppSettings = AppSettings()
    @Published public var temporarySong: Song?
    
    /// Problemy z odczytem lub zapisem plików danych do pokazania użytkownikowi.
    @Published public private(set) var persistenceIssues: [PersistenceIssue] = []
    
    private let fileStore = JSONFileStore()
    /// Pliki, których nie udało się odczytać; zapis do nich jest wstrzymany, żeby ich nie nadpisać.
    private var lockedFileNames: Set<String> = []
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "persistence")
    
    private let dataDirectory: URL
    private let songsFileURL: URL
    private let plansFileURL: URL
    private let settingsFileURL: URL
    
    public convenience init() {
        self.init(paths: AppPaths.shared)
    }
    
    convenience init(dataDirectory: URL) {
        self.init(paths: AppPaths(dataDirectory: dataDirectory))
    }
    
    init(paths: AppPaths) {
        self.dataDirectory = paths.dataDirectory
        self.songsFileURL = paths.songsFile
        self.plansFileURL = paths.plansFile
        self.settingsFileURL = paths.settingsFile
        
        if case .failed(let legacy, let error) = paths.migration {
            persistenceIssues.append(PersistenceIssue(
                kind: .migrationFailed,
                fileName: legacy.path,
                quarantinedCopy: nil,
                errorDescription: error
            ))
        }
        
        createDataDirectoryIfNeeded()
        loadSettings()
        loadSongs()
        loadPlans()
    }
    
    private func createDataDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: dataDirectory.path) {
            try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Active Plan Helper
    public var activePlan: ServicePlan? {
        get {
            guard let id = activePlanId else { return plans.first }
            return plans.first(where: { $0.id == id }) ?? plans.first
        }
        set {
            if let newValue = newValue {
                if let idx = plans.firstIndex(where: { $0.id == newValue.id }) {
                    plans[idx] = newValue
                } else {
                    plans.append(newValue)
                }
                activePlanId = newValue.id
                savePlans()
            }
        }
    }
    
    public var selectedSong: Song? {
        if let temp = temporarySong, temp.id == selectedSongId {
            return temp
        }
        guard let id = selectedSongId else { return songs.first }
        return songs.first(where: { $0.id == id })
    }
    
    // MARK: - Current Live Slide
    public var currentLiveSlide: SongSlide? {
        guard let song = activeSong, !song.slides.isEmpty else { return nil }
        guard activeSlideIndex >= 0 && activeSlideIndex < song.slides.count else { return nil }
        return song.slides[activeSlideIndex]
    }
    
    // MARK: - Persistence
    public func loadSongs() {
        switch fileStore.load([Song].self, from: songsFileURL) {
        case .missing:
            unlock(songsFileURL)
            self.songs = SampleSongs.loadDefaults()
            saveSongs()
        case .loaded(let decoded):
            unlock(songsFileURL)
            self.songs = decoded
        case .unreadable(let error, let copy):
            lock(songsFileURL, error: error, quarantinedCopy: copy)
            self.songs = []
        }
        if selectedSongId == nil {
            selectedSongId = songs.first?.id
        }
    }
    
    public func saveSongs() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        persist(songs, to: songsFileURL, encoder: encoder)
    }
    
    public func loadPlans() {
        switch fileStore.load([ServicePlan].self, from: plansFileURL) {
        case .missing:
            unlock(plansFileURL)
            // Default initial plan
            let initialPlan = ServicePlan(
                name: "Niedziela - Zestaw pieśni",
                items: songs.prefix(4).map { PlanItem(songId: $0.id) }
            )
            self.plans = [initialPlan]
            savePlans()
        case .loaded(let decoded):
            unlock(plansFileURL)
            self.plans = decoded
        case .unreadable(let error, let copy):
            lock(plansFileURL, error: error, quarantinedCopy: copy)
            self.plans = []
        }
        if activePlanId == nil {
            activePlanId = plans.first?.id
        }
    }
    
    public func savePlans() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        persist(plans, to: plansFileURL, encoder: encoder)
    }
    
    public func loadSettings() {
        switch fileStore.load(AppSettings.self, from: settingsFileURL) {
        case .missing:
            unlock(settingsFileURL)
            self.settings = AppSettings()
            saveSettings()
        case .loaded(let decoded):
            unlock(settingsFileURL)
            self.settings = decoded
        case .unreadable(let error, let copy):
            lock(settingsFileURL, error: error, quarantinedCopy: copy)
            self.settings = AppSettings()
        }
    }
    
    public func saveSettings() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        persist(settings, to: settingsFileURL, encoder: encoder)
    }
    
    public func dismissPersistenceIssue(_ issue: PersistenceIssue) {
        persistenceIssues.removeAll { $0.id == issue.id }
    }
    
    private func persist<Value: Encodable>(_ value: Value, to url: URL, encoder: JSONEncoder) {
        let fileName = url.lastPathComponent
        guard !lockedFileNames.contains(fileName) else {
            Self.logger.warning("Pominięto zapis \(fileName, privacy: .public): plik był nieczytelny przy wczytywaniu")
            return
        }
        do {
            try fileStore.save(value, to: url, encoder: encoder)
            persistenceIssues.removeAll { $0.kind == .saveFailed && $0.fileName == fileName }
        } catch {
            Self.logger.error("Błąd zapisu \(fileName, privacy: .public): \(String(describing: error), privacy: .public)")
            // Jedno powiadomienie na plik, nie przy każdym kolejnym zapisie.
            if !persistenceIssues.contains(where: { $0.kind == .saveFailed && $0.fileName == fileName }) {
                persistenceIssues.append(PersistenceIssue(
                    kind: .saveFailed,
                    fileName: fileName,
                    quarantinedCopy: nil,
                    errorDescription: error.localizedDescription
                ))
            }
        }
    }
    
    private func lock(_ url: URL, error: Error, quarantinedCopy: URL?) {
        let fileName = url.lastPathComponent
        lockedFileNames.insert(fileName)
        persistenceIssues.removeAll { $0.fileName == fileName }
        persistenceIssues.append(PersistenceIssue(
            kind: .unreadable,
            fileName: fileName,
            quarantinedCopy: quarantinedCopy,
            errorDescription: String(describing: error)
        ))
    }
    
    private func unlock(_ url: URL) {
        let fileName = url.lastPathComponent
        lockedFileNames.remove(fileName)
        persistenceIssues.removeAll { $0.kind == .unreadable && $0.fileName == fileName }
    }
    
    // MARK: - Song Operations
    public func addSong(_ song: Song) {
        let song = Song.assigningUniqueIdentifiers([song], existing: Set(songs.map(\.id)))[0]
        songs.insert(song, at: 0)
        selectedSongId = song.id
        saveSongs()
    }
    
    public func addSongs(_ newSongs: [Song]) {
        guard !newSongs.isEmpty else { return }
        let newSongs = Song.assigningUniqueIdentifiers(newSongs, existing: Set(songs.map(\.id)))
        songs.append(contentsOf: newSongs)
        if selectedSongId == nil {
            selectedSongId = newSongs.first?.id
        }
        saveSongs()
    }
    
    public func updateSong(_ song: Song) {
        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
            var updated = song
            updated.updatedAt = Date()
            songs[idx] = updated
            if activeSong?.id == song.id {
                activeSong = updated
                if activeSlideIndex >= updated.slides.count {
                    activeSlideIndex = max(0, updated.slides.count - 1)
                }
            }
            saveSongs()
        }
    }
    
    public func deleteSong(id: UUID) {
        songs.removeAll(where: { $0.id == id })
        if selectedSongId == id {
            selectedSongId = songs.first?.id
        }
        if activeSong?.id == id {
            stopLive()
        }
        // Remove from all plans
        for i in 0..<plans.count {
            plans[i].items.removeAll(where: { $0.songId == id })
        }
        saveSongs()
        savePlans()
    }
    
    // MARK: - Plan Operations
    public func createPlan(name: String) -> ServicePlan {
        let plan = ServicePlan(name: name, items: [])
        plans.append(plan)
        activePlanId = plan.id
        savePlans()
        return plan
    }
    
    public func deletePlan(id: UUID) {
        plans.removeAll(where: { $0.id == id })
        if activePlanId == id {
            activePlanId = plans.first?.id
        }
        savePlans()
    }
    
    public func addSongToPlan(songId: UUID, planId: UUID? = nil) {
        let targetId = planId ?? activePlanId
        guard let targetId = targetId,
              let idx = plans.firstIndex(where: { $0.id == targetId }) else { return }
        
        let newItem = PlanItem(songId: songId)
        plans[idx].items.append(newItem)
        plans[idx].updatedAt = Date()
        savePlans()
    }
    
    public func removePlanItem(id: UUID, in planId: UUID) {
        guard let idx = plans.firstIndex(where: { $0.id == planId }) else { return }
        plans[idx].items.removeAll(where: { $0.id == id })
        plans[idx].updatedAt = Date()
        savePlans()
    }
    
    public func movePlanItem(from source: IndexSet, to destination: Int, in planId: UUID) {
        guard let idx = plans.firstIndex(where: { $0.id == planId }) else { return }
        plans[idx].items.move(fromOffsets: source, toOffset: destination)
        plans[idx].updatedAt = Date()
        savePlans()
    }
    
    // MARK: - Presentation Navigation & Controls
    public func present(song: Song, slideIndex: Int = 0) {
        self.activeSong = song
        self.activeSlideIndex = min(max(0, slideIndex), max(0, song.slides.count - 1))
        self.isLive = true
        self.isBlackScreen = false
        self.isClearText = false
    }
    
    /// Presents ad-hoc text or announcement on screen immediately without saving it to the database
    public func presentQuickText(text: String, title: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let customTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let songTitle = customTitle.isEmpty ? "Szybki tekst" : customTitle
        
        let quickSong = Song(
            id: UUID(),
            title: songTitle,
            author: "Tymczasowy",
            key: "",
            tags: ["Szybki tekst"],
            rawLyrics: trimmed
        )
        
        self.temporarySong = quickSong
        self.selectedSongId = quickSong.id
        self.present(song: quickSong, slideIndex: 0)
    }
    
    public func nextSlide() {
        guard let song = activeSong else { return }
        if activeSlideIndex < song.slides.count - 1 {
            activeSlideIndex += 1
            isClearText = false
            isBlackScreen = false
        } else {
            // Check if we can transition to next song in active plan
            nextSongInPlan()
        }
    }
    
    public func prevSlide() {
        guard let _ = activeSong else { return }
        if activeSlideIndex > 0 {
            activeSlideIndex -= 1
            isClearText = false
            isBlackScreen = false
        }
    }
    
    public func jumpToSlide(index: Int) {
        guard let song = activeSong else { return }
        if index >= 0 && index < song.slides.count {
            activeSlideIndex = index
            isClearText = false
            isBlackScreen = false
        }
    }
    
    public func jumpToVerse(number: Int) {
        guard let song = activeSong else { return }
        let targetLabel = "Zwrotka \(number)"
        if let idx = song.slides.firstIndex(where: { $0.label.lowercased().contains(targetLabel.lowercased()) }) {
            jumpToSlide(index: idx)
        } else if number - 1 < song.slides.count {
            jumpToSlide(index: number - 1)
        }
    }
    
    public func jumpToChorus() {
        guard let song = activeSong else { return }
        if let idx = song.slides.firstIndex(where: { $0.type == .chorus }) {
            jumpToSlide(index: idx)
        }
    }
    
    public func toggleBlackScreen() {
        isBlackScreen.toggle()
    }
    
    public func toggleClearText() {
        isClearText.toggle()
    }
    
    public func stopLive() {
        isLive = false
        isBlackScreen = false
        isClearText = false
    }
    
    public func nextSongInPlan() {
        guard let plan = activePlan, !plan.items.isEmpty else { return }
        guard let currentSong = activeSong,
              let currentIndex = plan.items.firstIndex(where: { $0.songId == currentSong.id }) else {
            if let firstId = plan.items.first?.songId,
               let song = songs.first(where: { $0.id == firstId }) {
                present(song: song, slideIndex: 0)
            }
            return
        }
        
        let nextIndex = currentIndex + 1
        if nextIndex < plan.items.count {
            let nextId = plan.items[nextIndex].songId
            if let nextSong = songs.first(where: { $0.id == nextId }) {
                present(song: nextSong, slideIndex: 0)
                selectedSongId = nextSong.id
            }
        }
    }
    
    public func prevSongInPlan() {
        guard let plan = activePlan, !plan.items.isEmpty else { return }
        guard let currentSong = activeSong,
              let currentIndex = plan.items.firstIndex(where: { $0.songId == currentSong.id }) else { return }
        
        let prevIndex = currentIndex - 1
        if prevIndex >= 0 {
            let prevId = plan.items[prevIndex].songId
            if let prevSong = songs.first(where: { $0.id == prevId }) {
                present(song: prevSong, slideIndex: 0)
                selectedSongId = prevSong.id
            }
        }
    }
    
    // MARK: - UI Zoom Scaling (Keyboard & Button actions)
    public func zoomInUI() {
        settings.uiScale = min(1.6, settings.uiScale + 0.1)
        saveSettings()
    }
    
    public func zoomOutUI() {
        settings.uiScale = max(0.8, settings.uiScale - 0.1)
        saveSettings()
    }
    
    public func resetZoomUI() {
        settings.uiScale = 1.0
        saveSettings()
    }
    
    // MARK: - Logo Customization
    public func updateActiveLogo(id: String) {
        settings.activeLogoId = id
        saveSettings()
        
        let standbyURL = dataDirectory.appendingPathComponent("standby.html")
        if FileManager.default.fileExists(atPath: standbyURL.path),
           var content = try? String(contentsOf: standbyURL, encoding: .utf8) {
            let logoPreset = LogoCatalog.getById(id)
            let regexPattern = "(<div class=\"logo-wrapper\">)[\\s\\S]*?(</div>)"
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
                let range = NSRange(location: 0, length: (content as NSString).length)
                // Escape $ in svg content if any
                let safeSvg = logoPreset.svgContent.replacingOccurrences(of: "$", with: "\\$")
                let replacement = "$1\n            " + safeSvg + "\n        $2"
                content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: replacement)
                try? content.write(to: standbyURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
