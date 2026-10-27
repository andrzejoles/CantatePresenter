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

    @Test("Projekcja na ekranie operatora wyłącza pozycje otwierające arkusz, panel albo okno (R8-02)")
    func projectionOnOperatorScreenDisablesWindows() {
        let opening = ["quickTextAction", "importAction", "createBackupAction", "restoreBackupAction", "focusSongSearchAction",
                       "undoRestoreAction", "exportJSONAction", "exportFolderAction", "openUserManualAction", "showAboutPanelAction",
                       "installToApplicationsAction", "checkForUpdates:", "openInstructionMarkdownAction", "openGitHubProjectAction"]
        for action in opening {
            #expect(!AppDelegate.isMenuItemEnabled(action: NSSelectorFromString(action), hasAttachedSheet: false, canUndoRestore: true, presentationCoversMainWindow: true), "\(action)")
            #expect(AppDelegate.isMenuItemEnabled(action: NSSelectorFromString(action), hasAttachedSheet: false, canUndoRestore: true, presentationCoversMainWindow: false), "\(action)")
        }
        // Zoom, edycja i zakończenie programu (z widocznym pytaniem) zostają.
        for action in ["zoomInAction", "copy:", "terminate:"] {
            #expect(AppDelegate.isMenuItemEnabled(action: NSSelectorFromString(action), hasAttachedSheet: false, canUndoRestore: true, presentationCoversMainWindow: true), "\(action)")
        }
    }
}

// MARK: - R4-18: zamykanie w trakcie projekcji

@MainActor
@Suite("Zamykanie w trakcie projekcji (R4-18)")
struct QuitWhileLiveTests {
    @Test("Pytanie, gdy tekst jest na ekranie albo okno projekcji jest otwarte")
    func asksWhileLive() {
        #expect(AppDelegate.needsQuitConfirmation(isLive: true, isPresentationActive: false, alreadyConfirmed: false))
        #expect(AppDelegate.needsQuitConfirmation(isLive: false, isPresentationActive: true, alreadyConfirmed: false))
    }

    @Test("Bez pytania poza projekcją i po potwierdzeniu przy zamykaniu okna głównego")
    func noQuestion() {
        #expect(!AppDelegate.needsQuitConfirmation(isLive: false, isPresentationActive: false, alreadyConfirmed: false))
        #expect(!AppDelegate.needsQuitConfirmation(isLive: true, isPresentationActive: true, alreadyConfirmed: true))
    }
}
