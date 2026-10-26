import Foundation
import SwiftUI

public struct SongSlidesView: View {
    @Bindable var store = DataStore.shared
    @Binding var isShowingEditor: Bool
    @Binding var songToEdit: Song?
    
    /// Pieśń, dla której otwarto okno chwytów. Zapamiętana przy otwarciu: zaznaczenie może się zmienić
    /// w trakcie (pilot, przejście do następnej pieśni), a chwyty nie mogą trafić do innej pieśni (R8-05).
    @State private var chordsTarget: Song?
    
    public init(isShowingEditor: Binding<Bool>, songToEdit: Binding<Song?>) {
        self._isShowingEditor = isShowingEditor
        self._songToEdit = songToEdit
    }
    
    private var selectedSong: Song? {
        return store.selectedSong
    }
    
    // MARK: - Header
    
    private func songTitleBlock(_ song: Song, scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(song.title)
                    .font(.scaled(18, weight: .bold, scale: scale))
                    .lineLimit(2)
                
                if !song.key.isEmpty {
                    Text(song.key)
                        .font(.scaled(12, weight: .bold, scale: scale))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                        .fixedSize()
                }
            }
            
            if !song.author.isEmpty {
                Text(song.displayAuthor)
                    .font(.scaled(12, scale: scale))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    /// Przyciski pieśni; `compact` zostawia same ikony (pełna nazwa w podpowiedzi).
    private func songButtons(_ song: Song, scale: Double, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                store.present(song: song, slideIndex: 0)
            }) {
                headerLabel(L("Prezentuj"), icon: "play.fill", compact: compact)
                    .font(.scaled(12, weight: .semibold, scale: scale))
            }
            .buttonStyle(.borderedProminent)
            .help(L("Prezentuj"))
            
            Button(action: {
                store.addSongToPlan(songId: song.id)
            }) {
                headerLabel(L("+ Do planu"), icon: "text.badge.plus", compact: compact)
                    .font(.scaled(12, scale: scale))
            }
            .buttonStyle(.bordered)
            .help(L("+ Do planu"))
            
            Button(action: {
                chordsTarget = song
            }) {
                headerLabel(song.chords != nil ? L("Chwyty (✓)") : L("Chwyty"), icon: "guitars", compact: compact)
                    .font(.scaled(12, scale: scale))
            }
            .buttonStyle(.bordered)
            .tint(song.chords != nil ? .orange : .secondary)
            .help(song.chords != nil ? L("Chwyty (✓)") : L("Chwyty"))
            
            Button(action: {
                songToEdit = song
                isShowingEditor = true
            }) {
                headerLabel(L("Edytuj pieśń i chwyty"), icon: "pencil.line", compact: compact)
                    .font(.scaled(12, weight: .medium, scale: scale))
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("e", modifiers: [.command])
            .help(L("Edytuj słowa, sekcje i chwyty wybranej pieśni (⌘E)"))
        }
        .fixedSize()
    }
    
    @ViewBuilder
    private func headerLabel(_ title: String, icon: String, compact: Bool) -> some View {
        if compact {
            Label(title, systemImage: icon).labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: icon)
        }
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            if let song = selectedSong {
                VStack(spacing: 0) {
                    // Live Presentation Alert Banner (when viewing/editing another song)
                    if store.isLive, let liveSong = store.activeSong, liveSong.id != song.id {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(L("PROJEKTOR: Trwa projekcja '{0}' (slajd {1}/{2})", liveSong.title, store.activeSlideIndex + 1, liveSong.slides.count))
                                .font(.scaled(11, weight: .bold, scale: scale))
                                .foregroundColor(.red)
                            Spacer()
                            Button(L("Wróć do prezentowanej pieśni")) {
                                store.selectedSongId = liveSong.id
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.12))
                        
                        Divider()
                    }
                    
                    // Header of the selected song. Przy wąskim panelu przyciski schodzą pod tytuł, a potem
                    // zostają same ikony; wcześniej zbyt szeroki wiersz był ucinany z obu stron, także tytuł.
                    VStack(alignment: .leading, spacing: 6) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top) {
                                songTitleBlock(song, scale: scale)
                                Spacer(minLength: 12)
                                songButtons(song, scale: scale, compact: false)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                songTitleBlock(song, scale: scale)
                                songButtons(song, scale: scale, compact: false)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                songTitleBlock(song, scale: scale)
                                songButtons(song, scale: scale, compact: true)
                            }
                        }
                        
                        if !song.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(song.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.scaled(10, scale: scale))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12))
                                            .foregroundColor(.secondary)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    Divider()
                    
                    // Slide cards list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            let hints = song.slideShortcutHints
                            ForEach(Array(song.slides.enumerated()), id: \.element.id) { index, slide in
                                let isCurrentLive = (store.activeSong?.id == song.id) &&
                                                    (store.activeSlideIndex == index) &&
                                                    store.isLive
                                
                                SlideCardView(
                                    slide: slide,
                                    shortcutHint: hints[index],
                                    isLive: isCurrentLive,
                                    scale: scale,
                                    onSelect: {
                                        store.present(song: song, slideIndex: index)
                                    }
                                )
                            }
                        }
                        .padding(14)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(L("Wybierz pieśń z biblioteki po lewej stronie"))
                        .font(.scaled(14, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .sheet(item: $chordsTarget) { song in
            ChordsSearchSheet(
                song: song,
                isPresented: Binding(get: { chordsTarget != nil }, set: { if !$0 { chordsTarget = nil } }),
                onApply: { newChords, newKey in
                    // Bieżąca wersja tej samej pieśni, żeby nie cofnąć zmian zapisanych w międzyczasie.
                    var updated = store.songs.first(where: { $0.id == song.id }) ?? song
                    updated.chords = newChords
                    if !newKey.isEmpty && updated.key.isEmpty {
                        updated.key = newKey
                    }
                    store.updateSong(updated)
                }
            )
        }
    }
}

// MARK: - Slide Card
private struct SlideCardView: View {
    let slide: SongSlide
    /// Klawisz, który przechodzi do tego slajdu (R4-03); `nil`: brak znaczka.
    let shortcutHint: String?
    let isLive: Bool
    let scale: Double
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card header
            HStack {
                // Type Badge
                HStack(spacing: 4) {
                    Text(slide.type.shortBadge)
                        .font(.scaled(10, weight: .bold, scale: scale))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColorForType(slide.type))
                        .foregroundColor(.white)
                        .cornerRadius(3)
                    
                    Text(slide.displayLabel)
                        .font(.scaled(12, weight: .bold, scale: scale))
                        .foregroundColor(isLive ? .green : .primary)
                }
                
                Spacer()
                
                // Shortcut badge
                if let shortcutHint {
                    Text("[\(shortcutHint)]")
                        .font(.scaled(10, scale: scale, isMonospaced: true))
                        .foregroundColor(.secondary)
                        .help(L("Kliknij lub naciśnij {0}", shortcutHint))
                }
                
                if isLive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(L("NA EKRANIE"))
                            .font(.scaled(10, weight: .bold, scale: scale))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(4)
                }
            }
            
            // Text Content
            Text(slide.text)
                .font(.scaled(14, scale: scale))
                .foregroundColor(isLive ? .primary : .primary.opacity(0.9))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(isLive ? Color.green.opacity(0.08) : (isHovered ? Color.secondary.opacity(0.08) : Color(NSColor.controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isLive ? Color.green : (isHovered ? Color.secondary.opacity(0.3) : Color.clear), lineWidth: isLive ? 2.5 : 1)
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func badgeColorForType(_ type: SlideType) -> Color {
        switch type {
        case .chorus: return .orange
        case .verse: return .blue
        case .bridge: return .purple
        case .preChorus: return .teal
        case .coda: return .pink
        case .interlude: return .mint
        case .ending: return .brown
        case .intro, .outro: return .gray
        case .tag: return .yellow
        default: return .indigo
        }
    }
}
