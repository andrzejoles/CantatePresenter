import AppKit
import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - R4-04: menu przy otwartym arkuszu

@MainActor
@Suite("Menu przy otwartym arkuszu (R4-04)")
struct MenuValidationTests {
    private func enabled(_ action: String, sheet: Bool, canUndo: Bool = true) -> Bool {
        AppDelegate.isMenuItemEnabled(action: NSSelectorFromString(action), hasAttachedSheet: sheet, canUndoRestore: canUndo)
    }

    @Test("Szybki tekst, import, kopia, przywracanie i szukanie są wyłączone przy otwartym arkuszu")
    func sheetDisablesItemsOpeningSheets() {
        for action in ["quickTextAction", "importAction", "createBackupAction", "restoreBackupAction", "focusSongSearchAction", "undoRestoreAction"] {
            #expect(!enabled(action, sheet: true), "\(action)")
            #expect(enabled(action, sheet: false), "\(action)")
        }
    }

    @Test("Cofnięcie przywracania zależy też od tego, czy jest co cofać")
    func undoRestoreNeedsBackup() {
        #expect(!enabled("undoRestoreAction", sheet: false, canUndo: false))
    }

    @Test("Pozycje edycji i eksportu nie zależą od arkusza")
    func otherItemsStayEnabled() {
        #expect(enabled("copy:", sheet: true))
        #expect(enabled("exportJSONAction", sheet: true))
    }
}
