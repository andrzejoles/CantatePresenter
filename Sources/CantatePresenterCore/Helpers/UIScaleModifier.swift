import Foundation
import SwiftUI

extension Font {
    public static func scaled(
        _ baseSize: CGFloat,
        weight: Font.Weight = .regular,
        scale: Double = 1.0,
        isMonospaced: Bool = false
    ) -> Font {
        return Font.system(
            size: baseSize * CGFloat(scale),
            weight: weight,
            design: isMonospaced ? .monospaced : .default
        )
    }
}
