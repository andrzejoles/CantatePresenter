import Foundation
import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Remote Control Sheet

/// Pilot ze smartfona: włączenie serwera w sieci lokalnej i kod QR z adresem i tokenem.
public struct RemoteControlSheet: View {
    @Bindable var store = DataStore.shared
    @Bindable var server = RemoteControlServer.shared
    @Binding var isPresented: Bool
    @State private var showsMusicianCode = false
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    public var body: some View {
        let scale = store.settings.uiScale
        
        VStack(spacing: 0) {
            HStack {
                Label(L("Pilot ze smartfona"), systemImage: "iphone.radiowaves.left.and.right")
                    .font(.scaled(16, weight: .bold, scale: scale))
                Spacer()
                Button(L("Zamknij")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            
            Divider()
            
            VStack(spacing: 14) {
                Toggle(L("Włącz pilota"), isOn: Binding(
                    get: { server.isRunning },
                    set: { $0 ? server.start() : server.stop() }
                ))
                .toggleStyle(.switch)
                .font(.scaled(13, weight: .semibold, scale: scale))
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if server.isRunning {
                    Picker("", selection: $showsMusicianCode) {
                        Text(L("Sterowanie")).tag(false)
                        Text(L("Muzycy (chwyty, tylko podgląd)")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    
                    if let address = showsMusicianCode ? server.stageAddress : server.address {
                        if let qr = Self.qrImage(for: address.absoluteString) {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 220, height: 220)
                                .padding(10)
                                .background(Color.white)
                                .cornerRadius(8)
                        }
                        Text(showsMusicianCode
                             ? L("Muzycy skanują ten kod: bieżący slajd z chwytami na tablecie lub telefonie, bez sterowania prezentacją.")
                             : L("Zeskanuj kod aparatem telefonu albo wpisz adres w przeglądarce:"))
                            .font(.scaled(12, scale: scale))
                            .foregroundColor(.secondary)
                        Text(address.absoluteString)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(L("Połączone telefony: {0}", server.connectedDevices(now: context.date)))
                                .font(.scaled(12, weight: .medium, scale: scale))
                        }
                        
                        Button(action: { server.regenerateToken() }) {
                            Label(L("Nowy kod (rozłącza telefony)"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    } else {
                        Text(L("Ten Mac nie jest połączony z siecią lokalną (Wi-Fi lub Ethernet)."))
                            .foregroundColor(.orange)
                    }
                }
                
                if let error = server.errorMessage {
                    Text(error)
                        .font(.scaled(12, scale: scale))
                        .foregroundColor(.red)
                }
                
                Spacer(minLength: 0)
                
                Text(L("Telefon musi być w tej samej sieci Wi-Fi co ten Mac. Przy pierwszym włączeniu macOS może zapytać o zgodę na połączenia przychodzące i dostęp do sieci lokalnej. Pilot działa, dopóki aplikacja jest otwarta."))
                    .font(.scaled(11, scale: scale))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .frame(width: 460, height: 620)
    }
    
    static func qrImage(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
