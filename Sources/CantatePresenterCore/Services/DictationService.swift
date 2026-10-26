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
        
        self.partialHandler = onPartial
        self.finalHandler = onFinal
        self.currentRecognizedText = ""
        self.finalDelivery.start()
        self.errorMessage = nil
        
        // Request microphone permission first
        AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] micGranted in
            guard micGranted else {
                Task { @MainActor in
                    self?.errorMessage = Lnow("Brak dostępu do mikrofonu. Nadaj uprawnienia w Ustawienia systemowe > Prywatność i ochrona > Mikrofon.")
                    self?.isRecording = false
                }
                return
            }
            
            SFSpeechRecognizer.requestAuthorization { @Sendable [weak self] authStatus in
                Task { @MainActor in
                    guard authStatus == .authorized else {
                        self?.errorMessage = Lnow("Brak uprawnień do rozpoznawania mowy. Włącz uprawnienia w Ustawieniach systemowych.")
                        self?.isRecording = false
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
            self.errorMessage = Lnow("Rozpoznawanie mowy dla języka {0} nie jest obecnie dostępne na tym urządzeniu.", localeIdentifier)
            self.isRecording = false
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            self.errorMessage = Lnow("Nie można utworzyć żądania rozpoznawania mowy.")
            self.isRecording = false
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
            self.errorMessage = Lnow("Nieprawidłowy format wejścia mikrofonu.")
            self.isRecording = false
            return
        }
        
        inputNode.removeTap(onBus: 0)
        Self.installTap(on: inputNode, format: recordingFormat, feeding: request)
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            self.isRecording = true
        } catch {
            self.errorMessage = Lnow("Nie udało się uruchomić silnika audio: {0}", error.localizedDescription)
            self.isRecording = false
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
                }
            }
            self.stopDictation()
        }
    }
    
    // MARK: - Audio Callbacks
    
    /// Bufory z mikrofonu przychodzą w wątku audio, więc domknięcie nie może należeć do głównego aktora
    /// (w trybie Swift 6 takie wywołanie zatrzymuje aplikację). `append` można wołać z dowolnego wątku.
    nonisolated private static func installTap(
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
