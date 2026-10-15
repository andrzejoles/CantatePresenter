import Foundation
import SwiftUI
import AppKit

public struct ImportExportSheet: View {
    @ObservedObject var store = DataStore.shared
    @Binding var isPresented: Bool
    
    @State private var selectedTab: Int = 0 // 0: Eksport, 1: Import
    @State private var exportScope: Int = 0 // 0: Cała baza, 1: Wybrana pieśń
    @State private var exportFormat: Int = 0 // 0: JSON backup, 1: Folder z .txt
    @State private var statusMessage: String?
    @State private var isSuccessStatus: Bool = true
    
    @State private var pendingImportReport: ImportProcessingResult?
    @State private var isShowingGoogleDriveBackups: Bool = false
    @State private var isUploadingToDrive: Bool = false
    
    // Asynchronous background progress state
    @State private var isProcessingImport: Bool = false
    @State private var importProgressValue: Double = 0.0
    @State private var importProgressTitle: String = ""
    @State private var importProgressDetail: String = ""
    
    private let sampleMuflPath = "/Users/aoles/dev_gem/2026-10-14_16-19-00.mufl"
    
    /// Po otwarciu od razu pokazuje wybór plików do importu (pozycja menu Plik → Importuj pieśni, S3).
    private let startsImportOnAppear: Bool
    
    public init(isPresented: Binding<Bool>, startsImportOnAppear: Bool = false) {
        self._isPresented = isPresented
        self.startsImportOnAppear = startsImportOnAppear
        self._selectedTab = State(initialValue: startsImportOnAppear ? 1 : 0)
    }
    
    private var selectedSong: Song? {
        return store.selectedSong
    }
    
    private var hasSampleMuflFile: Bool {
        return FileManager.default.fileExists(atPath: sampleMuflPath)
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        Group {
            if isShowingGoogleDriveBackups {
                GoogleDriveBackupsSheet(isPresented: $isShowingGoogleDriveBackups)
                    .frame(minWidth: 700, minHeight: 520)
            } else if let report = pendingImportReport {
                ImportReviewSheet(
                    report: report,
                    onCommit: { songsToCommit in
                        store.addSongs(songsToCommit)
                        pendingImportReport = nil
                        isSuccessStatus = true
                        statusMessage = "Pomyślnie zaimportowano \(songsToCommit.count) pieśni do biblioteki! (Wzbogacono \(report.enrichmentRecords.count), pominięto \(report.duplicateRecords.count) duplikatów)"
                    },
                    onCancel: {
                        pendingImportReport = nil
                    }
                )
                .frame(minWidth: 800, minHeight: 600)
            } else {
                mainImportExportContent(scale: scale)
                    .frame(minWidth: 640, minHeight: 520)
            }
        }
        .onAppear {
            guard startsImportOnAppear else { return }
            // Panel wyboru dopiero po pokazaniu arkusza.
            DispatchQueue.main.async {
                pickAndProcessFiles(chooseDirectories: false)
            }
        }
    }
    
    @ViewBuilder
    private func mainImportExportContent(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import, Eksport i Kopia Zapasowa")
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
            
            // Tab Switcher
            Picker("", selection: $selectedTab) {
                Text("Eksport pieśni").tag(0)
                Text("Import pieśni").tag(1)
                Text("Pełny backup & Dysk Google").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(14)
            .disabled(isProcessingImport)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    if selectedTab == 0 {
                        // MARK: - EKSPORT
                        GroupBox(label: Label("Zakres eksportu", systemImage: "tray.and.arrow.up")) {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("", selection: $exportScope) {
                                    Text("Cała biblioteka pieśni (\(store.songs.count) utworów)").tag(0)
                                    if let song = selectedSong {
                                        Text("Tylko zaznaczona pieśń: '\(song.title)'").tag(1)
                                    }
                                }
                                .pickerStyle(RadioGroupPickerStyle())
                            }
                            .padding(8)
                        }
                        
                        GroupBox(label: Label("Format eksportu", systemImage: "doc.badge.gearshape")) {
                            VStack(alignment: .leading, spacing: 12) {
                                if exportScope == 0 {
                                    Picker("", selection: $exportFormat) {
                                        Text("Kopia zapasowa JSON (.json) — przeniesienie całej bazy").tag(0)
                                        Text("Folder z osobnymi plikami tekstowymi (.txt)").tag(1)
                                    }
                                    .pickerStyle(RadioGroupPickerStyle())
                                } else {
                                    Picker("", selection: $exportFormat) {
                                        Text("Plik tekstowy (.txt)").tag(0)
                                        Text("Plik JSON (.json)").tag(1)
                                    }
                                    .pickerStyle(RadioGroupPickerStyle())
                                }
                            }
                            .padding(8)
                        }
                        
                        HStack {
                            Spacer()
                            Button(action: performExport) {
                                Label("Eksportuj...", systemImage: "square.and.arrow.up")
                                    .font(.scaled(12, weight: .semibold, scale: scale))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        
                    } else if selectedTab == 1 {
                        // MARK: - IMPORT
                        
                        // Active Import Progress Card
                        if isProcessingImport {
                            VStack(spacing: 14) {
                                HStack(spacing: 12) {
                                    ProgressView()
                                        .controlSize(.regular)
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(importProgressTitle)
                                            .font(.scaled(13, weight: .bold, scale: scale))
                                            .foregroundColor(.purple)
                                        
                                        Text(importProgressDetail)
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                }
                                
                                ProgressView(value: importProgressValue, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                            }
                            .padding(16)
                            .background(Color.purple.opacity(0.08))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        // Highlighted Banner for sample .mufl file if available
                        if hasSampleMuflFile {
                            HStack(alignment: .center, spacing: 14) {
                                Image(systemName: "sparkles.rectangle.stack.fill")
                                    .font(.scaled(28, scale: scale))
                                    .foregroundColor(.purple)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Dostępna próbka bazy Holyrics (.mufl)")
                                        .font(.scaled(13, weight: .bold, scale: scale))
                                    Text("Plik: 2026-10-14_16-19-00.mufl (901 utworów). Aplikacja automatycznie przeszuka duplikaty i uzupełni brakujących autorów oraz tytuły.")
                                        .font(.scaled(11, scale: scale))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    importFromPath(sampleMuflPath)
                                }) {
                                    Label("Przeanalizuj i zaimportuj", systemImage: "arrow.down.circle.fill")
                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .disabled(isProcessingImport)
                            }
                            .padding(12)
                            .background(Color.purple.opacity(0.08))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                            )
                        }
                        
                        GroupBox(label: Label("Wybierz pliki do importu", systemImage: "tray.and.arrow.down")) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Aplikacja obsługuje pliki bazy Holyrics (.muf, .mufl, .hly), pliki tekstowe (.txt) z dowolnym kodowaniem, formaty XML (OpenLyrics / OpenSong), pliki JSON oraz archiwa ZIP.")
                                    .font(.scaled(11, scale: scale))
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button(action: {
                                        pickAndProcessFiles(chooseDirectories: false)
                                    }) {
                                        Label("Wybierz pliki (Holyrics .mufl, .txt, .json)...", systemImage: "doc.badge.plus")
                                            .font(.scaled(12, scale: scale))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isProcessingImport)
                                    
                                    Button(action: {
                                        pickAndProcessFiles(chooseDirectories: true)
                                    }) {
                                        Label("Wybierz cały folder...", systemImage: "folder.badge.plus")
                                            .font(.scaled(12, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isProcessingImport)
                                }
                            }
                            .padding(8)
                        }
                        
                        GroupBox(label: Label("Stan aktualnej biblioteki", systemImage: "chart.bar")) {
                            HStack(spacing: 30) {
                                VStack(alignment: .leading) {
                                    Text("\(store.songs.count)")
                                        .font(.scaled(22, weight: .bold, scale: scale))
                                    Text("Pieśni w bazie")
                                        .font(.scaled(11, scale: scale))
                                        .foregroundColor(.secondary)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("\(store.plans.count)")
                                        .font(.scaled(22, weight: .bold, scale: scale))
                                    Text("Zapisanych planów")
                                        .font(.scaled(11, scale: scale))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }
                    } else {
                        // MARK: - FULL BACKUP & GOOGLE DRIVE
                        GroupBox(label: Label("Lokalna kopia zapasowa (.cantatebackup)", systemImage: "archivebox.fill")) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pełna kopia zapasowa zabezpiecza wszystkie elementy aplikacji: bazę pieśni wraz z chwytami, plany nabożeństw, pełne ustawienia, ekran początkowy Standby, zainstalowane języki tłumaczeń oraz bibliotekę oficjalnych logotypów.")
                                    .font(.scaled(11, scale: scale))
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button(action: createLocalBackupAction) {
                                        Label("Utwórz pełną kopię zapasową (.cantatebackup)...", systemImage: "square.and.arrow.up.fill")
                                            .font(.scaled(11, weight: .semibold, scale: scale))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    
                                    Button(action: restoreLocalBackupAction) {
                                        Label("Przywróć z pliku kopii zapasowej...", systemImage: "arrow.counterclockwise.circle")
                                            .font(.scaled(11, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(8)
                        }
                        
                        GroupBox(label: Label("Kopia w chmurze Google Drive", systemImage: "externaldrive.badge.icloud")) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Integracja z kontem Dysku Google:")
                                            .font(.scaled(12, weight: .semibold, scale: scale))
                                        Text(store.settings.googleDrive.isEnabled ? "Włączona dla konta: \(store.settings.googleDrive.accountEmail.isEmpty ? "" : store.settings.googleDrive.accountEmail)" : "Wyłączona (możesz skonfigurować logowanie w Ustawieniach)")
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                
                                HStack(spacing: 12) {
                                    if isUploadingToDrive {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Przesyłanie kopii do chmury...")
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Button(action: uploadToGoogleDriveAction) {
                                            Label("Wyślij bieżący backup na Dysk Google", systemImage: "arrow.up.to.line.circle.fill")
                                                .font(.scaled(11, weight: .semibold, scale: scale))
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    
                                    Button(action: {
                                        isShowingGoogleDriveBackups = true
                                    }) {
                                        Label("Przeglądaj i przywróć kopie z Dysku Google...", systemImage: "clock.arrow.circlepath")
                                            .font(.scaled(11, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(8)
                        }
                    }
                    
                    // Status alert if present
                    if let msg = statusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: isSuccessStatus ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isSuccessStatus ? .green : .orange)
                            Text(msg)
                                .font(.scaled(12, weight: .medium, scale: scale))
                            Spacer()
                        }
                        .padding(10)
                        .background(isSuccessStatus ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(16)
            }
        }
    }
    
    private func performExport() {
        statusMessage = nil
        if exportScope == 0 {
            if exportFormat == 0 {
                let success = SongExporter.exportSongsAsJSONFile(store.songs)
                if success {
                    isSuccessStatus = true
                    statusMessage = "Pomyślnie wyeksportowano całą bazę (\(store.songs.count) pieśni) do pliku JSON."
                }
            } else {
                let count = SongExporter.exportSongsToFolder(store.songs)
                if count > 0 {
                    isSuccessStatus = true
                    statusMessage = "Pomyślnie wyeksportowano \(count) pieśni jako osobne pliki .txt."
                }
            }
        } else if let song = selectedSong {
            if exportFormat == 0 {
                let success = SongExporter.exportSongAsTextFile(song)
                if success {
                    isSuccessStatus = true
                    statusMessage = "Pomyślnie wyeksportowano pieśń '\(song.title)' jako plik .txt."
                }
            } else {
                let success = SongExporter.exportSongsAsJSONFile([song], defaultName: song.title)
                if success {
                    isSuccessStatus = true
                    statusMessage = "Pomyślnie wyeksportowano pieśń '\(song.title)' jako JSON."
                }
            }
        }
    }
    
    private func importFromPath(_ path: String) {
        statusMessage = nil
        isProcessingImport = true
        importProgressValue = 0.1
        importProgressTitle = "Wczytywanie bazy Holyrics (.mufl)..."
        importProgressDetail = "Odczyt i parsowanie bazy danych..."
        
        Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: path)
            
            await MainActor.run {
                self.importProgressValue = 0.35
                self.importProgressTitle = "Deserializacja rekordów Holyrics..."
                self.importProgressDetail = "Parsowanie obiektów pieśni..."
            }
            
            let existing = await MainActor.run { self.store.songs }
            
            await MainActor.run {
                self.importProgressValue = 0.65
                self.importProgressTitle = "Deduplikacja i wzbogacanie metadanych..."
                self.importProgressDetail = "Wykrywanie duplikatów, naprawa polskich znaków i dopasowywanie autorów..."
            }
            
            let (_, report) = HolyricsImporter.importFromURLWithReport(url, existingLibrary: existing)
            
            await MainActor.run {
                self.importProgressValue = 1.0
                self.isProcessingImport = false
                self.pendingImportReport = report
            }
        }
    }
    
    private func pickAndProcessFiles(chooseDirectories: Bool) {
        statusMessage = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = !chooseDirectories
        panel.canChooseDirectories = chooseDirectories
        panel.allowsMultipleSelection = true
        panel.allowedFileTypes = ["txt", "json", "muf", "mufl", "hly", "holyrics", "xml", "zip"]
        panel.prompt = "Wybierz do analizy"
        panel.message = "Wybierz pliki Holyrics (.mufl), pliki tekstowe lub archiwa"
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            
            isProcessingImport = true
            importProgressValue = 0.05
            importProgressTitle = "Wczytywanie wybranych plików..."
            importProgressDetail = "Przygotowywanie do analizy..."
            
            Task.detached(priority: .userInitiated) {
                var rawSongs: [Song] = []
                let totalFiles = urls.count
                
                for (idx, url) in urls.enumerated() {
                    let progress = 0.1 + (0.5 * Double(idx) / Double(totalFiles))
                    await MainActor.run {
                        self.importProgressValue = progress
                        self.importProgressTitle = "Wczytywanie pliku \(idx + 1) z \(totalFiles)..."
                        self.importProgressDetail = url.lastPathComponent
                    }
                    rawSongs.append(contentsOf: TextImporter.importFromURL(url))
                }
                
                guard !rawSongs.isEmpty else {
                    await MainActor.run {
                        self.isProcessingImport = false
                        self.isSuccessStatus = false
                        self.statusMessage = "Nie znaleziono żadnych pieśni w wybranych plikach."
                    }
                    return
                }
                
                let rawCount = rawSongs.count
                await MainActor.run {
                    self.importProgressValue = 0.75
                    self.importProgressTitle = "Deduplikacja i wzbogacanie (\(rawCount) pieśni)..."
                    self.importProgressDetail = "Porównywanie tekstów, wykrywanie duplikatów i uzupełnianie autorów..."
                }
                
                let existing = await MainActor.run { self.store.songs }
                let report = SongDeduplicationService.shared.processAndDeduplicate(incoming: rawSongs, existingLibrary: existing)
                
                await MainActor.run {
                    self.importProgressValue = 1.0
                    self.isProcessingImport = false
                    self.pendingImportReport = report
                }
            }
        }
    }
    
    // MARK: - Backup Actions
    
    private func createLocalBackupAction() {
        statusMessage = nil
        let success = BackupService.shared.exportBackupWithSavePanel()
        if success {
            isSuccessStatus = true
            statusMessage = "Pomyślnie utworzono i wyeksportowano pełną kopię zapasową (.cantatebackup)!"
        }
    }
    
    private func restoreLocalBackupAction() {
        statusMessage = nil
        Task {
            let res = await BackupService.shared.restoreBackupWithOpenPanel()
            isSuccessStatus = res.success
            statusMessage = res.message
        }
    }
    
    private func uploadToGoogleDriveAction() {
        statusMessage = nil
        isUploadingToDrive = true
        
        Task {
            do {
                let (archiveURL, _) = try BackupService.shared.createBackupArchive(comment: "Backup z okna Import/Eksport")
                let item = try await GoogleDriveService.shared.uploadBackupToDrive(archiveURL: archiveURL)
                try? FileManager.default.removeItem(at: archiveURL)
                
                await MainActor.run {
                    self.isUploadingToDrive = false
                    self.isSuccessStatus = true
                    self.statusMessage = "Pomyślnie przesłano kopię '\(item.name)' na Dysk Google (\(item.formattedSize))!"
                }
            } catch {
                await MainActor.run {
                    self.isUploadingToDrive = false
                    self.isSuccessStatus = false
                    self.statusMessage = "Błąd wysyłania na Dysk Google: \(error.localizedDescription)"
                }
            }
        }
    }
}
