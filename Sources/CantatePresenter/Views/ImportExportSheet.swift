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
    @State private var isShowingReviewSheet: Bool = false
    @State private var isShowingGoogleDriveBackups: Bool = false
    @State private var isUploadingToDrive: Bool = false
    
    private let sampleMuflPath = "/Users/aoles/dev_gem/2026-10-14_16-19-00.mufl"
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    private var selectedSong: Song? {
        return store.selectedSong
    }
    
    private var hasSampleMuflFile: Bool {
        return FileManager.default.fileExists(atPath: sampleMuflPath)
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
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
                                    
                                    Button(action: {
                                        pickAndProcessFiles(chooseDirectories: true)
                                    }) {
                                        Label("Wybierz cały folder...", systemImage: "folder.badge.plus")
                                            .font(.scaled(12, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
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
                                        Text(store.settings.googleDrive.isEnabled ? "Włączona dla konta: \(store.settings.googleDrive.accountEmail.isEmpty ? "andrzej.oles.tel@gmail.com" : store.settings.googleDrive.accountEmail)" : "Wyłączona (możesz skonfigurować logowanie w Ustawieniach)")
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
        .frame(minWidth: 580, minHeight: 480)
        .sheet(isPresented: $isShowingReviewSheet) {
            if let report = pendingImportReport {
                ImportReviewSheet(
                    report: report,
                    onCommit: { songsToCommit in
                        store.addSongs(songsToCommit)
                        isShowingReviewSheet = false
                        isSuccessStatus = true
                        statusMessage = "Pomyślnie zaimportowano \(songsToCommit.count) pieśni do biblioteki! (Wzbogacono \(report.enrichmentRecords.count), pominięto \(report.duplicateRecords.count) duplikatów)"
                    },
                    onCancel: {
                        isShowingReviewSheet = false
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingGoogleDriveBackups) {
            GoogleDriveBackupsSheet(isPresented: $isShowingGoogleDriveBackups)
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
        let url = URL(fileURLWithPath: path)
        let (_, report) = HolyricsImporter.importFromURLWithReport(url, existingLibrary: store.songs)
        self.pendingImportReport = report
        self.isShowingReviewSheet = true
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
            var rawSongs: [Song] = []
            for url in panel.urls {
                rawSongs.append(contentsOf: TextImporter.importFromURL(url))
            }
            guard !rawSongs.isEmpty else {
                isSuccessStatus = false
                statusMessage = "Nie znaleziono żadnych pieśni w wybranych plikach."
                return
            }
            
            // Deduplicate and enrich
            let report = SongDeduplicationService.shared.processAndDeduplicate(incoming: rawSongs, existingLibrary: store.songs)
            self.pendingImportReport = report
            self.isShowingReviewSheet = true
        }
    }
    
    // MARK: - Backup Actions
    
    private func createLocalBackupAction() {
        statusMessage = nil
        let success = BackupService.shared.exportBackupWithSavePanel()
        if success {
            isSuccessStatus = true
            statusMessage = "Pomyślnie utworzono i wyeksportowano pełną kopię zapasową (.holyricsbackup)!"
        }
    }
    
    private func restoreLocalBackupAction() {
        statusMessage = nil
        let res = BackupService.shared.restoreBackupWithOpenPanel()
        isSuccessStatus = res.success
        statusMessage = res.message
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
