import AppKit
import SwiftUI

@MainActor
final class QuickMemoWindowController {
    static let shared = QuickMemoWindowController()
    private var window: NSPanel?
    private weak var currentLine: Line?

    func show(line: Line, editingMemoID: UUID? = nil) {
        self.currentLine = line

        // Always recreate or reset the window to ensure editingMemoID, text and color are 100% accurate
        if let window {
            window.close()
            self.window = nil
        }

        let initialText: String
        let initialColor: String
        let initialAspectRatio: String
        if let editingMemoID,
           let memo = line.items.first(where: { $0.id == editingMemoID && $0.isMemo }) {
            initialText = memo.memoText
            initialColor = memo.memoColor
            initialAspectRatio = memo.aspectRatio
        } else {
            initialText = ""
            initialColor = "yellow"
            initialAspectRatio = "wide"
        }

        let view = QuickMemoView(
            editingID: editingMemoID,
            initialText: initialText,
            initialColor: initialColor,
            initialAspectRatio: initialAspectRatio,
            onSave: { [weak self] text, color, aspectRatio in
                guard let self, let line = self.currentLine else { return }
                let sourceRect = self.window?.frame
                self.close()
                if let editingMemoID {
                    line.updateMemo(id: editingMemoID, text: text, color: color, aspectRatio: aspectRatio)
                    NotificationCenter.default.post(name: .tendederoRevealLine, object: nil)
                } else if let appDelegate = AppDelegate.shared {
                    appDelegate.hangMemoFlight(text: text, color: color, aspectRatio: aspectRatio, from: sourceRect)
                } else {
                    line.addMemo(text: text, color: color, aspectRatio: aspectRatio)
                    NotificationCenter.default.post(name: .tendederoRevealLine, object: nil)
                }
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        let initialSize = (MemoAspectRatio(rawValue: initialAspectRatio) ?? .wide).editorWindowSize
        let hosting = NSHostingView(rootView: view)
        let win = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.minSize = NSSize(width: 360, height: 260)
        win.maxSize = NSSize(width: 1200, height: 1000)
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isFloatingPanel = true
        win.level = .floating
        win.backgroundColor = .clear
        win.contentView = hosting
        if let screen = NSScreen.screens.first {
            let visible = screen.visibleFrame
            win.setFrameOrigin(CGPoint(x: visible.midX - initialSize.width / 2, y: visible.midY - initialSize.height / 2))
        } else {
            win.center()
        }
        win.isReleasedWhenClosed = false
        self.window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func resizeWindow(to size: CGSize) {
        guard let window else { return }
        var frame = window.frame
        let oldCenter = CGPoint(x: frame.midX, y: frame.midY)
        frame.size = size
        frame.origin = CGPoint(x: oldCenter.x - size.width / 2, y: oldCenter.y - size.height / 2)
        window.animator().setFrame(frame, display: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

extension Notification.Name {
    static let sunMemoRevealLine = Notification.Name("sunMemoRevealLine")
    static let tendederoRevealLine = sunMemoRevealLine
}

struct QuickMemoView: View {
    let editingID: UUID?
    @State private var text: String
    @State private var color: String
    @State private var aspectRatio: String
    @State private var isPreviewMode: Bool = false
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    init(editingID: UUID?, initialText: String, initialColor: String, initialAspectRatio: String = "wide",
         onSave: @escaping (String, String, String) -> Void,
         onCancel: @escaping () -> Void) {
        self.editingID = editingID
        _text = State(initialValue: initialText)
        _color = State(initialValue: initialColor)
        _aspectRatio = State(initialValue: initialAspectRatio)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Top Bar (Header & Controls)
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(editingID == nil ? "写下想法 / 待办备忘" : "编辑便签")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                HStack(alignment: .center, spacing: 14) {
                    // Color selection buttons (real buttons so clicks are 100% responsive)
                    HStack(spacing: 7) {
                        ForEach(["yellow", "green", "pink", "blue"], id: \.self) { c in
                            Button {
                                color = c
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(colorDot(c))
                                        .frame(width: 17, height: 17)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.black.opacity(color == c ? 0.8 : 0.2), lineWidth: color == c ? 2 : 0.8)
                                        )
                                    if color == c {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .heavy))
                                            .foregroundStyle(Color.black.opacity(0.75))
                                    }
                                }
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Close button
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // MARK: Markdown Quick Toolbar & Aspect Ratio Selector
            HStack(spacing: 7) {
                // Formatting buttons
                Button {
                    insertTextPrefix("- [ ] ")
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checklist")
                            .font(.system(size: 10.5))
                        Text("待办")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    wrapText(with: "**")
                } label: {
                    Text("B 粗体")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    insertTextPrefix("- ")
                } label: {
                    HStack(spacing: 3) {
                        Text("•")
                            .font(.system(size: 12, weight: .bold))
                        Text("列表")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    insertTextPrefix("## ")
                } label: {
                    Text("H 标题")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                // Aspect Ratio Selector Pills [▭ 宽版] [□ 方版] [▯ 竖版]
                HStack(spacing: 2) {
                    ForEach(MemoAspectRatio.allCases, id: \.rawValue) { ratio in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                aspectRatio = ratio.rawValue
                                QuickMemoWindowController.shared.resizeWindow(to: ratio.editorWindowSize)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(ratio.symbol)
                                    .font(.system(size: 9.5, weight: .bold))
                                Text(ratio.title)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                aspectRatio == ratio.rawValue ? Color.black.opacity(0.12) : Color.white.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .foregroundStyle(aspectRatio == ratio.rawValue ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                // Edit vs Preview Segmented Toggle
                Picker("", selection: $isPreviewMode) {
                    Text("编辑").tag(false)
                    Text("MD 预览").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 105)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            // MARK: Large Editor or Markdown Preview
            Group {
                if isPreviewMode {
                    MarkdownPreviewScrollView(text: text, onToggleTodo: { lineIdx in
                        let result = MemoSyncManager.toggleTodoLine(in: text, lineIndex: lineIdx)
                        text = result.newText
                    })
                } else {
                    MacTextEditor(
                        text: $text,
                        placeholder: "写下想法、未完成的事项或临时待办...\n\n• 支持 Markdown 语法与清单 (- [ ] 待办)\n• 按 回车 自动续接待办列表\n• 按 ⌘ + 回车 即可挂上晾衣绳",
                        onCommit: commit
                    )
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MARK: Bottom Action Bar
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Text("⌘ + Return 挂上 · Esc 取消")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.85))

                    Button {
                        MemoSyncManager.shared.openInEditor()
                    } label: {
                        Text("📄 本地 MD 备份")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("取消") {
                        onCancel()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        commit()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(editingID == nil ? "挂上晾衣绳" : "更新便签")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6.5)
                        .background(
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.black.opacity(0.28)
                                : Color.black.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(minWidth: 380, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
        .background(memoBackground(for: color))
        .animation(.easeInOut(duration: 0.22), value: color)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 20, y: 10)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, color, aspectRatio)
    }

    private func insertTextPrefix(_ prefix: String) {
        if text.isEmpty {
            text = prefix
        } else if text.hasSuffix("\n") {
            text += prefix
        } else {
            text += "\n" + prefix
        }
    }

    private func wrapText(with wrapper: String) {
        if text.isEmpty {
            text = "\(wrapper)重点内容\(wrapper)"
        } else {
            text += " \(wrapper)重点内容\(wrapper)"
        }
    }

    private func colorDot(_ c: String) -> Color {
        switch c {
        case "green": return Color(red: 0.82, green: 0.93, blue: 0.82)
        case "pink": return Color(red: 0.98, green: 0.83, blue: 0.88)
        case "blue": return Color(red: 0.80, green: 0.89, blue: 0.98)
        default: return Color(red: 0.98, green: 0.91, blue: 0.58)
        }
    }

    private func memoBackground(for c: String) -> some View {
        let (c1, c2): (Color, Color)
        switch c.lowercased() {
        case "green":
            c1 = Color(red: 0.89, green: 0.98, blue: 0.89)
            c2 = Color(red: 0.82, green: 0.93, blue: 0.82)
        case "pink":
            c1 = Color(red: 1.0, green: 0.91, blue: 0.94)
            c2 = Color(red: 0.98, green: 0.84, blue: 0.89)
        case "blue":
            c1 = Color(red: 0.89, green: 0.95, blue: 1.0)
            c2 = Color(red: 0.80, green: 0.90, blue: 0.98)
        default: // yellow
            c1 = Color(red: 1.0, green: 0.97, blue: 0.74)
            c2 = Color(red: 0.98, green: 0.92, blue: 0.60)
        }
        return LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Markdown Preview View with interactive checkboxes

struct MarkdownPreviewScrollView: View {
    let text: String
    var onToggleTodo: (Int) -> Void

    var body: some View {
        ScrollView(.vertical) {
            let lines = text.components(separatedBy: "\n")
            VStack(alignment: .leading, spacing: 6) {
                if lines.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("暂无内容可预览")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .padding(.top, 10)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, rawLine in
                        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") || trimmed.hasPrefix("[ ] ") {
                            let content = String(trimmed.dropFirst(trimmed.hasPrefix("[ ] ") ? 4 : 6))
                            HStack(alignment: .top, spacing: 6) {
                                Button {
                                    onToggleTodo(index)
                                } label: {
                                    Image(systemName: "square")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.secondary)
                                }
                                .buttonStyle(.plain)

                                Text(LocalizedStringKey(content))
                                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                                    .foregroundStyle(Color.primary)
                            }
                        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") ||
                                  trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") ||
                                  trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
                            let content = String(trimmed.dropFirst(trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") ? 4 : 6))
                            HStack(alignment: .top, spacing: 6) {
                                Button {
                                    onToggleTodo(index)
                                } label: {
                                    Image(systemName: "checkmark.square.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.green)
                                }
                                .buttonStyle(.plain)

                                Text(LocalizedStringKey(content))
                                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                                    .strikethrough(true, color: .secondary)
                            }
                        } else if trimmed.hasPrefix("#") {
                            let header = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                            Text(LocalizedStringKey(header))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primary)
                                .padding(.top, 2)
                        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                            let content = String(trimmed.dropFirst(2))
                            HStack(alignment: .top, spacing: 5) {
                                Text("•")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.secondary)
                                Text(LocalizedStringKey(content))
                                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                            }
                        } else if !trimmed.isEmpty {
                            Text(LocalizedStringKey(trimmed))
                                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                                .foregroundStyle(Color.primary)
                        } else {
                            Spacer().frame(height: 4)
                        }
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Native MacTextEditor with zero background and smart checklist typing

struct MacTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4

        let textView = CustomNSTextView()
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: 14.5, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.systemBlue
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.placeholderString = placeholder
        textView.onCmdReturn = onCommit

        scrollView.documentView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CustomNSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextEditor
        init(_ parent: MacTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

final class CustomNSTextView: NSTextView {
    var placeholderString: String = ""
    var onCmdReturn: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.keyCode == 36 { // ⌘ + Return
            onCmdReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Smart Return for markdown checklists (- [ ]) and lists (- )
    override func insertNewline(_ sender: Any?) {
        let currentString = (self.string as NSString)
        let selectedRange = self.selectedRange()
        let lineRange = currentString.lineRange(for: selectedRange)
        let lineString = currentString.substring(with: lineRange)
        let trimmed = lineString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("- [ ] ") {
            if trimmed == "- [ ]" || trimmed == "- [ ] " {
                let replaceLen = min(lineString.count, selectedRange.location - lineRange.location)
                let replaceRange = NSRange(location: lineRange.location, length: replaceLen)
                if shouldChangeText(in: replaceRange, replacementString: "") {
                    replaceCharacters(in: replaceRange, with: "")
                }
                super.insertNewline(sender)
                return
            } else {
                super.insertNewline(sender)
                insertText("- [ ] ", replacementRange: self.selectedRange())
                return
            }
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            super.insertNewline(sender)
            insertText("- [ ] ", replacementRange: self.selectedRange())
            return
        } else if trimmed.hasPrefix("- ") && !trimmed.hasPrefix("- [") {
            if trimmed == "-" || trimmed == "- " {
                let replaceLen = min(lineString.count, selectedRange.location - lineRange.location)
                let replaceRange = NSRange(location: lineRange.location, length: replaceLen)
                if shouldChangeText(in: replaceRange, replacementString: "") {
                    replaceCharacters(in: replaceRange, with: "")
                }
                super.insertNewline(sender)
                return
            } else {
                super.insertNewline(sender)
                insertText("- ", replacementRange: self.selectedRange())
                return
            }
        }

        super.insertNewline(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !placeholderString.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 14.5),
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.55),
                .paragraphStyle: paragraph
            ]
            let x = textContainerInset.width
            let y = textContainerInset.height
            let rect = NSRect(
                x: x,
                y: y,
                width: bounds.width - x * 2,
                height: bounds.height - y * 2
            )
            (placeholderString as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}
