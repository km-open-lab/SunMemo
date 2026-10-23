import AppKit

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

guard CommandLine.arguments.contains("--demo") else {
    fatalError("Regression runner requires --demo to isolate all test data")
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    if CommandLine.arguments.contains("--drag-check") {
        await runDragCheck()
    } else {
        await runRegression()
    }
}
app.run()
