import AppKit
import SwiftUI

@MainActor
final class MemoPreviewWindowController {
    static let shared = MemoPreviewWindowController()
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private weak var currentLine: Line?

    var isOpen: Bool { panel != nil }

    func show(line: Line, itemID: UUID) {
        self.currentLine = line
        close()

        guard let item = line.items.first(where: { $0.id == itemID && !$0.falling }) else { return }

        let screen = LinePanel.screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first!
        let originFrame = AppDelegate.shared?.cardFrame(for: itemID)

        let previewView = HeroPreviewHostView(
            line: line,
            itemID: itemID,
            originFrame: originFrame,
            screen: screen,
            onClose: { [weak self] in
                self?.close()
            },
            onEditMemo: { [weak self] in
                self?.close()
                QuickMemoWindowController.shared.show(line: line, editingMemoID: itemID)
            },
            onMarkupImage: { [weak self] in
                self?.close()
                line.markup(itemID)
            },
            onDiscard: { [weak self] in
                self?.close()
                line.discard(itemID)
            },
            onTrash: { [weak self] in
                self?.close()
                line.trash(itemID)
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
                if item.isMemo {
                    self.close()
                    QuickMemoWindowController.shared.show(line: line, editingMemoID: itemID)
                    return nil
                }
            } else if event.keyCode == 8 /* C */ && event.modifierFlags.contains(.command) {
                line.copy(itemID)
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

// MARK: - Hero Preview Container View (带弹性伸缩牵引线 + 宽屏拟物大卡片)

struct HeroPreviewHostView: View {
    @ObservedObject var line: Line
    let itemID: UUID
    let originFrame: CGRect?
    let screen: NSScreen
    let onClose: () -> Void
    let onEditMemo: () -> Void
    let onMarkupImage: () -> Void
    let onDiscard: () -> Void
    let onTrash: () -> Void

    @State private var isExpanded: Bool = false
    @State private var copied: Bool = false

    private var item: Pegged? {
        line.items.first(where: { $0.id == itemID && !$0.falling })
    }

    // Memo card size: Widescreen landscape aspect ratio (~1.59:1), matching rope memo (220x140)!
    private let memoCardWidth: CGFloat = 510
    private let memoCardHeight: CGFloat = 320

    private var cardSize: CGSize {
        guard let item else { return CGSize(width: memoCardWidth, height: memoCardHeight) }
        if item.isMemo {
            return CGSize(width: memoCardWidth, height: memoCardHeight)
        } else {
            // Photo / screenshot size: preserve aspect ratio, bounded inside 620x420
            let imgSize = item.thumb.size
            guard imgSize.width > 0, imgSize.height > 0 else {
                return CGSize(width: 480, height: 320)
            }
            let maxW: CGFloat = 620, maxH: CGFloat = 420
            let scale = min(maxW / imgSize.width, maxH / imgSize.height)
            return CGSize(width: max(320, imgSize.width * scale),
                          height: max(220, imgSize.height * scale))
        }
    }

    private var ropePegPoint: CGPoint {
        guard let origin = originFrame else {
            return CGPoint(x: 0, y: -screen.frame.height / 2 + 30)
        }
        let px = origin.midX - screen.frame.midX
        let py = -(origin.maxY - screen.frame.midY) + 12
        return CGPoint(x: px, y: py)
    }

    private var cardClipPoint: CGPoint {
        CGPoint(x: 0, y: -cardSize.height / 2 - 12)
    }

    private var deltaOffset: CGSize {
        guard let origin = originFrame else {
            return CGSize(width: 0, height: -screen.frame.height * 0.42)
        }
        let dx = origin.midX - screen.frame.midX
        let dy = -(origin.midY - screen.frame.midY)
        return CGSize(width: dx, height: dy)
    }

    private var initialScale: CGFloat {
        guard let origin = originFrame, origin.width > 0 else { return 0.52 }
        return max(0.40, min(0.68, origin.width / cardSize.width))
    }

    private var initialTilt: Double {
        item?.tilt ?? 0
    }

    var body: some View {
        ZStack {
            // Soft translucent backdrop blur (clicking outside closes preview)
            Color.black.opacity(isExpanded ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWithAnimation()
                }

            if let item {
                // MARK: Elastic Tether Cord (从晾衣绳牵引到卡片的松弛伸缩拉绳)
                elasticCordView

                // MARK: The Main Card
                VStack(spacing: -14) {
                    // Top Clothespin hanging the card
                    Clothespin()
                        .frame(width: 26, height: 52)
                        .zIndex(2)

                    if item.isMemo {
                        widescreenMemoCard(item)
                            .zIndex(1)
                    } else {
                        photoPreviewCard(item)
                            .zIndex(1)
                    }
                }
                .rotationEffect(.degrees(isExpanded ? 0 : initialTilt), anchor: .top)
                .scaleEffect(isExpanded ? 1.0 : initialScale, anchor: .top)
                .offset(x: isExpanded ? 0 : deltaOffset.width,
                        y: isExpanded ? 0 : deltaOffset.height)
                .opacity(isExpanded ? 1.0 : 0.0)
                .animation(.spring(response: 0.38, dampingFraction: 0.74), value: isExpanded)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                isExpanded = true
            }
        }
    }

    // MARK: - Elastic Tension Cord View
    private var elasticCordView: some View {
        ZStack {
            // Top Mini Clothespin clipped on the clothesline
            Clothespin()
                .frame(width: 15, height: 28)
                .position(x: screen.frame.width / 2 + ropePegPoint.x,
                          y: screen.frame.height / 2 + ropePegPoint.y)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1)

            // Elastic Cord drawing with gentle organic curve
            Path { path in
                let start = CGPoint(x: screen.frame.width / 2 + ropePegPoint.x,
                                    y: screen.frame.height / 2 + ropePegPoint.y + 12)
                let end = CGPoint(x: screen.frame.width / 2 + (isExpanded ? cardClipPoint.x : (deltaOffset.width + cardClipPoint.x * initialScale)),
                                  y: screen.frame.height / 2 + (isExpanded ? cardClipPoint.y : (deltaOffset.height + cardClipPoint.y * initialScale)))
                path.move(to: start)
                let dx = end.x - start.x
                let midY = (start.y + end.y) / 2
                let control = CGPoint(x: start.x + dx * 0.45 + (dx >= 0 ? -10 : 10),
                                      y: midY - 14)
                path.addQuadCurve(to: end, control: control)
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.38, green: 0.35, blue: 0.42).opacity(0.72),
                        Color(red: 0.50, green: 0.46, blue: 0.55).opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
        }
        .opacity(isExpanded ? 1.0 : 0.0)
        .animation(.spring(response: 0.38, dampingFraction: 0.74), value: isExpanded)
    }

    private func dismissWithAnimation() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onClose()
        }
    }

    // MARK: - Widescreen Memo Card (宽屏比例横版便签)
    private func widescreenMemoCard(_ item: Pegged) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(alignment: .center, spacing: 8) {
                let stats = MemoSyncManager.calculateTodoStats(text: item.memoText)
                if stats.total > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: stats.completed == stats.total ? "checkmark.circle.fill" : "checklist")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("\(stats.completed)/\(stats.total) 完成")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(stats.completed == stats.total ? Color.green : Color.primary.opacity(0.78))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.55), in: Capsule())
                }

                Spacer()

                Text(timeString(from: item.createdAt))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.85))

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
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 16)
                .opacity(0.35)

            // Markdown Body with interactive checkboxes (Widescreen layout)
            MarkdownPreviewScrollView(text: item.memoText) { lineIndex in
                line.toggleMemoTodoLine(id: item.id, lineIndex: lineIndex)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(height: 185)

            Divider()
                .padding(.horizontal, 16)
                .opacity(0.35)

            // Bottom Action Bar
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    // Copy full text button
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.memoText, forType: .string)
                        copied = true
                        line.play("Tink", volume: 0.25)
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
                        .padding(.horizontal, 13)
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
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // Edit button
                    Button {
                        onEditMemo()
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
                        .background(Color.black.opacity(0.82), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Text("按 Esc 或点击空白处收起 · 双击卡片或按 Enter 编辑")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.65))
            }
            .padding(.horizontal, 18)
            .padding(.top, 9)
            .padding(.bottom, 12)
        }
        .frame(width: memoCardWidth, height: memoCardHeight)
        .background(memoBackground(for: item.memoColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 34, y: 16)
        .onTapGesture(count: 2) {
            onEditMemo()
        }
    }

    // MARK: - Photo / Screenshot Preview Card (高清图片大卡片)
    private func photoPreviewCard(_ item: Pegged) -> some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 11))
                    Text(item.url.lastPathComponent)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.primary.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .glassFrame(capsule: true)

                Spacer()

                Button {
                    dismissWithAnimation()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 22, height: 22)
                        .glassFrame(circle: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // High resolution image display
            Image(nsImage: item.thumb)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: cardSize.width - 24, maxHeight: cardSize.height - 90)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            // Bottom Action Bar
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    // Double click / single click copy button
                    Button {
                        line.copy(item.id)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .bold))
                            Text(copied ? "已复制" : "复制图片")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(copied ? Color.green : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassFrame(capsule: true)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Markup button
                    Button {
                        onMarkupImage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil.tip.crop.circle")
                                .font(.system(size: 11))
                            Text("标记")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassFrame(capsule: true)
                    }
                    .buttonStyle(.plain)

                    // Trash button
                    Button {
                        onTrash()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("移至废纸篓")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color.red.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassFrame(capsule: true)
                    }
                    .buttonStyle(.plain)
                }

                Text("按 Esc 或空白处收起 · 双击图片直接复制")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .glassFrame(cornerRadius: 18)
        .shadow(color: .black.opacity(0.35), radius: 34, y: 16)
        // Double click anywhere on photo copies image!
        .onTapGesture(count: 2) {
            line.copy(item.id)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                copied = false
            }
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
