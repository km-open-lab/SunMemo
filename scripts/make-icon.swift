// Draws the SunMemo (晾想法) app icon:
// A warm sunrise squircle, clothesline, and hanging pastel memo cards with checklists.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func shadow(_ alpha: CGFloat, blur: CGFloat, y: CGFloat) {
    let s = NSShadow()
    s.shadowColor = color(15, 20, 45, alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.set()
}

// MARK: - Squircle Body (macOS Icon Grid: 824pt square, 100pt margin)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
shadow(0.32, blur: 30, y: -16)
color(240, 210, 180).setFill()
shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()

// Warm sunrise gradient background
NSGradient(colors: [
    color(255, 175, 75),   // Warm morning amber
    color(255, 120, 110),  // Coral peach
    color(135, 140, 245)   // Soft sky violet
], atLocations: [0.0, 0.52, 1.0], colorSpace: .sRGB)!
    .draw(in: body, angle: -65)

// Golden morning sun glow in top right
let sunCenter = NSPoint(x: 740, y: 740)
let sunGradient = NSGradient(colors: [color(255, 255, 220, 0.75), color(255, 230, 120, 0.25), color(255, 255, 255, 0)],
                             atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
sunGradient.draw(fromCenter: sunCenter, radius: 0, toCenter: sunCenter, radius: 260, options: [])

// Soft specular highlight from top
NSGradient(colors: [color(255, 255, 255, 0.40), color(255, 255, 255, 0)],
           atLocations: [0, 1], colorSpace: .sRGB)!
    .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

// MARK: - The Clothesline
let left = NSPoint(x: 60, y: 720), right = NSPoint(x: 964, y: 720)
let control = NSPoint(x: 512, y: 610)
func lineY(_ x: CGFloat) -> CGFloat {
    let t = (x - left.x) / (right.x - left.x)
    return (1 - t) * (1 - t) * left.y + 2 * (1 - t) * t * control.y + t * t * right.y
}
func linePath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: left)
    p.curve(to: right,
            controlPoint1: NSPoint(x: left.x + (control.x - left.x) * 2 / 3, y: left.y + (control.y - left.y) * 2 / 3),
            controlPoint2: NSPoint(x: right.x + (control.x - right.x) * 2 / 3, y: right.y + (control.y - right.y) * 2 / 3))
    return p
}

ctx.saveGState()
shadow(0.25, blur: 10, y: -6)
let line = linePath()
line.lineWidth = 10
color(90, 80, 110).setStroke()
line.stroke()
ctx.restoreGState()

let highlight = linePath()
highlight.lineWidth = 3
highlight.transform(using: AffineTransform(translationByX: 0, byY: 2.5))
color(255, 255, 255, 0.65).setStroke()
highlight.stroke()

// MARK: - Hanging Memo Card Helper
func hangMemo(centerX: CGFloat, width: CGFloat, height: CGFloat, angle: CGFloat, bgColors: [NSColor], isTodo: Bool) {
    let top = lineY(centerX) + 38
    ctx.saveGState()
    ctx.translateBy(x: centerX, y: top)
    ctx.rotate(by: angle * .pi / 180)

    let radius: CGFloat = 48
    let cardRect = NSRect(x: -width / 2, y: -height, width: width, height: height)
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)

    // Soft card shadow
    ctx.saveGState()
    shadow(0.35, blur: 36, y: -20)
    color(255, 255, 255).setFill()
    cardPath.fill()
    ctx.restoreGState()

    // Card gradient fill
    NSGradient(colors: bgColors, atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: cardPath, angle: -85)

    // Subtle card border
    color(0, 0, 0, 0.08).setStroke()
    cardPath.lineWidth = 2
    cardPath.stroke()

    // Draw content on card
    ctx.saveGState()
    cardPath.addClip()

    if isTodo {
        // Checklist rows
        let startY = cardRect.maxY - 75
        let spacing: CGFloat = 62

        // Row 1: Checked item
        drawCheckRow(y: startY, width: width, checked: true, textWidth: 160)
        // Row 2: Checked item
        drawCheckRow(y: startY - spacing, width: width, checked: true, textWidth: 190)
        // Row 3: Pending item
        drawCheckRow(y: startY - spacing * 2, width: width, checked: false, textWidth: 140)
        // Row 4: Pending item
        drawCheckRow(y: startY - spacing * 3, width: width, checked: false, textWidth: 110)
    } else {
        // Idea Note (Sun / Sparkle header + lines)
        let cx: CGFloat = 0
        let iconY = cardRect.maxY - 90

        // Golden spark / sun dot
        color(255, 160, 50).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 22, y: iconY, width: 44, height: 44)).fill()

        // Content lines
        let startY = iconY - 55
        for (i, w) in [180, 200, 160, 130].enumerated() {
            let ry = startY - CGFloat(i) * 44
            color(0, 0, 0, 0.18).setFill()
            let p = NSBezierPath(roundedRect: NSRect(x: -CGFloat(w) / 2, y: ry, width: CGFloat(w), height: 14), xRadius: 7, yRadius: 7)
            p.fill()
        }
    }

    ctx.restoreGState()

    // Wooden Clothespin clipping top of card
    drawClothespin()

    ctx.restoreGState()
}

func drawCheckRow(y: CGFloat, width: CGFloat, checked: Bool, textWidth: CGFloat) {
    let boxX = -width / 2 + 38
    let boxRect = NSRect(x: boxX, y: y, width: 28, height: 28)

    if checked {
        color(76, 175, 80).setFill()
        let bp = NSBezierPath(roundedRect: boxRect, xRadius: 7, yRadius: 7)
        bp.fill()

        // Checkmark
        let check = NSBezierPath()
        check.move(to: NSPoint(x: boxX + 6, y: y + 14))
        check.line(to: NSPoint(x: boxX + 11, y: y + 8))
        check.line(to: NSPoint(x: boxX + 22, y: y + 21))
        color(255, 255, 255).setStroke()
        check.lineWidth = 3.5
        check.lineCapStyle = .round
        check.stroke()

        // Text line (grey strikethrough)
        let lineRect = NSRect(x: boxX + 44, y: y + 8, width: textWidth, height: 12)
        color(0, 0, 0, 0.22).setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: 6, yRadius: 6).fill()
    } else {
        color(0, 0, 0, 0.18).setStroke()
        let bp = NSBezierPath(roundedRect: boxRect, xRadius: 7, yRadius: 7)
        bp.lineWidth = 2.5
        bp.stroke()

        // Text line (active)
        let lineRect = NSRect(x: boxX + 44, y: y + 8, width: textWidth, height: 12)
        color(40, 45, 60, 0.70).setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: 6, yRadius: 6).fill()
    }
}

func drawClothespin() {
    let pinW: CGFloat = 26
    let pinH: CGFloat = 90
    let pinRect = NSRect(x: -pinW / 2, y: -45, width: pinW, height: pinH)

    ctx.saveGState()
    shadow(0.32, blur: 10, y: -5)
    // Warm wood / honey clip gradient
    NSGradient(colors: [color(245, 205, 140), color(210, 160, 95)], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: NSBezierPath(roundedRect: pinRect, xRadius: 7, yRadius: 7), angle: 0)
    ctx.restoreGState()

    // Metal spring ring
    let springRect = NSRect(x: -pinW / 2 + 3, y: -8, width: pinW - 6, height: 16)
    color(130, 135, 150).setFill()
    NSBezierPath(roundedRect: springRect, xRadius: 3, yRadius: 3).fill()
}

// MARK: - Polaroid Photo Helper
func hangPhoto(centerX: CGFloat, width: CGFloat, height: CGFloat, angle: CGFloat) {
    let top = lineY(centerX) + 38
    ctx.saveGState()
    ctx.translateBy(x: centerX, y: top)
    ctx.rotate(by: angle * .pi / 180)

    let radius: CGFloat = 40
    let cardRect = NSRect(x: -width / 2, y: -height, width: width, height: height)
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)

    // Soft photo card shadow
    ctx.saveGState()
    shadow(0.38, blur: 36, y: -20)
    color(255, 255, 255).setFill()
    cardPath.fill()
    ctx.restoreGState()

    // Crisp polaroid paper base
    NSGradient(colors: [color(255, 255, 255), color(246, 247, 250)], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: cardPath, angle: -85)

    // Subtle paper edge stroke
    color(0, 0, 0, 0.10).setStroke()
    cardPath.lineWidth = 2
    cardPath.stroke()

    // Inner photo area (classic Polaroid: thin top/sides, wide bottom margin)
    let sideMargin: CGFloat = 24
    let topMargin: CGFloat = 28
    let bottomMargin: CGFloat = 82
    let photoW = width - sideMargin * 2
    let photoH = height - topMargin - bottomMargin
    let photoRect = NSRect(x: -width / 2 + sideMargin, y: -height + bottomMargin, width: photoW, height: photoH)
    let photoPath = NSBezierPath(roundedRect: photoRect, xRadius: 20, yRadius: 20)

    ctx.saveGState()
    photoPath.addClip()

    // Photo contents: Vivid blue sky, golden sun & lush hill
    NSGradient(colors: [color(52, 140, 245), color(125, 202, 255), color(255, 230, 205)],
               atLocations: [0, 0.6, 1.0], colorSpace: .sRGB)!
        .draw(in: photoRect, angle: -90)

    // Golden sun
    let sunR: CGFloat = 28
    let sunP = NSPoint(x: photoRect.minX + 54, y: photoRect.maxY - 52)
    color(255, 235, 120).setFill()
    NSBezierPath(ovalIn: NSRect(x: sunP.x - sunR, y: sunP.y - sunR, width: sunR * 2, height: sunR * 2)).fill()

    // Distant mountain
    let mountain1 = NSBezierPath()
    mountain1.move(to: NSPoint(x: photoRect.minX - 10, y: photoRect.minY))
    mountain1.line(to: NSPoint(x: photoRect.minX + photoW * 0.45, y: photoRect.minY + photoH * 0.52))
    mountain1.line(to: NSPoint(x: photoRect.maxX + 10, y: photoRect.minY))
    mountain1.close()
    color(105, 138, 205, 0.78).setFill()
    mountain1.fill()

    // Near green hill
    let hill = NSBezierPath()
    hill.move(to: NSPoint(x: photoRect.minX - 10, y: photoRect.minY))
    hill.curve(to: NSPoint(x: photoRect.maxX + 10, y: photoRect.minY + photoH * 0.32),
               controlPoint1: NSPoint(x: photoRect.minX + photoW * 0.35, y: photoRect.minY + photoH * 0.44),
               controlPoint2: NSPoint(x: photoRect.minX + photoW * 0.75, y: photoRect.minY + photoH * 0.22))
    hill.line(to: NSPoint(x: photoRect.maxX + 10, y: photoRect.minY))
    hill.close()
    NSGradient(colors: [color(68, 182, 116), color(42, 138, 82)], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: hill, angle: -80)

    // Glossy diagonal sheen reflection
    let sheen = NSBezierPath()
    sheen.move(to: NSPoint(x: photoRect.minX - 20, y: photoRect.maxY + 10))
    sheen.line(to: NSPoint(x: photoRect.minX + photoW * 0.62, y: photoRect.maxY + 10))
    sheen.line(to: NSPoint(x: photoRect.minX - 20, y: photoRect.minY + photoH * 0.36))
    sheen.close()
    color(255, 255, 255, 0.24).setFill()
    sheen.fill()

    ctx.restoreGState()

    // Photo cutout inner border
    color(0, 0, 0, 0.12).setStroke()
    photoPath.lineWidth = 1.5
    photoPath.stroke()

    // Subtle handwritten caption line on Polaroid bottom chin
    let captionW: CGFloat = 88
    let captionRect = NSRect(x: -captionW / 2, y: -height + 36, width: captionW, height: 8)
    color(0, 0, 0, 0.14).setFill()
    NSBezierPath(roundedRect: captionRect, xRadius: 4, yRadius: 4).fill()

    // Wooden Clothespin clipping top of photo
    drawClothespin()

    ctx.restoreGState()
}

// Left Card: Main Todo Checklist Note (Yellow Pastel)
hangMemo(centerX: 360, width: 330, height: 380, angle: -4.5,
         bgColors: [color(255, 248, 200), color(255, 235, 160)], isTodo: true)

// Right Card: Polaroid Photo (Screenshot / Image Capture)
hangPhoto(centerX: 665, width: 310, height: 375, angle: 6.0)

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

let tiff = rep.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("Wrote SunMemo icon to \(out)")
