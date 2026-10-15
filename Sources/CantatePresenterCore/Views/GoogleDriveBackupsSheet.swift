import Foundation
import SwiftUI
import AppKit

public struct GoogleDriveBackupsSheet: View {
    @Bindable var store = DataStore.shared
    @Binding var isPresented: Bool
    
    @State private var remoteBackups: [RemoteBackupItem] = []
    @State private var isLoading: Bool = true
    @State private var isRestoring: Bool = false
    @State private var restoringFileId: String?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.icloud")
                        .font(.scaled(18, weight: .bold, scale: scale))
                        .foregroundColor(.blue)
                    Text(L("Kopie zapasowe na Dysku Google"))
                        .font(.scaled(16, weight: .bold, scale: scale))
                }
                Spacer()
                Button(L("Zamknij")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Subtitle & Folder
            HStack {
                Text(L("Folder na dysku: "))
                    .font(.scaled(11, weight: .medium, scale: scale))
                    .foregroundColor(.secondary)
                + Text(store.settings.googleDrive.targetFolder)
                    .font(.scaled(11, weight: .bold, scale: scale))
                
                Spacer()
                
                Button(action: {
                    Task { await loadBackups() }
                }) {
                    Label(L("Odśwież"), systemImage: "arrow.clockwise")
                        .font(.scaled(11, scale: scale))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Feedback alerts
            if let err = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.scaled(11, weight: .medium, scale: scale))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
            }
            
            if let succ = successMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(succ)
                        .font(.scaled(11, weight: .medium, scale: scale))
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
            }
            
            // Content
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L("Wczytywanie listy kopii zapasowych z Dysku Google..."))
                        .font(.scaled(12, scale: scale))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if remoteBackups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.scaled(36, scale: scale))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(L("Brak zapisanych kopii zapasowych w folderze '{0}'", store.settings.googleDrive.targetFolder))
                        .font(.scaled(13, weight: .medium, scale: scale))
                    Text(L("Kliknij 'Wyślij bieżący backup na Dysk Google' w Ustawieniach, aby utworzyć pierwszą kopię w chmurze."))
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(remoteBackups) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox.fill")
                            .font(.scaled(22, scale: scale))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.scaled(12, weight: .semibold, scale: scale))
                            
                            HStack(spacing: 12) {
                                Label(item.formattedDate, systemImage: "clock")
                                Label(item.formattedSize, systemImage: "doc")
                            }
                            .font(.scaled(10, scale: scale))
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if isRestoring && restoringFileId == item.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(action: {
                                Task { await restoreItem(item) }
                            }) {
                                Label(L("Przywróć tę kopię"), systemImage: "arrow.counterclockwise.circle.fill")
                                    .font(.scaled(11, weight: .medium, scale: scale))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isRestoring)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .task {
            await loadBackups()
        }
    }
    
    private func loadBackups() async {
        isLoading = true
        errorMessage = nil
        do {
            let items = try await GoogleDriveService.shared.listBackupsFromDrive()
            self.remoteBackups = items
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
    
    private func restoreItem(_ item: RemoteBackupItem) async {
        isRestoring = true
        restoringFileId = item.id
        errorMessage = nil
        successMessage = nil
        
        do {
            let manifest = try await GoogleDriveService.shared.restoreFromDrive(fileId: item.id, fileName: item.name)
            self.isRestoring = false
            self.restoringFileId = nil
            self.successMessage = L("Pomyślnie przywrócono stan programu z Dysku Google! (Pieśni: {0}, Plany: {1})", manifest.songsCount, manifest.plansCount)
        } catch {
            self.isRestoring = false
            self.restoringFileId = nil
            self.errorMessage = L("Błąd przywracania z Dysku Google: {0}", error.localizedDescription)
        }
    }
}
