import Cocoa

func generateIcon() {
    let size: CGFloat = 1024
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    
    // Outer shadow / glow
    ctx.saveGState()
    
    // Squircle path (macOS icon standard dimensions: 824x824 at center of 1024x1024, radius ~185)
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: iconRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 35, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Clip to squircle for gradient & content
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    
    // Background gradient: Deep royal navy to dark sapphire
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.04, green: 0.08, blue: 0.18, alpha: 1.0), // Deep navy
        CGColor(red: 0.08, green: 0.18, blue: 0.38, alpha: 1.0), // Royal blue
        CGColor(red: 0.06, green: 0.12, blue: 0.28, alpha: 1.0)  // Bottom depth
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    
    // Radial glow in upper center
    let glowColors = [
        CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.35), // Cyan glow
        CGColor(red: 0.08, green: 0.18, blue: 0.38, alpha: 0.0)
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGradient, startCenter: CGPoint(x: 512, y: 650), startRadius: 10, endCenter: CGPoint(x: 512, y: 650), endRadius: 360, options: [])
    }
    
    // Inner border highlight
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18))
    ctx.setLineWidth(4)
    ctx.addPath(path)
    ctx.strokePath()
    
    // Draw Symbol: Cross + Musical Notes / Waves
    // 1. Cross (Golden / Amber gradient)
    let crossWidth: CGFloat = 44
    let crossHeight: CGFloat = 380
    let crossCenterX: CGFloat = 430
    let crossCenterY: CGFloat = 520
    
    // Vertical beam
    let vBeamRect = CGRect(x: crossCenterX - crossWidth/2, y: crossCenterY - 180, width: crossWidth, height: crossHeight)
    let vBeamPath = CGPath(roundedRect: vBeamRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
    
    // Horizontal beam
    let hBeamWidth: CGFloat = 220
    let hBeamRect = CGRect(x: crossCenterX - hBeamWidth/2, y: crossCenterY + 60, width: hBeamWidth, height: crossWidth)
    let hBeamPath = CGPath(roundedRect: hBeamRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
    
    let goldColors = [
        CGColor(red: 0.98, green: 0.82, blue: 0.35, alpha: 1.0), // Amber gold
        CGColor(red: 0.96, green: 0.62, blue: 0.15, alpha: 1.0)  // Deep gold
    ] as CFArray
    if let goldGradient = CGGradient(colorsSpace: colorSpace, colors: goldColors, locations: [0.0, 1.0]) {
        // Cross shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(red: 0.96, green: 0.62, blue: 0.15, alpha: 0.45))
        ctx.addPath(vBeamPath)
        ctx.addPath(hBeamPath)
        ctx.fillPath()
        ctx.restoreGState()
        
        ctx.saveGState()
        ctx.addPath(vBeamPath)
        ctx.addPath(hBeamPath)
        ctx.clip()
        ctx.drawLinearGradient(goldGradient, start: CGPoint(x: 512, y: 750), end: CGPoint(x: 512, y: 300), options: [])
        ctx.restoreGState()
    }
    
    // 2. Musical Symbol: Connected Double Eighth Note (Cyan glowing)
    let noteColor = CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.95) // Cyan
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: CGColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.6))
    
    // Right note head
    let noteHead1 = CGRect(x: 540, y: 350, width: 70, height: 50)
    let noteHead2 = CGRect(x: 670, y: 390, width: 70, height: 50)
    
    ctx.setFillColor(noteColor)
    
    // Rotate slightly for musical tilt
    ctx.saveGState()
    ctx.translateBy(x: 575, y: 375)
    ctx.rotate(by: -0.25)
    ctx.fillEllipse(in: CGRect(x: -35, y: -25, width: 70, height: 50))
    ctx.restoreGState()
    
    ctx.saveGState()
    ctx.translateBy(x: 705, y: 415)
    ctx.rotate(by: -0.25)
    ctx.fillEllipse(in: CGRect(x: -35, y: -25, width: 70, height: 50))
    ctx.restoreGState()
    
    // Stems
    ctx.setStrokeColor(noteColor)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    
    ctx.move(to: CGPoint(x: 600, y: 380))
    ctx.addLine(to: CGPoint(x: 600, y: 620))
    ctx.strokePath()
    
    ctx.move(to: CGPoint(x: 730, y: 420))
    ctx.addLine(to: CGPoint(x: 730, y: 660))
    ctx.strokePath()
    
    // Beam connecting the notes
    let beamPath = CGMutablePath()
    beamPath.move(to: CGPoint(x: 593, y: 605))
    beamPath.addLine(to: CGPoint(x: 737, y: 645))
    beamPath.addLine(to: CGPoint(x: 737, y: 665))
    beamPath.addLine(to: CGPoint(x: 593, y: 625))
    beamPath.closeSubpath()
    
    ctx.addPath(beamPath)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 3. Subtle Acoustic Waves / Light Rays radiating out
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15))
    ctx.setLineWidth(6)
    for radius: CGFloat in [130, 180, 230] {
        ctx.addArc(center: CGPoint(x: 430, y: 580), radius: radius, startAngle: -0.8, endAngle: 0.8, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()
    
    // Top glass reflection highlight arc
    ctx.saveGState()
    let highlightPath = CGMutablePath()
    highlightPath.addArc(center: CGPoint(x: 512, y: 1100), radius: 460, startAngle: CGFloat.pi, endAngle: 0, clockwise: false)
    ctx.addPath(highlightPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.setLineWidth(10)
    ctx.strokePath()
    ctx.restoreGState()
    
    ctx.restoreGState() // Unclip
    
    img.unlockFocus()
    
    // Save to 1024x1024 PNG
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Błąd konwersji do PNG")
        return
    }
    
    let outUrl = URL(fileURLWithPath: "AppIcon_1024.png")
    try? pngData.write(to: outUrl)
    print("Wygenerowano: \(outUrl.path)")
}

generateIcon()
