import Foundation
import SwiftUI

public struct QuickTextSheet: View {
    @Bindable var store = DataStore.shared
    @Binding var isPresented: Bool
    
    @State private var title: String = ""
    @State private var text: String = ""
    @FocusState private var isTextFocused: Bool
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    private var slideCount: Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return Song.parseLyrics(trimmed).count
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Szybki tekst na żywo")
                        .font(.scaled(16, weight: .bold, scale: scale))
                    Text("Wpisz tekst lub ogłoszenie — zostanie wyświetlone na projektorze bez zapisywania w bazie.")
                        .font(.scaled(11, scale: scale))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider()
            
            // Title Input (optional)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tytuł (opcjonalny):")
                    .font(.scaled(11, weight: .medium, scale: scale))
                    .foregroundColor(.secondary)
                TextField("np. Ogłoszenie, Intencja, Słowo na dziś...", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.scaled(13, scale: scale))
            }
            
            // Text Input
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Treść do wyświetlenia:")
                        .font(.scaled(11, weight: .medium, scale: scale))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Dictation button for voice input
                    DictationButtonView(text: $text, mode: .appendNewline, size: 12)
                    
                    if slideCount > 0 {
                        Text("\(slideCount) \(slideCount == 1 ? "slajd" : "slajdy")")
                            .font(.scaled(10.5, weight: .semibold, scale: scale))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.scaled(13, scale: scale))
                        .focused($isTextFocused)
                        .frame(minHeight: 180, maxHeight: 300)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                    
                    if text.isEmpty {
                        Text("Wpisz lub wklej treść do wyświetlenia...\n\nPuste linie dzielą tekst na kolejne slajdy.")
                            .font(.scaled(13, scale: scale))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
            }
            
            // Helpful tip
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Wskazówka: Naciśnij ⌘+Return lub przycisk poniżej, aby natychmiast wysłać na ekran.")
                    .font(.scaled(10.5, scale: scale))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Action Buttons
            HStack {
                Button("Anuluj") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: {
                    presentNow()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                        Text("Wyświetl teraz")
                    }
                    .font(.scaled(12, weight: .semibold, scale: scale))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 380)
        .onAppear {
            isTextFocused = true
        }
    }
    
    private func presentNow() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        store.presentQuickText(text: trimmed, title: title)
        isPresented = false
    }
}
