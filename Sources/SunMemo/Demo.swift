import AppKit
import SwiftUI

/// `--demo`: a scripted tour of SunMemo, for recording the promo video with
/// `scripts/record-demo.sh`.
///
/// It runs on throwaway data. Settings go to a separate defaults suite and
/// files to a temporary folder, both wiped when the demo starts, so your
/// memos, your screenshots, `~/Documents/SunMemo.md` and the macOS screenshot
/// settings are never touched. The app quits when the tour ends.
///
/// Options, after `--demo`:
/// - `--demo-backdrop <image>`: the picture behind the line. Without it, a
///   drawn sunrise. Either way it covers the desktop icons and other windows.
/// - `--demo-markers <file>`: writes one JSON line per moment of the tour,
///   timed from the first frame of the backdrop, so a video editor can put
///   titles and sounds on the right frame.
/// - `--demo-no-captions`: leaves the captions out, for adding them later.
enum Demo {
    static let isActive = CommandLine.arguments.contains("--demo")

    private static let suiteName = "com.zhangkaiming.SunMemo.demo"

    /// Where settings are kept: a fresh suite in the demo, the app's own otherwise.
    static let defaults: UserDefaults = {
        guard isActive else { return .standard }
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName) ?? .standard
    }()

    /// Where the demo's memos, screenshots and export live, emptied at start.
    static let folder: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SunMemo-Demo", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: folder)
    }

    /// The value after an option, as in `--demo-markers /tmp/m.jsonl`.
    static func option(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var showsCaptions: Bool { !CommandLine.arguments.contains("--demo-no-captions") }
}

/// The demo's own words, in the language the app runs in. They live here
/// rather than in the string tables, which hold only the app's own text.
private func T(_ english: String, _ chinese: String, _ spanish: String) -> String {
    switch Bundle.main.preferredLocalizations.first {
    case "zh-Hans": return chinese
    case "es": return spanish
    default: return english
    }
}

/// Plays the tour, about a minute, on the main display.
@MainActor
enum DemoDirector {
    static func run(_ app: AppDelegate) {
        Task { @MainActor in
            await tour(app)
            Demo.cleanUp()
            NSApp.terminate(nil)
        }
    }

    private static func tour(_ app: AppDelegate) async {
        let line = app.demoLine
        let backdrop = DemoBackdrop()
        let markers = DemoMarkers()
        let caption = DemoCaption(visible: Demo.showsCaptions)
        app.demoHold = true
        parkPointer()

        // A black frame, then the backdrop: the cut marks time zero in the video.
        await pause(1.2)
        backdrop.showPicture()
        markers.start(backdrop: backdrop)
        parkPointer()
        await pause(3.6)

        // The empty line comes down.
        caption.show(T("Hang your thoughts on the clothesline", "把想法晾在桌面阳光下", "Tiende tus ideas en el tendedero"), "SunMemo")
        markers.mark("line_down")
        app.demoShowLine()
        await pause(2.6)

        // A screenshot lifts off and flies to the line.
        caption.show(T("Screenshots hang themselves on the line", "截图，自己飞上晾衣绳", "Las capturas se cuelgan solas"))
        await pause(0.5)
        if let shot = makeScreenshot(.sunset, at: CGRect(x: 0, y: 0, width: 760, height: 475), centered: true) {
            markers.mark("shot_fly")
            app.demoHang(shot)
        }
        let shotID = line.items.last?.id
        markers.card("shot_land", shotID, app, after: 0.7)
        await pause(2.8)

        // A memo typed in the editor.
        caption.show(T("Jot a memo with ⌃⌥N", "⌃⌥N，随手记一张", "Anota con ⌃⌥N"))
        markers.mark("editor_open")
        QuickMemoWindowController.shared.showForDemo(line: line, color: "yellow", aspectRatio: "wide")
        await pause(0.9)
        markers.windows("editor")
        let release = [
            "## " + T("This week's release", "本周发布", "Lanzamiento de la semana"),
            "- [x] " + T("Screenshots hang themselves", "截图自动挂绳", "Capturas que se cuelgan solas"),
            "- [ ] " + T("Record the promo video", "录一支宣传片", "Grabar el vídeo promocional"),
            "- [ ] " + T("Ship v1.2", "发布 v1.2", "Publicar la v1.2"),
        ].joined(separator: "\n")
        await type(release, markers)
        await pause(0.7)
        markers.mark("memo_commit")
        QuickMemoWindowController.shared.commitForDemo()
        let releaseID = line.items.last(where: { $0.isMemo })?.id
        markers.card("memo_land", releaseID, app, after: 0.75)
        await pause(2.4)

        // More colors and shapes.
        caption.show(T("Four colors, three shapes", "四种颜色，三种比例", "Cuatro colores, tres formas"))
        let center = NSScreen.screens.first.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? .zero
        let screenSize = NSScreen.screens.first?.frame.size ?? CGSize(width: 1440, height: 900)
        markers.mark("memo_fly")
        app.hangMemoFlight(text: "## " + T("Idea", "灵感", "Idea") + "\n"
                           + T("A clothesline for everything you have not finished yet",
                               "给所有还没做完的事，一根晾衣绳", "Un tendedero para todo lo que aún no has terminado"),
                           color: "green", aspectRatio: "square",
                           from: CGRect(x: center.x - screenSize.width * 0.3, y: center.y - 60, width: 260, height: 260))
        markers.card("memo_land", line.items.last?.id, app, after: 0.75)
        await pause(1.0)
        markers.mark("memo_fly")
        app.hangMemoFlight(text: [
            "## " + T("Weekend", "周末", "Fin de semana"),
            "- [x] " + T("Coffee by the window", "窗边喝杯咖啡", "Café junto a la ventana"),
            "- [ ] " + T("Bike along the coast", "沿海边骑车", "Bici por la costa"),
            "- [ ] " + T("Water the plants", "给绿植浇水", "Regar las plantas"),
        ].joined(separator: "\n"), color: "pink", aspectRatio: "tall",
                           from: CGRect(x: center.x - 120, y: center.y - 120, width: 240, height: 320))
        let weekendID = line.items.last(where: { $0.isMemo })?.id
        markers.card("memo_land", weekendID, app, after: 0.75)
        await pause(1.0)
        markers.mark("memo_fly")
        app.hangMemoFlight(text: "## " + T("Next week", "下周", "La próxima semana") + "\n"
                           + T("Sort the holiday photos", "整理旅行照片", "Ordenar las fotos del viaje"),
                           color: "blue", aspectRatio: "wide",
                           from: CGRect(x: center.x + screenSize.width * 0.15, y: center.y - 50, width: 340, height: 216))
        markers.card("memo_land", line.items.last?.id, app, after: 0.75)
        await pause(2.6)

        // A to-do ticked on the line.
        caption.show(T("Tick off to-dos right on the line", "待办，在绳上直接打勾", "Marca tareas en el tendedero"))
        if let releaseID {
            line.hoveredID = releaseID
            markers.card("hover", releaseID, app, after: 0.3)
            await pause(1.0)
            markers.mark("tick")
            line.toggleMemoTodoLine(id: releaseID, lineIndex: 2)
            await pause(1.6)
            line.hoveredID = nil
            await pause(0.4)
        }

        // Taken down to read, with the tether back to the line.
        caption.show(T("Click to take a card down and read it", "单击取下，放大细看", "Haz clic para descolgarla y leerla"))
        if let releaseID {
            markers.mark("preview_open")
            MemoPreviewWindowController.shared.show(line: line, itemID: releaseID)
            await pause(0.8)
            markers.windows("preview")
            await pause(1.2)
            markers.mark("tick")
            line.toggleMemoTodoLine(id: releaseID, lineIndex: 3)
            await pause(1.8)
            markers.mark("preview_close")
            MemoPreviewWindowController.shared.close()
            await pause(1.0)
        }
        _ = shotID

        // Torn off and archived.
        caption.show(T("Tear it off. The text stays in SunMemo.md", "撕下即归档，文字留在 SunMemo.md",
                       "Arráncala: el texto queda en SunMemo.md"))
        await pause(0.6)
        if let weekendID {
            markers.card("tear", weekendID, app)
            line.discard(weekendID)
        }
        await pause(2.4)

        // A busy week: the line fills up and the cards close ranks.
        caption.show(T("Dozens of cards, never a mess", "挂几十张，也不乱", "Decenas de tarjetas, sin desorden"))
        markers.mark("cascade_start")
        for (i, entry) in cascade.enumerated() {
            let size = CGSize(width: 240, height: 180)
            let spot = cascadeOrigins[i % cascadeOrigins.count]
            // Between the middle of the screen and the line, left to right.
            let from = CGRect(x: center.x + spot.x * screenSize.width - size.width / 2,
                              y: center.y + spot.y * screenSize.height - size.height / 2,
                              width: size.width, height: size.height)
            switch entry {
            case .memo(let text, let color, let shape):
                app.hangMemoFlight(text: text, color: color, aspectRatio: shape, from: from)
            case .shot(let scene):
                // Screenshot areas are in points from the top left of the display.
                let top = NSScreen.screens.first?.frame.height ?? 0
                let area = CGRect(x: from.minX, y: top - from.maxY, width: 288, height: 180)
                if let url = makeScreenshot(scene, at: area, centered: false) { app.demoHang(url) }
            }
            markers.card("cascade_fly", line.items.last?.id, app)
            await pause(0.24)
        }
        markers.mark("cascade_end")
        await pause(1.8)

        // The cards part like a hand of playing cards.
        caption.show(T("Hover and the cards make room", "划过去，卡片像扑克牌一样让开",
                       "Pasa por encima y las tarjetas se apartan"))
        markers.mark("sweep_start")
        markers.cards("sweep_cards", line.items.filter { !$0.falling }.map(\.id), app)
        for item in line.items where !item.falling {
            line.hoveredID = item.id
            await pause(0.17)
        }
        markers.mark("sweep_end")
        if let releaseID {
            line.hoveredID = releaseID
            markers.card("hover", releaseID, app, after: 0.3)
        }
        await pause(1.6)
        line.hoveredID = nil
        await pause(0.8)

        // Tucked away, and pulled back down.
        caption.show(T("Push the pointer to the top edge to pull it down", "鼠标碰到屏幕顶边，随时拉下来",
                       "Lleva el puntero arriba para bajarlo"))
        markers.mark("line_up")
        app.demoHideLine()
        await pause(1.6)
        markers.mark("line_down")
        app.demoShowLine()
        await pause(2.6)

        // Closing.
        caption.show(T("Hang your thoughts on the clothesline", "把想法晾在桌面阳光下", "Tiende tus ideas en el tendedero"), "SunMemo")
        markers.mark("end_hold")
        await pause(3.5)
        caption.hide()
        markers.mark("end")
        await pause(0.8)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Types into the editor one character at a time, like a person.
    private static func type(_ text: String, _ markers: DemoMarkers) async {
        for character in text {
            guard let view = QuickMemoWindowController.shared.demoTextView else { return }
            view.insertText(String(character), replacementRange: view.selectedRange())
            markers.mark(character == "\n" ? "key_return" : "key")
            await pause(character == "\n" ? 0.3 : 0.06)
        }
    }

    /// Moves the pointer to the bottom edge, out of the shot: the demo moves
    /// nothing but its own windows.
    private static func parkPointer() {
        guard let main = NSScreen.screens.first else { return }
        CGWarpMouseCursorPosition(CGPoint(x: main.frame.midX, y: main.frame.height - 2))
    }

    // MARK: Cascade

    private enum Entry {
        case memo(String, String, String)
        case shot(DemoScene)
    }

    private static let cascade: [Entry] = [
        .memo("## " + T("Reading", "读书笔记", "Lectura") + "\n- [x] " + T("Chapter 3", "第三章", "Capítulo 3")
              + "\n- [ ] " + T("Copy the quotes", "整理摘抄", "Copiar las citas"), "yellow", "wide"),
        .shot(.night),
        .memo("## " + T("Groceries", "买菜", "Compra") + "\n- [ ] " + T("Avocados", "牛油果", "Aguacates")
              + "\n- [ ] " + T("Oat milk", "燕麦奶", "Leche de avena") + "\n- [x] " + T("Eggs", "鸡蛋", "Huevos"), "green", "tall"),
        .memo("## 15:00\n" + T("Agree on the launch date", "确认上线时间", "Fijar la fecha de lanzamiento"), "pink", "wide"),
        .shot(.hills),
        .memo("## " + T("Call", "电话", "Llamar") + "\n" + T("Ring the landlord back", "回电给房东", "Devolver la llamada al casero"), "blue", "square"),
        .memo("## " + T("Running", "跑步", "Correr") + "\n- [x] " + T("Mon 5 km", "周一 5 公里", "Lun 5 km")
              + "\n- [ ] " + T("Wed 5 km", "周三 5 公里", "Mié 5 km") + "\n- [ ] " + T("Sat 10 km", "周六 10 公里", "Sáb 10 km"), "yellow", "tall"),
        .shot(.dunes),
        .memo("## " + T("To read", "待读", "Por leer") + "\n" + T("A long piece on focus", "一篇讲专注力的长文", "Un artículo largo sobre la concentración"), "green", "wide"),
        .memo("## " + T("Gift", "礼物", "Regalo") + "\n" + T("Mum's birthday on the 20th", "妈妈 20 号生日", "Cumpleaños de mamá el día 20"), "pink", "square"),
        .shot(.lake),
        .memo("## " + T("Bug", "Bug", "Error") + "\n" + T("Clipboard button flickers", "剪贴板按钮会闪", "El botón del portapapeles parpadea"), "blue", "wide"),
        .memo("## " + T("Trip", "出行", "Viaje") + "\n- [ ] " + T("Book the train", "订高铁票", "Reservar el tren")
              + "\n- [ ] " + T("Pack the camera", "带上相机", "Llevar la cámara"), "yellow", "square"),
        .shot(.sunset),
    ]

    /// Where cascade cards take off, as shares of the screen from its middle,
    /// clear of the bottom where a video puts its titles.
    private static let cascadeOrigins: [CGPoint] = [
        CGPoint(x: -0.30, y: 0.04), CGPoint(x: 0.26, y: 0.10), CGPoint(x: -0.08, y: 0.00), CGPoint(x: 0.12, y: 0.12),
        CGPoint(x: -0.38, y: 0.12), CGPoint(x: 0.36, y: 0.02), CGPoint(x: 0.02, y: 0.10), CGPoint(x: -0.20, y: 0.14),
        CGPoint(x: 0.22, y: -0.02), CGPoint(x: -0.02, y: 0.16), CGPoint(x: 0.40, y: 0.12), CGPoint(x: -0.42, y: 0.02),
        CGPoint(x: 0.08, y: 0.04), CGPoint(x: -0.14, y: 0.08),
    ]

    // MARK: Screenshots

    /// Draws a landscape into the demo's screenshots folder, tagged with a
    /// capture area, in points from the top left of the main display, so it
    /// takes off from there like a real screenshot.
    private static func makeScreenshot(_ scene: DemoScene, at area: CGRect, centered: Bool) -> URL? {
        let width = 1280, height = 800
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        scene.draw(in: NSSize(width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let folder = Inbox.folder
        let url = folder.appendingPathComponent("Screenshot \(UUID().uuidString.prefix(8)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
        } catch {
            log.error("Demo screenshot not written: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        var rect = area
        if centered, let main = NSScreen.screens.first {
            rect.origin = CGPoint(x: (main.frame.width - area.width) / 2, y: (main.frame.height - area.height) / 2 + 40)
        }
        let values = [rect.minX, rect.minY, rect.width, rect.height].map { NSNumber(value: Double($0)) }
        if let plist = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) {
            url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return }
                _ = plist.withUnsafeBytes {
                    setxattr(path, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", $0.baseAddress, plist.count, 0, 0)
                }
            }
        }
        return url
    }
}

/// The landscapes the demo's screenshots show.
private enum DemoScene {
    case sunset, night, hills, dunes, lake

    private struct Palette {
        let sky: [NSColor]
        let sun: NSColor
        let far: NSColor
        let near: [NSColor]
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: a)
    }

    private var palette: Palette {
        switch self {
        case .sunset:
            return Palette(sky: [Self.rgb(0.98, 0.58, 0.42), Self.rgb(0.95, 0.78, 0.52), Self.rgb(0.56, 0.72, 0.88)],
                           sun: Self.rgb(1.0, 0.92, 0.75, 0.95), far: Self.rgb(0.28, 0.32, 0.45, 0.88),
                           near: [Self.rgb(0.32, 0.44, 0.58, 0.95), Self.rgb(0.18, 0.24, 0.36)])
        case .night:
            return Palette(sky: [Self.rgb(0.20, 0.22, 0.42), Self.rgb(0.10, 0.12, 0.28), Self.rgb(0.04, 0.05, 0.14)],
                           sun: Self.rgb(0.98, 0.96, 0.86), far: Self.rgb(0.14, 0.16, 0.30, 0.95),
                           near: [Self.rgb(0.08, 0.10, 0.20), Self.rgb(0.03, 0.04, 0.10)])
        case .hills:
            return Palette(sky: [Self.rgb(0.80, 0.92, 0.98), Self.rgb(0.55, 0.78, 0.95), Self.rgb(0.40, 0.66, 0.92)],
                           sun: Self.rgb(1.0, 0.98, 0.88), far: Self.rgb(0.45, 0.66, 0.48, 0.9),
                           near: [Self.rgb(0.42, 0.68, 0.36), Self.rgb(0.26, 0.48, 0.24)])
        case .dunes:
            return Palette(sky: [Self.rgb(0.99, 0.86, 0.66), Self.rgb(0.97, 0.72, 0.52), Self.rgb(0.86, 0.60, 0.62)],
                           sun: Self.rgb(1.0, 0.97, 0.88), far: Self.rgb(0.86, 0.56, 0.38, 0.9),
                           near: [Self.rgb(0.90, 0.64, 0.40), Self.rgb(0.72, 0.44, 0.28)])
        case .lake:
            return Palette(sky: [Self.rgb(0.93, 0.80, 0.86), Self.rgb(0.78, 0.76, 0.92), Self.rgb(0.58, 0.68, 0.90)],
                           sun: Self.rgb(1.0, 0.95, 0.92, 0.9), far: Self.rgb(0.42, 0.40, 0.62, 0.9),
                           near: [Self.rgb(0.56, 0.66, 0.86, 0.95), Self.rgb(0.36, 0.44, 0.70)])
        }
    }

    func draw(in size: NSSize) {
        let p = palette
        NSGradient(colors: p.sky)?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        if self == .night {
            p.sun.withAlphaComponent(0.85).setFill()
            for i in 0..<60 {
                let x = CGFloat((i * 397) % 1280), y = CGFloat(380 + (i * 211) % 400)
                let r = CGFloat(1 + i % 3)
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: r, height: r)).fill()
            }
        }
        p.sun.setFill()
        let sunX: CGFloat = self == .night ? 900 : 560
        NSBezierPath(ovalIn: NSRect(x: sunX, y: 400, width: 150, height: 150)).fill()

        let far = NSBezierPath()
        far.move(to: NSPoint(x: 0, y: 290))
        if self == .hills || self == .dunes {
            far.curve(to: NSPoint(x: 640, y: 380), controlPoint1: NSPoint(x: 200, y: 420), controlPoint2: NSPoint(x: 420, y: 300))
            far.curve(to: NSPoint(x: 1280, y: 330), controlPoint1: NSPoint(x: 860, y: 460), controlPoint2: NSPoint(x: 1080, y: 300))
        } else {
            far.line(to: NSPoint(x: 350, y: 510))
            far.line(to: NSPoint(x: 770, y: 350))
            far.line(to: NSPoint(x: 1020, y: 540))
            far.line(to: NSPoint(x: 1280, y: 320))
        }
        far.line(to: NSPoint(x: 1280, y: 0))
        far.line(to: NSPoint(x: 0, y: 0))
        far.close()
        p.far.setFill()
        far.fill()

        if self == .hills || self == .dunes {
            let near = NSBezierPath()
            near.move(to: NSPoint(x: 0, y: 200))
            near.curve(to: NSPoint(x: 1280, y: 230), controlPoint1: NSPoint(x: 420, y: 330), controlPoint2: NSPoint(x: 860, y: 120))
            near.line(to: NSPoint(x: 1280, y: 0))
            near.line(to: NSPoint(x: 0, y: 0))
            near.close()
            NSGradient(colors: p.near)?.draw(in: near, angle: -90)
        } else {
            NSGradient(colors: p.near)?.draw(in: NSRect(x: 0, y: 0, width: size.width, height: 250), angle: -90)
        }
    }
}

/// A full screen picture just above other apps' windows and below
/// SunMemo's, so the video shows nothing of your desktop.
@MainActor
private final class DemoBackdrop {
    private let window: NSWindow
    private let imageView = NSImageView()
    /// Where the picture sits, in points from the top left of the main
    /// display, without the menu bar and the Dock.
    let visibleArea: CGRect
    let screenSize: CGSize
    let scale: CGFloat

    init() {
        let screen = NSScreen.screens.first
        let frame = screen?.frame ?? .zero
        let visible = screen?.visibleFrame ?? .zero
        screenSize = frame.size
        scale = screen?.backingScaleFactor ?? 1
        visibleArea = CGRect(x: visible.minX - frame.minX, y: frame.maxY - visible.maxY,
                             width: visible.width, height: visible.height)

        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = NSRect(origin: .zero, size: frame.size)
        imageView.autoresizingMask = [.width, .height]
        imageView.isHidden = true
        window.contentView?.addSubview(imageView)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func showPicture() {
        let picture = Demo.option("--demo-backdrop").flatMap { NSImage(contentsOfFile: $0) } ?? Self.sunrise(window.frame.size)
        imageView.image = Self.filling(picture, window.frame.size)
        imageView.isHidden = false
        window.display()
    }

    /// The picture cropped to fill the screen without stretching.
    private static func filling(_ image: NSImage, _ size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let k = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * k, h = image.size.height * k
            image.draw(in: NSRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            return true
        }
    }

    private static func sunrise(_ size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.93, green: 0.80, blue: 0.70, alpha: 1),
                NSColor(red: 0.98, green: 0.88, blue: 0.74, alpha: 1),
                NSColor(red: 0.74, green: 0.78, blue: 0.92, alpha: 1),
                NSColor(red: 0.58, green: 0.62, blue: 0.84, alpha: 1),
            ])?.draw(in: rect, angle: 90)
            return true
        }
    }
}

/// The tour's timeline, one JSON line per moment, for the video editor.
/// Times are seconds from the first frame of the backdrop; rectangles are
/// in points from the top left of the main display.
@MainActor
private final class DemoMarkers {
    private let handle: FileHandle?
    private var zero: CFTimeInterval = 0

    init() {
        guard let path = Demo.option("--demo-markers") else { handle = nil; return }
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    func start(backdrop: DemoBackdrop) {
        zero = CACurrentMediaTime()
        let v = backdrop.visibleArea
        write(["event": "start", "t": 0,
               "screen": [backdrop.screenSize.width, backdrop.screenSize.height],
               "scale": backdrop.scale,
               "visible": [v.minX, v.minY, v.width, v.height]])
    }

    func mark(_ event: String, _ extra: [String: Any] = [:]) {
        var line = extra
        line["event"] = event
        line["t"] = (CACurrentMediaTime() - zero).rounded(places: 3)
        write(line)
    }

    /// Where a card hangs, now or a moment later once it has landed.
    func card(_ event: String, _ id: UUID?, _ app: AppDelegate, after delay: Double = 0) {
        guard handle != nil, let id else { return }
        let t = CACurrentMediaTime() - zero
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let frame = app.cardFrame(for: id) else { return }
                self.mark(event, ["at": t.rounded(places: 3), "rect": self.topLeft(frame)])
            }
        }
    }

    /// Where several cards hang right now.
    func cards(_ event: String, _ ids: [UUID], _ app: AppDelegate) {
        guard handle != nil else { return }
        mark(event, ["rects": ids.compactMap { app.cardFrame(for: $0) }.map(topLeft)])
    }

    /// The frames of SunMemo's windows other than the line, the backdrop and the captions.
    func windows(_ event: String) {
        let rects = NSApp.windows
            .filter { $0.isVisible && $0.level == .floating && !($0 is LinePanel) && $0.frame.width < 2000 }
            .map { topLeft($0.frame) }
        mark(event, ["rects": rects])
    }

    private func topLeft(_ r: CGRect) -> [Double] {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return [r.minX, height - r.maxY, r.width, r.height].map { Double($0).rounded(places: 1) }
    }

    private func write(_ object: [String: Any]) {
        guard let handle, let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        handle.write(data + Data([0x0A]))
    }
}

private extension Double {
    func rounded(places: Int) -> Double {
        let k = pow(10, Double(places))
        return (self * k).rounded() / k
    }
}

private extension CGFloat {
    func rounded(places: Int) -> Double { Double(self).rounded(places: places) }
}

/// A caption at the bottom of the main display, above everything, that never
/// takes a click.
@MainActor
private final class DemoCaption {
    private let panel: NSPanel?
    private let model = DemoCaptionModel()

    init(visible: Bool) {
        guard visible else { panel = nil; return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: DemoCaptionView(model: model))
        if let screen = NSScreen.screens.first {
            let visible = screen.visibleFrame
            panel.setFrame(NSRect(x: visible.minX, y: visible.minY + 48, width: visible.width, height: 120), display: false)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func show(_ title: String, _ subtitle: String? = nil) {
        model.caption = DemoCaptionModel.Caption(title: title, subtitle: subtitle)
    }

    func hide() {
        model.caption = nil
    }
}

private final class DemoCaptionModel: ObservableObject {
    struct Caption: Hashable {
        let title: String
        let subtitle: String?
    }

    @Published var caption: Caption?
}

private struct DemoCaptionView: View {
    @ObservedObject var model: DemoCaptionModel

    var body: some View {
        ZStack {
            if let caption = model.caption {
                VStack(spacing: 4) {
                    if let subtitle = caption.subtitle {
                        Text(subtitle)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(caption.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                .id(caption)
                .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.35), value: model.caption)
    }
}
