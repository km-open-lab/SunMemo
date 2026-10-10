import AppKit
import SwiftUI

final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    @MainActor
    func show(onEnableInbox: @escaping (Bool) -> Void) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = WelcomeView(
            onDismiss: { [weak self] enableInbox in
                self?.window?.close()
                self?.window = nil
                onEnableInbox(enableInbox)
            }
        )
        let hosting = NSHostingView(rootView: view)
        let win = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 530),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isFloatingPanel = true
        win.level = .floating
        win.hasShadow = true
        win.backgroundColor = .clear
        win.contentView = hosting
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

struct WelcomeView: View {
    @State private var enableScreenshots: Bool = true
    let onDismiss: (Bool) -> Void

    var body: some View {
        VStack(spacing: 18) {
            // App Icon & Brand Title
            VStack(spacing: 10) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                }

                VStack(spacing: 4) {
                    Text("欢迎使用 SunMemo")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("把未完成的想法与待办，晾在桌面阳光下")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 18)

            // Features List
            VStack(spacing: 14) {
                FeatureRow(
                    icon: "sparkles",
                    iconColor: Color.orange,
                    title: "桌面顶部晾衣绳",
                    description: "快捷键随时呼出收起，卡片多时自然扇面叠放"
                )
                FeatureRow(
                    icon: "checklist",
                    iconColor: Color.blue,
                    title: "便签速记与待办清单",
                    description: "弹窗速记与多色卡片，直接在绳上卡片点击打勾"
                )
                FeatureRow(
                    icon: "camera.fill",
                    iconColor: Color.indigo,
                    title: "截图与剪贴板接管",
                    description: "一键收纳截图与复制内容，桌面始终干净清爽"
                )
                FeatureRow(
                    icon: "doc.text.fill",
                    iconColor: Color.green,
                    title: "本地 Markdown 实时备份",
                    description: "实时同步至 ~/Documents/SunMemo.md，安心防丢失"
                )
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )

            // Screenshot Integration Toggle Option
            HStack(alignment: .top, spacing: 10) {
                Toggle(isOn: $enableScreenshots) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("允许 SunMemo 接管系统截图")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("截图瞬间自动晾到绳上，不堆积在桌面。随时可从菜单栏关闭。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)
            )

            Spacer(minLength: 0)

            // Action Buttons
            HStack(spacing: 14) {
                Button("以后再说") {
                    onDismiss(false)
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

                Button("开始使用") {
                    onDismiss(enableScreenshots)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color(red: 255/255, green: 140/255, blue: 60/255), Color(red: 255/255, green: 90/255, blue: 95/255)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .shadow(color: Color.orange.opacity(0.35), radius: 5, y: 2)
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 24)
        .frame(width: 440, height: 540)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }
}

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
