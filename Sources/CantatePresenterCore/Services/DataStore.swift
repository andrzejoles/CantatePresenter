import Foundation
import Combine
import SwiftUI

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
    
    private let dataDirectory: URL
    private let songsFileURL: URL
    private let plansFileURL: URL
    private let settingsFileURL: URL
    
    public init() {
        // Data directory inside current working directory or bundle path
        let bundleURL = Bundle.main.bundleURL
        let projectFolder: URL
        if bundleURL.pathExtension == "app" {
            projectFolder = bundleURL.deletingLastPathComponent()
        } else {
            projectFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        let baseURL = projectFolder.appendingPathComponent("data")
        self.dataDirectory = baseURL
        self.songsFileURL = baseURL.appendingPathComponent("songs.json")
        self.plansFileURL = baseURL.appendingPathComponent("plans.json")
        self.settingsFileURL = baseURL.appendingPathComponent("settings.json")
        
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
        if FileManager.default.fileExists(atPath: songsFileURL.path),
           let data = try? Data(contentsOf: songsFileURL),
           let decoded = try? JSONDecoder().decode([Song].self, from: data) {
            self.songs = decoded
        } else {
            self.songs = SampleSongs.loadDefaults()
            saveSongs()
        }
        if selectedSongId == nil {
            selectedSongId = songs.first?.id
        }
    }
    
    public func saveSongs() {
        createDataDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(songs) {
            try? data.write(to: songsFileURL, options: .atomic)
        }
    }
    
    public func loadPlans() {
        if FileManager.default.fileExists(atPath: plansFileURL.path),
           let data = try? Data(contentsOf: plansFileURL),
           let decoded = try? JSONDecoder().decode([ServicePlan].self, from: data) {
            self.plans = decoded
        } else {
            // Default initial plan
            let initialPlan = ServicePlan(
                name: "Niedziela - Zestaw pieśni",
                items: songs.prefix(4).map { PlanItem(songId: $0.id) }
            )
            self.plans = [initialPlan]
            savePlans()
        }
        if activePlanId == nil {
            activePlanId = plans.first?.id
        }
    }
    
    public func savePlans() {
        createDataDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(plans) {
            try? data.write(to: plansFileURL, options: .atomic)
        }
    }
    
    public func loadSettings() {
        if FileManager.default.fileExists(atPath: settingsFileURL.path),
           let data = try? Data(contentsOf: settingsFileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
            saveSettings()
        }
    }
    
    public func saveSettings() {
        createDataDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(settings) {
            try? data.write(to: settingsFileURL, options: .atomic)
        }
    }
    
    // MARK: - Song Operations
    public func addSong(_ song: Song) {
        songs.insert(song, at: 0)
        selectedSongId = song.id
        saveSongs()
    }
    
    public func addSongs(_ newSongs: [Song]) {
        guard !newSongs.isEmpty else { return }
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
