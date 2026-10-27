import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ImportExportSheet: View {
    @Bindable var store = DataStore.shared
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
                        statusMessage = L("Pomyślnie zaimportowano {0} pieśni do biblioteki! (Wzbogacono {1}, pominięto {2} duplikatów)", songsToCommit.count, report.enrichmentRecords.count, report.duplicateRecords.count)
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
                Text(L("Import, Eksport i Kopia Zapasowa"))
                    .font(.scaled(16, weight: .bold, scale: scale))
                Spacer()
                Button(L("Zamknij")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Tab Switcher
            Picker("", selection: $selectedTab) {
                Text(L("Eksport pieśni")).tag(0)
                Text(L("Import pieśni")).tag(1)
                Text(L("Pełny backup & Dysk Google")).tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(14)
            .disabled(isProcessingImport)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    if selectedTab == 0 {
                        // MARK: - EKSPORT
                        GroupBox(label: Label(L("Zakres eksportu"), systemImage: "tray.and.arrow.up")) {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("", selection: $exportScope) {
                                    Text(L("Cała biblioteka pieśni ({0} utworów)", store.songs.count)).tag(0)
                                    if let song = selectedSong {
                                        Text(L("Tylko zaznaczona pieśń: '{0}'", song.title)).tag(1)
                                    }
                                }
                                .pickerStyle(RadioGroupPickerStyle())
                            }
                            .padding(8)
                        }
                        
                        GroupBox(label: Label(L("Format eksportu"), systemImage: "doc.badge.gearshape")) {
                            VStack(alignment: .leading, spacing: 12) {
                                if exportScope == 0 {
                                    Picker("", selection: $exportFormat) {
                                        Text(L("Kopia zapasowa JSON (.json) — przeniesienie całej bazy")).tag(0)
                                        Text(L("Folder z osobnymi plikami tekstowymi (.txt)")).tag(1)
                                    }
                                    .pickerStyle(RadioGroupPickerStyle())
                                } else {
                                    Picker("", selection: $exportFormat) {
                                        Text(L("Plik tekstowy (.txt)")).tag(0)
                                        Text(L("Plik JSON (.json)")).tag(1)
                                    }
                                    .pickerStyle(RadioGroupPickerStyle())
                                }
                            }
                            .padding(8)
                        }
                        
                        HStack {
                            Spacer()
                            Button(action: performExport) {
                                Label(L("Eksportuj..."), systemImage: "square.and.arrow.up")
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
                        
                        
                        GroupBox(label: Label(L("Wybierz pliki do importu"), systemImage: "tray.and.arrow.down")) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(L("Aplikacja obsługuje pliki bazy Holyrics (.muf, .mufl, .hly), pliki tekstowe (.txt) z dowolnym kodowaniem, formaty XML (OpenLyrics / OpenSong), pliki JSON, archiwa ZIP oraz pliki pobrane z CCLI SongSelect (.txt, .usr, ChordPro .pro)."))
                                    .font(.scaled(11, scale: scale))
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button(action: {
                                        pickAndProcessFiles(chooseDirectories: false)
                                    }) {
                                        Label(L("Wybierz pliki (Holyrics .mufl, .txt, .json)..."), systemImage: "doc.badge.plus")
                                            .font(.scaled(12, scale: scale))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isProcessingImport)
                                    
                                    Button(action: {
                                        pickAndProcessFiles(chooseDirectories: true)
                                    }) {
                                        Label(L("Wybierz cały folder..."), systemImage: "folder.badge.plus")
                                            .font(.scaled(12, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isProcessingImport)
                                }
                            }
                            .padding(8)
                        }
                        
                        GroupBox(label: Label(L("Stan aktualnej biblioteki"), systemImage: "chart.bar")) {
                            HStack(spacing: 30) {
                                VStack(alignment: .leading) {
                                    Text("\(store.songs.count)")
                                        .font(.scaled(22, weight: .bold, scale: scale))
                                    Text(L("Pieśni w bazie"))
                                        .font(.scaled(11, scale: scale))
                                        .foregroundColor(.secondary)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("\(store.plans.count)")
                                        .font(.scaled(22, weight: .bold, scale: scale))
                                    Text(L("Zapisanych planów"))
                                        .font(.scaled(11, scale: scale))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }
                    } else {
                        // MARK: - FULL BACKUP & GOOGLE DRIVE
                        GroupBox(label: Label(L("Lokalna kopia zapasowa (.cantatebackup)"), systemImage: "archivebox.fill")) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L("Pełna kopia zapasowa zawiera bazę pieśni wraz z chwytami, plany nabożeństw, ustawienia, własne języki tłumaczeń i raport CCLI. Logo są wbudowane w program. Własnego pliku planszy startowej wybranego w Ustawieniach kopia nie zawiera."))
                                    .font(.scaled(11, scale: scale))
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button(action: createLocalBackupAction) {
                                        Label(L("Utwórz pełną kopię zapasową (.cantatebackup)..."), systemImage: "square.and.arrow.up.fill")
                                            .font(.scaled(11, weight: .semibold, scale: scale))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    
                                    Button(action: restoreLocalBackupAction) {
                                        Label(L("Przywróć z pliku kopii zapasowej..."), systemImage: "arrow.counterclockwise.circle")
                                            .font(.scaled(11, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(8)
                        }
                        
                        GroupBox(label: Label(L("Kopia w chmurze Google Drive"), systemImage: "externaldrive.badge.icloud")) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(L("Integracja z kontem Dysku Google:"))
                                            .font(.scaled(12, weight: .semibold, scale: scale))
                                        Text(store.settings.googleDrive.isEnabled ? L("Włączona dla konta: {0}", store.settings.googleDrive.accountEmail.isEmpty ? L("nie połączono") : store.settings.googleDrive.accountEmail) : L("Wyłączona (możesz skonfigurować logowanie w Ustawieniach)"))
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                
                                HStack(spacing: 12) {
                                    if isUploadingToDrive {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(L("Przesyłanie kopii do chmury..."))
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Button(action: uploadToGoogleDriveAction) {
                                            Label(L("Wyślij bieżący backup na Dysk Google"), systemImage: "arrow.up.to.line.circle.fill")
                                                .font(.scaled(11, weight: .semibold, scale: scale))
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    
                                    Button(action: {
                                        isShowingGoogleDriveBackups = true
                                    }) {
                                        Label(L("Przeglądaj i przywróć kopie z Dysku Google..."), systemImage: "clock.arrow.circlepath")
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
                    statusMessage = L("Pomyślnie wyeksportowano całą bazę ({0} pieśni) do pliku JSON.", store.songs.count)
                }
            } else {
                let count = SongExporter.exportSongsToFolder(store.songs)
                if count > 0 {
                    isSuccessStatus = true
                    statusMessage = L("Pomyślnie wyeksportowano {0} pieśni jako osobne pliki .txt.", count)
                }
            }
        } else if let song = selectedSong {
            if exportFormat == 0 {
                let success = SongExporter.exportSongAsTextFile(song)
                if success {
                    isSuccessStatus = true
                    statusMessage = L("Pomyślnie wyeksportowano pieśń '{0}' jako plik .txt.", song.title)
                }
            } else {
                let success = SongExporter.exportSongsAsJSONFile([song], defaultName: song.title)
                if success {
                    isSuccessStatus = true
                    statusMessage = L("Pomyślnie wyeksportowano pieśń '{0}' jako JSON.", song.title)
                }
            }
        }
    }
    
    private func pickAndProcessFiles(chooseDirectories: Bool) {
        statusMessage = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = !chooseDirectories
        panel.canChooseDirectories = chooseDirectories
        panel.allowsMultipleSelection = true
        // allowedContentTypes zamiast przestarzałego allowedFileTypes (N6); .mufl itp. jako typy z rozszerzenia.
        panel.allowedContentTypes = TextImporter.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = L("Wybierz do analizy")
        panel.message = L("Wybierz pliki Holyrics (.mufl), pliki tekstowe lub archiwa")
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            
            isProcessingImport = true
            importProgressValue = 0.05
            importProgressTitle = L("Wczytywanie wybranych plików...")
            importProgressDetail = L("Przygotowywanie do analizy...")
            
            Task.detached(priority: .userInitiated) {
                var rawSongs: [Song] = []
                var problems: [ImportProblem] = []
                let totalFiles = urls.count
                
                for (idx, url) in urls.enumerated() {
                    let progress = 0.1 + (0.5 * Double(idx) / Double(totalFiles))
                    await MainActor.run {
                        self.importProgressValue = progress
                        self.importProgressTitle = L("Wczytywanie pliku {0} z {1}...", idx + 1, totalFiles)
                        self.importProgressDetail = url.lastPathComponent
                    }
                    let outcome = TextImporter.importFile(url)
                    rawSongs.append(contentsOf: outcome.songs)
                    problems.append(contentsOf: outcome.problems)
                }
                
                guard !rawSongs.isEmpty else {
                    let details = problems.prefix(3).map { "\($0.fileName): \($0.message)" }.joined(separator: "\n")
                    await MainActor.run {
                        self.isProcessingImport = false
                        self.isSuccessStatus = false
                        self.statusMessage = details.isEmpty
                            ? L("Nie znaleziono żadnych pieśni w wybranych plikach.")
                            : L("Nie znaleziono żadnych pieśni w wybranych plikach.") + "\n" + details
                    }
                    return
                }
                
                let rawCount = rawSongs.count
                await MainActor.run {
                    self.importProgressValue = 0.75
                    self.importProgressTitle = L("Deduplikacja i wzbogacanie ({0} pieśni)...", rawCount)
                    self.importProgressDetail = L("Porównywanie tekstów, wykrywanie duplikatów i uzupełnianie autorów...")
                }
                
                let existing = await MainActor.run { self.store.songs }
                var report = SongDeduplicationService.shared.processAndDeduplicate(incoming: rawSongs, existingLibrary: existing)
                report.fileProblems = problems
                
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
        Task {
            if await BackupService.shared.exportBackupWithSavePanel() {
                isSuccessStatus = true
                statusMessage = L("Pomyślnie utworzono i wyeksportowano pełną kopię zapasową (.cantatebackup)!")
            }
        }
    }
    
    private func restoreLocalBackupAction() {
        statusMessage = nil
        Task {
            let outcome = await BackupService.shared.restoreBackupWithOpenPanel()
            isSuccessStatus = outcome.isSuccess
            statusMessage = outcome.message
        }
    }
    
    private func uploadToGoogleDriveAction() {
        statusMessage = nil
        isUploadingToDrive = true
        
        Task {
            do {
                let (archiveURL, _) = try await BackupService.shared.createBackupArchive(comment: "Backup z okna Import/Eksport")
                defer { BackupService.removeTemporaryArchive(archiveURL) }
                let item = try await GoogleDriveService.shared.uploadBackupToDrive(archiveURL: archiveURL)
                
                await MainActor.run {
                    self.isUploadingToDrive = false
                    self.isSuccessStatus = true
                    self.statusMessage = L("Pomyślnie przesłano kopię '{0}' na Dysk Google ({1})!", item.name, item.formattedSize)
                }
            } catch {
                await MainActor.run {
                    self.isUploadingToDrive = false
                    self.isSuccessStatus = false
                    self.statusMessage = L("Błąd wysyłania na Dysk Google: {0}", error.localizedDescription)
                }
            }
        }
    }
}
