import Foundation
import SwiftUI
import AppKit

// MARK: - Resizable Sheet

/// Arkusz, którego rozmiar można zmieniać, przeciągając krawędź. SwiftUI w macOS tego nie pozwalał: treść miała
/// tylko `minWidth`/`minHeight`, a okno arkusza nie ma `.resizable`. Ostatni rozmiar zostaje w `UserDefaults`
/// (wygoda tego Maca, nie dane biblioteki) i jest rozmiarem przy następnym otwarciu.
struct ResizableSheetFrame: ViewModifier {
    let key: String
    let minSize: CGSize
    let defaultSize: CGSize

    init(id: String, minSize: CGSize, defaultSize: CGSize) {
        self.key = "sheetSize." + id
        self.minSize = minSize
        self.defaultSize = defaultSize
    }

    func body(content: Content) -> some View {
        let ideal = Self.idealSize(stored: UserDefaults.standard.string(forKey: key) ?? "", minSize: minSize, defaultSize: defaultSize)
        content
            .frame(
                minWidth: minSize.width, idealWidth: ideal.width, maxWidth: .infinity,
                minHeight: minSize.height, idealHeight: ideal.height, maxHeight: .infinity
            )
            .background(SheetWindowResizer(minSize: minSize, initialSize: ideal))
            // Zapis przy każdej zmianie rozmiaru: SwiftUI nie wywołuje `onDisappear` przy zamknięciu arkusza.
            // Prosto do `UserDefaults`, bez stanu widoku, żeby zapis nie przerysowywał arkusza w trakcie przeciągania.
            .background(GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size) { _, size in
                    if let value = Self.storedValue(for: size, minSize: minSize) {
                        UserDefaults.standard.set(value, forKey: key)
                    }
                }
            })
    }

    /// Zapamiętany rozmiar („szerokość x wysokość”), nie mniejszy niż minimum, a bez zapisu domyślny.
    nonisolated static func idealSize(stored: String, minSize: CGSize, defaultSize: CGSize) -> CGSize {
        let parts = stored.split(separator: "x").compactMap { Double($0) }
        let size = parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : defaultSize
        return CGSize(width: max(size.width, minSize.width), height: max(size.height, minSize.height))
    }

    /// Wartość do zapisu; `nil` dla rozmiaru, który nie pochodzi z wyświetlonego arkusza (zero przed pomiarem).
    nonisolated static func storedValue(for size: CGSize, minSize: CGSize) -> String? {
        guard size.width >= minSize.width - 1, size.height >= minSize.height - 1 else { return nil }
        return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}

/// Okno arkusza od SwiftUI nie ma `.resizable` w `styleMask`, nawet gdy treść jest elastyczna, więc krawędzi
/// nie dało się przeciągnąć. Dodajemy flagę i minimum, gdy widok trafi do okna.
private struct SheetWindowResizer: NSViewRepresentable {
    let minSize: CGSize
    /// Rozmiar przy otwarciu: SwiftUI bierze szerokość arkusza z treści i pomija `idealWidth`.
    let initialSize: CGSize

    func makeNSView(context: Context) -> ResizerView {
        let view = ResizerView()
        view.minSize = minSize
        view.initialSize = initialSize
        return view
    }

    func updateNSView(_ nsView: ResizerView, context: Context) {
        nsView.minSize = minSize
    }

    final class ResizerView: NSView {
        var minSize: CGSize = .zero
        var initialSize: CGSize = .zero
        private var didSetInitialSize = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Modyfikator stoi tylko na arkuszach. Okno arkusza nie jest tu jeszcze przyczepione (`isSheet` = false),
            // więc sprawdzenie `isSheet` pomijało je.
            guard let window, window !== AppDelegate.shared?.mainWindow else { return }
            window.styleMask.insert(.resizable)
            window.contentMinSize = minSize
            guard !didSetInitialSize else { return }
            didSetInitialSize = true
            let size = initialSize
            // Po pierwszym ułożeniu przez SwiftUI, inaczej nadpisałby rozmiar dopasowaniem do treści.
            DispatchQueue.main.async { [weak window] in
                window?.setContentSize(size)
            }
        }
    }
}

extension View {
    /// Arkusz z możliwością zmiany rozmiaru i zapamiętanym rozmiarem (`id` rozróżnia arkusze).
    func resizableSheet(_ id: String, minWidth: CGFloat, minHeight: CGFloat, idealWidth: CGFloat? = nil, idealHeight: CGFloat? = nil) -> some View {
        modifier(ResizableSheetFrame(
            id: id,
            minSize: CGSize(width: minWidth, height: minHeight),
            defaultSize: CGSize(width: idealWidth ?? minWidth, height: idealHeight ?? minHeight)
        ))
    }
}
