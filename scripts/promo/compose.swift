// Edits the recorded --demo tour into the promo: camera moves, titles,
// an opening and a closing card. Picture only; make-promo.sh adds the sound.
//
// Usage: compose <recording.mov> <markers.jsonl> <icon.png> <out.mov> [zh|en]
//
// Times come from the markers the demo wrote: zero is the first frame of the
// backdrop, found in the recording as the cut from black. Rectangles in the
// markers are in points from the top left of the main display.
import AppKit
import AVFoundation
import CoreImage

let args = CommandLine.arguments
guard args.count >= 5 else {
    FileHandle.standardError.write("usage: compose <recording.mov> <markers.jsonl> <icon.png> <out.mov> [zh|en]\n".data(using: .utf8)!)
    exit(2)
}
let videoURL = URL(fileURLWithPath: args[1])
let markersURL = URL(fileURLWithPath: args[2])
let iconURL = URL(fileURLWithPath: args[3])
let outURL = URL(fileURLWithPath: args[4])
let lang = args.count > 5 ? args[5] : "zh"

let fps: Int32 = 60
let outW = 1920, outH = 1080
let outro = 5.5

// MARK: - Markers

struct Mark {
    let event: String
    let t: Double
    let at: Double?
    let rect: CGRect?
    let rects: [CGRect]
    let raw: [String: Any]
}

func rect(_ any: Any?) -> CGRect? {
    guard let a = any as? [Double], a.count == 4 else { return nil }
    return CGRect(x: a[0], y: a[1], width: a[2], height: a[3])
}

let marks: [Mark] = try! String(contentsOf: markersURL, encoding: .utf8)
    .split(separator: "\n")
    .compactMap { line in
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        return Mark(event: o["event"] as! String, t: o["t"] as! Double, at: o["at"] as? Double,
                    rect: rect(o["rect"]), rects: (o["rects"] as? [[Double]] ?? []).compactMap { rect($0) }, raw: o)
    }

func all(_ e: String) -> [Mark] { marks.filter { $0.event == e } }
func time(_ e: String, _ i: Int = 0) -> Double {
    let m = all(e)
    guard !m.isEmpty else { fatalError("no \(e) in the markers") }
    return m[min(i, m.count - 1)].t
}

let start = all("start")[0].raw
let screen = (start["screen"] as! [Double])
let visibleArr = start["visible"] as! [Double]
let V = CGRect(x: visibleArr[0], y: visibleArr[1], width: visibleArr[2], height: visibleArr[3])
let tEnd = time("end")
let total = tEnd + outro

// MARK: - Source

let asset = AVURLAsset(url: videoURL)
let track = asset.tracks(withMediaType: .video)[0]
let srcSize = track.naturalSize
let k = srcSize.width / CGFloat(screen[0]) // pixels per point in the recording

func makeReader() -> (AVAssetReader, AVAssetReaderTrackOutput) {
    let reader = try! AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    reader.startReading()
    return (reader, output)
}

/// Mean brightness of the visible area, sampled on a coarse grid.
func brightness(_ pb: CVPixelBuffer) -> Double {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(pb)
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
    var sum = 0.0, n = 0.0
    let x0 = Int(V.minX * k), x1 = min(w, Int(V.maxX * k)), y0 = Int(V.minY * k), y1 = min(h, Int(V.maxY * k))
    for y in stride(from: y0 + 20, to: y1 - 20, by: 37) {
        for x in stride(from: x0 + 20, to: x1 - 20, by: 41) {
            let p = base + y * row + x * 4
            sum += 0.11 * Double(p[0]) + 0.59 * Double(p[1]) + 0.3 * Double(p[2])
            n += 1
        }
    }
    return sum / max(n, 1)
}

/// The recording time of the first backdrop frame: the end of the black.
func findSync() -> Double {
    let (_, output) = makeReader()
    var blackSince: Double?
    var lastBlack = -1.0
    while let sb = output.copyNextSampleBuffer() {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
        let b = brightness(pb)
        if b < 8 {
            if blackSince == nil { blackSince = pts }
            lastBlack = pts
        } else if let since = blackSince, lastBlack - since > 0.4, b > 30 {
            return pts
        } else if b >= 8 {
            blackSince = nil
        }
        if pts > 30 { break }
    }
    fatalError("no cut from black found in the recording")
}

let sync = findSync()
print(String(format: "backdrop appears at %.3fs in the recording; tour %.2fs, promo %.2fs", sync, tEnd, total))

// MARK: - Camera

/// The largest 16:9 frame inside the visible area, the camera at zoom 1.
let W0 = min(V.width, V.height * 16 / 9)
let H0 = W0 * 9 / 16

struct Cam {
    var cx: CGFloat, cy: CGFloat, z: CGFloat
    var crop: CGRect {
        let w = W0 / z, h = H0 / z
        var x = cx - w / 2, y = cy - h / 2
        x = min(max(x, V.minX), V.maxX - w)
        y = min(max(y, V.minY), V.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

func top(_ z: CGFloat, _ cx: CGFloat = V.midX, drop: CGFloat = 0) -> Cam {
    Cam(cx: cx, cy: V.minY + H0 / z / 2 + drop, z: z)
}
func wide(_ z: CGFloat = 1) -> Cam { Cam(cx: V.midX, cy: V.midY, z: z) }
/// Frames a rectangle so it fills this share of the frame's height.
func frame(_ r: CGRect, fill: CGFloat, maxZ: CGFloat = 1.7, lift: CGFloat = 0) -> Cam {
    let z = min(maxZ, max(1, H0 * fill / max(r.height, 1)))
    return Cam(cx: r.midX, cy: r.midY + lift, z: z)
}

struct Move { let at: Double; let dur: Double; let to: Cam }

func ease(_ x: Double) -> Double {
    let p = min(max(x, 0), 1)
    return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
}

var moves: [Move] = []
func move(_ at: Double, _ dur: Double, _ to: Cam) { moves.append(Move(at: at, dur: dur, to: to)) }

let lineDown = all("line_down").map(\.t)
let firstHover = all("hover").first?.rect
let lastHover = all("hover").last?.rect
let editorRect = all("editor").first?.rects.max { $0.height < $1.height }
/// The card taken down to read. Its window covers the screen; the card is a
/// wide 510 × 320 just below the middle.
let previewRect: CGRect? = all("preview").first.map { _ in
    CGRect(x: screen[0] / 2 - 255, y: screen[1] / 2 - 146, width: 510, height: 320)
}
let sweepCards = all("sweep_cards").first?.rects ?? []

move(0, 4.0, wide(1.0))
move(0.01, lineDown[0] - 0.2, wide(1.05))
move(lineDown[0] - 0.25, 1.3, top(1.38))
move(time("shot_fly") - 0.35, 0.9, top(1.18))
if let r = editorRect {
    move(time("editor_open") + 0.15, 1.0, frame(r, fill: 0.62, maxZ: 1.6, lift: 40))
}
move(time("memo_commit") - 0.05, 0.85, top(1.2))
move(time("memo_fly") + 0.3, 1.6, top(1.4))
if let r = firstHover {
    move(time("tick") - 1.1, 1.0, Cam(cx: r.midX, cy: r.midY + 150, z: 1.75))
}
if let r = previewRect {
    // The line and the card taken down from it, with the tether between.
    // The card ends three quarters down, leaving the bottom to the title.
    let needed = (r.maxY + 8 - V.minY) / 0.76
    let z = min(1.6, max(1, H0 / needed))
    move(time("preview_open") - 0.05, 0.9, Cam(cx: r.midX, cy: V.minY + H0 / z / 2, z: z))
}
move(time("preview_close") + 0.1, 0.9, top(1.3))
if let tear = all("tear").first?.at {
    move(tear - 0.3, 0.6, top(1.12))
}
move(time("cascade_start") - 0.4, 0.8, wide(1.0))
move(time("cascade_end") + 0.4, 1.0, top(1.25))
let sweep0 = time("sweep_start"), sweep1 = time("sweep_end")
if let left = sweepCards.first, let right = sweepCards.last {
    move(sweep0 - 0.6, 0.6, top(1.55, left.midX + 260))
    move(sweep0, sweep1 - sweep0 + 0.1, top(1.55, right.midX - 260))
} else {
    move(sweep0 - 0.6, 0.6, top(1.55, V.minX + V.width * 0.3))
    move(sweep0, sweep1 - sweep0 + 0.1, top(1.55, V.minX + V.width * 0.7))
}
if let r = lastHover {
    move(sweep1 + 0.15, 0.8, Cam(cx: r.midX, cy: r.midY + 150, z: 1.6))
}
move(time("line_up") - 0.35, 0.8, top(1.22))
move(time("end_hold") - 0.2, tEnd - time("end_hold") + 1.0, top(1.06))

moves.sort { $0.at < $1.at }

/// Where the camera is at a time: each move eases from wherever the camera
/// was when it began.
let initial = wide(1.0)
var fromValues: [Cam] = []
func camera(_ t: Double, upTo limit: Int? = nil) -> Cam {
    var cur = initial
    for (i, m) in moves.enumerated() {
        if let limit, i >= limit { break }
        if t < m.at { break }
        let from = i < fromValues.count ? fromValues[i] : cur
        let p = CGFloat(ease((t - m.at) / m.dur))
        cur = Cam(cx: from.cx + (m.to.cx - from.cx) * p,
                  cy: from.cy + (m.to.cy - from.cy) * p,
                  z: exp(log(from.z) + (log(m.to.z) - log(from.z)) * p))
    }
    return cur
}
for i in moves.indices { fromValues.append(camera(moves[i].at, upTo: i)) }

// MARK: - Type

let ink = NSColor(red: 0.15, green: 0.13, blue: 0.18, alpha: 1)
let inkSoft = NSColor(red: 0.27, green: 0.24, blue: 0.31, alpha: 0.9)
let amber = NSColor(red: 0.80, green: 0.50, blue: 0.16, alpha: 1)

func font(_ name: String, _ size: CGFloat) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold)
}

let titleFont = font(lang == "zh" ? "PingFangSC-Semibold" : "SFProRounded-Semibold", 62)
let subFont = font(lang == "zh" ? "PingFangSC-Regular" : "SFProRounded-Regular", 28)
let chipFont = font("SFProRounded-Semibold", 26)

func glow(_ alpha: CGFloat = 0.85, _ blur: CGFloat = 22) -> NSShadow {
    let s = NSShadow()
    s.shadowColor = NSColor(white: 1, alpha: alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = .zero
    return s
}

func attr(_ s: String, _ f: NSFont, _ c: NSColor, kern: CGFloat = 0, shadow: NSShadow? = glow()) -> NSAttributedString {
    var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c, .kern: kern]
    if let shadow { a[.shadow] = shadow }
    return NSAttributedString(string: s, attributes: a)
}

/// Draws into a transparent image of this size, flipped so y grows down.
func image(_ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

/// A keycap, like the ones on the keyboard.
func drawChip(_ label: String, at p: CGPoint) -> CGFloat {
    let text = attr(label, chipFont, ink, shadow: nil)
    let w = max(44, text.size().width + 26), h: CGFloat = 44
    let r = CGRect(x: p.x, y: p.y, width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.16)
    shadow.shadowBlurRadius = 10
    shadow.shadowOffset = NSSize(width: 0, height: -3)
    shadow.set()
    NSColor(white: 1, alpha: 0.94).setFill()
    NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 0, alpha: 0.08).setStroke()
    let border = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
    border.lineWidth = 1
    border.stroke()
    text.draw(at: CGPoint(x: r.midX - text.size().width / 2, y: r.midY - text.size().height / 2))
    return w
}

struct Caption {
    let start: Double
    let end: Double
    let title: String
    let sub: String
    let chips: [String]
    let low: Bool // in the lower middle; otherwise along the bottom
    var light = false // white type, over a dimmed picture
    var picture: CGImage? = nil
}

/// A title with a line of keycaps and a softer line under it, centered.
func render(_ c: Caption) -> CGImage {
    let size = CGSize(width: 1600, height: 200)
    return image(size) { _ in
        let shade = NSShadow()
        shade.shadowColor = NSColor(white: 0, alpha: 0.55)
        shade.shadowBlurRadius = 18
        shade.shadowOffset = NSSize(width: 0, height: -2)
        let title = attr(c.title, titleFont, c.light ? .white : ink, kern: lang == "zh" ? 2 : 0,
                         shadow: c.light ? shade : glow())
        let ts = title.size()
        title.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: 22))
        let sub = attr(c.sub, subFont, c.light ? NSColor(white: 1, alpha: 0.88) : inkSoft, kern: lang == "zh" ? 1 : 0,
                       shadow: c.light ? shade : glow(0.9, 14))
        let ss = sub.size()
        let chipWidths = c.chips.map { max(44, attr($0, chipFont, ink).size().width + 26) }
        let chipsW = chipWidths.reduce(0, +) + CGFloat(max(c.chips.count - 1, 0)) * 8
        let gap: CGFloat = c.chips.isEmpty ? 0 : 16
        var x = (size.width - chipsW - gap - ss.width) / 2
        let y: CGFloat = 22 + ts.height + 14
        for chip in c.chips {
            x += drawChip(chip, at: CGPoint(x: x, y: y)) + 8
        }
        if !c.chips.isEmpty { x += gap - 8 }
        sub.draw(at: CGPoint(x: x, y: y + (44 - ss.height) / 2))
    }
}

func T(_ zh: String, _ en: String) -> String { lang == "zh" ? zh : en }

let firstFly = time("memo_fly")
let hover0 = all("hover").first?.t ?? (time("tick") - 1.0)
let tear0 = all("tear").first?.at ?? (time("cascade_start") - 3)
var captions: [Caption] = [
    Caption(start: lineDown[0] + 0.45, end: time("shot_fly") - 0.25,
            title: T("屏幕顶端，挂一根晾衣绳", "A clothesline along the top of your screen"),
            sub: T("鼠标推到顶边也能拉下来", "or push the pointer to the top edge"),
            chips: ["⌃", "⌥", "Space"], low: true),
    Caption(start: time("shot_fly") - 0.1, end: time("editor_open") - 0.2,
            title: T("截图，自己飞上绳", "Screenshots hang themselves"),
            sub: T("截完图，不用再去桌面翻文件", "no more digging through the desktop"),
            chips: [], low: true),
    Caption(start: time("editor_open") + 0.35, end: time("memo_commit") + 0.6,
            title: T("想到什么，随手记一张", "Jot down whatever comes to mind"),
            sub: T("Markdown 和待办清单都支持", "Markdown and checklists included"),
            chips: ["⌃", "⌥", "N"], low: false),
    Caption(start: firstFly - 0.1, end: hover0 - 0.3,
            title: T("四种颜色，三种比例", "Four colors, three shapes"),
            sub: T("宽版、方版、竖版，按内容挑", "wide, square or tall, to fit what you write"),
            chips: [], low: true),
    Caption(start: hover0 + 0.1, end: time("preview_open") - 0.2,
            title: T("待办，在绳上直接打勾", "Tick off to-dos right on the line"),
            sub: T("不用点开，进度条跟着走", "the progress bar keeps up"),
            chips: [], low: true),
    Caption(start: time("preview_open") + 0.3, end: time("preview_close") + 0.2,
            title: T("单击取下，放大细看", "Click to take a card down"),
            sub: T("一根拉绳，连着它原来的位置", "a tether keeps it tied to its place"),
            chips: [], low: false, light: true),
    Caption(start: tear0 - 0.35, end: time("cascade_start") - 0.25,
            title: T("撕下就归档", "Tear it off to archive it"),
            sub: T("文字自动存进本地 SunMemo.md", "the text is kept in SunMemo.md"),
            chips: [], low: true),
    Caption(start: time("cascade_start") + 0.9, end: sweep0 - 0.3,
            title: T("挂几十张，也不乱", "Dozens of cards, never a mess"),
            sub: T("越挂越多，间距自动收紧", "the line closes ranks as it fills"),
            chips: [], low: true),
    Caption(start: sweep0 - 0.1, end: time("line_up") - 0.3,
            title: T("划过去，像扑克牌一样让开", "Hover, and the cards make room"),
            sub: T("想看哪张，哪张就站到前面", "like a hand of playing cards"),
            chips: [], low: true),
    Caption(start: time("line_up") + 0.05, end: tEnd - 1.4,
            title: T("用完收起，随叫随到", "Out of the way until you need it"),
            sub: T("鼠标碰到屏幕顶边，它就下来", "touch the top edge to bring it back"),
            chips: [], low: true),
]
for i in captions.indices { captions[i].picture = render(captions[i]) }

// Opening and closing cards.
let icon = NSImage(contentsOf: iconURL)!

func brandBlock(tagline: String, footer: String?) -> CGImage {
    let size = CGSize(width: 1400, height: 760)
    return image(size) { _ in
        let iconSize: CGFloat = 176
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor(white: 0, alpha: 0.18)
        s.shadowBlurRadius = 30
        s.shadowOffset = NSSize(width: 0, height: -10)
        s.set()
        icon.draw(in: CGRect(x: (size.width - iconSize) / 2, y: 40, width: iconSize, height: iconSize),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        let name = attr(T("晾想法", "SunMemo"), font(lang == "zh" ? "PingFangSC-Semibold" : "SFProRounded-Bold", 96), ink, kern: 6)
        let ns = name.size()
        name.draw(at: CGPoint(x: (size.width - ns.width) / 2, y: 248))
        var y = 248 + ns.height + 2
        if lang == "zh" {
            let latin = attr("SUNMEMO", font("SFProRounded-Semibold", 26), amber, kern: 9, shadow: glow(0.8, 12))
            let ls = latin.size()
            latin.draw(at: CGPoint(x: (size.width - ls.width) / 2, y: y))
            y += ls.height + 22
        } else {
            y += 14
        }
        let tag = attr(tagline, subFont.withSize(34), inkSoft, kern: lang == "zh" ? 2 : 0)
        let tsz = tag.size()
        tag.draw(at: CGPoint(x: (size.width - tsz.width) / 2, y: y))
        y += tsz.height + 40
        if let footer {
            let f = attr(footer, subFont.withSize(24), inkSoft, kern: 1, shadow: glow(0.9, 10))
            let fs = f.size()
            f.draw(at: CGPoint(x: (size.width - fs.width) / 2, y: y))
        }
    }
}

let tagline = T("把没做完的想法，晾在桌面的阳光下", "Hang your unfinished thoughts in the sun")
let openingCard = brandBlock(tagline: tagline, footer: nil)
let closingCard = brandBlock(tagline: tagline,
                             footer: T("免费开源 · 数据只存本机 · macOS 13+   github.com/km-open-lab/SunMemo",
                                       "Free and open source · Local only · macOS 13+   github.com/km-open-lab/SunMemo"))

// MARK: - Render

let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mov)
try? FileManager.default.removeItem(at: outURL)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: outW,
    AVVideoHeightKey: outH,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 40_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoExpectedSourceFrameRateKey: fps,
    ],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: outW,
    kCVPixelBufferHeightKey as String: outH,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let (_, output) = makeReader()
var current: CGImage?
var pending: CMSampleBuffer? = output.copyNextSampleBuffer()

func cgImage(_ sb: CMSampleBuffer) -> CGImage? {
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { return nil }
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: CVPixelBufferGetWidth(pb),
                        height: CVPixelBufferGetHeight(pb), bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    return ctx?.makeImage()
}

/// The newest recorded frame at or before this recording time.
func frame(at src: Double) -> CGImage? {
    while let sb = pending, CMSampleBufferGetPresentationTimeStamp(sb).seconds <= src + 0.0005 {
        if let img = cgImage(sb) { current = img }
        pending = output.copyNextSampleBuffer()
    }
    return current
}

let ci = CIContext(options: [.useSoftwareRenderer: false])
let frames = Int(total * Double(fps))
let freezeAt = tEnd + 0.3
let blurFrom = tEnd - 1.0

func smooth(_ a: Double, _ b: Double, _ t: Double) -> CGFloat {
    CGFloat(ease((t - a) / (b - a)))
}

/// Fades a picture in with a small rise and out with a small lift.
func drawAnimated(_ ctx: CGContext, _ img: CGImage, centerY: CGFloat, t: Double, start: Double, end: Double,
                  rise: CGFloat = 24, scale: CGFloat = 1) {
    let inP = smooth(start, start + 0.5, t)
    let outP = smooth(end - 0.35, end, t)
    let alpha = inP * (1 - outP)
    guard alpha > 0.001 else { return }
    let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
    let dy = rise * (1 - inP) - 12 * outP
    // centerY counts from the top of the frame.
    let y = CGFloat(outH) - centerY - h / 2 - dy
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.draw(img, in: CGRect(x: (CGFloat(outW) - w) / 2, y: y, width: w, height: h))
    ctx.restoreGState()
}

let started = Date()
for i in 0..<frames {
    autoreleasepool {
        let t = Double(i) / Double(fps)
        let src = sync + min(t, freezeAt)
        while !input.isReadyForMoreMediaData { usleep(2000) }
        var pbOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pbOut)
        guard let pb = pbOut else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: outW, height: outH, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.interpolationQuality = .high
        ctx.setFillColor(.black)
        ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))

        // The recording through the camera.
        if let img = frame(at: src) {
            let c = camera(t).crop
            let s = CGFloat(outW) / (c.width * k)
            let imgW = CGFloat(img.width), imgH = CGFloat(img.height)
            let dest = CGRect(x: -c.minX * k * s, y: CGFloat(outH) + c.minY * k * s - imgH * s,
                              width: imgW * s, height: imgH * s)
            if t > blurFrom {
                // The closing card: the last frame softens behind the logo.
                let p = smooth(blurFrom, tEnd + 0.4, t)
                let layer = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
                layer.interpolationQuality = .high
                layer.draw(img, in: dest)
                let base = CIImage(cgImage: layer.makeImage()!)
                let blurred = base.clampedToExtent().applyingGaussianBlur(sigma: Double(p) * 26).cropped(to: base.extent)
                if let out = ci.createCGImage(blurred, from: base.extent) {
                    ctx.draw(out, in: CGRect(x: 0, y: 0, width: outW, height: outH))
                }
                ctx.setFillColor(NSColor(white: 1, alpha: 0.38 * p).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
            } else {
                ctx.draw(img, in: dest)
            }
        }

        // Opening card, over the empty backdrop.
        drawAnimated(ctx, openingCard, centerY: 510, t: t, start: 0.45, end: lineDown[0] - 0.05, rise: 30, scale: 0.92)

        for c in captions where t >= c.start - 0.05 && t <= c.end + 0.05 {
            if let pic = c.picture {
                drawAnimated(ctx, pic, centerY: c.low ? 790 : 935, t: t, start: c.start, end: c.end)
            }
        }

        // Closing card.
        drawAnimated(ctx, closingCard, centerY: 500, t: t, start: tEnd - 0.1, end: total + 10, rise: 30, scale: 0.92)

        // Fade up from black, and down to it at the very end.
        let black = max(1 - smooth(0, 0.8, t), smooth(total - 0.9, total, t))
        if black > 0.001 {
            ctx.setFillColor(NSColor(white: 0, alpha: black).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
        }

        CVPixelBufferUnlockBaseAddress(pb, [])
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        if i % 300 == 0 {
            print(String(format: "  %5.1fs / %.1fs  (%.0fs elapsed)", t, total, Date().timeIntervalSince(started)))
        }
    }
}

input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed {
    print("writing failed: \(writer.error?.localizedDescription ?? "unknown")")
    exit(1)
}
print("wrote \(outURL.path)")
