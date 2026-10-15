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
            let bgColor = Color(hex: settings.backgroundColorHex)
            
            ZStack {
                bgColor
                
                if isDimmed {
                    Color.black.opacity(0.22)
                }
                
                SlideTextView(
                    text: text,
                    settings: settings,
                    fontSize: previewFontSize,
                    containerSize: size,
                    scaleFactor: scaleFactor,
                    isDimmed: isDimmed
                )
                
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
}

