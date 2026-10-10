import SwiftUI

/// One photo or memo card with its clothespin. All the charm lives here: it drops onto
/// the line, swings, sways with the breeze and falls when you pull it off.
struct PeggedView: View {
    let item: Pegged
    @ObservedObject var line: Line

    @State private var swing: Double = 0
    @State private var arrived = false
    @State private var hovering = false
    @State private var isEditing = false
    @State private var editText = ""

    private var copied: Bool { line.copiedID == item.id }
    private var dragging: Bool { line.draggingID == item.id }
    private var pressed: Bool { line.pressedID == item.id }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin()
                .zIndex(1)
            if item.isMemo {
                memoCard
            } else {
                card
            }
        }
        .rotationEffect(.degrees(swing + item.tilt), anchor: .top)
        .offset(y: arrived ? 0 : -46)
        .opacity(item.falling || item.flying ? 0 : (arrived ? 1 : 0))
        .zIndex(hovering ? 999 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .transaction { t in if item.falling { t.animation = nil } }
        .animation(.easeOut(duration: 0.16), value: item.flying)
        .onAppear(perform: arrive)
        .onChange(of: item.flying) { was, now in if was && !now { land() } }
        .onChange(of: line.gust) { _, _ in breeze() }
        .onChange(of: copied) { _, isCopied in if isCopied { nudge(3) } }
        .onChange(of: line.editingID) { _, newID in
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

    static let cardOffsetBelowTop: CGFloat = 26 - 12

    private var photoSize: CGSize { Self.photoSize(for: item.thumb.size) }

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
            .scaleEffect(pressed ? 0.95 : (hovering ? 1.035 : 1), anchor: .top)
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
            .animation(.easeOut(duration: 0.18), value: hovering)
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
                // Interactive Markdown & Todo Checklist Renderer
                MarkdownMemoCardBody(memo: item, line: line)

                Spacer(minLength: 2)

                HStack(alignment: .center) {
                    Button {
                        line.toggleMemoDone(item.id)
                    } label: {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)

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
        .padding(10)
        .frame(width: (item.isMemo ? Layout.memoWidth : Layout.cardWidth) - 14,
               height: item.isMemo ? 122 : 104)
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
        .scaleEffect(pressed ? 0.95 : (hovering ? 1.035 : 1), anchor: .top)
        .animation(pressed ? .easeInOut(duration: 0.45) : .spring(response: 0.3, dampingFraction: 0.6), value: pressed)
        .opacity(dragging ? 0.45 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
        .onTapGesture(count: 2) {
            QuickMemoWindowController.shared.show(line: line, editingMemoID: item.id)
        }
        .onTapGesture(count: 1) {
            MemoPreviewWindowController.shared.show(line: line, itemID: item.id)
        }
        .overlay(alignment: .topLeading) {
            if hovering && !dragging && !isEditing {
                Button {
                    line.discard(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 18, height: 18)
                        .glassFrame(circle: true)
                }
                .buttonStyle(.plain)
                .padding(4)
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
        .animation(.easeOut(duration: 0.18), value: hovering)
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
        if item.flying {
            arrived = true
            return
        }
        swing = 16
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { arrived = true }
        withAnimation(.interpolatingSpring(stiffness: 46, damping: 2.6)) { swing = 0 }
    }

    private func land() {
        nudge(2.2)
    }

    private func breeze() {
        let delay = Double.random(in: 0...0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            nudge(Double.random(in: 1.6...3.4))
        }
    }

    private func nudge(_ degrees: Double) {
        withAnimation(.easeOut(duration: 0.3)) { swing = degrees }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interpolatingSpring(stiffness: 38, damping: 2.4)) { swing = 0 }
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
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1.5)
            .allowsHitTesting(false)
    }
}

// MARK: - Clothesline Card Markdown & Interactive Todo Body

struct MarkdownMemoCardBody: View {
    let memo: Pegged
    @ObservedObject var line: Line

    var body: some View {
        let lines = memo.memoText.components(separatedBy: "\n")
        let visibleLines = Array(lines.prefix(4).enumerated())

        VStack(alignment: .leading, spacing: 3.5) {
            ForEach(visibleLines, id: \.offset) { index, rawLine in
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") || trimmed.hasPrefix("[ ] ") {
                    let content = String(trimmed.dropFirst(trimmed.hasPrefix("[ ] ") ? 4 : 6))
                    HStack(alignment: .top, spacing: 5) {
                        Button {
                            line.toggleMemoTodoLine(id: memo.id, lineIndex: index)
                        } label: {
                            Image(systemName: "square")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)

                        Text(LocalizedStringKey(content))
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                    }
                } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") ||
                          trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") ||
                          trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
                    let content = String(trimmed.dropFirst(trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") ? 4 : 6))
                    HStack(alignment: .top, spacing: 5) {
                        Button {
                            line.toggleMemoTodoLine(id: memo.id, lineIndex: index)
                        } label: {
                            Image(systemName: "checkmark.square.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.green)
                        }
                        .buttonStyle(.plain)

                        Text(LocalizedStringKey(content))
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .strikethrough(true, color: .secondary)
                            .lineLimit(1)
                    }
                } else if trimmed.hasPrefix("#") {
                    let header = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    Text(LocalizedStringKey(header))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(memo.isDone ? Color.secondary : Color.primary)
                        .strikethrough(memo.isDone, color: .secondary)
                        .lineLimit(1)
                } else {
                    Text(LocalizedStringKey(trimmed))
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(memo.isDone ? Color.secondary : Color.primary)
                        .strikethrough(memo.isDone, color: .secondary)
                        .lineLimit(1)
                }
            }
            if lines.count > 4 {
                Text("... 还有 \(lines.count - 4) 项")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

