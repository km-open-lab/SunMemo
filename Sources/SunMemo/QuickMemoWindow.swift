import AppKit
import SwiftUI

/// What the editor holds: the text and how the card looks.
struct MemoDraft: Codable, Equatable {
    var text: String
    var color: String
    var aspectRatio: String

    static let empty = MemoDraft(text: "", color: "yellow", aspectRatio: "wide")

    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// The memo editor. It never throws away what you typed without asking:
/// unsaved text is kept as a draft on every keystroke, so it also survives
/// a crash, and closing or switching to another memo asks first.
@MainActor
final class QuickMemoWindowController: NSObject, NSWindowDelegate {
    static let shared = QuickMemoWindowController()
    private var window: NSPanel?
    private weak var currentLine: Line?

    /// The memo being edited, nil for a new one.
    private var editingMemoID: UUID?
    /// The memo as saved, or empty for a new one.
    private var original = MemoDraft.empty
    /// What the editor holds right now.
    private var current = MemoDraft.empty

    private var hasUnsavedChanges: Bool { current != original && !current.isBlank }

    func show(line: Line, editingMemoID: UUID? = nil) {
        if let editingMemoID {
            MemoPreviewWindowController.shared.show(line: line, itemID: editingMemoID, startEditing: true)
            return
        }

        if let window {
            // Already editing this one: bring it back with what you typed.
            if editingMemoID == self.editingMemoID {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            guard confirmClose() else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            closeWindow()
        }

        self.currentLine = line
        self.editingMemoID = editingMemoID
        Drafts.prune(keeping: Set(line.items.map(\.id)))

        if let editingMemoID,
           let memo = line.items.first(where: { $0.id == editingMemoID && $0.isMemo }) {
            original = MemoDraft(text: memo.memoText, color: memo.memoColor, aspectRatio: memo.aspectRatio)
        } else {
            original = .empty
        }
        // Text left unsaved last time comes back.
        current = Drafts.load(for: editingMemoID) ?? original

        let view = QuickMemoView(
            editingID: editingMemoID,
            initialText: current.text,
            initialColor: current.color,
            initialAspectRatio: current.aspectRatio,
            onEdit: { [weak self] text, color, aspectRatio in
                self?.draftChanged(MemoDraft(text: text, color: color, aspectRatio: aspectRatio))
            },
            onSave: { [weak self] text, color, aspectRatio in
                self?.save(MemoDraft(text: text, color: color, aspectRatio: aspectRatio))
            },
            onCancel: { [weak self] in
                self?.requestClose()
            }
        )

        let initialSize = (MemoAspectRatio(rawValue: current.aspectRatio) ?? .wide).editorWindowSize
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
        win.delegate = self
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

    private func draftChanged(_ draft: MemoDraft) {
        current = draft
        if hasUnsavedChanges {
            Drafts.store(draft, for: editingMemoID)
        } else {
            Drafts.remove(for: editingMemoID)
        }
    }

    private func save(_ draft: MemoDraft) {
        guard let line = currentLine, !draft.isBlank else { return }
        let sourceRect = window?.frame
        let editingMemoID = self.editingMemoID
        Drafts.remove(for: editingMemoID)
        closeWindow()

        // A memo taken down while it was being edited is hung again as a new
        // one, so the edit is not lost.
        if let editingMemoID, line.items.contains(where: { $0.id == editingMemoID && $0.isMemo && !$0.falling }) {
            line.updateMemo(id: editingMemoID, text: draft.text, color: draft.color, aspectRatio: draft.aspectRatio)
            NotificationCenter.default.post(name: .sunMemoRevealLine, object: nil)
        } else if let appDelegate = AppDelegate.shared {
            appDelegate.hangMemoFlight(text: draft.text, color: draft.color, aspectRatio: draft.aspectRatio, from: sourceRect)
        } else {
            line.addMemo(text: draft.text, color: draft.color, aspectRatio: draft.aspectRatio)
            NotificationCenter.default.post(name: .sunMemoRevealLine, object: nil)
        }
    }

    /// Esc, the Cancel button or the cross: closes, asking first when there
    /// is unsaved text.
    private func requestClose() {
        if confirmClose() { closeWindow() }
    }

    /// Whether the editor may close. With unsaved text, the choice is to keep
    /// it as a draft, discard it, or go back to editing.
    private func confirmClose() -> Bool {
        guard hasUnsavedChanges else {
            Drafts.remove(for: editingMemoID)
            return true
        }
        let alert = NSAlert()
        if editingMemoID == nil {
            alert.messageText = L("This memo is not on the line yet")
            alert.informativeText = L("Keep it as a draft and it comes back the next time you write a new memo.")
        } else {
            alert.messageText = L("This memo has unsaved changes")
            alert.informativeText = L("Keep them as a draft and they come back the next time you edit this memo.")
        }
        alert.addButton(withTitle: L("Keep Draft"))
        alert.addButton(withTitle: L("Keep Editing"))
        alert.addButton(withTitle: L("Discard"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Drafts.store(current, for: editingMemoID)
            return true
        case .alertThirdButtonReturn:
            Drafts.remove(for: editingMemoID)
            return true
        default:
            return false
        }
    }

    /// The window's own close button.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard confirmClose() else { return false }
        sender.delegate = nil
        resetState()
        return true
    }

    func resizeWindow(to size: CGSize) {
        guard let window else { return }
        var frame = window.frame
        let oldCenter = CGPoint(x: frame.midX, y: frame.midY)
        frame.size = size
        frame.origin = CGPoint(x: oldCenter.x - size.width / 2, y: oldCenter.y - size.height / 2)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: Demo hooks

    /// Opens the editor for a new memo with this color and shape, empty.
    func showForDemo(line: Line, color: String, aspectRatio: String) {
        Drafts.store(MemoDraft(text: "", color: color, aspectRatio: aspectRatio), for: nil)
        show(line: line)
    }

    /// The editor's text view, so the demo can type into it like a person.
    var demoTextView: NSTextView? {
        func find(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            for sub in view.subviews { if let text = find(sub) { return text } }
            return nil
        }
        if let text = window?.firstResponder as? NSTextView { return text }
        return window?.contentView.flatMap(find)
    }

    /// Hangs what the editor holds, as ⌘Return does.
    func commitForDemo() {
        var draft = current
        if let text = demoTextView?.string { draft.text = text }
        save(draft)
    }

    /// Closes the editor, asking first if there is unsaved text.
    func close() {
        requestClose()
    }

    private func closeWindow() {
        window?.delegate = nil
        window?.close()
        resetState()
    }

    private func resetState() {
        window = nil
        editingMemoID = nil
        original = .empty
        current = .empty
    }
}

/// Unsaved editor text, one draft per memo plus one for a new memo, kept in
/// the user defaults so it survives quitting and crashes.
private enum Drafts {
    private static let key = "memoDrafts"
    private static let newMemo = "new"

    private static func slot(_ id: UUID?) -> String { id?.uuidString ?? newMemo }

    private static func all() -> [String: MemoDraft] {
        guard let data = Demo.defaults.data(forKey: key),
              let drafts = try? JSONDecoder().decode([String: MemoDraft].self, from: data) else { return [:] }
        return drafts
    }

    private static func save(_ drafts: [String: MemoDraft]) {
        if drafts.isEmpty {
            Demo.defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(drafts) {
            Demo.defaults.set(data, forKey: key)
        }
    }

    static func load(for id: UUID?) -> MemoDraft? { all()[slot(id)] }

    static func store(_ draft: MemoDraft, for id: UUID?) {
        var drafts = all()
        drafts[slot(id)] = draft
        save(drafts)
    }

    static func remove(for id: UUID?) {
        var drafts = all()
        guard drafts.removeValue(forKey: slot(id)) != nil else { return }
        save(drafts)
    }

    /// Drafts of memos that are no longer on the line are dropped. The new
    /// memo draft always stays.
    static func prune(keeping ids: Set<UUID>) {
        let drafts = all()
        let kept = drafts.filter { key, _ in key == newMemo || UUID(uuidString: key).map(ids.contains) == true }
        if kept.count != drafts.count { save(kept) }
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
    let onEdit: (String, String, String) -> Void
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    init(editingID: UUID?, initialText: String, initialColor: String, initialAspectRatio: String = "wide",
         onEdit: @escaping (String, String, String) -> Void = { _, _, _ in },
         onSave: @escaping (String, String, String) -> Void,
         onCancel: @escaping () -> Void) {
        self.editingID = editingID
        self.onEdit = onEdit
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
                            withAnimation(Motion.snappy) {
                                aspectRatio = ratio.rawValue
                            }
                            QuickMemoWindowController.shared.resizeWindow(to: ratio.editorWindowSize)
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
                    Text(editingID == nil ? "⌘ + Return 挂上 · Esc 取消" : "⌘ + Return 保存并飞回 · Esc 取消")
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
        // Every change is reported, so the controller can keep a draft.
        .onChange(of: text) { _ in onEdit(text, color, aspectRatio) }
        .onChange(of: color) { _ in onEdit(text, color, aspectRatio) }
        .onChange(of: aspectRatio) { _ in onEdit(text, color, aspectRatio) }
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
                                AnimatedTodoCheckbox(isChecked: false, size: 14) {
                                    onToggleTodo(index)
                                }
                                AnimatedStrikethroughText(text: content, isStruck: false, font: .system(size: 13.5, weight: .regular, design: .rounded), lineLimit: nil)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onToggleTodo(index)
                            }
                        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") ||
                                  trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") ||
                                  trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
                            let content = String(trimmed.dropFirst(trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") ? 4 : 6))
                            HStack(alignment: .top, spacing: 6) {
                                AnimatedTodoCheckbox(isChecked: true, size: 14) {
                                    onToggleTodo(index)
                                }
                                AnimatedStrikethroughText(text: content, isStruck: true, font: .system(size: 13.5, weight: .regular, design: .rounded), lineLimit: nil)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onToggleTodo(index)
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
        textView.allowsUndo = true
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

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CustomNSTextView else { return }
        context.coordinator.parent = self
        textView.onCmdReturn = onCommit
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI may create this view before attaching it to the panel.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeKey()
            window.makeFirstResponder(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if event.keyCode == 36 { // ⌘ + Return
                onCmdReturn?()
                return true
            }
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "v":
                    paste(nil)
                    return true
                case "c":
                    copy(nil)
                    return true
                case "x":
                    cut(nil)
                    return true
                case "a":
                    selectAll(nil)
                    return true
                case "z":
                    undoManager?.undo()
                    return true
                default:
                    break
                }
            }
        } else if flags == [.command, .shift] {
            if event.charactersIgnoringModifiers?.lowercased() == "z" {
                undoManager?.redo()
                return true
            }
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
