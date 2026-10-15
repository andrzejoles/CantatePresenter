import Foundation
import SwiftUI

public enum DictationTargetMode {
    case replace
    case append(separator: String = " ")
    case appendNewline
}

public struct DictationButtonView: View {
    @ObservedObject var dictationService = DictationService.shared
    @Bindable var store = DataStore.shared
    
    @Binding var text: String
    public var mode: DictationTargetMode = .replace
    public var size: CGFloat = 13.0
    public var customPrompt: String? = nil
    
    @State private var originalTextBeforeRecording: String = ""
    @State private var isPulsing: Bool = false
    @State private var isThisButtonRecording: Bool = false
    
    public init(
        text: Binding<String>,
        mode: DictationTargetMode = .replace,
        size: CGFloat = 13.0,
        customPrompt: String? = nil
    ) {
        self._text = text
        self.mode = mode
        self.size = size
        self.customPrompt = customPrompt
    }
    
    public var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 4) {
                if isThisButtonRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isPulsing ? 1.3 : 0.8)
                        .animation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                    
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                        .font(.system(size: size, weight: .bold))
                    
                    Text("Dyktuję...")
                        .font(.system(size: max(9, size - 2), weight: .semibold))
                        .foregroundColor(.red)
                } else {
                    Image(systemName: "mic")
                        .foregroundColor(.blue)
                        .font(.system(size: size))
                }
            }
            .padding(.horizontal, isThisButtonRecording ? 6 : 4)
            .padding(.vertical, 3)
            .background(isThisButtonRecording ? Color.red.opacity(0.12) : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
        .help(isThisButtonRecording ? "Kliknij, aby zakończyć dyktowanie" : (customPrompt ?? "Dyktuj głosowo (\(dictationLanguageName))"))
        .onChange(of: dictationService.isRecording) { _, isRec in
            if !isRec && isThisButtonRecording {
                isThisButtonRecording = false
                isPulsing = false
            }
        }
        .popover(isPresented: Binding(
            get: { isThisButtonRecording && dictationService.errorMessage != nil },
            set: { _ in dictationService.errorMessage = nil }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Problem z dyktowaniem")
                        .font(.headline)
                }
                Text(dictationService.errorMessage ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: 300)
        }
    }
    
    private var dictationLanguageName: String {
        let code = store.settings.dictationLanguage
        return LanguagePresets.dictationLanguages.first(where: { $0.code == code })?.name ?? code
    }
    
    private func toggleRecording() {
        if isThisButtonRecording {
            dictationService.stopDictation()
            isThisButtonRecording = false
            isPulsing = false
        } else {
            // Stop any other active dictation
            dictationService.stopDictation()
            
            originalTextBeforeRecording = text
            isThisButtonRecording = true
            isPulsing = true
            
            let currentMode = self.mode
            let baseText = self.originalTextBeforeRecording
            
            dictationService.startDictation(
                localeIdentifier: store.settings.dictationLanguage,
                onPartial: { recognized in
                    applyRecognizedText(recognized, baseText: baseText, mode: currentMode)
                },
                onFinal: { finalResult in
                    applyRecognizedText(finalResult, baseText: baseText, mode: currentMode)
                    isThisButtonRecording = false
                    isPulsing = false
                }
            )
        }
    }
    
    private func applyRecognizedText(_ recognized: String, baseText: String, mode: DictationTargetMode) {
        let cleanRecognized = recognized.trimmingCharacters(in: .whitespaces)
        guard !cleanRecognized.isEmpty else { return }
        
        switch mode {
        case .replace:
            self.text = cleanRecognized
        case .append(let separator):
            if baseText.trimmingCharacters(in: .whitespaces).isEmpty {
                self.text = cleanRecognized
            } else {
                self.text = baseText + separator + cleanRecognized
            }
        case .appendNewline:
            if baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.text = cleanRecognized
            } else {
                self.text = baseText + "\n\n" + cleanRecognized
            }
        }
    }
}
