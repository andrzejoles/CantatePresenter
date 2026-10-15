import Foundation
import SwiftUI
import AppKit

public struct UserManualSection: Identifiable {
    public let id: String
    public let title: String
    public let icon: String
    public let content: [ManualParagraph]
}

public struct ManualParagraph: Identifiable {
    public let id = UUID()
    public let heading: String
    public let body: String
    public let tip: String?
    public let shortcuts: [(key: String, desc: String)]?
    
    public init(heading: String, body: String, tip: String? = nil, shortcuts: [(key: String, desc: String)]? = nil) {
        self.heading = heading
        self.body = body
        self.tip = tip
        self.shortcuts = shortcuts
    }
}

public struct UserManualView: View {
    @Bindable var store = DataStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSectionId: String = "intro"
    @State private var searchText: String = ""
    
    private let sections: [UserManualSection] = [
        UserManualSection(
            id: "intro",
            title: L("1. Wprowadzenie"),
            icon: "sparkles",
            content: [
                ManualParagraph(
                    heading: L("O programie CantatePresenter"),
                    body: L("CantatePresenter to profesjonalne narzędzie macOS stworzone dla wspólnot, zespołów muzycznych, parafii oraz Ruchu Equipes Notre-Dame (END). Umożliwia prezentację słów pieśni, chwytów gitarowych i slajdów liturgicznych."),
                    tip: L("Aplikacja jest w 100% natywna dla Apple Silicon (M1–M5), co zapewnia natychmiastowe działanie i znikome zużycie baterii.")
                ),
                ManualParagraph(
                    heading: L("Układ trzypanelowy"),
                    body: L("• Lewy panel: Biblioteka pieśni z wyszukiwarką oraz Plany nabożeństw.\n• Środkowy panel: Podgląd slajdów wybranej pieśni wraz z chwytami gitarowymi.\n• Prawy panel (Live Monitor): Podgląd stanu rzutnika na żywo, podgląd następnego slajdu i kontrola monitorów.")
                )
            ]
        ),
        UserManualSection(
            id: "presentation",
            title: L("2. Prezentacja i Ekrany"),
            icon: "display",
            content: [
                ManualParagraph(
                    heading: L("Prezentacja na projektorze lub monitorze"),
                    body: L("Wybierz docelowy monitor w prawym panelu i kliknij 'Prezentuj na pełnym ekranie'. Kliknięcie w dowolny slajd włącza projekcję na żywo."),
                    tip: L("Możesz także otworzyć 'Okno testowe' w prawym panelu, aby testować wygląd slajdów bez podłączania projektora.")
                ),
                ManualParagraph(
                    heading: L("Prezentacja na jednym ekranie & Wyjście ESC"),
                    body: L("Gdy podłączony jest tylko 1 ekran, prezentacja uruchamia się w trybie pełnoekranowym na Twoim Macu. Naciśnij w dowolnym momencie klawisz ESC, aby natychmiast wrócić do aplikacji."),
                    shortcuts: [
                        ("ESC", L("Natychmiastowe wyjście z pełnego ekranu")),
                        (L("Spacja / → / ↓ / Page Down / Enter"), L("Przejście do następnego slajdu")),
                        (L("← / ↑ / Page Up"), L("Przejście do poprzedniego slajdu")),
                        ("B", L("Czarny ekran (Black Screen)")),
                        ("C", L("Ukrycie tekstu (Clear Text)"))
                    ]
                )
            ]
        ),
        UserManualSection(
            id: "standby",
            title: L("3. Plansza Czuwania i Logo"),
            icon: "photo.badge.checkmark",
            content: [
                ManualParagraph(
                    heading: L("Plansza czuwania (Standby)"),
                    body: L("Gdy nie trwa prezentacja pieśni, na rzutniku widoczna jest elegancka plansza czuwania z nazwą programu 'CantatePresenter', wersją, zegarem i wybranym logo."),
                    tip: L("Plansza aktualizuje się automatycznie przy każdej zmianie logo w Ustawieniach.")
                ),
                ManualParagraph(
                    heading: L("Galeria 23 propozycji logo"),
                    body: L("W Ustawieniach dostępna jest bogata galeria logotypów, w tym oficjalne logo Equipes Notre-Dame (END: ryba i obrączki przymierza), złota gitara akustyczna, Lira Dawidowa, klucz wiolinowy z korektorem, harfa i fale harmoniczne.")
                )
            ]
        ),
        UserManualSection(
            id: "editor",
            title: L("4. Baza Pieśni i Edytor"),
            icon: "square.and.pencil",
            content: [
                ManualParagraph(
                    heading: L("Edycja istniejących pieśni i dodawanie nowych"),
                    body: L("Kliknij 'Nowa pieśń' lub wybierz pieśń i kliknij 'Edytuj' (Cmd E). Edytor posiada podgląd podziału na slajdy na żywo.")
                ),
                ManualParagraph(
                    heading: L("Obsługiwane sekcje utworu"),
                    body: L("Program rozpoznaje znaczniki:\n• [Zwrotka 1], [Zwrotka 2], [1], [2]\n• [Refren], [Refren 1], [R]\n• [Coda] lub [Koda]\n• [Bridge] lub [Mostek]\n• [Przejście] lub [Interlude]\n• [Zakończenie] lub [Ending]\n• [Intro] oraz [Outro]"),
                    tip: L("Możesz też po prostu oddzielać zwrotki pustą linią — program sam podzieli tekst na slajdy.")
                )
            ]
        ),
        UserManualSection(
            id: "chords",
            title: L("5. Chwyty Gitarowe"),
            icon: "guitars",
            content: [
                ManualParagraph(
                    heading: L("Akordy i transpozycja"),
                    body: L("Pieśń może zawierać chwyty gitarowe (np. D A h G). Przyciski +1 / -1 pozwalają transponować tonację całego utworu jednym kliknięciem.")
                ),
                ManualParagraph(
                    heading: L("Pobieranie chwytów z internetu"),
                    body: L("Kliknij 'Szukaj chwytów online' — aplikacja przeszuka polskie serwisy (tekstowo.pl, kompasje.pl) i pozwoli wstawić akordy bezpośrednio do pieśni.")
                )
            ]
        ),
        UserManualSection(
            id: "dictation",
            title: L("6. Dyktowanie Głosowe"),
            icon: "mic.fill",
            content: [
                ManualParagraph(
                    heading: L("Wprowadzanie tekstu i szukanie głosem"),
                    body: L("Kliknij ikonę mikrofonu w edytorze lub obok paska szukania, aby podyktować słowa pieśni lub wyszukać utwór głosem."),
                    tip: L("Język rozpoznawania mowy (domyślnie polski pl-PL) można ustawić w Ustawieniach.")
                )
            ]
        ),
        UserManualSection(
            id: "plans",
            title: L("7. Plany Nabożeństw"),
            icon: "list.bullet.rectangle",
            content: [
                ManualParagraph(
                    heading: L("Przygotowanie listy utworów"),
                    body: L("W lewym panelu przełącz na 'Plan'. Utwórz nowy plan na mszę lub spotkanie i przeciągaj pieśni z biblioteki. Naciśnięcie spacji na końcu utworu płynnie przełącza do kolejnej pieśni z planu!")
                )
            ]
        ),
        UserManualSection(
            id: "import",
            title: L("8. Import i Eksport"),
            icon: "tray.and.arrow.down",
            content: [
                ManualParagraph(
                    heading: L("Formaty Holyrics, OpenLyrics, JSON i TXT"),
                    body: L("W oknie Import/Eksport (Cmd I) możesz importować bazy Holyrics (.mufl, .muf), pliki tekstowe .txt (pojedyncze i całe foldery), pliki JSON oraz XML."),
                    tip: L("Aplikacja automatycznie naprawia polskie litery z kodowań Windows-1250 i ISO-8859-2 oraz wykrywa duplikaty.")
                )
            ]
        ),
        UserManualSection(
            id: "backup",
            title: L("9. Kopie Zapasowe i Dysk Google"),
            icon: "archivebox.fill",
            content: [
                ManualParagraph(
                    heading: L("Pełny backup (.cantatebackup)"),
                    body: L("Kopia zapasowa zabezpiecza całą bazę pieśni, chwyty, plany, ustawienia, planszę standby, języki i loga.")
                ),
                ManualParagraph(
                    heading: L("Integracja z Google Drive"),
                    body: L("Po autoryzacji Google OAuth w Ustawieniach, kopie są automatycznie przesyłane do dedykowanego folderu CantatePresenter_Backups w chmurze."),
                    tip: L("Włącz opcję 'Automatyczny backup przy zamykaniu', aby program tworzył kopię po każdym użyciu.")
                )
            ]
        ),
        UserManualSection(
            id: "shortcuts",
            title: L("10. Skróty Klawiszowe"),
            icon: "keyboard",
            content: [
                ManualParagraph(
                    heading: L("Szybkie sterowanie prezentacją"),
                    body: L("Domyślne skróty prezentacji (zmienisz je w Ustawieniach → Skróty klawiszowe) oraz klawisze stałe. {0}", KeyboardRouter.shortcutsNote),
                    shortcuts: [
                        (L("Spacja"), L("Następny slajd / następna pieśń z planu")),
                        (L("Enter"), L("Uruchomienie projekcji zaznaczonej pieśni")),
                        ("[ / ]", L("Poprzednia / następna pieśń z planu")),
                        ("B", L("Włącz/Wyłącz czarny ekran")),
                        ("C", L("Włącz/Wyłącz ukrycie tekstu"))
                    ] + KeyboardRouter.fixedKeysHelp.map { (key: $0.keys, desc: $0.action) } + [
                        ("⌘E", L("Edycja zaznaczonej pieśni")),
                        ("⌘I", L("Import pieśni")),
                        ("⌘B", L("Utwórz pełną kopię zapasową")),
                        ("⌘?", L("Instrukcja obsługi (to okno)"))
                    ]
                )
            ]
        )
    ]
    
    public init() {}
    
    private var filteredSections: [UserManualSection] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return sections
        }
        let query = searchText.lowercased()
        return sections.filter { sec in
            sec.title.lowercased().contains(query) ||
            sec.content.contains { p in
                p.heading.lowercased().contains(query) ||
                p.body.lowercased().contains(query) ||
                (p.tip?.lowercased().contains(query) ?? false)
            }
        }
    }
    
    private var activeSection: UserManualSection {
        return sections.first(where: { $0.id == selectedSectionId }) ?? sections[0]
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(L("Instrukcja Obsługi CantatePresenter"))
                            .font(.scaled(16, weight: .bold, scale: scale))
                        
                        Text("v1.0.0")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    Text(L("Podręcznik użytkownika, skróty klawiszowe i wskazówki operacyjne"))
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(L("Otwórz plik INSTRUKCJA.md")) {
                    openMarkdownFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(L("GitHub")) {
                    if let url = URL(string: "https://github.com/andrzejoles/CantatePresenter") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(L("Zamknij")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L("Szukaj w instrukcji..."), text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.scaled(12, scale: scale))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content with Sidebar
            HSplitView {
                // Sidebar Sections
                List(filteredSections, selection: $selectedSectionId) { section in
                    NavigationLink(value: section.id) {
                        Label(section.title, systemImage: section.icon)
                            .font(.scaled(12, weight: selectedSectionId == section.id ? .semibold : .regular, scale: scale))
                    }
                    .tag(section.id)
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 220, maxWidth: 280)
                
                // Section Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: activeSection.icon)
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            Text(activeSection.title)
                                .font(.scaled(20, weight: .bold, scale: scale))
                            Spacer()
                        }
                        .padding(.bottom, 6)
                        
                        Divider()
                        
                        ForEach(activeSection.content) { para in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(para.heading)
                                    .font(.scaled(15, weight: .bold, scale: scale))
                                    .foregroundColor(.primary)
                                
                                Text(para.body)
                                    .font(.scaled(13, scale: scale))
                                    .lineSpacing(4)
                                    .foregroundColor(.primary.opacity(0.9))
                                
                                if let tip = para.tip {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundColor(.orange)
                                        Text(tip)
                                            .font(.scaled(12, scale: scale))
                                            .foregroundColor(.orange)
                                    }
                                    .padding(10)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                
                                if let shortcuts = para.shortcuts {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(L("Skróty klawiszowe:"))
                                            .font(.scaled(11, weight: .semibold, scale: scale))
                                            .foregroundColor(.secondary)
                                        
                                        ForEach(shortcuts, id: \.key) { sc in
                                            HStack {
                                                Text(sc.key)
                                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(Color.primary.opacity(0.08))
                                                    .cornerRadius(5)
                                                    .frame(minWidth: 140, alignment: .leading)
                                                
                                                Text(sc.desc)
                                                    .font(.scaled(12, scale: scale))
                                                Spacer()
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .padding(24)
                }
                .frame(minWidth: 500)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private func openMarkdownFile() {
        let fileManager = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        let projectFolder = bundleURL.pathExtension == "app"
            ? bundleURL.deletingLastPathComponent()
            : URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        let docURL = projectFolder.appendingPathComponent("INSTRUKCJA.md")
        if fileManager.fileExists(atPath: docURL.path) {
            NSWorkspace.shared.open(docURL)
        }
    }
}
