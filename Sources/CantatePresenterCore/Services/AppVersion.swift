import Foundation

// MARK: - App Version

/// Wersja aplikacji z Info.plist; `build_app.sh` wpisuje ją z pliku `VERSION` (N10).
public enum AppVersion {
    public static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
