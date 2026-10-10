import AppKit
import SwiftUI

/// `--demo`: a scripted tour of SunMemo, for recording the promo video with
/// `scripts/record-demo.sh`.
///
/// It runs on throwaway data. Settings go to a separate defaults suite and
/// files to a temporary folder, both wiped when the demo starts, so your
/// memos, your screenshots, `~/Documents/SunMemo.md` and the macOS screenshot
/// settings are never touched. The app quits when the tour ends.
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
}

/// Plays the tour, about 50 seconds, on the main display.
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
        let caption = DemoCaption()
        app.demoHold = true
        await pause(1.0)

        // Opening: the empty line comes down.
        caption.show(L("Hang your thoughts on the clothesline"), "SunMemo")
        app.demoShowLine()
        await pause(3.0)

        // A screenshot lifts off and flies to the line.
        caption.show(L("Screenshots hang themselves on the line"))
        await pause(0.8)
        if let shot = makeScreenshot() {
            app.demoHang(shot)
        }
        let shotID = line.items.last?.id
        await pause(3.0)

        // A memo typed in the editor.
        caption.show(L("Jot a memo with ⌃⌥N"))
        QuickMemoWindowController.shared.showForDemo(line: line, color: "yellow", aspectRatio: "wide")
        await pause(1.0)
        let release = [
            "## " + L("This week's release"),
            "- [x] " + L("Screenshots hang themselves"),
            "- [ ] " + L("Record the promo video"),
            "- [ ] " + L("Ship v1.2"),
        ].joined(separator: "\n")
        await type(release)
        await pause(0.8)
        QuickMemoWindowController.shared.commitForDemo()
        let releaseID = line.items.last(where: { $0.isMemo })?.id
        await pause(2.6)

        // More colors and shapes.
        caption.show(L("Four colors, three shapes"))
        app.hangMemoFlight(text: "## " + L("Idea") + "\n" + L("A clothesline for everything you have not finished yet"),
                           color: "green", aspectRatio: "square")
        await pause(1.6)
        app.hangMemoFlight(text: [
            "## " + L("Weekend"),
            "- [x] " + L("Coffee by the window"),
            "- [ ] " + L("Bike along the coast"),
            "- [ ] " + L("Water the plants"),
        ].joined(separator: "\n"), color: "pink", aspectRatio: "tall")
        let weekendID = line.items.last(where: { $0.isMemo })?.id
        await pause(2.4)

        // The cards part like a hand of playing cards.
        caption.show(L("Hover and the cards make room"))
        for item in line.items where !item.falling {
            line.hoveredID = item.id
            await pause(0.7)
        }
        line.hoveredID = nil
        await pause(0.8)

        // A to-do ticked on the line.
        caption.show(L("Tick off to-dos right on the line"))
        if let releaseID {
            line.hoveredID = releaseID
            await pause(0.8)
            line.toggleMemoTodoLine(id: releaseID, lineIndex: 2)
            await pause(1.6)
            line.hoveredID = nil
        }

        // Taken down to read, with the tether back to the line.
        caption.show(L("Click to take a card down and read it"))
        if let releaseID {
            MemoPreviewWindowController.shared.show(line: line, itemID: releaseID)
            await pause(2.0)
            line.toggleMemoTodoLine(id: releaseID, lineIndex: 3)
            await pause(2.0)
            MemoPreviewWindowController.shared.close()
            await pause(0.8)
        }
        if let shotID {
            MemoPreviewWindowController.shared.show(line: line, itemID: shotID)
            await pause(2.8)
            MemoPreviewWindowController.shared.close()
            await pause(0.8)
        }

        // Torn off and archived.
        caption.show(L("Tear it off. The text stays in SunMemo.md"))
        await pause(0.8)
        if let weekendID {
            line.discard(weekendID)
        }
        await pause(2.4)

        // Tucked away, and pulled back down.
        caption.show(L("Push the pointer to the top edge to pull it down"))
        app.demoHideLine()
        await pause(1.8)
        app.demoShowLine()
        await pause(2.6)

        // Closing.
        caption.show(L("Hang your thoughts on the clothesline"), "SunMemo")
        await pause(3.5)
        caption.hide()
        await pause(1.0)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Types into the editor one character at a time, like a person.
    private static func type(_ text: String) async {
        for character in text {
            guard let view = QuickMemoWindowController.shared.demoTextView else { return }
            view.insertText(String(character), replacementRange: view.selectedRange())
            await pause(character == "\n" ? 0.28 : 0.045)
        }
    }

    /// Draws a landscape photo into the demo's screenshots folder, tagged with
    /// a capture area in the middle of the main display, so it takes off from
    /// there like a real screenshot.
    private static func makeScreenshot() -> URL? {
        let width = 1280, height = 800
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let size = NSSize(width: width, height: height)
        NSGradient(colors: [
            NSColor(red: 0.98, green: 0.58, blue: 0.42, alpha: 1),
            NSColor(red: 0.95, green: 0.78, blue: 0.52, alpha: 1),
            NSColor(red: 0.56, green: 0.72, blue: 0.88, alpha: 1),
        ])?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: 560, y: 380, width: 160, height: 160)).fill()
        let mountains = NSBezierPath()
        mountains.move(to: NSPoint(x: 0, y: 290))
        mountains.line(to: NSPoint(x: 350, y: 510))
        mountains.line(to: NSPoint(x: 770, y: 350))
        mountains.line(to: NSPoint(x: 1020, y: 540))
        mountains.line(to: NSPoint(x: 1280, y: 320))
        mountains.line(to: NSPoint(x: 1280, y: 0))
        mountains.line(to: NSPoint(x: 0, y: 0))
        mountains.close()
        NSColor(red: 0.28, green: 0.32, blue: 0.45, alpha: 0.88).setFill()
        mountains.fill()
        NSGradient(colors: [
            NSColor(red: 0.32, green: 0.44, blue: 0.58, alpha: 0.95),
            NSColor(red: 0.18, green: 0.24, blue: 0.36, alpha: 1),
        ])?.draw(in: NSRect(x: 0, y: 0, width: width, height: 250), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let folder = Inbox.folder
        let url = folder.appendingPathComponent("Screenshot \(Int(Date().timeIntervalSince1970)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
        } catch {
            log.error("Demo screenshot not written: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // The capture area, in global points from the top left of the main
        // display, as macOS records it on real screenshots.
        if let main = NSScreen.screens.first {
            let w: CGFloat = 640, h: CGFloat = 400
            let rect: [CGFloat] = [(main.frame.width - w) / 2, (main.frame.height - h) / 2 - 40, w, h]
            let values = rect.map { NSNumber(value: Double($0)) }
            if let plist = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) {
                url.withUnsafeFileSystemRepresentation { path in
                    guard let path else { return }
                    _ = plist.withUnsafeBytes {
                        setxattr(path, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", $0.baseAddress, plist.count, 0, 0)
                    }
                }
            }
        }
        return url
    }
}

/// A caption at the bottom of the main display, above everything, that never
/// takes a click.
@MainActor
private final class DemoCaption {
    private let panel: NSPanel
    private let model = DemoCaptionModel()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
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
