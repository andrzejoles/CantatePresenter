import Foundation
import SwiftUI

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    public var uiScale: Double {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

extension View {
    public func applyUIScale(_ scale: Double) -> some View {
        self.environment(\.uiScale, scale)
    }
}

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
