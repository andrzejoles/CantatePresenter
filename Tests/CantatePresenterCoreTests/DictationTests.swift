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

@Suite("Dyktowanie: stan przycisku z usługi (R4-11)")
struct DictationOwnershipTests {
    private let button = UUID()

    @Test("Błąd przed startem nagrywania (np. brak mikrofonu) kończy sesję przycisku i zostawia przy nim komunikat")
    func errorBeforeRecordingEndsSession() {
        var ownership = DictationOwnership()
        ownership.start(button, isRetry: false)
        ownership.fail()
        #expect(ownership.active == nil)
        #expect(ownership.failed == button)
        ownership.clearError()
        #expect(ownership.failed == nil)
    }

    @Test("Ponowienie przez serwer Apple nie zmienia przycisku, który dyktuje")
    func serverRetryKeepsOwner() {
        var ownership = DictationOwnership()
        ownership.start(button, isRetry: false)
        ownership.start(nil, isRetry: true)
        #expect(ownership.active == button)
    }

    @Test("Nowa sesja innego przycisku czyści stary błąd; zatrzymanie kończy sesję")
    func newSessionAndStop() {
        var ownership = DictationOwnership()
        ownership.start(button, isRetry: false)
        ownership.fail()
        let other = UUID()
        ownership.start(other, isRetry: false)
        #expect(ownership.failed == nil && ownership.active == other)
        ownership.end()
        #expect(ownership.active == nil)
    }
}
