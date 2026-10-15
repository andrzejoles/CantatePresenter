import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SettingsSheet: View {
    @ObservedObject var store = DataStore.shared
    @Binding var isPresented: Bool
    
    @State private var availableFonts: [String] = []
    @State private var testDictationText: String = ""
    @State private var isShowingLogoGallery: Bool = false
    @State private var translationNotice: String? = nil
    @State private var isShowingGoogleDriveBackups: Bool = false
    @State private var isUploadingToDrive: Bool = false
    @State private var isAuthorizingDrive: Bool = false
    @State private var driveAuthCodeInput: String = ""
    @State private var backupStatusMessage: String? = nil
    @State private var isBackupSuccess: Bool = true
    @State private var showDriveCredentials: Bool = false
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Ustawienia prezentacji i wyglądu")
                    .font(.scaled(16, weight: .bold, scale: scale))
                Spacer()
                Button("Gotowe") {
                    store.saveSettings()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // MARK: - Languages & Voice Dictation
                    GroupBox(label: Label("Języki i dyktowanie głosowe", systemImage: "waveform.and.mic")) {
                        VStack(alignment: .leading, spacing: 14) {
                            // App Language
                            HStack {
                                Text("Język aplikacji:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 170, alignment: .leading)
                                
                                Picker("", selection: $store.settings.appLanguage) {
                                    ForEach(LanguagePresets.appLanguages) { lang in
                                        Text("\(lang.flag)  \(lang.name)").tag(lang.code)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 200)
                                
                                Spacer()
                            }
                            
                            // Translation Export & Import Buttons
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Button(action: exportTranslationTemplate) {
                                        Label("Eksportuj słownik do tłumaczenia (JSON dla AI)...", systemImage: "square.and.arrow.up")
                                            .font(.scaled(11, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Eksportuje plik JSON ze wszystkimi tekstami programu i opisami kontekstu dla narzędzi AI")
                                    
                                    Button(action: importTranslationJSON) {
                                        Label("Importuj plik tłumaczenia (JSON)...", systemImage: "square.and.arrow.down")
                                            .font(.scaled(11, weight: .medium, scale: scale))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .help("Wczytaj przetłumaczony plik języka JSON i dodaj do listy języków interfejsu")
                                }
                                
                                if let notice = translationNotice {
                                    HStack(spacing: 6) {
                                        Image(systemName: notice.contains("Błąd") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                            .foregroundColor(notice.contains("Błąd") ? .red : .green)
                                        Text(notice)
                                            .font(.scaled(11, weight: .medium, scale: scale))
                                            .foregroundColor(notice.contains("Błąd") ? .red : .green)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background((notice.contains("Błąd") ? Color.red : Color.green).opacity(0.12))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.leading, 170)
                            
                            // Search Language
                            HStack {
                                Text("Język wyszukiwania pieśni:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 170, alignment: .leading)
                                
                                Picker("", selection: $store.settings.onlineSearchLanguage) {
                                    ForEach(LanguagePresets.searchLanguages) { lang in
                                        Text("\(lang.flag)  \(lang.name)").tag(lang.code)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 260)
                                
                                Spacer()
                            }
                            
                            // Dictation Language
                            HStack {
                                Text("Język dyktowania głosem:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 170, alignment: .leading)
                                
                                Picker("", selection: $store.settings.dictationLanguage) {
                                    ForEach(LanguagePresets.dictationLanguages) { lang in
                                        Text("\(lang.flag)  \(lang.name)").tag(lang.code)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 260)
                                
                                Spacer()
                            }
                            
                            Divider()
                            
                            // Dictation Test Box
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Przetestuj dyktowanie mikrofonem:")
                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    DictationButtonView(text: $testDictationText, mode: .append(separator: " "), size: 12)
                                }
                                
                                HStack {
                                    TextField("Kliknij mikrofon obok i powiedz kilka słów...", text: $testDictationText)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.scaled(11, scale: scale))
                                    
                                    if !testDictationText.isEmpty {
                                        Button("Wyczyść") {
                                            testDictationText = ""
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                                
                                Text("Dyktowanie działa bezpośrednio w wyszukiwarkach (biblioteka, online, autor/tytuł) oraz w edytorze nowej pieśni (tytuł, autor i treść zwrotek).")
                                    .font(.scaled(10, scale: scale))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                            .cornerRadius(6)
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Standby Screen (Plansza startowa HTML) & Wybór Logo
                    GroupBox(label: Label("Plansza startowa i Logo aplikacji", systemImage: "sparkles.tv")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gdy prezentacja pieśni nie jest aktywna, na ekranie projektora wyświetlana jest plansza powitalna HTML z wybranym logo programu.")
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                            
                            // Active Logo Row with quick gallery opener
                            HStack(spacing: 12) {
                                let activeLogo = LogoCatalog.getById(store.settings.activeLogoId)
                                
                                SVGThumbnailView(svgString: activeLogo.svgContent)
                                    .frame(width: 50, height: 50)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Aktywne logo:")
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                        Text(activeLogo.name)
                                            .font(.scaled(12, weight: .bold, scale: scale))
                                    }
                                    Text(activeLogo.subtitle)
                                        .font(.scaled(10, scale: scale))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    isShowingLogoGallery = true
                                }) {
                                    Label("Wybierz inne logo (\(LogoCatalog.all.count) propozycje)...", systemImage: "square.grid.2x2")
                                        .font(.scaled(11, weight: .medium, scale: scale))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(8)
                            
                            Divider()
                            
                            HStack {
                                Text("Własny plik HTML:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 120, alignment: .leading)
                                
                                TextField("Domyślna plansza (Holyrics Mac v1.0.0)", text: $store.settings.standbyHtmlPath)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.scaled(11, scale: scale))
                                
                                Button("Wybierz plik...") {
                                    pickHtmlFile()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                if !store.settings.standbyHtmlPath.isEmpty {
                                    Button("Domyślna") {
                                        store.settings.standbyHtmlPath = ""
                                        store.saveSettings()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            HStack {
                                Spacer()
                                Button("Otwórz plik planszy w edytorze / przeglądarce") {
                                    openStandbyHtmlFile()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.blue)
                                .font(.scaled(11, scale: scale))
                            }
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Backup & Google Drive
                    GroupBox(label: Label("Kopia zapasowa i Dysk Google", systemImage: "externaldrive.badge.icloud")) {
                        VStack(alignment: .leading, spacing: 14) {
                            // Summary info
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.scaled(20, scale: scale))
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Kompletna ochrona danych aplikacji")
                                        .font(.scaled(12, weight: .bold, scale: scale))
                                    Text("Kopia zapasowa (.holyricsbackup) zawiera: całą bazę pieśni (\(store.songs.count)), plany nabożeństw (\(store.plans.count)), chwyty gitarowe, wszystkie ustawienia programu, stronę początkową Standby, języki tłumaczeń oraz oficjalne loga.")
                                        .font(.scaled(11, scale: scale))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.08))
                            .cornerRadius(8)
                            
                            // Local Backup Buttons
                            HStack(spacing: 10) {
                                Button(action: createLocalBackupAction) {
                                    Label("Utwórz pełną kopię zapasową (.holyricsbackup)...", systemImage: "square.and.arrow.up.fill")
                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Button(action: restoreLocalBackupAction) {
                                    Label("Przywróć z pliku kopii zapasowej...", systemImage: "arrow.counterclockwise.circle")
                                        .font(.scaled(11, scale: scale))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Divider()
                            
                            // Google Drive Integration Section
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Toggle(isOn: $store.settings.googleDrive.isEnabled) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "icloud.and.arrow.up")
                                                .foregroundColor(store.settings.googleDrive.isEnabled ? .blue : .secondary)
                                            Text("Synchronizacja i kopie na koncie Dysk Google (Google Drive)")
                                                .font(.scaled(12, weight: .semibold, scale: scale))
                                        }
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                    
                                    Spacer()
                                    
                                    if store.settings.googleDrive.isEnabled {
                                        Text(store.settings.googleDrive.accountEmail.isEmpty ? "" : store.settings.googleDrive.accountEmail)
                                            .font(.scaled(10, weight: .bold, scale: scale))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundColor(.blue)
                                            .cornerRadius(6)
                                    }
                                }
                                
                                if store.settings.googleDrive.isEnabled {
                                    VStack(alignment: .leading, spacing: 10) {
                                        // Account Email
                                        HStack {
                                            Text("Konto Google:")
                                                .font(.scaled(11, weight: .medium, scale: scale))
                                                .frame(width: 140, alignment: .leading)
                                            TextField("np. ", text: $store.settings.googleDrive.accountEmail)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                                .font(.scaled(11, scale: scale))
                                        }
                                        
                                        // Action buttons for Google Drive
                                        HStack(spacing: 10) {
                                            if isUploadingToDrive {
                                                ProgressView()
                                                    .controlSize(.small)
                                                Text("Wysyłanie kopii do chmury Google...")
                                                    .font(.scaled(11, scale: scale))
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Button(action: uploadToGoogleDriveAction) {
                                                    Label("Wyślij bieżący backup na Dysk Google", systemImage: "arrow.up.to.line.circle.fill")
                                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .controlSize(.small)
                                            }
                                            
                                            Button(action: {
                                                isShowingGoogleDriveBackups = true
                                            }) {
                                                Label("Przeglądaj i przywróć kopie z Dysku Google...", systemImage: "clock.arrow.circlepath")
                                                    .font(.scaled(11, scale: scale))
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        
                                        // Auto Backup Checkbox
                                        Toggle(isOn: $store.settings.googleDrive.autoBackupOnExit) {
                                            Text("Twórz i wysyłaj kopię na Dysk Google automatycznie przy zamykaniu aplikacji")
                                                .font(.scaled(11, scale: scale))
                                                .foregroundColor(.secondary)
                                        }
                                        .toggleStyle(CheckboxToggleStyle())
                                        
                                        // Credentials Disclosure
                                        DisclosureGroup(isExpanded: $showDriveCredentials) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("Dane dostępowe Google Drive API (opcjonalne, dla własnego projektu w Google Cloud Console):")
                                                    .font(.scaled(10, scale: scale))
                                                    .foregroundColor(.secondary)
                                                
                                                HStack {
                                                    Text("Client ID:")
                                                        .font(.scaled(10, scale: scale))
                                                        .frame(width: 90, alignment: .leading)
                                                    TextField("Client ID z Google Cloud Console", text: $store.settings.googleDrive.clientId)
                                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                                        .font(.scaled(10, scale: scale))
                                                }
                                                
                                                HStack {
                                                    Text("Client Secret:")
                                                        .font(.scaled(10, scale: scale))
                                                        .frame(width: 90, alignment: .leading)
                                                    SecureField("Client Secret", text: $store.settings.googleDrive.clientSecret)
                                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                                        .font(.scaled(10, scale: scale))
                                                }
                                                
                                                HStack {
                                                    Text("Token dostępowy:")
                                                        .font(.scaled(10, scale: scale))
                                                        .frame(width: 90, alignment: .leading)
                                                    SecureField("Access Token / OAuth Token", text: $store.settings.googleDrive.accessToken)
                                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                                        .font(.scaled(10, scale: scale))
                                                }
                                                
                                                HStack {
                                                    Text("Folder w chmurze:")
                                                        .font(.scaled(10, scale: scale))
                                                        .frame(width: 90, alignment: .leading)
                                                    TextField("CantatePresenter_Backups", text: $store.settings.googleDrive.targetFolder)
                                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                                        .font(.scaled(10, scale: scale))
                                                }
                                                
                                                HStack(spacing: 8) {
                                                    Button(action: authorizeGoogleOAuthInBrowser) {
                                                        Label("Autoryzuj w przeglądarce (Google OAuth)...", systemImage: "globe")
                                                            .font(.scaled(10, scale: scale))
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.mini)
                                                    
                                                    if isAuthorizingDrive {
                                                        TextField("Wklej kod autoryzacji z Google", text: $driveAuthCodeInput)
                                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                                            .font(.scaled(10, scale: scale))
                                                        Button("Zatwierdź kod") {
                                                            submitDriveAuthCode()
                                                        }
                                                        .buttonStyle(.borderedProminent)
                                                        .controlSize(.mini)
                                                    }
                                                }
                                            }
                                            .padding(8)
                                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                                            .cornerRadius(6)
                                        } label: {
                                            Text("Zaawansowane dane logowania Google API (Client ID / Token)...")
                                                .font(.scaled(10, weight: .medium, scale: scale))
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.leading, 18)
                                }
                            }
                            
                            // Status feedback message
                            if let msg = backupStatusMessage {
                                HStack(spacing: 6) {
                                    Image(systemName: isBackupSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundColor(isBackupSuccess ? .green : .red)
                                    Text(msg)
                                        .font(.scaled(11, weight: .medium, scale: scale))
                                        .foregroundColor(isBackupSuccess ? .green : .red)
                                    Spacer()
                                }
                                .padding(8)
                                .background((isBackupSuccess ? Color.green : Color.red).opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Presentation Keyboard Shortcuts
                    GroupBox(label: Label("Skróty klawiszowe sterowania prezentacją", systemImage: "keyboard")) {
                        VStack(spacing: 10) {
                            shortcutRow(
                                title: "Poprzedni slajd:",
                                selection: $store.settings.shortcuts.prevSlideKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: "Następny slajd:",
                                selection: $store.settings.shortcuts.nextSlideKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: "Poprzedni utwór (z planu):",
                                selection: $store.settings.shortcuts.prevSongKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: "Następny utwór (z planu):",
                                selection: $store.settings.shortcuts.nextSongKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: "Uruchomienie prezentacji:",
                                selection: $store.settings.shortcuts.startPresentationKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: "Zatrzymanie prezentacji:",
                                selection: $store.settings.shortcuts.stopPresentationKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: "Czarny ekran (toggle):",
                                selection: $store.settings.shortcuts.blackScreenKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: "Ukrycie tekstu (toggle):",
                                selection: $store.settings.shortcuts.clearTextKey,
                                scale: scale
                            )
                            
                            let conflicts = store.settings.shortcuts.conflicts
                            if !conflicts.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(conflicts, id: \.self) { conflict in
                                        Label(conflict, systemImage: "exclamationmark.triangle.fill")
                                            .font(.scaled(11, weight: .medium, scale: scale))
                                            .foregroundColor(.orange)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            HStack {
                                Spacer()
                                Button("Przywróć domyślne skróty") {
                                    store.settings.shortcuts = ShortcutSettings()
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Font & Typography
                    GroupBox(label: Label("Typografia ekranu prezentacji", systemImage: "textformat")) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Czcionka systemowa:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 140, alignment: .leading)
                                
                                Picker("", selection: $store.settings.fontFamily) {
                                    ForEach(availableFonts, id: \.self) { fontName in
                                        Text(fontName).tag(fontName)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            
                            Toggle("Pogrubienie tekstu (Bold)", isOn: $store.settings.isBold)
                                .font(.scaled(12, scale: scale))
                            
                            Toggle("Cień pod tekstem (poprawia kontrast na projektorze)", isOn: $store.settings.hasShadow)
                                .font(.scaled(12, scale: scale))
                            
                            HStack {
                                Text("Wyrównanie tekstu:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 140, alignment: .leading)
                                
                                Picker("", selection: $store.settings.textAlignment) {
                                    Text("Środek").tag("center")
                                    Text("Do lewej").tag("left")
                                    Text("Do prawej").tag("right")
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            
                            HStack {
                                Text("Położenie pionowe:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 140, alignment: .leading)
                                
                                Picker("", selection: $store.settings.verticalAlignment) {
                                    Text("Środek").tag("center")
                                    Text("Góra").tag("top")
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Colors
                    GroupBox(label: Label("Kolory ekranu", systemImage: "paintpalette")) {
                        VStack(spacing: 14) {
                            HStack {
                                Text("Kolor tekstu:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 140, alignment: .leading)
                                
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: store.settings.textColorHex) },
                                    set: {
                                        store.settings.textColorHex = $0.toHex()
                                        store.saveSettings()
                                    }
                                ))
                                .labelsHidden()
                                
                                Text(store.settings.textColorHex)
                                    .font(.scaled(12, scale: scale, isMonospaced: true))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Biały") {
                                    store.settings.textColorHex = "#FFFFFF"
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("Żółty") {
                                    store.settings.textColorHex = "#FFE57F"
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            HStack {
                                Text("Kolor tła:")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 140, alignment: .leading)
                                
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: store.settings.backgroundColorHex) },
                                    set: {
                                        store.settings.backgroundColorHex = $0.toHex()
                                        store.saveSettings()
                                    }
                                ))
                                .labelsHidden()
                                
                                Text(store.settings.backgroundColorHex)
                                    .font(.scaled(12, scale: scale, isMonospaced: true))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Czarny") {
                                    store.settings.backgroundColorHex = "#000000"
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("Ciemny granat") {
                                    store.settings.backgroundColorHex = "#0A0E1A"
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Margins & Spacing
                    GroupBox(label: Label("Marginesy i interlinia", systemImage: "arrow.up.and.down.and.arrow.left.and.right")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Margines ekranu: \(Int(store.settings.marginPercent * 100))%")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 160, alignment: .leading)
                                
                                Slider(value: $store.settings.marginPercent, in: 0.03...0.18, step: 0.01)
                            }
                            
                            HStack {
                                Text("Interlinia: \(String(format: "%.2f", store.settings.lineSpacingFactor))x")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 160, alignment: .leading)
                                
                                Slider(value: $store.settings.lineSpacingFactor, in: 1.0...1.5, step: 0.05)
                            }
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Operator UI Zoom
                    GroupBox(label: Label("Wielkość elementów interfejsu (UI Scale)", systemImage: "plus.magnifyingglass")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Skala interfejsu: \(Int(store.settings.uiScale * 100))%")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 160, alignment: .leading)
                                
                                Slider(value: $store.settings.uiScale, in: 0.8...1.5, step: 0.05)
                                
                                Button("Resetuj (100%)") {
                                    store.resetZoomUI()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text("Możesz także używać skrótów Cmd + / Cmd - oraz przycisków w prawym górnym rogu paska narzędzi.")
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Bottom Control Bar Height
                    GroupBox(label: Label("Dolny pasek sterowania prezentacją", systemImage: "rectangle.bottomthird.inset.filled")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Wysokość paska: \(Int(store.settings.bottomBarHeight)) px")
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 170, alignment: .leading)
                                
                                Slider(value: $store.settings.bottomBarHeight, in: 52...160, step: 2)
                                
                                Button("Domyślna (72 px)") {
                                    store.settings.bottomBarHeight = 72.0
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text("Wielkość ikon, czcionek klawiszy i etykiet w dolnym pasku dostosowuje się automatycznie do wybranej wysokości. Pasek można także rozciągać przeciągając myszką uchwyt na linii podziału.")
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 620, minHeight: 640)
        .sheet(isPresented: $isShowingLogoGallery) {
            LogoGallerySheet(isPresented: $isShowingLogoGallery)
        }
        .sheet(isPresented: $isShowingGoogleDriveBackups) {
            GoogleDriveBackupsSheet(isPresented: $isShowingGoogleDriveBackups)
        }
        .onAppear {
            self.availableFonts = AutoFitEngine.availableSystemFonts()
        }
    }
    
    // MARK: - Backup & Google Drive Actions
    
    private func createLocalBackupAction() {
        backupStatusMessage = nil
        let success = BackupService.shared.exportBackupWithSavePanel()
        if success {
            isBackupSuccess = true
            backupStatusMessage = "Pomyślnie utworzono i zapisano pełną kopię zapasową (.holyricsbackup)!"
        }
    }
    
    private func restoreLocalBackupAction() {
        backupStatusMessage = nil
        let res = BackupService.shared.restoreBackupWithOpenPanel()
        isBackupSuccess = res.success
        backupStatusMessage = res.message
    }
    
    private func uploadToGoogleDriveAction() {
        backupStatusMessage = nil
        isUploadingToDrive = true
        
        Task {
            do {
                let (archiveURL, _) = try BackupService.shared.createBackupArchive(comment: "Ręczny backup z Ustawień")
                let item = try await GoogleDriveService.shared.uploadBackupToDrive(archiveURL: archiveURL)
                try? FileManager.default.removeItem(at: archiveURL)
                
                await MainActor.run {
                    self.isUploadingToDrive = false
                    self.isBackupSuccess = true
                    self.backupStatusMessage = "Pomyślnie przesłano kopię '\(item.name)' na Dysk Google (\(item.formattedSize)) do folderu '\(store.settings.googleDrive.targetFolder)'!"
                }
            } catch {
                await MainActor.run {
                    self.isUploadingToDrive = false
                    self.isBackupSuccess = false
                    self.backupStatusMessage = "Błąd wysyłania na Dysk Google: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func authorizeGoogleOAuthInBrowser() {
        let clientId = store.settings.googleDrive.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty else {
            backupStatusMessage = "Wpisz swój Client ID z Google Cloud Console przed uruchomieniem przeglądarki."
            isBackupSuccess = false
            return
        }
        
        if let authURL = GoogleDriveService.shared.generateOAuthURL(clientId: clientId) {
            isAuthorizingDrive = true
            NSWorkspace.shared.open(authURL)
            backupStatusMessage = "Otwarto okno logowania Google w przeglądarce. Po zatwierdzeniu skopiuj wygenerowany kod i wklej w polu poniżej."
            isBackupSuccess = true
        }
    }
    
    private func submitDriveAuthCode() {
        let code = driveAuthCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        
        Task {
            do {
                let res = try await GoogleDriveService.shared.exchangeCodeForTokens(
                    code: code,
                    clientId: store.settings.googleDrive.clientId,
                    clientSecret: store.settings.googleDrive.clientSecret
                )
                
                await MainActor.run {
                    self.store.settings.googleDrive.accessToken = res.accessToken
                    self.store.settings.googleDrive.refreshToken = res.refreshToken
                    if !res.email.isEmpty {
                        self.store.settings.googleDrive.accountEmail = res.email
                    }
                    self.store.saveSettings()
                    self.isAuthorizingDrive = false
                    self.driveAuthCodeInput = ""
                    self.isBackupSuccess = true
                    self.backupStatusMessage = "Pomyślnie połączono z kontem Google: \(store.settings.googleDrive.accountEmail)!"
                }
            } catch {
                await MainActor.run {
                    self.isBackupSuccess = false
                    self.backupStatusMessage = "Błąd autoryzacji kodu Google: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func shortcutRow(title: String, selection: Binding<UInt16>, scale: Double) -> some View {
        HStack {
            Text(title)
                .font(.scaled(12, weight: .medium, scale: scale))
                .frame(width: 200, alignment: .leading)
            
            Picker("", selection: selection) {
                ForEach(ShortcutPresets.availableKeys) { key in
                    Text(key.name).tag(key.id)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            Spacer()
        }
    }
    
    private func pickHtmlFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]
        panel.prompt = "Wybierz plik HTML"
        panel.message = "Wybierz plik HTML z planszą startową"
        
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.standbyHtmlPath = url.path
            store.saveSettings()
        }
    }
    
    private func openStandbyHtmlFile() {
        let fileManager = FileManager.default
        let path = store.settings.standbyHtmlPath
        let url: URL
        if !path.isEmpty && fileManager.fileExists(atPath: path) {
            url = URL(fileURLWithPath: path)
        } else {
            url = AppPaths.shared.standbyFile
        }
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Translation Export & Import
    private func exportTranslationTemplate() {
        guard let jsonString = LocalizationService.shared.exportTemplateJSON(sourceLanguage: store.settings.appLanguage) else {
            translationNotice = "Błąd: Nie udało się wygenerować szablonu JSON."
            return
        }
        
        let panel = NSSavePanel()
        panel.title = "Eksportuj słownik do tłumaczenia (szablon dla AI)"
        panel.nameFieldStringValue = "holyrics_translations_\(store.settings.appLanguage).json"
        panel.allowedContentTypes = [.json]
        panel.prompt = "Eksportuj"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try jsonString.write(to: url, atomically: true, encoding: .utf8)
                translationNotice = "Pomyślnie wyeksportowano szablon tłumaczenia do pliku: \(url.lastPathComponent)"
            } catch {
                translationNotice = "Błąd zapisu pliku: \(error.localizedDescription)"
            }
        }
    }
    
    private func importTranslationJSON() {
        let panel = NSOpenPanel()
        panel.title = "Importuj plik tłumaczenia interfejsu (JSON)"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "Importuj"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let res = try LocalizationService.shared.importTranslation(from: url)
                store.settings.appLanguage = res.code
                store.saveSettings()
                translationNotice = "Pomyślnie zaimportowano język: \(res.name) (\(res.code)) — \(res.count) przetłumaczonych fraz!"
            } catch {
                translationNotice = "Błąd importu pliku: \(error.localizedDescription)"
            }
        }
    }
}
