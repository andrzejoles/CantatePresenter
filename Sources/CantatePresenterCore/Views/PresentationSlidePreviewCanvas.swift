import Foundation
import SwiftUI
import AppKit

/// Renders a slide exactly matching the presentation screen's layout, scaled proportionally to any container size.
public struct PresentationSlidePreviewCanvas: View {
    public let text: String
    public let targetScreenSize: CGSize
    public let settings: AppSettings
    public var isDimmed: Bool = false
    public var label: String? = nil
    
    public init(
        text: String,
        targetScreenSize: CGSize,
        settings: AppSettings,
        isDimmed: Bool = false,
        label: String? = nil
    ) {
        self.text = text
        self.targetScreenSize = targetScreenSize
        self.settings = settings
        self.isDimmed = isDimmed
        self.label = label
    }
    
    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let targetWidth = max(1.0, targetScreenSize.width)
            let scaleFactor = max(0.01, size.width / targetWidth)
            
            // Calculate optimal font size for the actual presentation display
            let targetOptimalSize = AutoFitEngine.calculateOptimalFontSize(
                for: text,
                containerSize: targetScreenSize,
                fontFamily: settings.fontFamily,
                isBold: settings.isBold,
                lineSpacingFactor: settings.lineSpacingFactor,
                marginPercent: settings.marginPercent
            )
            
            // Scale font size and layout metrics to match container proportionally
            let previewFontSize = max(5.0, targetOptimalSize * scaleFactor)
            let horizontalPadding = size.width * CGFloat(settings.marginPercent)
            let verticalPadding = size.height * CGFloat(settings.marginPercent)
            let lineSpacing = previewFontSize * CGFloat(settings.lineSpacingFactor - 1.0)
            let shadowRadius = max(0.5, 4.0 * scaleFactor)
            let shadowOffset = max(0.5, 2.0 * scaleFactor)
            
            let bgColor = Color(hex: settings.backgroundColorHex)
            let txtColor = Color(hex: settings.textColorHex)
            
            ZStack {
                bgColor
                
                if isDimmed {
                    Color.black.opacity(0.22)
                }
                
                VStack(alignment: alignmentForString(settings.textAlignment)) {
                    if settings.verticalAlignment == "bottom" {
                        Spacer()
                    }
                    
                    Text(text)
                        .font(customFont(name: settings.fontFamily, size: previewFontSize, isBold: settings.isBold))
                        .foregroundColor(txtColor.opacity(isDimmed ? 0.65 : 1.0))
                        .multilineTextAlignment(textAlignmentForString(settings.textAlignment))
                        .lineSpacing(lineSpacing)
                        .shadow(
                            color: settings.hasShadow ? Color.black.opacity(isDimmed ? 0.4 : 0.85) : Color.clear,
                            radius: shadowRadius,
                            x: shadowOffset,
                            y: shadowOffset
                        )
                        .frame(maxWidth: .infinity, alignment: frameAlignmentForString(settings.textAlignment))
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                    
                    if settings.verticalAlignment == "top" {
                        Spacer()
                    }
                }
                .frame(width: size.width, height: size.height)
                
                if let label = label {
                    VStack {
                        HStack {
                            Text(label)
                                .font(.system(size: max(8.0, min(14.0, 9.0 * scaleFactor * 3.5)), weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.65))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(max(4.0, 8.0 * scaleFactor * 3.0))
                }
            }
        }
    }
    
    private func customFont(name: String, size: CGFloat, isBold: Bool) -> Font {
        if name == "System" || name == "SF Pro" {
            return .system(size: size, weight: isBold ? .bold : .regular)
        }
        return .custom(name, size: size).weight(isBold ? .bold : .regular)
    }
    
    private func alignmentForString(_ alignment: String) -> HorizontalAlignment {
        switch alignment.lowercased() {
        case "left", "lewo": return .leading
        case "right", "prawo": return .trailing
        default: return .center
        }
    }
    
    private func textAlignmentForString(_ alignment: String) -> TextAlignment {
        switch alignment.lowercased() {
        case "left", "lewo": return .leading
        case "right", "prawo": return .trailing
        default: return .center
        }
    }
    
    private func frameAlignmentForString(_ alignment: String) -> Alignment {
        switch alignment.lowercased() {
        case "left", "lewo": return .leading
        case "right", "prawo": return .trailing
        default: return .center
        }
    }
}
