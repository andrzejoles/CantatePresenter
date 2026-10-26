import Foundation
import Speech
import AVFoundation
import Combine
import os

@MainActor
public final class DictationService: ObservableObject {
    public static let shared = DictationService()
    
    @Published public var isRecording: Bool = false
    @Published public var currentRecognizedText: String = ""
    @Published public var errorMessage: String? = nil
    @Published public var isAuthorized: Bool = false
    /// Który przycisk dyktowania prowadzi sesję i przy którym pokazać błąd (R4-11).
    @Published public private(set) var ownership = DictationOwnership()
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var partialHandler: ((String) -> Void)?
    private var finalHandler: ((String) -> Void)?
    
    private init() {
        checkPermissions()
    }
    
    public func checkPermissions() {
        // Odpowiedź przychodzi w dowolnej kolejce: domknięcie @Sendable, stan zmieniany dopiero na głównym aktorze.
        SFSpeechRecognizer.requestAuthorization { @Sendable [weak self] authStatus in
            Task { @MainActor in
                switch authStatus {
                case .authorized:
                    self?.isAuthorized = true
                    self?.errorMessage = nil
                case .denied:
                    self?.isAuthorized = false
                    self?.errorMessage = Lnow("Odmówiono dostępu do rozpoznawania mowy w Ustawieniach systemowych.")
                case .restricted:
                    self?.isAuthorized = false
                    self?.errorMessage = Lnow("Rozpoznawanie mowy jest ograniczone na tym urządzeniu.")
                case .notDetermined:
                    self?.isAuthorized = false
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    private var usedOnDeviceRecognition = false
    /// Numer sesji: zdarzenia z anulowanej wcześniejszej próby nie mogą zatrzymać bieżącej.
    private var sessionID = 0
    private var retriedWithServer = false
    private var forceServerRecognition = false
    private var lastLocaleIdentifier = ""
    private static let logger = Logger(subsystem: "com.cantate.presenter", category: "dictation")
    
    public func startDictation(
        owner: UUID? = nil,
        localeIdentifier: String,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        lastLocaleIdentifier = localeIdentifier
        if !forceServerRecognition {
            retriedWithServer = false
        }
        if isRecording {
            stopDictation()
            return
        }
        // Ponowienie przez serwer (`forceServerRecognition`) to ta sama sesja tego samego przycisku.
        ownership.start(owner, isRetry: forceServerRecognition)
        
        self.partialHandler = onPartial
        self.finalHandler = onFinal
        self.currentRecognizedText = ""
        self.finalDelivery.start()
        self.errorMessage = nil
        
        // Request microphone permission first
        AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] micGranted in
            guard micGranted else {
                Task { @MainActor in
                    self?.fail(Lnow("Brak dostępu do mikrofonu. Nadaj uprawnienia w Ustawienia systemowe > Prywatność i ochrona > Mikrofon."))
                }
                return
            }
            
            SFSpeechRecognizer.requestAuthorization { @Sendable [weak self] authStatus in
                Task { @MainActor in
                    guard authStatus == .authorized else {
                        self?.fail(Lnow("Brak uprawnień do rozpoznawania mowy. Włącz uprawnienia w Ustawieniach systemowych."))
                        return
                    }
                    self?.isAuthorized = true
                    self?.beginAudioRecording(localeIdentifier: localeIdentifier)
                }
            }
        }
    }
    
    private func beginAudioRecording(localeIdentifier: String) {
        // Stop any previous task
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let locale = Locale(identifier: localeIdentifier)
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            fail(Lnow("Rozpoznawanie mowy dla języka {0} nie jest obecnie dostępne na tym urządzeniu.", localeIdentifier))
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            fail(Lnow("Nie można utworzyć żądania rozpoznawania mowy."))
            return
        }
        
        request.shouldReportPartialResults = true
        // Wybór z Ustawień (N4): tylko na tym Macu, jeśli system ma model mowy dla tego języka.
        // Bez modelu lokalnego (albo gdy opcja jest wyłączona) rozpoznawanie idzie przez serwery Apple.
        let onDeviceOnly = DataStore.shared.settings.dictationOnDeviceOnly && !forceServerRecognition
        request.requiresOnDeviceRecognition = onDeviceOnly && recognizer.supportsOnDeviceRecognition
        usedOnDeviceRecognition = request.requiresOnDeviceRecognition
        forceServerRecognition = false
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            fail(Lnow("Nieprawidłowy format wejścia mikrofonu."))
            return
        }
        
        inputNode.removeTap(onBus: 0)
        do {
            try Self.installTap(on: inputNode, format: recordingFormat, feeding: request)
            audioEngine.prepare()
            try audioEngine.start()
            self.isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            fail(Lnow("Nie udało się uruchomić silnika audio: {0}", error.localizedDescription))
            return
        }
        
        sessionID += 1
        let session = sessionID
        recognitionTask = Self.recognize(with: recognizer, request: request) { [weak self] transcribed, isFinal, error in
            Task { @MainActor in
                guard let self, session == self.sessionID else { return }
                self.handleRecognition(transcribed: transcribed, isFinal: isFinal, error: error)
            }
        }
    }
    
    private func handleRecognition(transcribed: String?, isFinal: Bool, error: Error?) {
        if let transcribed {
            self.currentRecognizedText = transcribed
            self.partialHandler?(transcribed)
            
            if isFinal {
                // Wynik oddaje stopDictation; tu wcześniej był drugi raz (N4).
                self.stopDictation()
            }
        }
        
        if let error = error {
            let nsError = error as NSError
            Self.logger.error("Rozpoznawanie mowy: \(nsError.domain, privacy: .public) \(nsError.code) (lokalnie: \(self.usedOnDeviceRecognition))")
            // macOS potrafi zgłaszać obsługę lokalną bez pobranego modelu mowy: wtedy jedno ponowienie
            // przez serwery Apple, zgodnie z opisem przy opcji w Ustawieniach (N4).
            if DictationFallback.shouldRetryWithServer(
                usedOnDevice: self.usedOnDeviceRecognition,
                recognizedText: self.currentRecognizedText,
                alreadyRetried: self.retriedWithServer
            ), let onPartial = self.partialHandler, let onFinal = self.finalHandler {
                self.retriedWithServer = true
                self.restartWithServerRecognition(onPartial: onPartial, onFinal: onFinal)
                return
            }
            // Ignore cancelation error
            if nsError.domain != "kAFAssistantErrorDomain" || (nsError.code != 203 && nsError.code != 216) {
                if !self.transcribedTextWasEmitted {
                    self.errorMessage = error.localizedDescription
                    self.ownership.fail()
                }
            }
            self.stopDictation()
        }
    }
    
    // MARK: - Audio Callbacks
    
    /// Bufory z mikrofonu przychodzą w wątku audio, więc domknięcie nie może należeć do głównego aktora
    /// (w trybie Swift 6 takie wywołanie zatrzymuje aplikację). `append` można wołać z dowolnego wątku.
    /// Od macOS 27 wersja zgłaszająca błąd (np. niezgodny format po zmianie mikrofonu) zamiast wyjątku
    /// Objective-C, który zamykał aplikację (R1-06). Wymaga SDK macOS 27 (Swift 6.4).
    nonisolated private static func installTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        feeding request: SFSpeechAudioBufferRecognitionRequest
    ) throws {
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            try node.__installTap(onBus: 0, bufferSize: 1024, format: format, error: ()) { buffer, _ in
                request.append(buffer)
            }
        } else {
            legacyInstallTap(on: node, format: format, feeding: request)
        }
        #else
        legacyInstallTap(on: node, format: format, feeding: request)
        #endif
    }

    @available(macOS, deprecated: 27.0, message: "installTap(onBus:bufferSize:format:error:block:)")
    nonisolated private static func legacyInstallTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        feeding request: SFSpeechAudioBufferRecognitionRequest
    ) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }
    
    /// Wyniki rozpoznawania przychodzą w kolejce systemowej; dalej idą tylko wartości `Sendable`.
    nonisolated private static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (_ transcribed: String?, _ isFinal: Bool, _ error: Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
        }
    }
    
    private var transcribedTextWasEmitted: Bool {
        return !currentRecognizedText.isEmpty
    }
    
    private var finalDelivery = DictationFinalDelivery()
    
    /// Zatrzymuje bieżącą próbę bez oddawania wyniku i zaczyna od nowa z rozpoznawaniem na serwerach Apple.
    private func restartWithServerRecognition(onPartial: @escaping (String) -> Void, onFinal: @escaping (String) -> Void) {
        sessionID += 1 // spóźnione zdarzenia anulowanej próby są od teraz ignorowane
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        forceServerRecognition = true
        startDictation(localeIdentifier: lastLocaleIdentifier, onPartial: onPartial, onFinal: onFinal)
    }
    
    public func stopDictation() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if isRecording {
            isRecording = false
            finalDelivery.deliver(currentRecognizedText) { finalHandler?($0) }
        }
        ownership.end()
    }

    /// Błąd przed nagrywaniem albo w jego trakcie: sesja się kończy, komunikat zostaje przy przycisku (R4-11).
    private func fail(_ message: String) {
        errorMessage = message
        isRecording = false
        ownership.fail()
    }

    public func clearError() {
        errorMessage = nil
        ownership.clearError()
    }
}

// MARK: - Ownership

/// Stan przycisku dyktowania wyliczany z usługi, a nie z lokalnego `@State` (R4-11): błąd przed startem
/// nagrywania kończy sesję (przycisk nie zostaje czerwony), a ponowienie przez serwer jej nie kończy.
public struct DictationOwnership: Equatable, Sendable {
    /// Przycisk, który prowadzi bieżącą sesję.
    public private(set) var active: UUID?
    /// Przycisk, przy którym pokazać komunikat o błędzie.
    public private(set) var failed: UUID?

    public init() {}

    mutating func start(_ owner: UUID?, isRetry: Bool) {
        guard !isRetry else { return }
        active = owner
        failed = nil
    }

    mutating func fail() {
        if active != nil {
            failed = active
        }
        active = nil
    }

    mutating func end() {
        active = nil
    }

    mutating func clearError() {
        failed = nil
    }
}

// MARK: - Final Delivery

/// Wynik dyktowania oddawany dokładnie raz na sesję (N4).
struct DictationFinalDelivery {
    private var delivered = false
    
    mutating func start() {
        delivered = false
    }
    
    mutating func deliver(_ text: String, to handler: (String) -> Void) {
        guard !delivered, !text.isEmpty else { return }
        delivered = true
        handler(text)
    }
}

// MARK: - Fallback

enum DictationFallback {
    /// Ponowienie przez serwer tylko, gdy wymuszone lokalne rozpoznawanie zawiodło, zanim padło jakiekolwiek słowo.
    static func shouldRetryWithServer(usedOnDevice: Bool, recognizedText: String, alreadyRetried: Bool) -> Bool {
        usedOnDevice && recognizedText.isEmpty && !alreadyRetried
    }
}
