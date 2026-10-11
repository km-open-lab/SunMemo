import SwiftUI

enum Layout {
    static let panelHeight: CGFloat = 275
    static let ropeTop: CGFloat = 10
    static let cardWidth: CGFloat = 150
    static let memoWidth: CGFloat = 220
    static let memoHeight: CGFloat = 140
    static let pinAbove: CGFloat = 9.5

    static func memoWidth(for aspectRatio: String) -> CGFloat {
        (MemoAspectRatio(rawValue: aspectRatio) ?? .wide).ropeSize.width
    }

    static func memoWidth(for item: Pegged) -> CGFloat {
        if let customW = item.customWidth {
            return MemoLimits.clampWidth(customW) + Frame.inset * 2
        }
        return memoWidth(for: item.aspectRatio)
    }

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
    @State private var ropeVibration: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalCards = line.items.count + 1

            ZStack(alignment: .topLeading) {
                Rope(width: width)

                // Hanging cards (Playing card parting / peeking effect on hover)
                ForEach(Array(line.items.enumerated()), id: \.element.id) { index, item in
                    let x = Layout.x(index: index, count: totalCards, width: width)
                    let ropeY = Layout.ropeY(x: x, width: width)
                    let itemWidth = item.isMemo ? Layout.memoWidth(for: item) : Layout.cardWidth
                    let peek = peekingTransform(index: index, hoveredID: line.hoveredID)
                    PeggedView(item: item, line: line)
                        .scaleEffect(peek.scale, anchor: .top)
                        .offset(x: peek.xOffset)
                        .rotationEffect(.degrees(peek.tilt), anchor: .top)
                        .frame(width: itemWidth, height: Layout.panelHeight - ropeY, alignment: .top)
                        .position(x: x, y: ropeY - Layout.pinAbove + (Layout.panelHeight - ropeY) / 2)
                        .zIndex(peek.zIndex)
                        .animation(Motion.snappy, value: line.hoveredID)
                }

                // Add Memo Card at the end of the line
                let addX = Layout.x(index: line.items.count, count: totalCards, width: width)
                let addRopeY = Layout.ropeY(x: addX, width: width)
                let addOffset = addCardPeekingOffset(hoveredID: line.hoveredID)
                AddMemoCardView(line: line)
                    .offset(x: addOffset)
                    .frame(width: Layout.memoWidth, height: Layout.panelHeight - addRopeY, alignment: .top)
                    .position(x: addX, y: addRopeY - Layout.pinAbove + (Layout.panelHeight - addRopeY) / 2)
                    .zIndex(Double(totalCards + 1))
                    .animation(Motion.snappy, value: line.hoveredID)

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
            .animation(Motion.gentle, value: line.items.map(\.id))
            .animation(.easeInOut(duration: 0.3), value: line.items.isEmpty)
            .offset(y: (line.revealed ? 0 : -(Layout.panelHeight + 12)) + ropeVibration)
            .animation(line.revealed ? Motion.gentle : .easeIn(duration: 0.22), value: line.revealed)
        }
        .onPreferenceChange(HitRectsKey.self) { rects in
            line.hitRects = rects
        }
        .onChange(of: line.shockToken) { _ in
            guard !Motion.shouldReduceMotion else { return }
            withAnimation(Motion.bouncy) {
                ropeVibration = 2.4 * (Bool.random() ? 1 : -1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(Motion.gentle) {
                    ropeVibration = 0
                }
            }
        }
        .onChange(of: line.hardSlapToken) { _ in
            guard !Motion.shouldReduceMotion else { return }
            withAnimation(Motion.bouncy) {
                ropeVibration = 5.5 * (Bool.random() ? 1 : -1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(Motion.gentle) {
                    ropeVibration = 0
                }
            }
        }
    }

    /// Scheme B: Hand-parting playing cards (扇面推开 / Peeking 让位)
    /// When hovering over a card:
    /// - Hovered card steps forward into clear view: a small lift anchored at its
    ///   clothespin, so the pin stays on the rope.
    /// - Adjacent cards part smoothly using a continuous exponential decay curve.
    /// - Respects Reduce Motion by disabling tilt and offsets.
    private func peekingTransform(index: Int, hoveredID: UUID?) -> (xOffset: CGFloat, scale: CGFloat, tilt: Double, zIndex: Double) {
        let baseZIndex = Double(index + 1)
        guard let hoveredID,
              let hIndex = line.items.firstIndex(where: { $0.id == hoveredID }) else {
            return (0.0, 1.0, 0.0, baseZIndex)
        }

        let maxCards = Double(line.items.count)
        if Motion.shouldReduceMotion {
            // Under reduce motion: no parting or tilting, hovered card slightly elevated
            let zIndex = (index == hIndex) ? (maxCards + 5) : baseZIndex
            return (0.0, 1.0, 0.0, zIndex)
        }

        let dist = abs(index - hIndex)
        if dist == 0 {
            // Hovered card steps forward into clear view
            return (0.0, Motion.hoverLift, 0.0, maxCards + 5)
        } else {
            // Continuous exponential decay curve (no discrete step jumps)
            let d = Double(dist)
            let decay = exp(-0.68 * (d - 1.0))
            let direction: CGFloat = (index < hIndex) ? -1.0 : 1.0
            let xOff = direction * CGFloat(28.0 * decay)
            let tilt = Double(direction) * (2.2 * decay)
            let zIndex = max(1.0, maxCards + 4 - Double(dist))
            return (xOff, 1.0, tilt, zIndex)
        }
    }

    private func addCardPeekingOffset(hoveredID: UUID?) -> CGFloat {
        guard !Motion.shouldReduceMotion,
              let hoveredID,
              let hIndex = line.items.firstIndex(where: { $0.id == hoveredID }) else {
            return 0
        }
        let dist = line.items.count - hIndex
        if dist >= 1 {
            let decay = exp(-0.68 * (Double(dist) - 1.0))
            return CGFloat(26.0 * decay)
        }
        return 0
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
        .onChange(of: line.isAddingMemo) { adding in
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
        .animation(Motion.snappy, value: isHovering)
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
