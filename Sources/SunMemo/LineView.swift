import SwiftUI

enum Layout {
    static let panelHeight: CGFloat = 245
    static let ropeTop: CGFloat = 10
    static let cardWidth: CGFloat = 150
    static let memoWidth: CGFloat = 220
    static let memoHeight: CGFloat = 140
    static let pinAbove: CGFloat = 9.5

    /// The rope hangs as a parabola from edge to edge of the screen.
    static func sag(width: CGFloat) -> CGFloat { min(32, width * 0.018) }

    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = x / width
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    /// Dynamically computes step spacing. When cards are few, they are spaced naturally (205pt).
    /// When cards increase, spacing smoothly compresses (down to 45pt), naturally overlapping like cards in hand!
    static func dynamicSpacing(count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return 205 }
        let naturalSpacing: CGFloat = 205
        let availableWidth = max(260, width - 260)
        let neededWidth = CGFloat(count - 1) * naturalSpacing
        if neededWidth <= availableWidth {
            return naturalSpacing
        }
        return max(45, availableWidth / CGFloat(count - 1))
    }

    static func x(index: Int, count: Int, width: CGFloat) -> CGFloat {
        let step = dynamicSpacing(count: count, width: width)
        let total = CGFloat(max(count - 1, 0)) * step
        return width / 2 - total / 2 + CGFloat(index) * step
    }
}

struct LineView: View {
    @ObservedObject var line: Line

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalCards = line.items.count + 1

            ZStack(alignment: .topLeading) {
                Rope(width: width)

                // Hanging cards (with macOS Dock-like magnification wave on hover)
                ForEach(Array(line.items.enumerated()), id: \.element.id) { index, item in
                    let x = Layout.x(index: index, count: totalCards, width: width)
                    let ropeY = Layout.ropeY(x: x, width: width)
                    let itemWidth = item.isMemo ? Layout.memoWidth : Layout.cardWidth
                    let mag = dockMagnification(index: index, hoveredID: line.hoveredID)
                    PeggedView(item: item, line: line)
                        .scaleEffect(mag.scale, anchor: .top)
                        .offset(y: mag.yOffset)
                        .frame(width: itemWidth, height: Layout.panelHeight - ropeY, alignment: .top)
                        .position(x: x, y: ropeY - Layout.pinAbove + (Layout.panelHeight - ropeY) / 2)
                        .zIndex(mag.zIndex)
                        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: line.hoveredID)
                }

                // Add Memo Card at the end of the line
                let addX = Layout.x(index: line.items.count, count: totalCards, width: width)
                let addRopeY = Layout.ropeY(x: addX, width: width)
                AddMemoCardView(line: line)
                    .frame(width: Layout.memoWidth, height: Layout.panelHeight - addRopeY, alignment: .top)
                    .position(x: addX, y: addRopeY - Layout.pinAbove + (Layout.panelHeight - addRopeY) / 2)
                    .zIndex(Double(totalCards + 1))

                // Top right control buttons
                HStack(spacing: 8) {
                    HangClipboardButton(line: line)
                    SettingsCornerButton(line: line)
                }
                .position(x: width - 85, y: Layout.ropeTop + 24)
                .zIndex(9999)

                if line.items.isEmpty {
                    Hint()
                        .position(x: width / 2, y: Layout.ropeY(x: width / 2, width: width) + 165)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: line.items.map(\.id))
            .animation(.easeInOut(duration: 0.3), value: line.items.isEmpty)
            .offset(y: line.revealed ? 0 : -(Layout.panelHeight + 12))
            .animation(line.revealed ? .spring(response: 0.42, dampingFraction: 0.82)
                                     : .easeIn(duration: 0.22), value: line.revealed)
        }
        .onPreferenceChange(HitRectsKey.self) { rects in
            line.hitRects = rects
        }
    }

    private func dockMagnification(index: Int, hoveredID: UUID?) -> (scale: CGFloat, yOffset: CGFloat, zIndex: Double) {
        guard let hoveredID,
              let hIndex = line.items.firstIndex(where: { $0.id == hoveredID }) else {
            return (1.0, 0.0, Double(index + 1))
        }
        let dist = abs(index - hIndex)
        if dist == 0 {
            return (1.18, 14.0, 1000.0)
        } else if dist == 1 {
            return (1.09, 7.0, 900.0 + Double(index))
        } else if dist == 2 {
            return (1.04, 3.0, 800.0 + Double(index))
        } else {
            return (1.0, 0.0, Double(index + 1))
        }
    }
}

struct AddMemoCardView: View {
    @ObservedObject var line: Line
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .zIndex(1)
            cardContent
        }
        .onChange(of: line.isAddingMemo) { _, adding in
            if adding {
                line.isAddingMemo = false
                QuickMemoWindowController.shared.show(line: line)
            }
        }
    }

    private var cardContent: some View {
        Button {
            QuickMemoWindowController.shared.show(line: line)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
                Text("记想法 / 待办")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("点击打开大窗口写便签\n(快捷键 ⌃ ⌥ N)")
                    .font(.system(size: 10.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(width: Layout.memoWidth - 14, height: Layout.memoHeight - 14)
            .background(isHovering ? Color.white.opacity(0.24) : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous)
                    .strokeBorder(isHovering ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .padding(Frame.inset)
        .glassFrame(cornerRadius: Frame.radius)
        .shadow(color: .black.opacity(isHovering ? 0.22 : 0.12), radius: isHovering ? 12 : 8, y: 4)
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
        .background(
            GeometryReader { g in
                Color.clear.preference(key: HitRectsKey.self,
                                       value: [line.addMemoButtonID: g.frame(in: .global)])
            }
        )
    }
}

private struct HangClipboardButton: View {
    @ObservedObject var line: Line
    private let id = UUID()
    @State private var justHung = false

    var body: some View {
        Button {
            let ok = ClipboardWatcher.shared.hangCurrentClipboard()
            if ok {
                justHung = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justHung = false }
            } else {
                NSSound.beep()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: justHung ? "checkmark.circle.fill" : "doc.on.clipboard.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(justHung ? .green : .secondary)
                Text(justHung ? "已挂上" : "挂上剪贴板")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassFrame(capsule: true)
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help("将当前剪贴板里的图片或文本挂上晾衣绳 (快捷键 ⌃ ⌥ V)")
        .background(
            GeometryReader { g in
                Color.clear.preference(key: HitRectsKey.self,
                                       value: [id: g.frame(in: .global)])
            }
        )
    }
}

private struct SettingsCornerButton: View {
    @ObservedObject var line: Line
    private let id = UUID()

    var body: some View {
        Button {
            SettingsWindowController.shared.show()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .glassFrame(circle: true)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help("自定义快捷键与防误触设置")
        .background(
            GeometryReader { g in
                Color.clear.preference(key: HitRectsKey.self,
                                       value: [id: g.frame(in: .global)])
            }
        )
    }
}

private struct Hint: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 11))
            Text(L("Take a screenshot and it will hang here"))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }
}

struct Rope: View {
    let width: CGFloat

    private var path: Path {
        Path { p in
            let top = Layout.ropeTop
            p.move(to: CGPoint(x: -20, y: top))
            p.addQuadCurve(
                to: CGPoint(x: width + 20, y: top),
                control: CGPoint(x: width / 2, y: top + 2 * Layout.sag(width: width)))
        }
    }

    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 1.4).offset(y: 1.2).blur(radius: 1.2)
            path.stroke(Color(white: 0.55), lineWidth: 1.2)
            path.stroke(Color.white.opacity(0.45), lineWidth: 0.4).offset(y: -0.35)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .allowsHitTesting(false)
    }
}

struct HitRectsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
