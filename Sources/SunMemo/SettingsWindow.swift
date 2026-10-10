import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    @MainActor
    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
        let hosting = NSHostingView(rootView: view)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "SunMemo 偏好设置"
        win.contentView = hosting
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    @ObservedObject var clipboardWatcher = ClipboardWatcher.shared
    @State private var recordingTarget: RecordingTarget?

    enum RecordingTarget {
        case toggle
        case memo
        case paste
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemSymbolName: "sun.max.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SunMemo (晾想法) 偏好设置")
                        .font(.headline)
                    Text("自定义全局快捷键与剪贴板防误触")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Shortcuts Section
            VStack(alignment: .leading, spacing: 12) {
                Text("全局快捷键（点击即可自定义录制）")
                    .font(.system(size: 13, weight: .semibold))

                // Toggle Line Shortcut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("呼出 / 隐藏晾衣绳")
                            .font(.system(size: 13))
                        Text("下拉或收起屏幕顶部的晾衣绳")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ShortcutButton(
                        text: KeyHelper.shortcutString(keyCode: hotKeyManager.toggleKey, modifiers: hotKeyManager.toggleMods),
                        isRecording: recordingTarget == .toggle
                    ) {
                        recordingTarget = (recordingTarget == .toggle) ? nil : .toggle
                    }
                }

                // New Memo Shortcut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("弹出桌面窗口写便签")
                            .font(.system(size: 13))
                        Text("弹出一个大便签窗口，写完点挂上")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ShortcutButton(
                        text: KeyHelper.shortcutString(keyCode: hotKeyManager.memoKey, modifiers: hotKeyManager.memoMods),
                        isRecording: recordingTarget == .memo
                    ) {
                        recordingTarget = (recordingTarget == .memo) ? nil : .memo
                    }
                }

                // Hang Clipboard Shortcut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("挂上当前剪贴板内容")
                            .font(.system(size: 13))
                        Text("截完图或复制文本后，按此键立即夹到绳上")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ShortcutButton(
                        text: KeyHelper.shortcutString(keyCode: hotKeyManager.pasteKey, modifiers: hotKeyManager.pasteMods),
                        isRecording: recordingTarget == .paste
                    ) {
                        recordingTarget = (recordingTarget == .paste) ? nil : .paste
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            // Clipboard Behavior Section
            VStack(alignment: .leading, spacing: 8) {
                Text("剪贴板与防误触")
                    .font(.system(size: 13, weight: .semibold))

                Toggle(isOn: Binding(
                    get: { clipboardWatcher.isAutoHangEnabled },
                    set: { clipboardWatcher.isAutoHangEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动将新复制的截图挂上绳")
                            .font(.system(size: 12.5))
                        Text("若关闭：复制普通图片绝不自动打扰，只在按快捷键或点击按钮时挂上。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            Spacer()

            // Bottom Actions
            HStack {
                Button("恢复默认快捷键") {
                    hotKeyManager.resetToDefaults()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))

                Spacer()

                Button("完成") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
        .background(KeyCaptureView(recordingTarget: $recordingTarget) { keyCode, modifiers in
            if recordingTarget == .toggle {
                hotKeyManager.toggleKey = keyCode
                hotKeyManager.toggleMods = modifiers
            } else if recordingTarget == .memo {
                hotKeyManager.memoKey = keyCode
                hotKeyManager.memoMods = modifiers
            } else if recordingTarget == .paste {
                hotKeyManager.pasteKey = keyCode
                hotKeyManager.pasteMods = modifiers
            }
            recordingTarget = nil
        })
    }
}

private struct ShortcutButton: View {
    let text: String
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isRecording ? "请按下组合键..." : text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isRecording ? Color.accentColor.opacity(0.15) : Color(NSColor.textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct KeyCaptureView: NSViewRepresentable {
    @Binding var recordingTarget: SettingsView.RecordingTarget?
    let onCaptured: (Int, Int) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCaptured = onCaptured
        view.onCancel = { recordingTarget = nil }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isCapturing = (recordingTarget != nil)
    }
}

private final class KeyCaptureNSView: NSView {
    var isCapturing = false {
        didSet {
            if isCapturing {
                window?.makeFirstResponder(self)
            }
        }
    }
    var onCaptured: ((Int, Int) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // ESC
            onCancel?()
            return
        }

        let mods = KeyHelper.carbonModifiers(from: event.modifierFlags)
        if mods != 0 {
            onCaptured?(Int(event.keyCode), mods)
        } else {
            NSSound.beep()
        }
    }
}

private extension Image {
    init(systemSymbolName: String) {
        if let img = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: nil) {
            self.init(nsImage: img)
        } else {
            self.init(systemName: "gear")
        }
    }
}
