import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let line = Line()
    private var panel: LinePanel!
    private var statusItem: NSStatusItem!
    private var watcher: ScreenshotWatcher!
    /// In inbox mode, a second watcher on the Desktop. If a macOS version
    /// ignores the screenshot settings (macOS 27 renamed one), captures keep
    /// landing on the Desktop, and they still hang on the line.
    private var safetyWatcher: ScreenshotWatcher?
    private var signalSources: [DispatchSourceSignal] = []
    private var cancellables = Set<AnyCancellable>()
    private var mouseTimer: Timer?

    /// Whether the panel is ordered in. It can be in and still tucked away
    /// above the top edge, like an auto-hiding Dock.
    private var isPresent = false
    /// Whether the line has slid down into view.
    private var isRevealed = false
    /// Opened on purpose with the shortcut or the menu: it stays down until
    /// the cursor has visited it and left, or the shortcut is pressed again.
    private var pinned = false
    /// A new screenshot shows itself for a moment, then tucks away.
    private var peekUntil = Date.distantPast
    private var hotZoneSince: Date?
    /// After a click in the menu bar the line stays up there hidden until the
    /// pointer leaves the menu bar, so it does not come back over a menu.
    private var menuBarSuppressed = false
    private var clickMonitors: [Any] = []
    private var awaySince: Date?
    /// Whether the line should be up, if nothing prevents it. A full screen
    /// app on that screen does: the line waits until you leave full screen.
    private var wanted = false
    /// Set when you open the line on purpose, so it stays up while empty.
    private var keepOpen = false
    private var lastLiveCount = 0
    /// The screen a new capture was taken on: the line goes there.
    private var pendingScreen: NSScreen?
    static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let host = NSHostingView(rootView: LineView(line: line))
        host.sizingOptions = []
        panel = LinePanel(content: host)
        panel.placeOnScreen()
        updateCapacity()

        if Inbox.isEnabled { Inbox.apply() }
        restoreSettingsOnTermination()
        // The demo shows only its own items, never real screenshots.
        if !Demo.isActive { startWatcher() }

        ClipboardWatcher.shared.setup(line: line) { [weak self] url in
            self?.hangCapture(url)
        }

        // Not in the demo, so it never fights an installed SunMemo for them.
        if !Demo.isActive {
            HotKeyManager.shared.start(
                onToggle: { [weak self] in self?.toggle() },
                onNewMemo: { [weak self] in
                    guard let self else { return }
                    QuickMemoWindowController.shared.show(line: self.line)
                },
                onHangClipboard: {
                    let _ = ClipboardWatcher.shared.hangCurrentClipboard()
                }
            )
        }

        for name in [Notification.Name.sunMemoRevealLine, Notification.Name.tendederoRevealLine] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.keepOpen = true
                    self?.wanted = true
                    self?.panel.placeOnScreen()
                    self?.updateCapacity()
                    self?.refresh()
                    self?.reveal(pinned: true)
                }
            }
        }

        for notifName in ["com.sunmemo.showQuickMemo", "com.tendedero.showQuickMemo"] {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(notifName),
                object: nil,
                queue: .main
            ) { [weak self] notif in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    var targetID: UUID? = nil
                    if let idStr = notif.userInfo?["id"] as? String, let uid = UUID(uuidString: idStr) {
                        targetID = uid
                    } else if let idx = notif.userInfo?["index"] as? Int, idx >= 0 && idx < self.line.items.count {
                        targetID = self.line.items[idx].id
                    }
                    QuickMemoWindowController.shared.show(line: self.line, editingMemoID: targetID)
                }
            }
        }

        for notifName in ["com.sunmemo.toggleLine", "com.tendedero.toggleLine"] {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(notifName),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.toggle()
                }
            }
        }

        for notifName in ["com.sunmemo.showWelcome", "com.tendedero.showWelcome"] {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(notifName),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.offerInbox()
                }
            }
        }

        #if DEBUG
        // Hooks for scripting demo screenshots. Any process on the Mac can post
        // a distributed notification, so they must never ship in a release build.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sunmemo.pinLine"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.keepOpen = true
                self.wanted = true
                self.pinned = true
                self.panel.placeOnScreen(NSScreen.screens.first)
                self.updateCapacity()
                self.refresh()
                self.reveal(pinned: true, peekFor: 300)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sunmemo.hoverIndex"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            MainActor.assumeIsolated {
                guard let self else { return }
                let idx = notif.userInfo?["index"] as? Int ?? -1
                if idx >= 0 && idx < self.line.items.count {
                    self.line.hoveredID = self.line.items[idx].id
                } else {
                    self.line.hoveredID = nil
                }
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sunmemo.showPreviewIndex"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            MainActor.assumeIsolated {
                guard let self else { return }
                let idx = notif.userInfo?["index"] as? Int ?? 1
                if idx >= 0 && idx < self.line.items.count {
                    MemoPreviewWindowController.shared.show(line: self.line, itemID: self.line.items[idx].id)
                }
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sunmemo.hidePreview"),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                MemoPreviewWindowController.shared.close()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.tendedero.createTestMemo"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            MainActor.assumeIsolated {
                guard let self else { return }
                let text = notif.userInfo?["text"] as? String ?? "# 🚀 项目待办冲刺\n- [ ] 优化 Tendedero 待办清单\n- [ ] 备份数据库与 **配置文件**\n- [x] 修复窗口排版对齐\n> 💡 支持 Markdown 语法与清单"
                let color = notif.userInfo?["color"] as? String ?? "green"
                self.line.addMemo(text: text, color: color)
                self.reveal(pinned: true)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.tendedero.updateFirstMemo"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            MainActor.assumeIsolated {
                guard let self, let target = self.line.items.first(where: { $0.isMemo && $0.memoText.contains("- [") }) else { return }
                let newColor = notif.userInfo?["color"] as? String ?? "pink"
                let newText = notif.userInfo?["text"] as? String ?? "# 🌸 更新后的备忘录\n- [x] 优化待办清单交互\n- [ ] 备份数据库与 **核心配置**\n- [x] 修复排版对齐与白条"
                self.line.updateMemo(id: target.id, text: newText, color: newColor)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.tendedero.toggleFirstTodo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let target = self.line.items.first(where: { $0.isMemo && $0.memoText.contains("- [") }) else { return }
                self.line.toggleMemoTodoLine(id: target.id, lineIndex: 1)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.tendedero.toggleCardDone"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let target = self.line.items.first(where: { $0.isMemo }) else { return }
                self.line.toggleMemoDone(target.id)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.tendedero.discardFirstMemo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let target = self.line.items.first(where: { $0.isMemo }) else { return }
                self.line.discard(target.id)
            }
        }
        #endif

        setUpStatusItem()
        watchMenuBarClicks()

        Markup.shared.onSaved = { [weak self] url in self?.line.reloadThumbnail(for: url) }
        line.onFall = { [weak self] item in self?.fall(item) }

        line.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.itemsChanged() }
            .store(in: &cancellables)

        // Entering or leaving full screen switches Space. Check again once the
        // switch animation has settled.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.refresh() }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel.placeOnScreen()
                self?.updateCapacity()
            }
        }

        if Demo.isActive {
            DemoDirector.run(self)
            return
        }

        if !Inbox.wasOffered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.offerInbox() }
        }

        if !Demo.defaults.bool(forKey: "welcomed") {
            Demo.defaults.set(true, forKey: "welcomed")
            keepOpen = true
            wanted = true
            refresh()
            reveal(pinned: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.line.liveCount == 0 else { return }
                self.keepOpen = false
                self.wanted = false
                self.refresh()
            }
        }

        UpdateChecker.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Inbox.isEnabled { Inbox.restore() }
    }

    // MARK: Inbox mode

    private func startWatcher() {
        watcher?.stop()
        safetyWatcher?.stop()
        safetyWatcher = nil
        watcher = ScreenshotWatcher(
            onNew: { [weak self] url in self?.hangCapture(url) },
            onChange: { [weak self] in self?.line.prune() })
        watcher.start()
        if Inbox.isEnabled, watcher.folder.standardizedFileURL != ScreenshotWatcher.desktop.standardizedFileURL {
            let safety = ScreenshotWatcher(
                folder: ScreenshotWatcher.desktop,
                onNew: { [weak self] url in
                    log.notice("Screenshot landed on the Desktop despite inbox mode: \(url.lastPathComponent, privacy: .public)")
                    self?.hangCapture(url)
                },
                onChange: { [weak self] in self?.line.prune() })
            safety.start()
            safetyWatcher = safety
        }
    }

    private func setInbox(_ on: Bool) {
        Inbox.isEnabled = on
        if on { Inbox.apply() } else { Inbox.restore() }
        startWatcher()
    }

    /// Asked once. Changing system settings is the user's call, never ours.
    private func offerInbox() {
        Inbox.wasOffered = true
        WelcomeWindowController.shared.show { [weak self] enableInbox in
            if enableInbox {
                self?.setInbox(true)
            }
        }
    }

    /// Quitting from the menu or logging out runs applicationWillTerminate.
    /// A plain kill does not, so settings are also restored on those signals.
    private func restoreSettingsOnTermination() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                if Inbox.isEnabled { Inbox.restore() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Showing and hiding

    private func itemsChanged() {
        let live = line.liveCount
        if live > lastLiveCount {
            panel.placeOnScreen(pendingScreen)
            pendingScreen = nil
            updateCapacity()
            wanted = true
            refresh()
            reveal(peekFor: 2.5)
        } else if live == 0 && !keepOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, self.line.liveCount == 0, !self.keepOpen else { return }
                self.wanted = false
                self.refresh()
            }
        }
        lastLiveCount = live
    }

    // MARK: The capture flying to the line

    /// A new screenshot lifts off from where it was taken and flies to its
    /// place on the line. Without a known capture area it simply drops in.
    private func hangCapture(_ url: URL) {
        let from = captureRect(of: url)
        if let from {
            let center = CGPoint(x: from.midX, y: from.midY)
            pendingScreen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
        }
        guard let id = line.hang(url, flying: from != nil), let from else { return }
        // Let the line come down and lay out before measuring the landing spot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.fly(id, from: from)
        }
    }

    private func fly(_ id: UUID, from: CGRect) {
        guard isPresent, isRevealed, let screen = panel.screen,
              let to = cardFrame(for: id),
              let item = line.items.first(where: { $0.id == id }) else {
            line.land(id)
            return
        }
        let pixels = Int(max(from.width, from.height) * screen.backingScaleFactor)
        guard let image = makeThumbnail(item.url, maxPixels: min(3000, max(400, pixels)))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            line.land(id)
            return
        }
        CaptureFlight.fly(image: image, from: from, to: to, tilt: CGFloat(item.tilt), on: screen) { [weak self] in
            self?.line.land(id)
        }
    }

    /// A discarded card falls over the whole screen, from where it hangs.
    private func fall(_ item: Pegged) {
        guard isPresent, isRevealed, !item.flying, let screen = panel.screen,
              let card = cardFrame(for: item.id),
              let image = item.thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        CaptureFlight.fall(image: image, card: card, tilt: CGFloat(item.tilt), on: screen)
    }

    /// Where a card will hang, in screen coordinates, using the same layout
    /// as the line view.
    func cardFrame(for id: UUID) -> CGRect? {
        guard let index = line.items.firstIndex(where: { $0.id == id }) else { return nil }
        let width = panel.frame.width
        let x = Layout.x(index: index, count: line.items.count + 1, width: width)
        let viewTop = Layout.ropeY(x: x, width: width) - Layout.pinAbove
        let cardTop = viewTop + PeggedView.cardOffsetBelowTop
        let size: CGSize = {
            if line.items[index].isMemo {
                return PeggedView.memoCardSize(for: line.items[index].aspectRatio)
            } else {
                return PeggedView.cardSize(for: line.items[index].thumb.size)
            }
        }()
        return CGRect(x: panel.frame.minX + x - size.width / 2,
                      y: panel.frame.maxY - cardTop - size.height,
                      width: size.width, height: size.height)
    }

    /// Animates a new memo card taking flight from the editor (or screen center)
    /// straight up onto the clothesline, matching screenshot capture flight.
    func hangMemoFlight(text: String, color: String, aspectRatio: String = "wide", from: CGRect? = nil) {
        keepOpen = true
        wanted = true
        panel.placeOnScreen()
        updateCapacity()
        refresh()
        reveal(pinned: true)

        let targetScreen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let originRect = from ?? {
            let center = CGPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
            return CGRect(x: center.x - 170, y: center.y - 130, width: 340, height: 260)
        }()

        guard let id = line.addMemo(text: text, color: color, aspectRatio: aspectRatio, flying: true) else { return }

        // Let the line come down and lay out before measuring the landing spot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, let screen = self.panel.screen ?? NSScreen.main,
                  let to = self.cardFrame(for: id),
                  let item = self.line.items.first(where: { $0.id == id }) else {
                self?.line.land(id)
                return
            }
            guard let image = item.thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self.line.land(id)
                return
            }
            CaptureFlight.fly(image: image, from: originRect, to: to, tilt: CGFloat(item.tilt), on: screen) { [weak self] in
                self?.line.land(id)
                self?.line.play("Tink", volume: 0.35)
            }
        }
    }

    /// Decides whether the panel is ordered in at all: something to show,
    /// and no full screen app on that screen.
    private func refresh() {
        let blocked = panel.screen.map(FullScreen.isActive(on:))
            ?? LinePanel.screenUnderPointer().map(FullScreen.isActive(on:)) ?? false
        if wanted && !blocked {
            present()
        } else {
            dismiss()
        }
        // The cursor is watched while there is a line, even tucked away,
        // to notice it pushing against the top edge.
        if wanted { startMouseTracking() } else { stopMouseTracking() }
    }

    private func present() {
        guard !isPresent else { return }
        isPresent = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func dismiss() {
        guard isPresent else { return }
        isPresent = false
        setRevealed(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isPresent else { return }
            self.panel.orderOut(nil)
        }
    }

    private func reveal(pinned: Bool = false, peekFor seconds: TimeInterval = 0) {
        guard isPresent else { return }
        if pinned { self.pinned = true }
        if seconds > 0 { peekUntil = Date().addingTimeInterval(seconds) }
        awaySince = nil
        setRevealed(true)
    }

    private func setRevealed(_ on: Bool) {
        guard on != isRevealed else { return }
        isRevealed = on
        line.revealed = on
        if !on {
            pinned = false
            peekUntil = .distantPast
            panel.ignoresMouseEvents = true
        }
    }

    @objc private func toggle() {
        if isRevealed {
            setRevealed(false)
            if line.liveCount == 0 {
                keepOpen = false
                wanted = false
                refresh()
            }
        } else {
            keepOpen = true
            wanted = true
            panel.placeOnScreen()
            updateCapacity()
            refresh()
            reveal(pinned: true)
        }
    }

    @objc private func quickMemo() {
        QuickMemoWindowController.shared.show(line: line)
    }

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        panel.ignoresMouseEvents = true
    }

    /// How long the cursor rests against the top edge before the line comes
    /// down. Short enough to feel instant, long enough that a quick trip to
    /// the menu bar does not trigger it.
    private static let revealDelay: TimeInterval = 0.25

    /// The menu bar strip at the top of a screen. With an auto-hiding menu
    /// bar the visible frame reaches the top, so the system thickness is used.
    static func menuBarBand(of screen: NSScreen) -> NSRect {
        var h = screen.frame.maxY - screen.visibleFrame.maxY
        if h < 1 { h = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top) }
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h)
    }

    /// A click anywhere in the top bar of any screen, a menu or an icon, puts the line away.
    private func watchMenuBarClicks() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let p = NSEvent.mouseLocation
                guard NSScreen.screens.contains(where: { NSMouseInRect(p, Self.menuBarBand(of: $0), false) }) else { return }
                self.menuBarSuppressed = true
                self.hotZoneSince = nil
                if self.isRevealed {
                    self.pinned = false
                    self.setRevealed(false)
                }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: handler) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { e in handler(e); return e }) {
            clickMonitors.append(local)
        }
    }
    /// How long the cursor is away before the line tucks back up.
    private static let retractDelay: TimeInterval = 0.5

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()

        let screenUnderPointer = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let inMenuBar = screenUnderPointer.map { NSMouseInRect(mouse, Self.menuBarBand(of: $0), false) } ?? false
        if !inMenuBar { menuBarSuppressed = false }

        guard isRevealed else {
            // Resting in the menu bar brings the line down on that screen.
            // Pushing against the top edge is part of it, and it also works
            // when another display sits above and the pointer never stops.
            if let screen = screenUnderPointer, inMenuBar, !menuBarSuppressed,
               !FullScreen.isActive(on: screen) {
                let since = hotZoneSince ?? now
                hotZoneSince = since
                if now.timeIntervalSince(since) >= Self.revealDelay {
                    hotZoneSince = nil
                    if panel.screen != screen {
                        panel.placeOnScreen()
                        updateCapacity()
                    }
                    refresh()
                    reveal()
                }
            } else {
                hotZoneSince = nil
            }
            return
        }

        updateMousePassThrough(mouse)

        // The line's zone runs from its lowest point up to the top of the
        // screen, menu bar included, so moving up never hides it.
        var zone = panel.frame
        if let screen = panel.screen { zone.size.height = screen.frame.maxY - zone.minY }
        let inside = NSMouseInRect(mouse, zone, false)
        if inside && pinned && !MemoPreviewWindowController.shared.isOpen { pinned = false }

        let busy = demoHold || pinned || GrabView.isDragging || line.pressedID != nil || MemoPreviewWindowController.shared.isOpen || now < peekUntil
        if inside || busy {
            awaySince = nil
        } else {
            let since = awaySince ?? now
            awaySince = since
            if now.timeIntervalSince(since) >= Self.retractDelay {
                awaySince = nil
                setRevealed(false)
            }
        }
    }

    /// The panel spans the whole width of the screen, so it only accepts the
    /// mouse while the cursor is over a photo. Everywhere else, clicks go to
    /// whatever is underneath.
    private func updateMousePassThrough(_ mouse: NSPoint) {
        guard !GrabView.isDragging else { return }
        let local = panel.convertPoint(fromScreen: mouse)
        let flipped = CGPoint(x: local.x, y: panel.frame.height - local.y)
        let overPhoto = line.hitRects.values.contains { $0.insetBy(dx: -4, dy: -4).contains(flipped) }
        if panel.ignoresMouseEvents == overPhoto {
            panel.ignoresMouseEvents = !overPhoto
        }
    }

    private func updateCapacity() {
        line.maxItems = 35
    }

    // MARK: Demo hooks

    /// Keeps the line down for the whole demo, wherever the pointer is.
    var demoHold = false
    var demoLine: Line { line }

    /// Brings the line down on the main display, as the shortcut does.
    func demoShowLine() {
        keepOpen = true
        wanted = true
        panel.placeOnScreen(NSScreen.screens.first)
        updateCapacity()
        refresh()
        reveal(pinned: true)
    }

    func demoHideLine() {
        setRevealed(false)
    }

    /// Hangs an image as if it had just been captured.
    func demoHang(_ url: URL) {
        hangCapture(url)
    }

    // MARK: Menu bar

    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // 1. The hanging rope (slight curve)
            let rope = NSBezierPath()
            rope.move(to: NSPoint(x: 0.5, y: 14.5))
            rope.curve(to: NSPoint(x: 21.5, y: 14.5),
                       controlPoint1: NSPoint(x: 7.0, y: 13.8),
                       controlPoint2: NSPoint(x: 15.0, y: 13.8))
            rope.lineWidth = 1.2
            rope.lineCapStyle = .round
            rope.stroke()

            // 2. Card 1 (Left memo card with checklist)
            let card1Rect = NSRect(x: 2.5, y: 3.5, width: 8.0, height: 9.8)
            let card1 = NSBezierPath(roundedRect: card1Rect, xRadius: 1.2, yRadius: 1.2)
            card1.lineWidth = 1.15
            card1.stroke()

            let dot1 = NSBezierPath(ovalIn: NSRect(x: 4.2, y: 9.8, width: 1.4, height: 1.4))
            dot1.fill()
            let line1_1 = NSBezierPath()
            line1_1.move(to: NSPoint(x: 6.4, y: 10.5))
            line1_1.line(to: NSPoint(x: 9.0, y: 10.5))
            line1_1.lineWidth = 0.9
            line1_1.lineCapStyle = .round
            line1_1.stroke()

            let dot2 = NSBezierPath(ovalIn: NSRect(x: 4.2, y: 6.8, width: 1.4, height: 1.4))
            dot2.fill()
            let line1_2 = NSBezierPath()
            line1_2.move(to: NSPoint(x: 6.4, y: 7.5))
            line1_2.line(to: NSPoint(x: 8.6, y: 7.5))
            line1_2.lineWidth = 0.9
            line1_2.lineCapStyle = .round
            line1_2.stroke()

            // Card 1 peg (clothespin)
            let peg1 = NSBezierPath(roundedRect: NSRect(x: 5.8, y: 12.0, width: 1.5, height: 3.4), xRadius: 0.6, yRadius: 0.6)
            peg1.fill()

            // 3. Card 2 (Right memo card with note lines)
            let card2Rect = NSRect(x: 11.5, y: 2.2, width: 8.0, height: 10.8)
            let card2 = NSBezierPath(roundedRect: card2Rect, xRadius: 1.2, yRadius: 1.2)
            card2.lineWidth = 1.15
            card2.stroke()

            let line2_1 = NSBezierPath()
            line2_1.move(to: NSPoint(x: 13.5, y: 9.8))
            line2_1.line(to: NSPoint(x: 17.5, y: 9.8))
            line2_1.lineWidth = 0.9
            line2_1.lineCapStyle = .round
            line2_1.stroke()

            let line2_2 = NSBezierPath()
            line2_2.move(to: NSPoint(x: 13.5, y: 7.0))
            line2_2.line(to: NSPoint(x: 17.0, y: 7.0))
            line2_2.lineWidth = 0.9
            line2_2.lineCapStyle = .round
            line2_2.stroke()

            let line2_3 = NSBezierPath()
            line2_3.move(to: NSPoint(x: 13.5, y: 4.2))
            line2_3.line(to: NSPoint(x: 16.0, y: 4.2))
            line2_3.lineWidth = 0.9
            line2_3.lineCapStyle = .round
            line2_3.stroke()

            // Card 2 peg (clothespin)
            let peg2 = NSBezierPath(roundedRect: NSRect(x: 14.8, y: 11.8, width: 1.5, height: 3.4), xRadius: 0.6, yRadius: 0.6)
            peg2.fill()

            return true
        }
        img.isTemplate = true
        return img
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = Self.makeMenuBarIcon()
        image.accessibilityDescription = "SunMemo"
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 发现新版本时置顶醒目显示
        if let update = UpdateChecker.shared.availableUpdate {
            let updateItem = ClosureMenuItem("✨ 发现新版本 v\(update.version) (点击更新)") {
                UpdateChecker.shared.showUpdateAlert(for: update)
            }
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

        let toggleItem = ClosureMenuItem(isRevealed ? L("Hide line") : L("Show line")) { [weak self] in
            self?.toggle()
        }
        menu.addItem(toggleItem)

        let memoItem = ClosureMenuItem("弹窗新建便签") { [weak self] in
            guard let self else { return }
            QuickMemoWindowController.shared.show(line: self.line)
        }
        menu.addItem(memoItem)

        let pasteItem = ClosureMenuItem("挂上剪贴板内容") {
            let _ = ClipboardWatcher.shared.hangCurrentClipboard()
        }
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let clearItem = ClosureMenuItem(L("Take everything down")) { [weak self] in
            self?.confirmClear()
        }
        clearItem.isEnabled = line.liveCount > 0
        menu.addItem(clearItem)

        menu.addItem(ClosureMenuItem("偏好设置与快捷键...") {
            SettingsWindowController.shared.show()
        })

        // 更多选项 (Submenu: 清爽折叠次要项)
        let moreMenu = NSMenu(title: "更多选项")

        moreMenu.addItem(ClosureMenuItem("🔄 检查更新...") {
            UpdateChecker.shared.checkForUpdates(userInitiated: true)
        })

        moreMenu.addItem(ClosureMenuItem("📄 打开本地备份 (SunMemo.md)") {
            MemoSyncManager.shared.openInEditor()
        })

        moreMenu.addItem(ClosureMenuItem(L("Open screenshots folder")) { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.watcher?.folder ?? Inbox.folder)
        })

        moreMenu.addItem(ClosureMenuItem("💡 欢迎与使用引导...") { [weak self] in
            WelcomeWindowController.shared.show { [weak self] enableInbox in
                if enableInbox {
                    self?.setInbox(true)
                }
            }
        })

        moreMenu.addItem(.separator())

        let inbox = ClosureMenuItem(L("Handle screenshots")) { [weak self] in
            self?.setInbox(!Inbox.isEnabled)
        }
        inbox.state = Inbox.isEnabled ? .on : .off
        inbox.toolTip = L("Screenshots hang instantly and skip the Desktop")
        moreMenu.addItem(inbox)

        let sound = ClosureMenuItem(L("Sounds")) { [weak self] in
            guard let self else { return }
            self.line.soundOn.toggle()
        }
        sound.state = line.soundOn ? .on : .off
        moreMenu.addItem(sound)

        let login = ClosureMenuItem(L("Open at login")) {
            AppDelegate.toggleLaunchAtLogin()
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        moreMenu.addItem(login)

        let moreItem = NSMenuItem(title: "更多选项", action: nil, keyEquivalent: "")
        moreItem.submenu = moreMenu
        menu.addItem(moreItem)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Quit SunMemo"), key: "q") {
            NSApp.terminate(nil)
        })
    }

    /// Taking everything down deletes every memo from the line, so it asks
    /// first. Screenshots only leave the line; their files stay where they are.
    private func confirmClear() {
        let memos = line.items.filter { $0.isMemo && !$0.falling }.count
        guard memos > 0 else {
            line.clear()
            return
        }
        let alert = NSAlert()
        alert.messageText = L("Take everything down?")
        alert.informativeText = String(format: L("%d memos will be removed from the line. Their text stays in the archive of ~/Documents/SunMemo.md, but they cannot be hung back from SunMemo."), memos)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Take everything down"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            line.clear()
        }
    }

    private static func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Could not change the login setting")
            alert.informativeText = L("Move SunMemo to the Applications folder and try again.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
