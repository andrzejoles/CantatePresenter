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
        .onAppear {
            self.availableFonts = AutoFitEngine.availableSystemFonts()
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
            let bundleURL = Bundle.main.bundleURL
            let projectFolder = bundleURL.pathExtension == "app"
                ? bundleURL.deletingLastPathComponent()
                : URL(fileURLWithPath: fileManager.currentDirectoryPath)
            url = projectFolder.appendingPathComponent("data/standby.html")
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
