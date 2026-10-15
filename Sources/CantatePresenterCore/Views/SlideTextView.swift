import Foundation
import SwiftUI
import AppKit

// MARK: - Slide Text View

/// Tekst slajdu rysowany tak samo w projekcji i w podglądach (N1).
///
/// Czcionka to ten sam `NSFont`, który mierzy `AutoFitEngine`, więc rozmiar dobrany przez Auto-Fit
/// zawsze odpowiada temu, co widać. `scaleFactor` skaluje cień w podglądach (1 = ekran projekcji).
public struct SlideTextView: View {
    public let text: String
    public let settings: AppSettings
    public let fontSize: CGFloat
    public let containerSize: CGSize
    public var scaleFactor: CGFloat = 1.0
    public var isDimmed: Bool = false
    /// Informacja o prawach autorskich (CCLI) drobnym drukiem przy dolnej krawędzi; nie wpływa na Auto-Fit.
    public var footer: String? = nil
    
    public init(text: String, settings: AppSettings, fontSize: CGFloat, containerSize: CGSize, scaleFactor: CGFloat = 1.0, isDimmed: Bool = false, footer: String? = nil) {
        self.text = text
        self.settings = settings
        self.fontSize = fontSize
        self.containerSize = containerSize
        self.scaleFactor = scaleFactor
        self.isDimmed = isDimmed
        self.footer = footer
    }
    
    public var body: some View {
        let alignment = SlideAlignment(settings.textAlignment)
        let shadowRadius = max(0.5, 4.0 * scaleFactor)
        let shadowOffset = max(0.5, 2.0 * scaleFactor)
        
        VStack(alignment: alignment.horizontal) {
            if settings.verticalAlignment == .bottom {
                Spacer()
            }
            
            Text(text)
                .font(Self.font(settings: settings, size: fontSize))
                .foregroundColor(Color(hex: settings.textColorHex).opacity(isDimmed ? 0.65 : 1.0))
                .multilineTextAlignment(alignment.text)
                .lineSpacing(fontSize * CGFloat(settings.lineSpacingFactor - 1.0))
                .shadow(
                    color: settings.hasShadow ? Color.black.opacity(isDimmed ? 0.4 : 0.85) : Color.clear,
                    radius: shadowRadius,
                    x: shadowOffset,
                    y: shadowOffset
                )
                .frame(maxWidth: .infinity, alignment: alignment.frame)
                .padding(.horizontal, containerSize.width * CGFloat(settings.marginPercent))
                .padding(.vertical, containerSize.height * CGFloat(settings.marginPercent))
            
            if settings.verticalAlignment == .top {
                Spacer()
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .overlay(alignment: .bottom) {
            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: max(5, containerSize.height * 0.022)))
                    .foregroundColor(Color(hex: settings.textColorHex).opacity(isDimmed ? 0.45 : 0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, containerSize.width * 0.04)
                    .padding(.bottom, containerSize.height * 0.012)
            }
        }
    }
    
    /// Ta sama czcionka co w pomiarze Auto-Fit.
    public static func font(settings: AppSettings, size: CGFloat) -> Font {
        Font(AutoFitEngine.makeFont(name: settings.fontFamily, size: size, isBold: settings.isBold))
    }
}

// MARK: - Slide Alignment

/// Wyrównanie z ustawień w trzech postaciach SwiftUI.
public struct SlideAlignment: Equatable {
    public let horizontal: HorizontalAlignment
    public let text: TextAlignment
    public let frame: Alignment
    
    public init(_ value: HorizontalTextAlignment) {
        switch value {
        case .left:
            (horizontal, text, frame) = (.leading, .leading, .leading)
        case .right:
            (horizontal, text, frame) = (.trailing, .trailing, .trailing)
        case .center:
            (horizontal, text, frame) = (.center, .center, .center)
        }
    }
}
