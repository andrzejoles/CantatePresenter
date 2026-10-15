import Foundation
import Testing
@testable import CantatePresenterCore

// MARK: - N4: dyktowanie

@Suite("Dyktowanie (N4)")
struct DictationTests {
    @Test("Wynik końcowy oddawany dokładnie raz na sesję")
    func finalDeliveredOnce() {
        var delivered: [String] = []
        var session = DictationFinalDelivery()
        session.start()

        session.deliver("Pan jest moim pasterzem") { delivered.append($0) }
        session.deliver("Pan jest moim pasterzem") { delivered.append($0) }

        #expect(delivered == ["Pan jest moim pasterzem"])
    }

    @Test("Pusty tekst nie jest oddawany; nowa sesja znowu pozwala oddać wynik")
    func emptyAndNewSession() {
        var delivered: [String] = []
        var session = DictationFinalDelivery()
        session.start()
        session.deliver("") { delivered.append($0) }
        session.deliver("Alleluja") { delivered.append($0) }
        session.start()
        session.deliver("Amen") { delivered.append($0) }

        #expect(delivered == ["Alleluja", "Amen"])
    }

    @Test("Domyślnie rozpoznawanie jak przed N4 (z serwerem Apple); stare ustawienia bez pola też")
    func onDeviceDefault() throws {
        #expect(!AppSettings().dictationOnDeviceOnly)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"dictationLanguage":"pl-PL"}"#.utf8))
        #expect(!old.dictationOnDeviceOnly)
    }
}

@Suite("Dyktowanie: powrót do serwera Apple (N4)")
struct DictationFallbackTests {
    @Test("Lokalne rozpoznawanie zawiodło przed pierwszym słowem: ponowienie przez serwer")
    func retriesWhenOnDeviceFailsEarly() {
        #expect(DictationFallback.shouldRetryWithServer(usedOnDevice: true, recognizedText: "", alreadyRetried: false))
    }

    @Test("Bez ponowienia: tekst już rozpoznany, tryb serwerowy albo drugie podejście")
    func noRetry() {
        #expect(!DictationFallback.shouldRetryWithServer(usedOnDevice: true, recognizedText: "Pan", alreadyRetried: false))
        #expect(!DictationFallback.shouldRetryWithServer(usedOnDevice: false, recognizedText: "", alreadyRetried: false))
        #expect(!DictationFallback.shouldRetryWithServer(usedOnDevice: true, recognizedText: "", alreadyRetried: true))
    }
}
