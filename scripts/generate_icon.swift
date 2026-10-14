import Cocoa

func generateIcon() {
    let svgContent = """
    <svg viewBox="15 15 170 170" fill="none" xmlns="http://www.w3.org/2000/svg">
        <defs>
            <linearGradient id="wave1" x1="20" y1="0" x2="180" y2="0" gradientUnits="userSpaceOnUse">
                <stop offset="0%" stop-color="#EC4899"/>
                <stop offset="100%" stop-color="#F59E0B"/>
            </linearGradient>
            <linearGradient id="wave2" x1="20" y1="0" x2="180" y2="0" gradientUnits="userSpaceOnUse">
                <stop offset="0%" stop-color="#06B6D4"/>
                <stop offset="100%" stop-color="#3B82F6"/>
            </linearGradient>
            <linearGradient id="wave3" x1="20" y1="0" x2="180" y2="0" gradientUnits="userSpaceOnUse">
                <stop offset="0%" stop-color="#8B5CF6"/>
                <stop offset="100%" stop-color="#10B981"/>
            </linearGradient>
        </defs>
        <rect x="15" y="15" width="170" height="170" rx="44" fill="#0B0F20"/>
        <path d="M 28 85 C 55 45, 80 135, 100 85 C 120 35, 145 125, 172 85" stroke="url(#wave1)" stroke-width="4.5" stroke-linecap="round" fill="none"/>
        <path d="M 28 100 C 55 140, 80 60, 100 100 C 120 140, 145 60, 172 100" stroke="url(#wave2)" stroke-width="4.5" stroke-linecap="round" fill="none"/>
        <path d="M 28 115 C 55 80, 80 150, 100 115 C 120 80, 145 150, 172 115" stroke="url(#wave3)" stroke-width="3" stroke-linecap="round" fill="none" opacity="0.75"/>
        <rect x="91" y="42" width="18" height="34" rx="9" fill="#1E293B" stroke="#FFFFFF" stroke-width="2"/>
        <line x1="91" y1="52" x2="109" y2="52" stroke="#94A3B8" stroke-width="1"/>
        <line x1="91" y1="60" x2="109" y2="60" stroke="#94A3B8" stroke-width="1"/>
        <path d="M 85 58 C 85 78, 115 78, 115 58" stroke="#FFFFFF" stroke-width="2.5" fill="none"/>
        <line x1="100" y1="78" x2="100" y2="92" stroke="#FFFFFF" stroke-width="2.5"/>
        <circle cx="100" cy="58" r="32" stroke="#FDE047" stroke-width="1.5" stroke-dasharray="3 3" opacity="0.6"/>
        <circle cx="48" cy="55" r="4" fill="#F43F5E"/>
        <line x1="52" y1="55" x2="52" y2="40" stroke="#F43F5E" stroke-width="1.5"/>
        <circle cx="154" cy="50" r="4" fill="#38BDF8"/>
        <line x1="158" y1="50" x2="158" y2="35" stroke="#38BDF8" stroke-width="1.5"/>
    </svg>
    """
    
    guard let data = svgContent.data(using: .utf8),
          let svgImg = NSImage(data: data) else {
        print("Błąd parsowania SVG")
        return
    }
    
    let size: CGFloat = 1024
    let finalImg = NSImage(size: NSSize(width: size, height: size))
    finalImg.lockFocus()
    
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    
    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 38, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.043, green: 0.059, blue: 0.125, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()
    
    // Clip to squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    svgImg.size = NSSize(width: 824, height: 824)
    svgImg.draw(in: iconRect)
    
    // Border highlight
    ctx.setStrokeColor(CGColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 0.45))
    ctx.setLineWidth(6)
    ctx.addPath(squirclePath)
    ctx.strokePath()
    
    ctx.restoreGState()
    finalImg.unlockFocus()
    
    guard let tiff = finalImg.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Błąd zapisu PNG")
        return
    }
    
    let outUrl = URL(fileURLWithPath: "AppIcon_Logo21.png")
    try? png.write(to: outUrl)
    print("Wygenerowano bazowy PNG dla Logo 21: \(outUrl.path)")
}

generateIcon()
