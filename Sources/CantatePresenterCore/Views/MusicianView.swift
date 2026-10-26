import Foundation
import SwiftUI
import AppKit
import Combine

// MARK: - Musician View

/// Ekran dla muzyków: bieżący slajd z chwytami nad tekstem, następny slajd, tonacja, transpozycja.
/// Czcionka o stałej szerokości, żeby akordy stały nad właściwą sylabą; mieści najdłuższy wiersz w oknie.
public struct MusicianView: View {
    @Bindable var store: DataStore

    @MainActor
    public init(store: DataStore? = nil) {
        self.store = store ?? .shared
    }

    public var body: some View {
        let semitones = store.settings.musicianTranspose
        let stage = MusicianStage.make(store: store, semitones: semitones)

        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                header(stage)
                Divider().overlay(Color.white.opacity(0.15))
                if let current = stage.current {
                    let size = fittedSize(current: current, next: stage.next, in: CGSize(width: geometry.size.width - 48, height: geometry.size.height - 90))
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 18) {
                            slideView(current, size: size, dimmed: false)
                            if let next = stage.next {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(stage.nextSongTitle.map { L("Następnie: {0}", $0) } ?? L("Następny slajd"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.gray)
                                    slideView(next, size: size * 0.7, dimmed: true)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "music.note.list").font(.system(size: 48)).foregroundColor(.gray)
                        Text(L("Brak aktywnej prezentacji")).font(.title2).foregroundColor(.gray)
                        if let upcoming = stage.nextSongTitle {
                            Text(L("Następnie: {0}", upcoming)).font(.title3).foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.black)
        .foregroundColor(.white)
    }

    private func header(_ stage: MusicianStage) -> some View {
        ViewThatFits(in: .horizontal) {
            headerContent(stage, compact: false)
            headerContent(stage, compact: true)
        }
    }

    /// Wersja skrócona dla wąskiego okna: bez opisów przy przyciskach i bez zegara.
    private func headerContent(_ stage: MusicianStage, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.songTitle.isEmpty ? L("Ekran dla muzyków") : stage.songTitle)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !stage.key.isEmpty {
                        Text(L("Tonacja: {0}", stage.key)).foregroundColor(.orange)
                    }
                    if let label = stage.current?.label {
                        Text("\(label) · \(stage.position)").foregroundColor(.gray)
                    }
                    if stage.isBlackScreen {
                        Text(L("CZARNY EKRAN")).foregroundColor(.red)
                    } else if stage.isClearText {
                        Text(L("TEKST UKRYTY")).foregroundColor(.yellow)
                    }
                    if stage.current != nil && !stage.hasChords {
                        Text(L("Brak chwytów dla tej pieśni")).foregroundColor(.gray)
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            control(compact ? "♯♭" : L("Transpozycja"), value: stage.semitones > 0 ? "+\(stage.semitones)" : "\(stage.semitones)") { delta in
                store.settings.musicianTranspose = (store.settings.musicianTranspose + delta) % 12
                store.saveSettings()
            }
            control(compact ? "A" : L("Czcionka"), value: "\(Int(store.settings.musicianFontSize))") { delta in
                store.settings.musicianFontSize = min(80, max(14, store.settings.musicianFontSize + Double(delta * 2)))
                store.saveSettings()
            }
            if !compact {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, style: .time).font(.system(size: 18, weight: .semibold, design: .monospaced)).foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func control(_ title: String, value: String, change: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundColor(.gray).fixedSize()
            Button("−") { change(-1) }
            Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced)).frame(minWidth: 28)
            Button("+") { change(1) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func slideView(_ slide: MusicianStage.Slide, size: CGFloat, dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: size * 0.15) {
            Text(slide.label)
                .font(.system(size: max(11, size * 0.45), weight: .bold))
                .foregroundColor(dimmed ? .gray : .orange.opacity(0.8))
            ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 0) {
                    if let chords = line.chords {
                        Text(chords)
                            .font(.system(size: size, weight: .bold, design: .monospaced))
                            .foregroundColor(dimmed ? .orange.opacity(0.55) : .orange)
                    }
                    if !line.text.isEmpty {
                        Text(line.text)
                            .font(.system(size: size, weight: .regular, design: .monospaced))
                            .foregroundColor(dimmed ? .gray : .white)
                    }
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            if let borrowed = slide.borrowedFrom {
                Text(L("Chwyty jak w: {0}", borrowed))
                    .font(.system(size: max(11, size * 0.4)))
                    .foregroundColor(.gray)
            }
        }
    }

    /// Czcionka z ustawień, zmniejszona tak, żeby najdłuższy wiersz zmieścił się w szerokości,
    /// a bieżący slajd z podglądem następnego (70%) w wysokości okna, bez przewijania.
    private func fittedSize(current: MusicianStage.Slide, next: MusicianStage.Slide?, in available: CGSize) -> CGFloat {
        func rows(_ slide: MusicianStage.Slide) -> CGFloat {
            CGFloat(slide.lines.reduce(0) { $0 + ($1.chords == nil ? 0 : 1) + ($1.text.isEmpty ? 0 : 1) }) + 0.6
                + (slide.borrowedFrom == nil ? 0 : 0.5)
        }
        let longest = [current, next].compactMap { $0 }.flatMap(\.lines).flatMap { [$0.chords ?? "", $0.text] }.map(\.count).max() ?? 1
        let widthFit = available.width / (CGFloat(max(longest, 1)) * 0.61)
        let totalRows = rows(current) * 1.3 + (next.map { rows($0) * 0.7 * 1.3 + 1.6 } ?? 0)
        let heightFit = available.height / max(totalRows, 1)
        return max(10, min(CGFloat(store.settings.musicianFontSize), widthFit, heightFit))
    }
}

// MARK: - Musician Window

/// Okno „Ekran dla muzyków”: zwykłe okno do przeniesienia na monitor muzyków (i pełny ekran).
@MainActor
public final class MusicianWindowManager: ObservableObject {
    public static let shared = MusicianWindowManager()
    @Published public private(set) var isOpen = false
    private var window: NSWindow?
    private var closeObserver: (any NSObjectProtocol)?

    public func toggle() {
        if let window {
            window.close()
        } else {
            open()
        }
    }

    public func open() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Na monitorze innym niż okno główne i projekcja, jeśli taki jest.
        let used = Set([NSApp.mainWindow?.screen, ScreenManager.shared.presentationWindow?.screen].compactMap { $0 })
        let screen = NSScreen.screens.first { !used.contains($0) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1100, height: 750)
        let size = NSSize(width: min(1100, frame.width - 80), height: min(750, frame.height - 80))
        let window = NSWindow(
            contentRect: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = Lnow("Ekran dla muzyków")
        window.minSize = NSSize(width: 500, height: 320)
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = NSHostingController(rootView: MusicianView())
        window.isReleasedWhenClosed = false
        // Jeden obserwator na okno, usuwany przy zamknięciu (R4-19).
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] notification in
            let closed = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, closed == self.window.map(ObjectIdentifier.init) else { return }
                if let observer = self.closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                self.closeObserver = nil
                self.window = nil
                self.isOpen = false
            }
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window
        isOpen = true
    }

    /// Tytuł okna po zmianie języka (R4-20).
    public func updateTitle() {
        window?.title = Lnow("Ekran dla muzyków")
    }
}
