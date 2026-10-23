import SwiftUI

/// One photo or memo card with its clothespin. All the charm lives here: it drops onto
/// the line, swings, sways with the breeze and falls when you pull it off.
struct PeggedView: View {
    let item: Pegged
    @ObservedObject var line: Line
    @ObservedObject private var textPreferences = MemoTextPreferences.shared

    @State private var swing: Double = 0
    @State private var arrived = false
    @State private var hovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var completedHop = false
    @State private var dragResizeDelta: CGSize = .zero
    @State private var isResizing = false
    /// Bumped by every nudge so a pending return from an older one is dropped.
    @State private var nudgeToken = 0

    private var copied: Bool { line.copiedID == item.id }
    private var dragging: Bool { line.draggingID == item.id }
    private var pressed: Bool { line.pressedID == item.id }
    /// While its preview is open the card body is on the preview panel instead.
    private var previewing: Bool { line.previewingID == item.id }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .zIndex(1)
            Group {
                if item.isMemo {
                    memoCard
                } else {
                    card
                }
            }
            // Swapped for the preview's copy with no animation, so the hand-off is invisible.
            .opacity(previewing ? 0 : 1)
            .animation(nil, value: previewing)
            .allowsHitTesting(!previewing)
        }
        .rotationEffect(.degrees(swing + item.tilt), anchor: .top)
        .offset(y: arrived ? 0 : -46)
        .opacity(item.falling || item.flying ? 0 : (arrived ? 1 : 0))
        .zIndex(hovering ? 999 : 0)
        .animation(Motion.snappy, value: hovering)
        .transaction { t in if item.falling { t.animation = nil } }
        .animation(.easeOut(duration: 0.16), value: item.flying)
        .onAppear(perform: arrive)
        .onChange(of: item.flying) { isFlying in if !isFlying { land() } }
        .onChange(of: line.gust) { _ in breeze() }
        .onChange(of: line.shockToken) { _ in
            guard !Motion.shouldReduceMotion, !previewing else { return }
            let intensity = line.shockIntensity
            let delay = Double.random(in: 0...0.12)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let deg = Double.random(in: 2.8...5.0) * intensity * (Bool.random() ? 1 : -1)
                nudge(deg)
            }
        }
        .onChange(of: line.hardSlapToken) { _ in
            guard !Motion.shouldReduceMotion, !previewing else { return }
            let delay = Double.random(in: 0...0.18)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let deg = Double.random(in: 10.0...18.0) * (Bool.random() ? 1 : -1)
                nudge(deg)
            }
        }
        .onChange(of: previewing) { isPreviewing in
            // Hold the pin still so the card lands where the preview expects it.
            guard isPreviewing else { return }
            nudgeToken += 1
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { swing = 0 }
        }
        .onChange(of: line.wobbledID) { newID in
            if newID == item.id {
                nudge(2.6)
            }
        }
        .onChange(of: item.isDone) { isDone in
            if isDone && !Motion.shouldReduceMotion {
                withAnimation(Motion.bouncy) {
                    completedHop = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(Motion.gentle) {
                        completedHop = false
                    }
                }
            }
        }
        .onChange(of: copied) { isCopied in if isCopied { nudge(3) } }
        .onChange(of: line.editingID) { newID in
            if newID == item.id {
                editText = item.memoText
                isEditing = true
            } else {
                isEditing = false
            }
        }
    }

    // MARK: Sizing

    static func photoSize(for size: CGSize) -> CGSize {
        let maxW = Layout.cardWidth - 14, maxH: CGFloat = 104
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxW, height: maxH) }
        let scale = min(maxW / size.width, maxH / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    static func cardSize(for size: CGSize) -> CGSize {
        let p = photoSize(for: size)
        return CGSize(width: p.width + Frame.inset * 2, height: p.height + Frame.inset * 2)
    }

    static func memoCardSize(for aspectRatio: String) -> CGSize {
        (MemoAspectRatio(rawValue: aspectRatio) ?? .wide).ropeSize
    }

    static func memoCardSize(for item: Pegged) -> CGSize {
        if let customW = item.customWidth, let customH = item.customHeight {
            return CGSize(width: MemoLimits.clampWidth(customW) + Frame.inset * 2,
                          height: MemoLimits.clampHeight(customH) + Frame.inset * 2)
        }
        return memoCardSize(for: item.aspectRatio)
    }

    static let cardOffsetBelowTop: CGFloat = 26 - 12

    /// The card as drawn on the line, frame included (the preview flies out of exactly this).
    static func lineCardSize(for item: Pegged) -> CGSize {
        if item.isMemo {
            if let customW = item.customWidth, let customH = item.customHeight {
                let w = MemoLimits.clampWidth(customW)
                let h = MemoLimits.clampHeight(customH)
                return CGSize(width: w + Frame.inset * 2, height: h + Frame.inset * 2)
            }
            let content = (MemoAspectRatio(rawValue: item.aspectRatio) ?? .wide).cardContentSize
            return CGSize(width: content.width + Frame.inset * 2, height: content.height + Frame.inset * 2)
        }
        return cardSize(for: item.thumb.size)
    }

    private var photoSize: CGSize { Self.photoSize(for: item.thumb.size) }
    private var memoRatio: MemoAspectRatio { MemoAspectRatio(rawValue: item.aspectRatio) ?? .wide }

    private var currentCardWidth: CGFloat {
        let base = item.customWidth ?? memoRatio.cardContentSize.width
        let w = base + (isResizing ? dragResizeDelta.width : 0)
        return MemoLimits.clampWidth(w)
    }

    private var currentCardHeight: CGFloat {
        let base = item.customHeight ?? memoRatio.cardContentSize.height
        let h = base + (isResizing ? dragResizeDelta.height : 0)
        return MemoLimits.clampHeight(h)
    }

    // MARK: Screenshot Card

    private var card: some View {
        Image(nsImage: item.thumb)
            .resizable()
            .interpolation(.high)
            .frame(width: photoSize.width, height: photoSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .padding(Frame.inset)
            .glassFrame(cornerRadius: Frame.radius)
            .shadow(color: .black.opacity(hovering ? 0.26 : 0.18), radius: hovering ? 14 : 10, y: hovering ? 8 : 5)
            .scaleEffect(pressed ? 0.96 : 1, anchor: .top)
            .animation(pressed ? .easeInOut(duration: 0.45) : .spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .opacity(dragging ? 0.45 : 1)
            .overlay(alignment: .topLeading) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .glassFrame(circle: true)
                    .padding(3)
                    .opacity(hovering && !dragging ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .allowsHitTesting(false)
            }
            .overlay(GrabArea(item: item, line: line))
            .overlay(alignment: .bottom) {
                if copied {
                    Label(L("Copied"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassFrame(capsule: true)
                        .offset(y: 16)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: copied)
            .onHover { hovering = $0; line.setHovered(item.id, hovering: $0) }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self,
                                           value: item.falling ? [:] : [item.id: g.frame(in: .global)])
                }
            )
    }

    // MARK: Sticky Note (Memo) Card

    private var memoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                VStack(spacing: 4) {
                    TextField("编辑备忘", text: $editText, onCommit: saveEdit)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(4)
                        .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button("取消") {
                            isEditing = false
                            line.editingID = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))

                        Spacer()

                        Button("保存") { saveEdit() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
            } else {
                let config = MemoTypography.config(for: item.memoText, fontSize: CGFloat(textPreferences.fontSize))
                if config.isSingleShortLine {
                    Spacer(minLength: 0)
                }

                // Interactive Markdown & Todo Checklist Renderer
                MarkdownMemoCardBody(memo: item, line: line, typography: config, cardHeight: currentCardHeight)

                Spacer(minLength: 2)

                HStack(alignment: .center) {
                    Button {
                        line.toggleMemoDone(item.id)
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(item.isDone ? Color.green : Color.secondary.opacity(0.8), lineWidth: 1.2)
                                .background(Circle().fill(item.isDone ? Color.green : Color.clear))
                                .frame(width: 14, height: 14)
                            CheckmarkPath()
                                .trim(from: 0, to: item.isDone ? 1.0 : 0.0)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                .frame(width: 10, height: 10)
                                .animation(Motion.snappy, value: item.isDone)
                        }
                        .scaleEffect(item.isDone ? 1.08 : 1.0)
                        .animation(Motion.bouncy, value: item.isDone)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .onTapGesture {
                        line.toggleMemoDone(item.id)
                    }

                    let stats = MemoSyncManager.calculateTodoStats(text: item.memoText)
                    if stats.total > 0 {
                        Text("\(stats.completed)/\(stats.total) 完成")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(stats.completed == stats.total ? Color.green : Color.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.06), in: Capsule())
                    }

                    Spacer()

                    Text(timeAgoString(from: item.createdAt))
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }
            }
        }
        .padding(.top, MemoCardLayout.headerHeight)
        .padding(10)
        .frame(width: currentCardWidth,
               height: currentCardHeight)
        .background(memoBackground(for: item.memoColor))
        .animation(.easeInOut(duration: 0.22), value: item.memoColor)
        .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .padding(Frame.inset)
        .glassFrame(cornerRadius: Frame.radius)
        .shadow(color: .black.opacity(hovering ? 0.26 : 0.18), radius: hovering ? 14 : 10, y: hovering ? 8 : 5)
        .scaleEffect(completedHop ? 1.04 : (pressed ? 0.96 : 1), anchor: .center)
        .offset(y: completedHop ? -4 : 0)
        .opacity(item.isDone ? 0.82 : (dragging ? 0.45 : 1))
        .animation(Motion.gentle, value: item.isDone)
        .animation(Motion.bouncy, value: completedHop)
        .animation(pressed ? .easeInOut(duration: 0.45) : Motion.bouncy, value: pressed)
        .contentShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
        .onTapGesture {
            guard !isResizing else { return }
            MemoPreviewWindowController.shared.show(line: line, itemID: item.id)
        }
        .overlay(alignment: .topTrailing) {
            if !dragging && !isEditing {
                Button {
                    line.discard(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 22, height: 22)
                        .glassFrame(circle: true)
                }
                .buttonStyle(.plain)
                .help(L("Take Down Memo"))
                .accessibilityLabel(L("Take Down Memo"))
                .opacity(hovering ? 1 : 0.55)
                .padding(6)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hovering && !dragging && !isEditing {
                MemoResizeHandleView(
                    isResizing: isResizing,
                    onResizeDelta: { delta in
                        isResizing = true
                        dragResizeDelta = delta
                    },
                    onResizeEnd: { translation in
                        let baseW = item.customWidth ?? memoRatio.cardContentSize.width
                        let baseH = item.customHeight ?? memoRatio.cardContentSize.height
                        let finalW = MemoLimits.clampWidth(baseW + translation.width)
                        let finalH = MemoLimits.clampHeight(baseH + translation.height)
                        dragResizeDelta = .zero
                        isResizing = false
                        line.updateMemoCustomSize(id: item.id, width: finalW, height: finalH)
                    },
                    onReset: {
                        withAnimation(Motion.bouncy) {
                            line.updateMemoCustomSize(id: item.id, width: nil, height: nil)
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .contextMenu {
            Button("查看完整便签") {
                MemoPreviewWindowController.shared.show(line: line, itemID: item.id)
            }
            Button("编辑便签") {
                QuickMemoWindowController.shared.show(line: line, editingMemoID: item.id)
            }
            Menu("切换比例") {
                Button("▭ 宽版 (16:10)") { line.updateMemoAspectRatio(id: item.id, aspectRatio: "wide") }
                Button("□ 方版 (1:1)") { line.updateMemoAspectRatio(id: item.id, aspectRatio: "square") }
                Button("▯ 竖版 (3:4)") { line.updateMemoAspectRatio(id: item.id, aspectRatio: "tall") }
            }
            Menu(L("Memo Font Size")) {
                ForEach(12...24, id: \.self) { size in
                    Button("\(Int(textPreferences.fontSize) == size ? "✓ " : "")\(size) pt") {
                        textPreferences.setFontSize(Double(size))
                    }
                }
            }
            if item.customWidth != nil || item.customHeight != nil {
                Button("恢复预设卡片大小") {
                    withAnimation(Motion.bouncy) {
                        line.updateMemoCustomSize(id: item.id, width: nil, height: nil)
                    }
                }
            }
            Button(item.isDone ? "标记为未完成" : "标记为已完成") {
                line.toggleMemoDone(item.id)
            }
            Button("复制便签文本") {
                line.copy(item.id)
            }
            Divider()
            Button("撕下便签", role: .destructive) {
                line.discard(item.id)
            }
        }
        .onDrag {
            NSItemProvider(object: item.memoText as NSString)
        }
        .onHover { hovering = $0; line.setHovered(item.id, hovering: $0) }
        .background(
            GeometryReader { g in
                Color.clear.preference(key: HitRectsKey.self,
                                       value: item.falling ? [:] : [item.id: g.frame(in: .global)])
            }
        )
    }

    private func saveEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            line.updateMemo(id: item.id, text: trimmed)
        }
        isEditing = false
        line.editingID = nil
    }

    private func memoBackground(for color: String) -> some View {
        let (c1, c2): (Color, Color)
        switch color.lowercased() {
        case "green":
            c1 = Color(red: 0.88, green: 0.97, blue: 0.88)
            c2 = Color(red: 0.82, green: 0.93, blue: 0.82)
        case "pink":
            c1 = Color(red: 1.0, green: 0.90, blue: 0.93)
            c2 = Color(red: 0.98, green: 0.83, blue: 0.88)
        case "blue":
            c1 = Color(red: 0.88, green: 0.94, blue: 1.0)
            c2 = Color(red: 0.80, green: 0.89, blue: 0.98)
        default: // yellow
            c1 = Color(red: 1.0, green: 0.96, blue: 0.72)
            c2 = Color(red: 0.98, green: 0.91, blue: 0.58)
        }
        return LinearGradient(colors: [c1, c2], startPoint: .top, endPoint: .bottom)
    }

    private func timeAgoString(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(max(1, seconds / 60))分钟前" }
        if seconds < 86400 { return "\(seconds / 3600)小时前" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    // MARK: Physics

    private func arrive() {
        if item.flying || Motion.shouldReduceMotion {
            arrived = true
            return
        }
        swing = Motion.arriveAngle
        withAnimation(Motion.bouncy) { arrived = true }
        withAnimation(Motion.arriveSwing) { swing = 0 }
    }

    private func land() {
        guard !Motion.shouldReduceMotion else { return }
        nudge(2.2)
    }

    private func breeze() {
        guard !Motion.shouldReduceMotion else { return }
        let delay = Double.random(in: 0...0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            nudge(Double.random(in: 1.6...3.4))
        }
    }

    /// One continuous motion: a quick push, and the swing back takes over before the
    /// peak so there is no dead stop. A newer nudge cancels the pending return.
    private func nudge(_ degrees: Double) {
        guard !Motion.shouldReduceMotion, !previewing else { return }
        nudgeToken += 1
        let token = nudgeToken
        withAnimation(Motion.nudgePush) { swing = degrees }
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.nudgeReturnDelay) {
            guard token == nudgeToken else { return }
            withAnimation(Motion.nudgeReturn) { swing = 0 }
        }
    }
}

enum Frame {
    static let radius: CGFloat = 16
    static let inset: CGFloat = 4
}

extension View {
    func glassFrame(cornerRadius: CGFloat = 0, circle: Bool = false, capsule: Bool = false) -> some View {
        let shape: AnyShape = circle ? AnyShape(Circle())
            : capsule ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        return background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.stroke(
                    LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .overlay(shape.stroke(Color.black.opacity(0.10), lineWidth: 0.5).padding(-0.5))
    }
}

/// A minimal aluminium clip: a brushed metal pill with a slot where it
/// grips the line, and a soft shadow so it reads on any background.
struct Clothespin: View {
    /// Off for a copy laid exactly over another pin, so the shadows do not double up.
    var shadowed = true

    private let metal = LinearGradient(
        stops: [
            .init(color: Color(white: 0.70), location: 0),
            .init(color: Color(white: 0.93), location: 0.35),
            .init(color: Color(white: 0.82), location: 0.65),
            .init(color: Color(white: 0.62), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(metal)
            .frame(width: 9, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.9), Color.black.opacity(0.18)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.6)
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 5, height: 1.4)
                    .padding(.top, 8.5)
            }
            .shadow(color: .black.opacity(shadowed ? 0.30 : 0), radius: 2, y: 1.5)
            .allowsHitTesting(false)
    }
}

// MARK: - Animated Checkbox & Strikethrough Feedback Components

struct CheckmarkPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.20, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.74))
        path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.26))
        return path
    }
}

struct AnimatedTodoCheckbox: View {
    let isChecked: Bool
    var size: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(isChecked ? Color.green : Color.secondary.opacity(0.8), lineWidth: 1.2)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(isChecked ? Color.green : Color.clear)
                    )
                    .frame(width: size, height: size)

                CheckmarkPath()
                    .trim(from: 0, to: isChecked ? 1.0 : 0.0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: size - 3, height: size - 3)
                    .animation(Motion.snappy, value: isChecked)
            }
            .scaleEffect(isChecked ? 1.08 : 1.0)
            .animation(Motion.bouncy, value: isChecked)
            .frame(width: size + 4, height: size + 4)
        }
        .buttonStyle(.plain)
    }
}

struct AnimatedStrikethroughText: View {
    let text: String
    let isStruck: Bool
    var font: Font = .system(size: 11.5, weight: .medium, design: .rounded)
    var textColor: Color = .primary
    var struckColor: Color = .secondary
    var lineLimit: Int? = 1

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(font)
            .foregroundStyle(isStruck ? struckColor : textColor)
            .lineLimit(lineLimit)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(struckColor.opacity(0.85))
                        .frame(width: isStruck ? geo.size.width : 0, height: 1.2)
                        .position(x: (isStruck ? geo.size.width : 0) / 2, y: geo.size.height / 2)
                        .animation(Motion.snappy, value: isStruck)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isStruck)
    }
}

// MARK: - Clothesline Card Markdown & Interactive Todo Body

struct MarkdownMemoCardBody: View {
    let memo: Pegged
    @ObservedObject var line: Line
    var typography: MemoTypographyConfig? = nil
    var cardHeight: CGFloat = 192

    var body: some View {
        let config = typography ?? MemoTypography.config(for: memo.memoText)
        let lines = memo.memoText.components(separatedBy: "\n")
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: config.lineSpacing) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, rawLine in
                    let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") || trimmed.hasPrefix("[ ] ") {
                        let content = String(trimmed.dropFirst(trimmed.hasPrefix("[ ] ") ? 4 : 6))
                        HStack(alignment: .center, spacing: config.fontSize > 16 ? 7 : 5) {
                            AnimatedTodoCheckbox(isChecked: false, size: config.todoBoxSize) {
                                line.toggleMemoTodoLine(id: memo.id, lineIndex: index)
                            }
                            .accessibilityLabel(content)
                            .accessibilityIdentifier("memo.todo.\(index)")
                            AnimatedStrikethroughText(
                                text: content,
                                isStruck: false,
                                font: .system(size: config.fontSize, weight: config.fontWeight, design: .rounded),
                                lineLimit: 1
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            line.toggleMemoTodoLine(id: memo.id, lineIndex: index)
                        }
                    } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") ||
                              trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") ||
                              trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
                        let content = String(trimmed.dropFirst(trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") ? 4 : 6))
                        HStack(alignment: .center, spacing: config.fontSize > 16 ? 7 : 5) {
                            AnimatedTodoCheckbox(isChecked: true, size: config.todoBoxSize) {
                                line.toggleMemoTodoLine(id: memo.id, lineIndex: index)
                            }
                            .accessibilityLabel(content)
                            .accessibilityIdentifier("memo.todo.\(index)")
                            AnimatedStrikethroughText(
                                text: content,
                                isStruck: true,
                                font: .system(size: config.fontSize, weight: config.fontWeight, design: .rounded),
                                lineLimit: 1
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            line.toggleMemoTodoLine(id: memo.id, lineIndex: index)
                        }
                    } else if trimmed.hasPrefix("#") {
                        let header = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                        AnimatedStrikethroughText(
                            text: header,
                            isStruck: memo.isDone,
                            font: .system(size: max(12, config.fontSize), weight: .bold, design: .rounded),
                            lineLimit: 1
                        )
                    } else {
                        AnimatedStrikethroughText(
                            text: trimmed,
                            isStruck: memo.isDone,
                            font: .system(size: config.fontSize, weight: config.fontWeight, design: .rounded),
                            lineLimit: 1
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: config.isSingleShortLine ? .center : .topLeading)
            .padding(.trailing, 6)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: max(1, cardHeight - MemoCardLayout.headerHeight - 46))
        .accessibilityIdentifier("memo.scrollableBody")
    }
}

