import Foundation
import AppKit

public struct AutoFitEngine {
    
    // MARK: - Cache (S2)
    
    /// Wynik zależy tylko od tych parametrów, więc ten sam slajd w tym samym oknie liczymy raz,
    /// zamiast przy każdym przerysowaniu projekcji i podglądów.
    private struct CacheKey: Hashable {
        let text: String
        let width: Int
        let height: Int
        let fontFamily: String
        let isBold: Bool
        let lineSpacingFactor: Double
        let marginPercent: Double
        let minFontSize: CGFloat
        let maxFontSize: CGFloat
    }
    
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [CacheKey: CGFloat] = [:]
    private static let cacheLimit = 512
    
    public static func clearCache() {
        cacheLock.withLock { cache.removeAll() }
    }
    
    /// Computes the optimal font size to fill the container without clipping or overflowing.
    public static func calculateOptimalFontSize(
        for text: String,
        containerSize: CGSize,
        fontFamily: String = "Helvetica Neue",
        isBold: Bool = true,
        lineSpacingFactor: Double = 1.15,
        marginPercent: Double = 0.07,
        minFontSize: CGFloat = 14.0,
        maxFontSize: CGFloat = 260.0
    ) -> CGFloat {
        let key = CacheKey(
            text: text,
            width: Int(containerSize.width.rounded()),
            height: Int(containerSize.height.rounded()),
            fontFamily: fontFamily,
            isBold: isBold,
            lineSpacingFactor: lineSpacingFactor,
            marginPercent: marginPercent,
            minFontSize: minFontSize,
            maxFontSize: maxFontSize
        )
        if let cached = cacheLock.withLock({ cache[key] }) {
            return cached
        }
        let size = computeOptimalFontSize(
            for: text,
            containerSize: containerSize,
            fontFamily: fontFamily,
            isBold: isBold,
            lineSpacingFactor: lineSpacingFactor,
            marginPercent: marginPercent,
            minFontSize: minFontSize,
            maxFontSize: maxFontSize
        )
        cacheLock.withLock {
            if cache.count >= cacheLimit {
                cache.removeAll(keepingCapacity: true)
            }
            cache[key] = size
        }
        return size
    }
    
    private static func computeOptimalFontSize(
        for text: String,
        containerSize: CGSize,
        fontFamily: String,
        isBold: Bool,
        lineSpacingFactor: Double,
        marginPercent: Double,
        minFontSize: CGFloat,
        maxFontSize: CGFloat
    ) -> CGFloat {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 48.0
        }
        guard containerSize.width > 50 && containerSize.height > 50 else {
            return 24.0
        }
        
        let usableWidth = max(40.0, containerSize.width * CGFloat(1.0 - 2.0 * marginPercent))
        let usableHeight = max(40.0, containerSize.height * CGFloat(1.0 - 2.0 * marginPercent))
        
        var low: CGFloat = minFontSize
        var high: CGFloat = maxFontSize
        var bestFit: CGFloat = minFontSize
        
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        // Binary search for optimal size
        for _ in 0..<12 {
            let mid = (low + high) / 2.0
            if mid < minFontSize { break }
            
            let font = makeFont(name: fontFamily, size: mid, isBold: isBold)
            
            // Check word clipping: each word must fit inside usableWidth
            var wordExceedsWidth = false
            for word in words {
                let wordSize = (word as NSString).size(withAttributes: [.font: font])
                if wordSize.width > usableWidth {
                    wordExceedsWidth = true
                    break
                }
            }
            
            if wordExceedsWidth {
                high = mid
                continue
            }
            
            // Calculate multi-line paragraph size
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.lineSpacing = mid * CGFloat(lineSpacingFactor - 1.0)
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
            
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let boundingBox = attributed.boundingRect(
                with: CGSize(width: usableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            
            if boundingBox.height <= usableHeight && boundingBox.width <= usableWidth + 2.0 {
                bestFit = mid
                low = mid // Try larger
            } else {
                high = mid // Try smaller
            }
        }
        
        return max(minFontSize, floor(bestFit))
    }
    
    public static func makeFont(name: String, size: CGFloat, isBold: Bool) -> NSFont {
        let fontManager = NSFontManager.shared
        
        if let baseFont = NSFont(name: name, size: size) {
            if isBold {
                let boldFont = fontManager.convert(baseFont, toHaveTrait: .boldFontMask)
                return boldFont
            }
            return baseFont
        }
        
        // Fallback to system font
        return isBold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }
    
    public static func availableSystemFonts() -> [String] {
        let families = NSFontManager.shared.availableFontFamilies
        return families.sorted()
    }
}
