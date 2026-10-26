import Foundation
import AppKit

// MARK: - Display Descriptor

/// Ekran opisany niezależnie od kolejności w `NSScreen.screens`.
public struct DisplayDescriptor: Equatable {
    public let id: UInt32
    public let name: String
    public let isPrimary: Bool
    
    public init(id: UInt32, name: String, isPrimary: Bool) {
        self.id = id
        self.name = name
        self.isPrimary = isPrimary
    }
    
    @MainActor
    public init(_ screen: NSScreen, isPrimary: Bool) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.init(id: number?.uint32Value ?? 0, name: screen.localizedName, isPrimary: isPrimary)
    }
}

// MARK: - Screen Selection

/// Wybór ekranu projekcji (S1). Ekran jest zapamiętywany po identyfikatorze (`CGDirectDisplayID`) i nazwie,
/// a nie po pozycji na liście, która zmienia się po odłączeniu i podłączeniu kabla.
public enum ScreenSelection {
    public struct Saved: Equatable {
        public var id: UInt32?
        public var name: String?
        /// Indeks z wcześniejszych wersji ustawień.
        public var legacyIndex: Int
        
        public init(id: UInt32?, name: String?, legacyIndex: Int) {
            self.id = id
            self.name = name
            self.legacyIndex = legacyIndex
        }
    }
    
    public enum Placement: Equatable {
        case show(Int)
        /// Ekranu projekcji nie ma: okno projekcji ukryte, nie przenoszone na ekran operatora.
        case hide
    }
    
    /// Indeks ekranu, na którym ma ruszyć projekcja.
    public static func resolve(_ screens: [DisplayDescriptor], saved: Saved) -> Int? {
        guard !screens.isEmpty else { return nil }
        if screens.count == 1 {
            return 0
        }
        if let id = saved.id, let index = screens.firstIndex(where: { $0.id == id }) {
            return index
        }
        if let name = saved.name, let index = screens.firstIndex(where: { $0.name == name }) {
            return index
        }
        if saved.id == nil, saved.name == nil, screens.indices.contains(saved.legacyIndex) {
            return saved.legacyIndex
        }
        // Zapamiętanego ekranu nie ma: zewnętrzny ekran, a nie ekran operatora.
        return screens.firstIndex(where: { !$0.isPrimary }) ?? 0
    }
    
    /// Gdzie ma być okno projekcji po zmianie konfiguracji ekranów.
    public static func placement(after screens: [DisplayDescriptor], presentingOn display: DisplayDescriptor) -> Placement {
        if let index = screens.firstIndex(where: { $0.id == display.id }) {
            return .show(index)
        }
        if let index = screens.firstIndex(where: { $0.name == display.name }) {
            return .show(index)
        }
        return .hide
    }
    
    /// Czy okno projekcji ma po starcie przejąć klawiaturę (R4-02). Tylko gdy zasłania okno główne
    /// (ten sam ekran). Na osobnym projektorze klawiatura zostaje w oknie głównym, więc pierwsze Esc
    /// operatora gasi tekst zamiast zamykać okno projekcji przed zgromadzeniem.
    public static func presentationWindowTakesKeyboard(projector: UInt32, operatorScreen: UInt32?) -> Bool {
        guard let operatorScreen else { return true }
        return operatorScreen == projector
    }
}
