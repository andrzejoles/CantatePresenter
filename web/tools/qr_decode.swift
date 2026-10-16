// Dekoder QR z macOS (CoreImage) do sprawdzania kodera web/src/core/qr.js: swift qr_decode.swift obraz.png
import CoreImage
import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let image = CIImage(contentsOf: url)!
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
for feature in detector.features(in: image) as! [CIQRCodeFeature] { print(feature.messageString ?? "<nil>") }
