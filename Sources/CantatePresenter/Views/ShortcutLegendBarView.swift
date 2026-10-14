import Foundation
import SwiftUI
import AppKit

public struct ShortcutLegendBarView: View {
    @ObservedObject var store = DataStore.shared
    public let scale: Double
    
    public init(scale: Double) {
        self.scale = scale
    }
    
    public var body: some View {
        let shortcuts = store.settings.shortcuts
        let heightFactor = max(0.75, min(2.4, store.settings.bottomBarHeight / 70.0))
        
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: max(10, round(16 * heightFactor))) {
                    // Label hint
                    HStack(spacing: max(4, round(6 * heightFactor))) {
                        Image(systemName: "command")
                            .font(.system(size: round(11 * heightFactor), weight: .bold))
                            .foregroundColor(.secondary)
                        Text("SKRÓTY:")
                            .font(.scaled(round(9 * heightFactor), weight: .bold, scale: scale))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)
                    
                    Divider()
                        .frame(height: max(18, round(24 * heightFactor)))
                    
                    // Prev slide
                    KeyboardShortcutItemView(
                        iconName: "chevron.left.circle.fill",
                        iconColor: .blue,
                        keyCapText: shortKeyName(for: shortcuts.prevSlideKey),
                        label: loc(.prevSlide),
                        scale: scale,
                        heightFactor: heightFactor,
                        action: { store.prevSlide() }
                    )
                    
                    // Next slide
                    KeyboardShortcutItemView(
                        iconName: "chevron.right.circle.fill",
                        iconColor: .blue,
                        keyCapText: shortKeyName(for: shortcuts.nextSlideKey),
                        label: loc(.nextSlide),
                        scale: scale,
                        heightFactor: heightFactor,
                        action: { store.nextSlide() }
                    )
                    
                    Divider()
                        .frame(height: max(18, round(24 * heightFactor)))
                    
                    // Chorus
                    KeyboardShortcutItemView(
                        iconName: "music.note",
                        iconColor: .orange,
                        keyCapText: "R",
                        label: loc(.chorus),
                        scale: scale,
                        heightFactor: heightFactor,
                        action: { store.jumpToChorus() }
                    )
                    
                    // Verses
                    KeyboardShortcutItemView(
                        iconName: "text.list.number",
                        iconColor: .purple,
                        keyCapText: "1 – 9",
                        label: loc(.verse),
                        scale: scale,
                        heightFactor: heightFactor
                    )
                    
                    Divider()
                        .frame(height: max(18, round(24 * heightFactor)))
                    
                    // Black screen
                    KeyboardShortcutItemView(
                        iconName: "moon.fill",
                        iconColor: store.isBlackScreen ? .red : .primary,
                        keyCapText: shortKeyName(for: shortcuts.blackScreenKey),
                        label: loc(.blackScreen),
                        scale: scale,
                        heightFactor: heightFactor,
                        isActive: store.isBlackScreen,
                        action: { store.toggleBlackScreen() }
                    )
                    
                    // Clear text
                    KeyboardShortcutItemView(
                        iconName: "eye.slash.fill",
                        iconColor: store.isClearText ? .orange : .primary,
                        keyCapText: shortKeyName(for: shortcuts.clearTextKey),
                        label: loc(.clearText),
                        scale: scale,
                        heightFactor: heightFactor,
                        isActive: store.isClearText,
                        action: { store.toggleClearText() }
                    )
                    
                    Divider()
                        .frame(height: max(18, round(24 * heightFactor)))
                    
                    // Prev song in plan
                    KeyboardShortcutItemView(
                        iconName: "backward.end.alt.fill",
                        iconColor: .teal,
                        keyCapText: shortKeyName(for: shortcuts.prevSongKey),
                        label: loc(.prevSong),
                        scale: scale,
                        heightFactor: heightFactor,
                        action: { store.prevSongInPlan() }
                    )
                    
                    // Next song in plan
                    KeyboardShortcutItemView(
                        iconName: "forward.end.alt.fill",
                        iconColor: .teal,
                        keyCapText: shortKeyName(for: shortcuts.nextSongKey),
                        label: loc(.nextSong),
                        scale: scale,
                        heightFactor: heightFactor,
                        action: { store.nextSongInPlan() }
                    )
                    
                    Divider()
                        .frame(height: max(18, round(24 * heightFactor)))
                    
                    // Start presentation
                    KeyboardShortcutItemView(
                        iconName: "play.circle.fill",
                        iconColor: .green,
                        keyCapText: shortKeyName(for: shortcuts.startPresentationKey),
                        label: loc(.present),
                        scale: scale,
                        heightFactor: heightFactor,
                        action: {
                            if let song = store.selectedSong {
                                store.present(song: song, slideIndex: 0)
                            }
                        }
                    )
                    
                    // Stop presentation (Standby)
                    KeyboardShortcutItemView(
                        iconName: "stop.circle.fill",
                        iconColor: .gray,
                        keyCapText: shortKeyName(for: shortcuts.stopPresentationKey),
                        label: loc(.standby),
                        scale: scale,
                        heightFactor: heightFactor,
                        action: {
                            if NSScreen.screens.count == 1 && ScreenManager.shared.isPresentationActive {
                                ScreenManager.shared.stopPresentation()
                            }
                            store.stopLive()
                        }
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, max(4, round(6 * heightFactor)))
            }
            
            Divider()
                .frame(height: max(18, round(24 * heightFactor)))
            
            // Bar height adjuster on the right side
            HStack(spacing: 4) {
                Button(action: {
                    store.settings.bottomBarHeight = max(52, store.settings.bottomBarHeight - 10)
                    store.saveSettings()
                }) {
                    Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: max(9, round(10 * heightFactor))))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Zmniejsz wysokość paska")
                
                Button(action: {
                    store.settings.bottomBarHeight = 72.0
                    store.saveSettings()
                }) {
                    Text("\(Int(store.settings.bottomBarHeight))px")
                        .font(.scaled(max(8, round(9 * heightFactor)), scale: scale, isMonospaced: true))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Kliknij, aby przywrócić domyślną wysokość (72px)")
                
                Button(action: {
                    store.settings.bottomBarHeight = min(160, store.settings.bottomBarHeight + 10)
                    store.saveSettings()
                }) {
                    Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: max(9, round(10 * heightFactor))))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Zwiększ wysokość paska")
            }
            .padding(.trailing, 10)
            .padding(.leading, 4)
        }
        .frame(height: store.settings.bottomBarHeight)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func shortKeyName(for code: UInt16) -> String {
        switch code {
        case 49: return "Spacja"
        case 124: return "→"
        case 123: return "←"
        case 125: return "↓"
        case 126: return "↑"
        case 36: return "↵ Enter"
        case 53: return "Esc"
        case 11: return "B"
        case 8: return "C"
        case 15: return "R"
        case 30: return "]"
        case 33: return "["
        case 48: return "Tab"
        case 51: return "⌫"
        case 121: return "PgDn"
        case 116: return "PgUp"
        case 96: return "F5"
        case 97: return "F6"
        case 45: return "N"
        case 35: return "P"
        default: return "\(code)"
        }
    }
}

public struct KeyboardShortcutItemView: View {
    public let iconName: String
    public let iconColor: Color
    public let keyCapText: String
    public let label: String
    public let scale: Double
    public let heightFactor: Double
    public var isActive: Bool = false
    public var action: (() -> Void)? = nil
    
    @State private var isHovered: Bool = false
    
    public init(
        iconName: String,
        iconColor: Color,
        keyCapText: String,
        label: String,
        scale: Double,
        heightFactor: Double = 1.0,
        isActive: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.iconName = iconName
        self.iconColor = iconColor
        self.keyCapText = keyCapText
        self.label = label
        self.scale = scale
        self.heightFactor = heightFactor
        self.isActive = isActive
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            action?()
        }) {
            VStack(spacing: max(2, round(3.0 * heightFactor))) {
                Image(systemName: iconName)
                    .font(.system(size: round(13.0 * heightFactor), weight: .bold))
                    .foregroundColor(isActive ? .white : iconColor)
                
                Text(keyCapText)
                    .font(.system(size: round(10.0 * heightFactor), weight: .bold, design: .rounded))
                    .foregroundColor(isActive ? .white : .primary)
                    .padding(.horizontal, max(4, round(6.0 * heightFactor)))
                    .padding(.vertical, max(2, round(2.0 * heightFactor)))
                    .background(isActive ? Color.red : (isHovered ? Color.secondary.opacity(0.18) : Color(NSColor.controlBackgroundColor)))
                    .cornerRadius(max(3, round(4.0 * heightFactor)))
                    .overlay(
                        RoundedRectangle(cornerRadius: max(3, round(4.0 * heightFactor)))
                            .stroke(isActive ? Color.white.opacity(0.6) : Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
                
                Text(label)
                    .font(.scaled(max(8, round(9.0 * heightFactor)), scale: scale))
                    .foregroundColor(isActive ? .red : .secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: max(46, round(54.0 * heightFactor)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
        .help(action != nil ? "Kliknij lub naciśnij \(keyCapText)" : label)
    }
}
