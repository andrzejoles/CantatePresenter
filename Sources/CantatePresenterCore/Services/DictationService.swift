import Foundation
import Speech
import AVFoundation
import Combine

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
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                switch authStatus {
                case .authorized:
                    self?.isAuthorized = true
                    self?.errorMessage = nil
                case .denied:
                    self?.isAuthorized = false
                    self?.errorMessage = "Odmówiono dostępu do rozpoznawania mowy w Ustawieniach systemowych."
                case .restricted:
                    self?.isAuthorized = false
                    self?.errorMessage = "Rozpoznawanie mowy jest ograniczone na tym urządzeniu."
                case .notDetermined:
                    self?.isAuthorized = false
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    public func startDictation(
        localeIdentifier: String,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        if isRecording {
            stopDictation()
            return
        }
        
        self.partialHandler = onPartial
        self.finalHandler = onFinal
        self.currentRecognizedText = ""
        self.errorMessage = nil
        
        // Request microphone permission first
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] micGranted in
            guard micGranted else {
                Task { @MainActor in
                    self?.errorMessage = "Brak dostępu do mikrofonu. Nadaj uprawnienia w Ustawienia systemowe > Prywatność i ochrona > Mikrofon."
                    self?.isRecording = false
                }
                return
            }
            
            SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
                Task { @MainActor in
                    guard authStatus == .authorized else {
                        self?.errorMessage = "Brak uprawnień do rozpoznawania mowy. Włącz uprawnienia w Ustawieniach systemowych."
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
            self.errorMessage = "Rozpoznawanie mowy dla języka \(localeIdentifier) nie jest obecnie dostępne na tym urządzeniu."
            self.isRecording = false
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            self.errorMessage = "Nie można utworzyć żądania rozpoznawania mowy."
            self.isRecording = false
            return
        }
        
        request.shouldReportPartialResults = true
        // Enable on-device recognition on Apple Silicon if available
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = false // Allow fallback to network if faster
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            self.errorMessage = "Nieprawidłowy format wejścia mikrofonu."
            self.isRecording = false
            return
        }
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            self.isRecording = true
        } catch {
            self.errorMessage = "Nie udało się uruchomić silnika audio: \(error.localizedDescription)"
            self.isRecording = false
            return
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    let transcribed = result.bestTranscription.formattedString
                    self.currentRecognizedText = transcribed
                    self.partialHandler?(transcribed)
                    
                    if result.isFinal {
                        self.finalHandler?(transcribed)
                        self.stopDictation()
                    }
                }
                
                if let error = error {
                    // Ignore cancelation error
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || (nsError.code != 203 && nsError.code != 216) {
                        if !self.transcribedTextWasEmitted {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                    self.stopDictation()
                }
            }
        }
    }
    
    private var transcribedTextWasEmitted: Bool {
        return !currentRecognizedText.isEmpty
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
            if !currentRecognizedText.isEmpty {
                finalHandler?(currentRecognizedText)
            }
        }
    }
    
    public func toggleDictation(
        localeIdentifier: String,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        if isRecording {
            stopDictation()
        } else {
            startDictation(localeIdentifier: localeIdentifier, onPartial: onPartial, onFinal: onFinal)
        }
    }
}
