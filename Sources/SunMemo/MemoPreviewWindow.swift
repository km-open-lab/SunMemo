import AppKit
import SwiftUI

@MainActor
final class MemoPreviewWindowController {
    static let shared = MemoPreviewWindowController()
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private weak var currentLine: Line?

    func show(line: Line, memoID: UUID) {
        self.currentLine = line
        close()

        guard line.items.contains(where: { $0.id == memoID && $0.isMemo }) else { return }

        let screen = LinePanel.screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first!
        let originFrame = AppDelegate.shared?.cardFrame(for: memoID)

        let previewView = MemoHeroPreviewView(
            line: line,
            memoID: memoID,
            originFrame: originFrame,
            screen: screen,
            onClose: { [weak self] in
                self?.close()
            },
            onEdit: { [weak self] in
                self?.close()
                QuickMemoWindowController.shared.show(line: line, editingMemoID: memoID)
            },
            onDiscard: { [weak self] in
                self?.close()
                line.discard(memoID)
            }
        )

        let hosting = NSHostingView(rootView: previewView)
        let win = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.isMovable = false
        win.contentView = hosting

        self.panel = win
        win.makeKeyAndOrderFront(nil)

        // Keyboard handler for Esc, Space, and Enter
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            if event.keyCode == 53 /* Esc */ || event.keyCode == 49 /* Space */ {
                self.close()
                return nil
            } else if event.keyCode == 36 /* Enter */ {
                self.close()
                QuickMemoWindowController.shared.show(line: line, editingMemoID: memoID)
                return nil
            }
            return event
        }
    }

    func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Hero Preview SwiftUI View (方案 B 拟物呈现 + 方案 A 交互闭环)

struct MemoHeroPreviewView: View {
    @ObservedObject var line: Line
    let memoID: UUID
    let originFrame: CGRect?
    let screen: NSScreen
    let onClose: () -> Void
    let onEdit: () -> Void
    let onDiscard: () -> Void

    @State private var isExpanded: Bool = false
    @State private var copied: Bool = false

    private var memo: Pegged? {
        line.items.first(where: { $0.id == memoID && $0.isMemo })
    }

    private var deltaOffset: CGSize {
        guard let origin = originFrame else {
            return CGSize(width: 0, height: -screen.frame.height * 0.42)
        }
        let screenCenterX = screen.frame.midX
        let screenCenterY = screen.frame.midY
        let cardCenterX = origin.midX
        let cardCenterY = origin.midY
        let dx = cardCenterX - screenCenterX
        let dy = -(cardCenterY - screenCenterY)
        return CGSize(width: dx, height: dy)
    }

    private var initialScale: CGFloat {
        guard let origin = originFrame, origin.width > 0 else { return 0.55 }
        return max(0.45, min(0.75, origin.width / 380))
    }

    private var initialTilt: Double {
        memo?.tilt ?? 0
    }

    var body: some View {
        ZStack {
            // Semi-transparent dimmed backdrop (clicking outside closes preview)
            Color.black.opacity(isExpanded ? 0.32 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWithAnimation()
                }

            if let memo {
                VStack(spacing: -14) {
                    // Top wooden clothespin hanging from the rope
                    Clothespin()
                        .frame(width: 24, height: 50)
                        .zIndex(2)

                    // Hero expanded memo card
                    memoCardBody(memo)
                        .zIndex(1)
                }
                .rotationEffect(.degrees(isExpanded ? 0 : initialTilt), anchor: .top)
                .scaleEffect(isExpanded ? 1.0 : initialScale, anchor: .top)
                .offset(x: isExpanded ? 0 : deltaOffset.width,
                        y: isExpanded ? 0 : deltaOffset.height)
                .opacity(isExpanded ? 1.0 : 0.0)
                .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isExpanded)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                isExpanded = true
            }
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onClose()
        }
    }

    private func memoCardBody(_ item: Pegged) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(alignment: .center, spacing: 8) {
                let stats = MemoSyncManager.calculateTodoStats(text: item.memoText)
                if stats.total > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: stats.completed == stats.total ? "checkmark.circle.fill" : "checklist")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(stats.completed)/\(stats.total) 完成")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(stats.completed == stats.total ? Color.green : Color.primary.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.55), in: Capsule())
                }

                Spacer()

                Text(timeString(from: item.createdAt))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.8))

                Button {
                    dismissWithAnimation()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 14)
                .opacity(0.4)

            // Rich Markdown Body with interactive checkboxes
            MarkdownPreviewScrollView(text: item.memoText) { lineIndex in
                line.toggleMemoTodoLine(id: item.id, lineIndex: lineIndex)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 180, maxHeight: 380)

            Divider()
                .padding(.horizontal, 14)
                .opacity(0.4)

            // Bottom Action Bar (方案 A 交互闭环)
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    // Copy full text button
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.memoText, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .bold))
                            Text(copied ? "已复制" : "复制全文")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(copied ? Color.green : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.65), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Discard / Archive button
                    Button {
                        onDiscard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("撕下归档")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color.red.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // Edit button
                    Button {
                        onEdit()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11, weight: .bold))
                            Text("编辑便签")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.78), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Keyboard shortcuts hint
                Text("按 Esc 或点击空白处收起 · 双击卡片或按 Enter 编辑")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 380)
        .background(memoBackground(for: item.memoColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 32, y: 14)
        // Double click anywhere on the card opens edit mode!
        .onTapGesture(count: 2) {
            onEdit()
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "今天 HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "昨天 HH:mm"
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
        }
        return formatter.string(from: date)
    }

    private func memoBackground(for c: String) -> some View {
        let (c1, c2): (Color, Color)
        switch c.lowercased() {
        case "green":
            c1 = Color(red: 0.90, green: 0.98, blue: 0.90)
            c2 = Color(red: 0.83, green: 0.94, blue: 0.83)
        case "pink":
            c1 = Color(red: 1.0, green: 0.92, blue: 0.95)
            c2 = Color(red: 0.98, green: 0.85, blue: 0.90)
        case "blue":
            c1 = Color(red: 0.90, green: 0.96, blue: 1.0)
            c2 = Color(red: 0.82, green: 0.91, blue: 0.98)
        default: // yellow
            c1 = Color(red: 1.0, green: 0.97, blue: 0.76)
            c2 = Color(red: 0.98, green: 0.92, blue: 0.62)
        }
        return LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom)
    }
}
