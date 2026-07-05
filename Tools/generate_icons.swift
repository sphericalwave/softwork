// generate_icons.swift
// Standalone macOS generator for the softwork app icon + launch logo.
// Run from project root: swift Tools/generate_icons.swift
// Not part of any build target; kept for reproducibility.
//
// Glyph: a heart (health / HRV) crossed by an ECG pulse line (heart rate),
// drawn by hand with CoreGraphics so there's no SF Symbol / macOS dependency.

import AppKit
import CoreGraphics

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDir  = projectRoot.appendingPathComponent("softwork/Assets.xcassets/AppIcon.appiconset")
let launchDir   = projectRoot.appendingPathComponent("softwork/Assets.xcassets/LaunchLogo.imageset")

let appName = "softwork"

// brandFill drives BOTH the AppIcon background AND the AccentColor colorset.
// Same hex as SwTheme.primaryColor (blue1 = 25,58,231 → #193AE7).
let brandFill  = NSColor(srgbRed: 25/255, green: 58/255, blue: 231/255, alpha: 1)
let glyphColor = NSColor.white

/// Parametric heart (y-up), filled white, then an ECG pulse line drawn through it.
/// clearCutouts:false → pulse line drawn in brandFill (AppIcon over solid bg).
/// clearCutouts:true  → pulse line punched to alpha (launch logo on transparent bg).
func drawGlyph(in full: CGRect, ctx: CGContext, clearCutouts: Bool = false) {
    let s  = full.width
    let cx = full.midX
    let cy = full.midY

    // --- Heart body ---
    // x = 16 sin^3 t ; y = 13 cos t − 5 cos 2t − 2 cos 3t − cos 4t
    let heart = CGMutablePath()
    let scale = (s * 0.66) / 32.0            // formula spans ~32 wide
    let yMid  = (12.0 + (-17.0)) / 2.0        // recentre the taller-than-wide shape
    var first = true
    var t = 0.0
    while t <= Double.pi * 2 + 0.02 {
        let x = 16 * pow(sin(t), 3)
        let y = 13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t)
        let px = cx + CGFloat(x) * scale
        let py = cy + CGFloat(y - yMid) * scale
        if first { heart.move(to: CGPoint(x: px, y: py)); first = false }
        else { heart.addLine(to: CGPoint(x: px, y: py)) }
        t += 0.01
    }
    heart.closeSubpath()

    ctx.saveGState()
    ctx.setFillColor(glyphColor.cgColor)
    ctx.addPath(heart)
    ctx.fillPath()
    ctx.restoreGState()

    // --- ECG pulse line across the heart ---
    let a = s * 0.30                          // half-width of the trace
    let baseY = cy - s * 0.02
    let pulse = CGMutablePath()
    pulse.move(to: CGPoint(x: cx - a,          y: baseY))
    pulse.addLine(to: CGPoint(x: cx - a*0.42,  y: baseY))
    pulse.addLine(to: CGPoint(x: cx - a*0.20,  y: baseY + a*0.55))   // up spike
    pulse.addLine(to: CGPoint(x: cx + a*0.02,  y: baseY - a*0.62))   // down spike
    pulse.addLine(to: CGPoint(x: cx + a*0.22,  y: baseY))
    pulse.addLine(to: CGPoint(x: cx + a,       y: baseY))

    ctx.saveGState()
    ctx.setLineWidth(s * 0.052)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    if clearCutouts {
        ctx.setBlendMode(.clear)
        ctx.setStrokeColor(NSColor.white.cgColor)   // colour irrelevant; .clear erases
    } else {
        ctx.setStrokeColor(brandFill.cgColor)
    }
    ctx.addPath(pulse)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let cg = gctx.cgContext

    let full = CGRect(x: 0, y: 0, width: size, height: size)
    cg.clear(full)
    cg.setFillColor(brandFill.cgColor)   // opaque — no alpha in the App Store icon
    cg.fill(full)
    drawGlyph(in: full, ctx: cg)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// Transparent canvas: heart glyph on top, app name centered below.
/// UILaunchScreen fills the screen with AccentColor and centers this image.
func renderLaunchLogo(iconSize: CGFloat) -> Data {
    let fontSize: CGFloat = iconSize * 0.20
    let gap: CGFloat      = iconSize * 0.10
    let textPad: CGFloat  = iconSize * 0.06

    let font = NSFont.boldSystemFont(ofSize: fontSize)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let attrStr  = NSAttributedString(string: appName, attributes: attrs)
    let textSize = attrStr.size()

    let canvasW = max(iconSize, ceil(textSize.width) + iconSize * 0.10)
    let canvasH = iconSize + gap + ceil(textSize.height) + textPad

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasW), pixelsHigh: Int(canvasH),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvasW, height: canvasH)

    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let cg = gctx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

    let iconX = (canvasW - iconSize) / 2
    let iconY = ceil(textSize.height) + gap + textPad
    drawGlyph(in: CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize),
              ctx: cg, clearCutouts: true)

    let textX = (canvasW - textSize.width) / 2
    attrStr.draw(at: NSPoint(x: textX, y: textPad))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, to dir: URL, name: String) {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try! data.write(to: url)
    print("wrote \(url.path)")
}

write(render(size: 1024), to: appIconDir, name: "icon-1024.png")
write(renderLaunchLogo(iconSize: 170), to: launchDir, name: "LaunchLogo.png")
write(renderLaunchLogo(iconSize: 340), to: launchDir, name: "LaunchLogo@2x.png")
write(renderLaunchLogo(iconSize: 512), to: launchDir, name: "LaunchLogo@3x.png")

print("done")
