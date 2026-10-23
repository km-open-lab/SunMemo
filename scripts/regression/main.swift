import AppKit
import SwiftUI

// Runs the real controllers with Demo's isolated defaults and files. It never
// launches AppDelegate, watchers, update checks or global shortcut registration.
@MainActor
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        Demo.cleanUp()
        exit(1)
    }
    print("PASS: \(message)")
}

@MainActor
func pause(_ seconds: Double = 0.15) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

@MainActor
func editor(in window: NSWindow) -> CustomNSTextView? {
    func find(_ view: NSView) -> CustomNSTextView? {
        if let text = view as? CustomNSTextView { return text }
        return view.subviews.lazy.compactMap(find).first
    }
    return window.contentView.flatMap(find)
}

@MainActor
func control(_ identifier: String, in window: NSWindow) -> NSButton? {
    func find(_ view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.identifier?.rawValue == identifier { return button }
        return view.subviews.lazy.compactMap(find).first
    }
    return window.contentView.flatMap(find)
}

@MainActor
func key(_ window: NSWindow, code: UInt16, text: String, modifiers: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: window.windowNumber, context: nil,
                                characters: text, charactersIgnoringModifiers: text,
                                isARepeat: false, keyCode: code)!
    NSApp.sendEvent(event)
}

@MainActor
func runRegression() async {
    let preferences = MemoTextPreferences.shared
    preferences.setFontSize(20)
    check(MemoTextPreferences(defaults: Demo.defaults).fontSize == 20, "font size survives preferences reload")
    check(MemoTypography.config(for: "长便签\n第二行\n第三行\n第四行").fontSize == 20,
          "card typography uses the saved font size")
    check(MemoTextPreferences.normalized(100) == 24 && MemoTextPreferences.normalized(1) == 12 &&
          MemoTextPreferences.normalized(.nan) == 16, "invalid font sizes stay within readable bounds")
    preferences.setFontSize(16)
    let sample = Array(repeating: "- [ ] 测试", count: 10).joined(separator: "\n")
    var layoutsFit = true
    for size in [12.0, 16, 24] {
        let config = MemoTypography.config(for: sample, fontSize: CGFloat(size))
        for ratio in MemoAspectRatio.allCases {
            for height in [MemoLimits.minHeight, ratio.cardContentSize.height] {
                let layout = MemoCardLayout.textLayout(text: sample, cardHeight: height, config: config, ratio: ratio)
                let used = CGFloat(layout.maxLines) * ceil(config.fontSize * 1.25) +
                    CGFloat(layout.maxLines - 1) * config.lineSpacing + (layout.showsMore ? 16 : 0)
                if used > height - MemoCardLayout.headerHeight - 46 { layoutsFit = false }
            }
        }
    }
    check(layoutsFit, "large text fits every card preset and the minimum custom height")
    let originalPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
    check(!originalPanel.canBecomeKey, "original borderless panel reproduces keyboard-focus defect")

    let line = Line()
    line.addMemo(text: "测试1\n- [ ] 原有待办", color: "yellow", aspectRatio: "wide")
    let id = line.items.first!.id
    let controller = MemoPreviewWindowController.shared

    // A direct edit request takes the same route as the card's edit action.
    QuickMemoWindowController.shared.show(line: line, editingMemoID: id)
    await pause(0.8)
    let panel = NSApp.windows.compactMap { $0 as? MemoPreviewPanel }.first { $0.isVisible }!
    let textView = editor(in: panel)!
    check(panel.isKeyWindow && panel.firstResponder === textView, "existing memo editor receives keyboard focus")
    check(textView.string == "测试1\n- [ ] 原有待办", "existing text is retained when reopening")
    textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    key(panel, code: 0, text: "a")
    await pause()
    check(textView.string.hasSuffix("a"), "keyboard event inserts text into existing memo")
    textView.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
    textView.insertText("中文", replacementRange: NSRange(location: NSNotFound, length: 0))
    await pause()
    check(textView.string.hasSuffix("a中文"), "Chinese marked-text composition commits correctly")
    let selectionBeforeFontChange = textView.selectedRange()
    let textBeforeFontChange = textView.string
    preferences.setFontSize(22)
    await pause()
    check(textView.font?.pointSize == 22 && textView.string == textBeforeFontChange &&
          textView.selectedRange() == selectionBeforeFontChange, "font changes preserve text and caret position")
    preferences.setFontSize(16)
    await pause()
    key(panel, code: 36, text: "\r")
    await pause()
    check(textView.string.hasSuffix("\n- [ ] "), "Return continues the checklist")
    key(panel, code: 11, text: "b")
    await pause()
    let expected = textView.string
    key(panel, code: 36, text: "\r", modifiers: .command)
    await pause(1.8)
    check(!controller.isOpen, "Command-Return saves and dismisses existing memo")
    check(line.items.first { $0.id == id }?.memoText == expected, "keyboard edits reach the saved memo")
    let restored = Line()
    check(restored.items.first { $0.id == id }?.memoText == expected, "edits survive persistence reload")

    // Enter from the read-only preview must transfer focus into its new editor.
    controller.show(line: line, itemID: id)
    await pause(0.8)
    let preview = NSApp.windows.compactMap { $0 as? MemoPreviewPanel }.first { $0.isVisible }!
    key(preview, code: 36, text: "\r")
    await pause()
    let reopened = editor(in: preview)!
    check(preview.firstResponder === reopened, "Enter from preview focuses the in-place editor")
    reopened.setSelectedRange(NSRange(location: (reopened.string as NSString).length, length: 0))
    key(preview, code: 8, text: "c")
    await pause()
    check(reopened.string.hasSuffix("bc"), "typing still works on a second edit")
    key(preview, code: 36, text: "\r", modifiers: .command)
    await pause(1.8)
    check(line.items.first { $0.id == id }?.memoText.hasSuffix("bc") == true, "second edit is saved")

    QuickMemoWindowController.shared.show(line: line)
    await pause()
    let newWindow = NSApp.keyWindow!
    let newText = editor(in: newWindow)!
    check(!newWindow.styleMask.contains(.titled), "standalone editor has no native titlebar behind the card")
    check(!newWindow.isOpaque && !newWindow.hasShadow, "standalone editor has transparent backing and no system shadow")
    check(!newWindow.hidesOnDeactivate, "standalone editor stays visible when screenshot tools take focus")
    check(newWindow.contentRect(forFrameRect: newWindow.frame).size == newWindow.frame.size,
          "standalone card fills the window without a titlebar strip")
    check(control("memo.close", in: newWindow) != nil && control("memo.minimize", in: newWindow) != nil &&
          control("memo.zoom", in: newWindow) != nil, "native close, minimize and zoom buttons are present")
    control("memo.minimize", in: newWindow)!.performClick(nil)
    await pause(0.8)
    check(newWindow.isMiniaturized, "yellow button minimizes the editor")
    QuickMemoWindowController.shared.show(line: line)
    await pause(0.8)
    check(!newWindow.isMiniaturized && newWindow.isVisible, "showing a minimized editor restores its window")
    let frameBeforeZoom = newWindow.frame
    control("memo.zoom", in: newWindow)!.performClick(nil)
    await pause(0.5)
    check(newWindow.frame == newWindow.screen?.visibleFrame, "green button maximizes to the usable screen")
    control("memo.zoom", in: newWindow)!.performClick(nil)
    await pause(0.5)
    check(newWindow.frame == frameBeforeZoom, "green button restores the original size and position")
    for marker in ["- [ ] ", "- ", "* [x] "] {
        newText.string = marker
        newText.setSelectedRange(NSRange(location: (marker as NSString).length, length: 0))
        key(newWindow, code: 36, text: "\r")
        await pause()
        check(newText.string == "\n", "Return exits an empty list: \(marker)")
    }
    newText.insertText("", replacementRange: NSRange(location: 0, length: (newText.string as NSString).length))
    await pause()
    key(newWindow, code: 0, text: "a")
    await pause()
    check(newText.string == "a", "new memo keyboard input remains functional")
    key(newWindow, code: 36, text: "\r", modifiers: .command)
    await pause()
    check(line.items.contains { $0.memoText == "a" }, "new memo can still be saved")
    QuickMemoWindowController.shared.show(line: line)
    await pause()
    let emptyWindow = QuickMemoWindowController.shared.demoTextView!.window!
    control("memo.close", in: emptyWindow)!.performClick(nil)
    await pause()
    check(!emptyWindow.isVisible, "red button closes an empty editor")

    let detector = MotionDetector.shared
    detector.start(line: line)
    await pause(5.5)
    check(detector.sensorStatus != .checking && detector.sensorStatus != .waitingForSamples,
          "motion detection reports hardware outcome instead of only the enabled switch")
    print("Hardware status: \(detector.statusMessage)")
    Demo.cleanUp()
    print("All regressions passed. Test data was isolated and removed.")
    exit(0)
}

@MainActor
func runDragCheck() async {
    let line = Line()
    QuickMemoWindowController.shared.show(line: line)
    await pause()
    let window = QuickMemoWindowController.shared.demoTextView!.window!
    let initial = window.frame
    var moved = false
    print("Drag check ready. Drag the top strip and title, then close the empty editor.")
    for _ in 0..<1800 {
        await pause(0.1)
        if !window.isVisible {
            check(moved, "native drag changed the editor's screen position")
            let draft = editor(in: window)?.string ?? ""
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                QuickMemoWindowController.shared.show(line: line)
                await pause()
                check(QuickMemoWindowController.shared.demoTextView?.string == draft,
                      "closing with Keep Draft restores the text on reopen")
            }
            Demo.cleanUp()
            exit(0)
        }
        if window.frame.origin != initial.origin && !moved {
            moved = true
            print("PASS: window moved from \(initial.origin) to \(window.frame.origin)")
            check(window.frame.size == initial.size, "drag moves the whole window without resizing it")
        }
    }
    check(false, "drag check timed out")
}

struct CardCheckView: View {
    @ObservedObject var line: Line

    var body: some View {
        VStack(spacing: 18) {
            Text("滚动勾选第八条待办，再点击右上角撕下")
                .font(.system(size: 13))
            if let memo = line.items.first(where: { !$0.falling }) {
                PeggedView(item: memo, line: line)
            }
            MemoFontSizeControl()
        }
        .padding(24)
        .frame(width: 360, height: 360)
    }
}

@MainActor
func runCardCheck() async {
    let line = Line()
    line.addMemo(text: (1...8).map { "- [ ] 待办第\($0)项" }.joined(separator: "\n"), color: "yellow", aspectRatio: "wide")
    let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 360, height: 360),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Memo Card Check"
    window.contentView = NSHostingView(rootView: CardCheckView(line: line))
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    var toggled = false
    for _ in 0..<1800 {
        await pause(0.1)
        if let memo = line.items.first, memo.memoText.components(separatedBy: "\n").last == "- [x] 待办第8项" && !toggled {
            check(!memo.falling && !MemoPreviewWindowController.shared.isOpen,
                  "eighth todo toggles after scrolling without taking down the card or opening its preview")
            toggled = true
        }
        if toggled && (line.items.isEmpty || line.items.first?.falling == true) {
            check(true, "separate top-right button takes down the memo")
            Demo.cleanUp()
            exit(0)
        }
    }
    check(false, "card interaction check timed out")
}

guard CommandLine.arguments.contains("--demo") else {
    fatalError("Regression runner requires --demo to isolate all test data")
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    if CommandLine.arguments.contains("--drag-check") {
        await runDragCheck()
    } else if CommandLine.arguments.contains("--card-check") {
        await runCardCheck()
    } else {
        await runRegression()
    }
}
app.run()
