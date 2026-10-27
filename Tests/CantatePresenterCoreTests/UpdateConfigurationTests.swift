import Foundation
import Testing
@testable import CantatePresenterCore

@Suite("Automatyczne aktualizacje (Sparkle)")
struct UpdateConfigurationTests {
    private let info: [String: Any] = [
        "SUFeedURL": "https://github.com/andrzejoles/CantatePresenter/releases/latest/download/appcast.xml",
        "SUPublicEDKey": "klucz"
    ]

    @Test("Kanał i klucz z Info.plist; bez klucza albo adresu aktualizacje wyłączone")
    func configuration() {
        #expect(UpdateConfiguration.from(infoDictionary: info, environment: [:]).isComplete)
        #expect(!UpdateConfiguration.from(infoDictionary: ["SUFeedURL": info["SUFeedURL"]!], environment: [:]).isComplete)
        #expect(!UpdateConfiguration.from(infoDictionary: ["SUPublicEDKey": "klucz"], environment: [:]).isComplete)
        #expect(!UpdateConfiguration.from(infoDictionary: nil, environment: [:]).isComplete)
        #expect(!UpdateConfiguration.from(infoDictionary: ["SUFeedURL": "file:///etc/appcast.xml", "SUPublicEDKey": "k"], environment: [:]).isComplete)
    }

    @Test("CANTATE_UPDATE_FEED zastępuje adres kanału (próby z lokalnym serwerem)")
    func environmentOverride() {
        let config = UpdateConfiguration.from(infoDictionary: info, environment: ["CANTATE_UPDATE_FEED": "http://127.0.0.1:8000/appcast.xml"])
        #expect(config.feedURL == "http://127.0.0.1:8000/appcast.xml")
        #expect(config.isComplete)
        // Sparkle dostaje adres z konfiguracji tylko, gdy różni się od Info.plist (R5-06).
        #expect(config.feedOverride(infoDictionary: info) == "http://127.0.0.1:8000/appcast.xml")
        #expect(UpdateConfiguration.from(infoDictionary: info, environment: [:]).feedOverride(infoDictionary: info) == nil)
    }

    /// Info.plist i podpis składane przez `build_app.sh` (R3-01, R3-09).
    private static let buildScript = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build_app.sh")

    @Test("Info.plist z build_app.sh: podpisany kanał i sprawdzenie archiwum przed rozpakowaniem")
    func signedFeedRequired() throws {
        let script = try String(contentsOf: Self.buildScript, encoding: .utf8)
        let start = try #require(script.range(of: "<?xml"))
        let end = try #require(script.range(of: "</plist>", range: start.upperBound..<script.endIndex))
        let plist = try PropertyListSerialization.propertyList(from: Data(script[start.lowerBound..<end.upperBound].utf8), format: nil)
        let info = try #require(plist as? [String: Any])
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(UpdateConfiguration.from(infoDictionary: info, environment: [:]).isComplete)
        #expect((info["SUFeedURL"] as? String)?.hasPrefix("https://") == true)
    }

    @Test("Podpis zawsze z Hardened Runtime, bez zmiennych DYLD_*")
    func hardenedRuntime() throws {
        let script = try String(contentsOf: Self.buildScript, encoding: .utf8)
        #expect(script.contains("SIGN_ARGS=(--force --options runtime --sign -)"))
        #expect(!script.contains("codesign --force --sign -"))
        #expect(!script.contains("com.apple.security.cs.allow-dyld-environment-variables"))
    }
}
