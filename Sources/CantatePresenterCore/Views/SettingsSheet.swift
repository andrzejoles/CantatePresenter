import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SettingsSheet: View {
    @Bindable var store = DataStore.shared
    @Binding var isPresented: Bool
    
    @State private var availableFonts: [String] = []
    @State private var testDictationText: String = ""
    @State private var isShowingLogoGallery: Bool = false
    @State private var translationNotice: String? = nil
    @State private var ccliReportNotice: String? = nil
    @State private var isShowingGoogleDriveBackups: Bool = false
    @State private var isUploadingToDrive: Bool = false
    @State private var isSigningInDrive: Bool = false
    @State private var isDriveSignedIn: Bool = false
    @State private var backupStatusMessage: String? = nil
    @State private var isBackupSuccess: Bool = true
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L("Ustawienia prezentacji i wyglądu"))
                    .font(.scaled(16, weight: .bold, scale: scale))
                Spacer()
                Button(L("Gotowe")) {
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
                    GroupBox(label: Label(L("Języki i dyktowanie głosowe"), systemImage: "waveform.and.mic")) {
                        VStack(alignment: .leading, spacing: 14) {
                            // App Language
                            HStack {
                                Text(L("Język aplikacji:"))
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
                                        Label(L("Eksportuj słownik do tłumaczenia (JSON dla AI)..."), systemImage: "square.and.arrow.up")
                                            .font(.scaled(11, scale: scale))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(L("Eksportuje plik JSON ze wszystkimi tekstami programu i opisami kontekstu dla narzędzi AI"))
                                    
                                    Button(action: importTranslationJSON) {
                                        Label(L("Importuj plik tłumaczenia (JSON)..."), systemImage: "square.and.arrow.down")
                                            .font(.scaled(11, weight: .medium, scale: scale))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .help(L("Wczytaj przetłumaczony plik języka JSON i dodaj do listy języków interfejsu"))
                                }
                                
                                if let notice = translationNotice {
                                    HStack(spacing: 6) {
                                        Image(systemName: notice.contains(L("Błąd")) ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                            .foregroundColor(notice.contains(L("Błąd")) ? .red : .green)
                                        Text(notice)
                                            .font(.scaled(11, weight: .medium, scale: scale))
                                            .foregroundColor(notice.contains(L("Błąd")) ? .red : .green)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background((notice.contains(L("Błąd")) ? Color.red : Color.green).opacity(0.12))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.leading, 170)
                            
                            // Search Language
                            HStack {
                                Text(L("Język wyszukiwania pieśni:"))
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
                                Text(L("Język dyktowania głosem:"))
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
                            
                            // Prywatność dyktowania (N4)
                            VStack(alignment: .leading, spacing: 3) {
                                Toggle(L("Rozpoznawaj mowę na tym Macu, gdy to możliwe"), isOn: $store.settings.dictationOnDeviceOnly)
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.scaled(11, scale: scale))
                                    .onChange(of: store.settings.dictationOnDeviceOnly) { _, _ in store.saveSettings() }
                                Text(L("Gdy macOS ma model mowy dla wybranego języka, nagrania nie są wysyłane do Apple i dyktowanie działa bez internetu. Bez takiego modelu, albo gdy rozpoznawanie na Macu się nie powiedzie, nagranie rozpoznają serwery Apple."))
                                    .font(.scaled(10, scale: scale))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            Divider()
                            
                            // Dictation Test Box
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(L("Przetestuj dyktowanie mikrofonem:"))
                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    DictationButtonView(text: $testDictationText, mode: .append(separator: " "), size: 12)
                                }
                                
                                HStack {
                                    TextField(L("Kliknij mikrofon obok i powiedz kilka słów..."), text: $testDictationText)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.scaled(11, scale: scale))
                                    
                                    if !testDictationText.isEmpty {
                                        Button(L("Wyczyść")) {
                                            testDictationText = ""
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                                
                                Text(L("Dyktowanie działa bezpośrednio w wyszukiwarkach (biblioteka, online, autor/tytuł) oraz w edytorze nowej pieśni (tytuł, autor i treść zwrotek)."))
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
                    GroupBox(label: Label(L("Plansza startowa i Logo aplikacji"), systemImage: "sparkles.tv")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("Gdy prezentacja pieśni nie jest aktywna, na ekranie projektora wyświetlana jest plansza powitalna HTML z wybranym logo programu."))
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
                                        Text(L("Aktywne logo:"))
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
                                    Label(L("Wybierz inne logo ({0} propozycje)...", LogoCatalog.all.count), systemImage: "square.grid.2x2")
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
                                Text(L("Własny plik HTML:"))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 120, alignment: .leading)
                                
                                TextField(L("Domyślna plansza"), text: $store.settings.standbyHtmlPath)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.scaled(11, scale: scale))
                                
                                Button(L("Wybierz plik...")) {
                                    pickHtmlFile()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                if !store.settings.standbyHtmlPath.isEmpty {
                                    Button(L("Domyślna")) {
                                        store.settings.standbyHtmlPath = ""
                                        store.saveSettings()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            HStack {
                                Spacer()
                                Button(L("Otwórz plik planszy w edytorze / przeglądarce")) {
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
                    GroupBox(label: Label(L("Kopia zapasowa i Dysk Google"), systemImage: "externaldrive.badge.icloud")) {
                        VStack(alignment: .leading, spacing: 14) {
                            // Summary info
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.scaled(20, scale: scale))
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L("Kompletna ochrona danych aplikacji"))
                                        .font(.scaled(12, weight: .bold, scale: scale))
                                    Text(L("Kopia zapasowa (.holyricsbackup) zawiera: całą bazę pieśni ({0}), plany nabożeństw ({1}), chwyty gitarowe, wszystkie ustawienia programu, stronę początkową Standby, języki tłumaczeń oraz oficjalne loga.", store.songs.count, store.plans.count))
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
                                    Label(L("Utwórz pełną kopię zapasową (.holyricsbackup)..."), systemImage: "square.and.arrow.up.fill")
                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Button(action: restoreLocalBackupAction) {
                                    Label(L("Przywróć z pliku kopii zapasowej..."), systemImage: "arrow.counterclockwise.circle")
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
                                            Text(L("Synchronizacja i kopie na koncie Dysk Google (Google Drive)"))
                                                .font(.scaled(12, weight: .semibold, scale: scale))
                                        }
                                    }
                                    .toggleStyle(CheckboxToggleStyle())
                                    
                                    Spacer()
                                    
                                    if store.settings.googleDrive.isEnabled {
                                        Text(isDriveSignedIn ? (store.settings.googleDrive.accountEmail.isEmpty ? L("Połączono") : store.settings.googleDrive.accountEmail) : L("Nie połączono"))
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
                                        // Account connection (W3: logowanie w przeglądarce, loopback + PKCE)
                                        HStack(spacing: 8) {
                                            Text(L("Konto Google:"))
                                                .font(.scaled(11, weight: .medium, scale: scale))
                                                .frame(width: 140, alignment: .leading)
                                            Text(isDriveSignedIn ? (store.settings.googleDrive.accountEmail.isEmpty ? L("połączono") : store.settings.googleDrive.accountEmail) : L("nie połączono"))
                                                .font(.scaled(11, scale: scale))
                                                .foregroundColor(isDriveSignedIn ? .primary : .secondary)
                                            Spacer()
                                            if isSigningInDrive {
                                                ProgressView()
                                                    .controlSize(.small)
                                                Text(L("Dokończ logowanie w przeglądarce..."))
                                                    .font(.scaled(10, scale: scale))
                                                    .foregroundColor(.secondary)
                                            } else if isDriveSignedIn {
                                                Button(L("Rozłącz"), action: disconnectGoogleAccount)
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                            } else if GoogleDriveService.shared.isSignInAvailable {
                                                Button(action: connectGoogleAccount) {
                                                    Label(L("Połącz z kontem Google..."), systemImage: "person.badge.key")
                                                        .font(.scaled(11, scale: scale))
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .controlSize(.small)
                                            } else {
                                                Text(L("Logowanie Google niedostępne w tej wersji aplikacji"))
                                                    .font(.scaled(10, scale: scale))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        // Action buttons for Google Drive
                                        HStack(spacing: 10) {
                                            if isUploadingToDrive {
                                                ProgressView()
                                                    .controlSize(.small)
                                                Text(L("Wysyłanie kopii do chmury Google..."))
                                                    .font(.scaled(11, scale: scale))
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Button(action: uploadToGoogleDriveAction) {
                                                    Label(L("Wyślij bieżący backup na Dysk Google"), systemImage: "arrow.up.to.line.circle.fill")
                                                        .font(.scaled(11, weight: .semibold, scale: scale))
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .controlSize(.small)
                                            }
                                            
                                            Button(action: {
                                                isShowingGoogleDriveBackups = true
                                            }) {
                                                Label(L("Przeglądaj i przywróć kopie z Dysku Google..."), systemImage: "clock.arrow.circlepath")
                                                    .font(.scaled(11, scale: scale))
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        
                                        // Auto Backup Checkbox
                                        Toggle(isOn: $store.settings.googleDrive.autoBackupOnExit) {
                                            Text(L("Twórz i wysyłaj kopię na Dysk Google automatycznie przy zamykaniu aplikacji"))
                                                .font(.scaled(11, scale: scale))
                                                .foregroundColor(.secondary)
                                        }
                                        .toggleStyle(CheckboxToggleStyle())
                                        
                                        // Folder na Dysku Google użytkownika
                                        HStack {
                                            Text(L("Folder na Dysku:"))
                                                .font(.scaled(11, weight: .medium, scale: scale))
                                                .frame(width: 140, alignment: .leading)
                                            TextField("CantatePresenter_Backups", text: $store.settings.googleDrive.targetFolder)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                                .font(.scaled(11, scale: scale))
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
                    GroupBox(label: Label(L("Skróty klawiszowe sterowania prezentacją"), systemImage: "keyboard")) {
                        VStack(spacing: 10) {
                            shortcutRow(
                                title: L("Poprzedni slajd:"),
                                selection: $store.settings.shortcuts.prevSlideKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: L("Następny slajd:"),
                                selection: $store.settings.shortcuts.nextSlideKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: L("Poprzedni utwór (z planu):"),
                                selection: $store.settings.shortcuts.prevSongKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: L("Następny utwór (z planu):"),
                                selection: $store.settings.shortcuts.nextSongKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: L("Uruchomienie prezentacji:"),
                                selection: $store.settings.shortcuts.startPresentationKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: L("Zatrzymanie prezentacji:"),
                                selection: $store.settings.shortcuts.stopPresentationKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: L("Czarny ekran (toggle):"),
                                selection: $store.settings.shortcuts.blackScreenKey,
                                scale: scale
                            )
                            shortcutRow(
                                title: L("Ukrycie tekstu (toggle):"),
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
                            
                            // Klawisze stałe (K3/W5) i działanie przy polu wyszukiwania
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("Klawisze stałe"))
                                    .font(.scaled(11, weight: .semibold, scale: scale))
                                ForEach(KeyboardRouter.fixedKeysHelp, id: \.keys) { item in
                                    HStack(alignment: .top) {
                                        Text(item.keys)
                                            .font(.scaled(11, weight: .medium, scale: scale))
                                            .frame(width: 200, alignment: .leading)
                                        Text(item.action)
                                            .font(.scaled(11, scale: scale))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Text(KeyboardRouter.shortcutsNote)
                                    .font(.scaled(10, scale: scale))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                            
                            HStack {
                                Spacer()
                                Button(L("Przywróć domyślne skróty")) {
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
                    GroupBox(label: Label(L("Typografia ekranu prezentacji"), systemImage: "textformat")) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(L("Czcionka systemowa:"))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 140, alignment: .leading)
                                
                                Picker("", selection: $store.settings.fontFamily) {
                                    ForEach(availableFonts, id: \.self) { fontName in
                                        Text(fontName).tag(fontName)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            
                            Toggle(L("Pogrubienie tekstu (Bold)"), isOn: $store.settings.isBold)
                                .font(.scaled(12, scale: scale))
                            
                            Toggle(L("Cień pod tekstem (poprawia kontrast na projektorze)"), isOn: $store.settings.hasShadow)
                                .font(.scaled(12, scale: scale))
                            
                            HStack {
                                Text(L("Wyrównanie tekstu:"))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 140, alignment: .leading)
                                
                                Picker("", selection: $store.settings.textAlignment) {
                                    Text(L("Środek")).tag(HorizontalTextAlignment.center)
                                    Text(L("Do lewej")).tag(HorizontalTextAlignment.left)
                                    Text(L("Do prawej")).tag(HorizontalTextAlignment.right)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            
                            HStack {
                                Text(L("Położenie pionowe:"))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 140, alignment: .leading)
                                
                                Picker("", selection: $store.settings.verticalAlignment) {
                                    Text(L("Góra")).tag(VerticalTextAlignment.top)
                                    Text(L("Środek")).tag(VerticalTextAlignment.center)
                                    Text(L("Dół")).tag(VerticalTextAlignment.bottom)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Colors
                    GroupBox(label: Label(L("Kolory ekranu"), systemImage: "paintpalette")) {
                        VStack(spacing: 14) {
                            HStack {
                                Text(L("Kolor tekstu:"))
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
                                
                                Button(L("Biały")) {
                                    store.settings.textColorHex = "#FFFFFF"
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button(L("Żółty")) {
                                    store.settings.textColorHex = "#FFE57F"
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            HStack {
                                Text(L("Kolor tła:"))
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
                                
                                Button(L("Czarny")) {
                                    store.settings.backgroundColorHex = "#000000"
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button(L("Ciemny granat")) {
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
                    GroupBox(label: Label(L("Marginesy i interlinia"), systemImage: "arrow.up.and.down.and.arrow.left.and.right")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text(L("Margines ekranu: {0}%", Int(store.settings.marginPercent * 100)))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 160, alignment: .leading)
                                
                                Slider(value: $store.settings.marginPercent, in: 0.03...0.18, step: 0.01)
                            }
                            
                            HStack {
                                Text(L("Interlinia: {0}x", String(format: "%.2f", store.settings.lineSpacingFactor)))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 160, alignment: .leading)
                                
                                Slider(value: $store.settings.lineSpacingFactor, in: 1.0...1.5, step: 0.05)
                            }
                        }
                        .padding(8)
                    }
                    
                    // MARK: - CCLI
                    GroupBox(label: Label(L("Licencja CCLI i prawa autorskie"), systemImage: "c.circle")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L("Numer licencji CCLI parafii:"))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 220, alignment: .leading)
                                TextField("1234567", text: $store.settings.ccliLicenseNumber)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 140)
                                Spacer()
                            }
                            
                            Picker(L("Informacja o prawach na slajdzie:"), selection: $store.settings.copyrightNoticePlacement) {
                                Text(L("Na pierwszym slajdzie")).tag(CopyrightNoticePlacement.firstSlide)
                                Text(L("Na ostatnim slajdzie")).tag(CopyrightNoticePlacement.lastSlide)
                                Text(L("Na każdym slajdzie")).tag(CopyrightNoticePlacement.allSlides)
                                Text(L("Nie pokazuj")).tag(CopyrightNoticePlacement.none)
                            }
                            .font(.scaled(12, scale: scale))
                            .frame(maxWidth: 460)
                            
                            Text(L("Dotyczy pieśni z numerem CCLI (np. zaimportowanych z SongSelect). Licencja CCLI wymaga pokazania tytułu, autorów, praw autorskich i numeru licencji przy wyświetlaniu tekstu."))
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Divider()
                            
                            HStack {
                                Text(L("Raport użycia: zapisane wyświetlenia: {0}", store.ccliUsage.count))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                Spacer()
                                Button(action: exportCCLIReport) {
                                    Label(L("Eksportuj raport CCLI (CSV)..."), systemImage: "tablecells")
                                }
                                .disabled(store.ccliUsage.isEmpty)
                            }
                            
                            Text(L("Każda pieśń z numerem CCLI jest zapisywana raz dziennie, gdy trafi na ekran. Plik CSV pomoże zgłosić użycie na stronie CCLI."))
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if let notice = ccliReportNotice {
                                Text(notice)
                                    .font(.scaled(11, scale: scale))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Operator UI Zoom
                    GroupBox(label: Label(L("Wielkość elementów interfejsu (UI Scale)"), systemImage: "plus.magnifyingglass")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text(L("Skala interfejsu: {0}%", Int(store.settings.uiScale * 100)))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 160, alignment: .leading)
                                
                                Slider(value: $store.settings.uiScale, in: AppSettings.uiScaleRange, step: 0.05)
                                
                                Button(L("Resetuj (100%)")) {
                                    store.resetZoomUI()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text(L("Możesz także używać skrótów Cmd + / Cmd - oraz przycisków w prawym górnym rogu paska narzędzi."))
                                .font(.scaled(11, scale: scale))
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }
                    
                    // MARK: - Bottom Control Bar Height
                    GroupBox(label: Label(L("Dolny pasek sterowania prezentacją"), systemImage: "rectangle.bottomthird.inset.filled")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text(L("Wysokość paska: {0} px", Int(store.settings.bottomBarHeight)))
                                    .font(.scaled(12, weight: .medium, scale: scale))
                                    .frame(width: 170, alignment: .leading)
                                
                                Slider(value: $store.settings.bottomBarHeight, in: 52...160, step: 2)
                                
                                Button(L("Domyślna (72 px)")) {
                                    store.settings.bottomBarHeight = 72.0
                                    store.saveSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text(L("Wielkość ikon, czcionek klawiszy i etykiet w dolnym pasku dostosowuje się automatycznie do wybranej wysokości. Pasek można także rozciągać przeciągając myszką uchwyt na linii podziału."))
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
            refreshDriveState()
            self.availableFonts = AutoFitEngine.availableSystemFonts()
        }
    }
    
    // MARK: - Backup & Google Drive Actions
    
    private func createLocalBackupAction() {
        backupStatusMessage = nil
        let success = BackupService.shared.exportBackupWithSavePanel()
        if success {
            isBackupSuccess = true
            backupStatusMessage = L("Pomyślnie utworzono i zapisano pełną kopię zapasową (.holyricsbackup)!")
        }
    }
    
    private func restoreLocalBackupAction() {
        backupStatusMessage = nil
        Task {
            let res = await BackupService.shared.restoreBackupWithOpenPanel()
            isBackupSuccess = res.success
            backupStatusMessage = res.message
        }
    }
    
    private func uploadToGoogleDriveAction() {
        backupStatusMessage = nil
        isUploadingToDrive = true
        
        Task {
            do {
                let (archiveURL, _) = try BackupService.shared.createBackupArchive(comment: L("Ręczny backup z Ustawień"))
                let item = try await GoogleDriveService.shared.uploadBackupToDrive(archiveURL: archiveURL)
                try? FileManager.default.removeItem(at: archiveURL)
                
                await MainActor.run {
                    self.isUploadingToDrive = false
                    self.isBackupSuccess = true
                    self.backupStatusMessage = L("Pomyślnie przesłano kopię '{0}' na Dysk Google ({1}) do folderu '{2}'!", item.name, item.formattedSize, store.settings.googleDrive.targetFolder)
                }
            } catch {
                await MainActor.run {
                    self.isUploadingToDrive = false
                    self.isBackupSuccess = false
                    self.backupStatusMessage = L("Błąd wysyłania na Dysk Google: {0}", error.localizedDescription)
                }
            }
        }
    }
    
    private func refreshDriveState() {
        do {
            isDriveSignedIn = try GoogleDriveService.shared.signInState()
        } catch {
            // Wpis jest, ale Pęk kluczy go nie udostępnił (R3-04): to nie „Nie połączono”; zostaje „Rozłącz”.
            isDriveSignedIn = true
            isBackupSuccess = false
            backupStatusMessage = error.localizedDescription
        }
    }
    
    private func connectGoogleAccount() {
        backupStatusMessage = nil
        isSigningInDrive = true
        Task {
            do {
                let email = try await GoogleDriveService.shared.signIn()
                store.settings.googleDrive.accountEmail = email
                store.saveSettings()
                isBackupSuccess = true
                backupStatusMessage = email.isEmpty ? L("Połączono z kontem Google.") : L("Połączono z kontem Google: {0}.", email)
            } catch {
                isBackupSuccess = false
                backupStatusMessage = L("Nie udało się połączyć z kontem Google: {0}", error.localizedDescription)
            }
            isSigningInDrive = false
            refreshDriveState()
        }
    }
    
    private func disconnectGoogleAccount() {
        backupStatusMessage = nil
        Task {
            do {
                // Odwołanie dostępu w Google, potem usunięcie tokenów z Pęku kluczy (R3-12).
                let revoked = try await GoogleDriveService.shared.signOut()
                store.settings.googleDrive.accountEmail = ""
                store.saveSettings()
                isBackupSuccess = true
                backupStatusMessage = revoked
                    ? L("Rozłączono konto Google: dostęp odwołany w Google, tokeny usunięte z Pęku kluczy.")
                    : L("Rozłączono konto Google i usunięto tokeny z Pęku kluczy, ale Google nie potwierdził odwołania dostępu (np. brak internetu). Dostęp możesz odebrać na stronie myaccount.google.com/permissions.")
            } catch {
                isBackupSuccess = false
                backupStatusMessage = L("Nie udało się rozłączyć konta Google: {0}", error.localizedDescription)
            }
            refreshDriveState()
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
        panel.prompt = L("Wybierz plik HTML")
        panel.message = L("Wybierz plik HTML z planszą startową")
        
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
    
    // MARK: - CCLI Report
    private func exportCCLIReport() {
        let panel = NSSavePanel()
        panel.title = L("Eksportuj raport CCLI (CSV)...")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "CCLI_usage_\(formatter.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.prompt = L("Eksportuj")
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CCLIUsageReport.csv(store.ccliUsage).write(to: url, atomically: true, encoding: .utf8)
            ccliReportNotice = L("Zapisano raport: {0}", url.lastPathComponent)
        } catch {
            ccliReportNotice = L("Błąd zapisu pliku: {0}", error.localizedDescription)
        }
    }
    
    // MARK: - Translation Export & Import
    private func exportTranslationTemplate() {
        guard let jsonString = LocalizationService.shared.exportTemplateJSON(sourceLanguage: store.settings.appLanguage) else {
            translationNotice = L("Błąd: Nie udało się wygenerować szablonu JSON.")
            return
        }
        
        let panel = NSSavePanel()
        panel.title = L("Eksportuj słownik do tłumaczenia (szablon dla AI)")
        panel.nameFieldStringValue = "holyrics_translations_\(store.settings.appLanguage).json"
        panel.allowedContentTypes = [.json]
        panel.prompt = L("Eksportuj")
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try jsonString.write(to: url, atomically: true, encoding: .utf8)
                translationNotice = L("Pomyślnie wyeksportowano szablon tłumaczenia do pliku: {0}", url.lastPathComponent)
            } catch {
                translationNotice = L("Błąd zapisu pliku: {0}", error.localizedDescription)
            }
        }
    }
    
    private func importTranslationJSON() {
        let panel = NSOpenPanel()
        panel.title = L("Importuj plik tłumaczenia interfejsu (JSON)")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = L("Importuj")
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let res = try LocalizationService.shared.importTranslation(from: url)
                store.settings.appLanguage = res.code
                store.saveSettings()
                translationNotice = L("Pomyślnie zaimportowano język: {0} ({1}) — {2} przetłumaczonych fraz!", res.name, res.code, res.count)
            } catch {
                translationNotice = L("Błąd importu pliku: {0}", error.localizedDescription)
            }
        }
    }
}
