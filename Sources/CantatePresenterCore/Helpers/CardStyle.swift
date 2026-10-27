import SwiftUI
import AppKit

// MARK: - Card Style

extension View {
    /// Karta: tło, zaokrąglenie i obrys także w spoczynku. W wyglądzie macOS 26+ `controlBackgroundColor`
    /// jest prawie tak jasne jak tło okna, więc bez obrysu karta zlewa się z tłem (R5-02, R12-09).
    /// `strokeBorder` rysuje obrys wewnątrz kształtu i po przycięciu, więc nie traci zewnętrznej połowy (R12-08).
    func cardStyle(
        fill: Color = Color(NSColor.controlBackgroundColor),
        cornerRadius: CGFloat,
        outline: Color = Color(NSColor.separatorColor),
        lineWidth: CGFloat = 1
    ) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(outline, lineWidth: lineWidth)
            )
    }
}

// MARK: - Slide Type Badge

extension SlideType {
    /// Kolor znaczka typu slajdu (karty slajdów, podgląd w edytorze).
    var badgeColor: Color {
        switch self {
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

    /// Na jasnym żółtym i miętowym biały tekst był słabo czytelny w obu trybach; tam ciemny (R12-09).
    var badgeTextColor: Color {
        switch self {
        case .tag, .interlude: return Color.black.opacity(0.8)
        default: return .white
        }
    }
}
