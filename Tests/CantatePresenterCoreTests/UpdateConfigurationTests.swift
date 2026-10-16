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
    }
}
