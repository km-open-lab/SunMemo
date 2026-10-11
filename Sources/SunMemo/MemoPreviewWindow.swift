import AppKit
import SwiftUI

@MainActor
final class MemoPreviewWindowController {
    static let shared = MemoPreviewWindowController()
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private weak var currentLine: Line?
    private var currentItemID: UUID?
    private var dismissAction: ((@escaping () -> Void) -> Void)?
    private var isClosing = false
    /// Completions asked for while a dismissal was already running.
    private var pendingCompletions: [() -> Void] = []
    /// Bumped by every show, so a late completion from an older preview is ignored.
    private var session = 0

    var isOpen: Bool { panel != nil }
    var isEditingActive: Bool = false
    var triggerInPlaceEdit: (() -> Void)?
    var cancelEditing: (() -> Void)?

    func show(line: Line, itemID: UUID, startEditing: Bool = false) {
        closeImmediate()
        pendingCompletions = []
        session += 1
        self.currentLine = line
        self.currentItemID = itemID
        self.isEditingActive = startEditing

        guard let item = line.items.first(where: { $0.id == itemID && !$0.falling }) else { return }

        let originProvider: () -> CGRect? = { AppDelegate.shared?.cardFrame(for: itemID) }
        // The preview covers the screen the card hangs on.
        let screen = originProvider().flatMap { origin in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: origin.midX, y: origin.midY)) }
        } ?? LinePanel.screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first!

        let previewView = HeroPreviewHostView(
            line: line,
            itemID: itemID,
            screen: screen,
            startEditing: startEditing,
            originProvider: originProvider,
            onClose: { [weak self] in
                self?.dismiss(animated: true)
            },
            onRegisterDismiss: { [weak self] action in
                self?.dismissAction = action
            },
            onEditMemo: { [weak self] in
                self?.triggerInPlaceEdit?()
            },
            onMarkupImage: { [weak self] in
                self?.dismiss(animated: true) { [weak self] in
                    self?.currentLine?.markup(itemID)
                }
            },
            onDiscard: { [weak self] in
                self?.dismiss(animated: true) { [weak self] in
                    self?.currentLine?.discard(itemID)
                }
            },
            onTrash: { [weak self] in
                self?.dismiss(animated: true) { [weak self] in
                    self?.currentLine?.trash(itemID)
                }
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
        // The preview draws the card as it hangs before the real one is hidden, so the swap is invisible.
        hosting.layoutSubtreeIfNeeded()
        win.displayIfNeeded()
        // Under Reduce Motion the preview fades in over the line card, which is hidden once it is up.
        if !Motion.shouldReduceMotion {
            line.previewingID = itemID
        }

        // Keyboard handler for Esc, Space, and Enter: all close routes follow animated dismissal
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            if self.isEditingActive {
                if event.keyCode == 53 /* Esc */ {
                    self.cancelEditing?()
                    return nil
                }
                return event
            }
            if event.keyCode == 53 /* Esc */ || event.keyCode == 49 /* Space */ {
                self.dismiss(animated: true)
                return nil
            } else if event.keyCode == 36 /* Enter */ {
                if item.isMemo {
                    self.triggerInPlaceEdit?()
                    return nil
                }
            } else if event.keyCode == 8 /* C */ && event.modifierFlags.contains(.command) {
                line.copy(itemID)
                return nil
            }
            return event
        }
    }

    /// Unified animated dismissal: the card flies back along the same path it came out on,
    /// and the preview closes only once it has landed on the line, then the card wobbles.
    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard panel != nil else {
            completion?()
            return
        }
        if let completion { pendingCompletions.append(completion) }
        guard !isClosing else { return }

        let ticket = session
        let finish: () -> Void = { [weak self] in
            guard let self, self.session == ticket, self.panel != nil else { return }
            let itemID = self.currentItemID
            let line = self.currentLine
            // The card is back on the line (and visible again) before it wobbles.
            line?.previewingID = nil
            // Give the line one frame to show its card under the preview, which looks the same.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.session == ticket, self.panel != nil else { return }
                let done = self.pendingCompletions
                self.pendingCompletions = []
                self.closeImmediate()
                if let itemID { line?.wobble(itemID) }
                done.forEach { $0() }
            }
        }

        if animated, let dismissAction {
            isClosing = true
            dismissAction(finish)
        } else {
            finish()
        }
    }

    func close() {
        dismiss(animated: true)
    }

    /// Every exit path ends here: the panel goes away and the card on the line is shown again.
    private func closeImmediate() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        currentLine?.previewingID = nil
        panel?.orderOut(nil)
        panel = nil
        dismissAction = nil
        isClosing = false
    }
}

// MARK: - Hero Geometry (卡片飞行的唯一几何来源)

/// Everything about the card's flight, derived from one `progress`. 0 is the card exactly as
/// it hangs on the line (tilted about its clothespin), 1 is the expanded preview. The card,
/// the pin riding on it, the eyelet ring and the cord's end all come from here, so the cord
/// stays tied on at every frame, spring overshoot and interruptions included.
/// Coordinates are the preview panel's view coordinates (origin top left, y down).
struct HeroGeometry {
    /// The card as it hangs on the line, hover lift included, before its tilt.
    var lineFrame: CGRect
    /// Top centre of the clothespin on the rope: the card tilts about this point.
    var pinTop: CGPoint
    /// The card's tilt on the line, in degrees.
    var tilt: Double
    /// Where the expanded card is centred.
    var center: CGPoint
    /// False under Reduce Motion: the card stays at its final place and only fades.
    var flies: Bool

    /// The cord is tied on near the lower end of the line pin, along its axis.
    static let jawOffset: CGFloat = 24
    /// Top of the pin that rides on the expanded card, and the eyelet ring above it, from the card's top edge.
    static let restPinTop: CGFloat = -19
    static let restRing: CGFloat = -24.5

    /// How far the pin top sits above the card's top edge on the line.
    var pinLead: CGFloat { lineFrame.minY - pinTop.y }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

    func frame(_ p: Double, previewSize: CGSize) -> CGRect {
        let end = CGRect(x: center.x - previewSize.width / 2, y: center.y - previewSize.height / 2,
                         width: previewSize.width, height: previewSize.height)
        guard flies else { return end }
        let w = max(1, lerp(lineFrame.width, previewSize.width, p))
        let h = max(1, lerp(lineFrame.height, previewSize.height, p))
        let cx = lerp(lineFrame.midX, center.x, p)
        let cy = lerp(lineFrame.midY, center.y, p)
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Radians; the tilt unwinds as the card comes down.
    func angle(_ p: Double) -> CGFloat {
        flies ? CGFloat(tilt * (1 - p)) * .pi / 180 : 0
    }

    /// The card turns about a point above its top edge: the pin top on the line, the card's top at rest.
    func pivot(_ frame: CGRect, _ p: Double) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.minY - pinLead * CGFloat(1 - p))
    }

    private func rotated(_ point: CGPoint, about pivot: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = point.x - pivot.x, dy = point.y - pivot.y
        return CGPoint(x: pivot.x + dx * cos(angle) - dy * sin(angle),
                       y: pivot.y + dx * sin(angle) + dy * cos(angle))
    }

    /// Maps a point given relative to the card (dx from its centre line, dy from its top edge,
    /// in points) through the card's exact transform.
    func cardPoint(dx: CGFloat = 0, dy: CGFloat, _ p: Double, previewSize: CGSize) -> CGPoint {
        let f = frame(p, previewSize: previewSize)
        return rotated(CGPoint(x: f.midX + dx, y: f.minY + dy), about: pivot(f, p), by: angle(p))
    }

    /// Where the cord starts: the jaw of the pin on the rope.
    var jaw: CGPoint {
        rotated(CGPoint(x: pinTop.x, y: pinTop.y + Self.jawOffset), about: pinTop, by: CGFloat(tilt) * .pi / 180)
    }

    /// The ring starts at the jaw, so the cord has no length on the line, and climbs to the pin top.
    private func climb(_ p: Double) -> Double {
        flies ? Motion.smoothstep(0, 0.55, p) : 1
    }

    func pinTopDY(_ p: Double) -> CGFloat { lerp(-pinLead, Self.restPinTop, climb(p)) }
    func ringDY(_ p: Double) -> CGFloat { lerp(Self.jawOffset - pinLead, Self.restRing, climb(p)) }

    /// Card-local content (laid out at its own size) to view coordinates:
    /// stretch to the current frame, then turn about the pivot.
    func cardTransform(_ p: Double, previewSize: CGSize, contentSize: CGSize) -> CGAffineTransform {
        let f = frame(p, previewSize: previewSize)
        let sx = contentSize.width > 0 ? f.width / contentSize.width : 1
        let sy = contentSize.height > 0 ? f.height / contentSize.height : 1
        let pv = pivot(f, p)
        return CGAffineTransform(scaleX: sx, y: sy)
            .concatenating(CGAffineTransform(translationX: f.minX, y: f.minY))
            .concatenating(CGAffineTransform(translationX: -pv.x, y: -pv.y))
            .concatenating(CGAffineTransform(rotationAngle: angle(p)))
            .concatenating(CGAffineTransform(translationX: pv.x, y: pv.y))
    }

    /// Card-local content (laid out with center at geo.center) to relative view coordinates:
    /// At progress 1, this evaluates to identity, ensuring SwiftUI hit-testing works natively.
    func cardRelativeTransform(_ p: Double, previewSize: CGSize, contentSize: CGSize) -> CGAffineTransform {
        let absT = cardTransform(p, previewSize: previewSize, contentSize: contentSize)
        let restX = center.x - previewSize.width / 2
        let restY = center.y - previewSize.height / 2
        return absT.concatenating(CGAffineTransform(translationX: -restX, y: -restY))
    }
}

/// Where the card hangs right now, in view coordinates.
struct HeroPlacement {
    var frame: CGRect
    var pinTop: CGPoint
    var lifted: Bool
}

private struct HeroCardEffect: GeometryEffect {
    var progress: Double
    var previewW: CGFloat
    var previewH: CGFloat
    let geo: HeroGeometry

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(previewW, previewH)) }
        set {
            progress = newValue.first
            previewW = newValue.second.first
            previewH = newValue.second.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(geo.cardRelativeTransform(progress, previewSize: CGSize(width: previewW, height: previewH),
                                                      contentSize: size))
    }
}

/// Fades its content over a window of the shared progress.
private struct HeroFade: ViewModifier, Animatable {
    var progress: Double
    let from: Double
    let to: Double
    var inverted = false

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = Motion.smoothstep(from, to, progress)
        content.opacity(inverted ? 1 - t : t)
    }
}

private struct HeroBackdrop: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Color.black.opacity(0.35 * min(max(progress, 0), 1))
            .ignoresSafeArea()
            .contentShape(Rectangle())
    }
}

/// The card as it looks hanging on the line, drawn at its own size and stretched to the
/// preview's frame; the preview face crossfades in over it.
private struct HeroLineFace: View {
    let item: Pegged
    let lifted: Bool
    let target: CGSize

    private var natural: CGSize { PeggedView.lineCardSize(for: item) }

    var body: some View {
        face
            .frame(width: natural.width, height: natural.height)
            .scaleEffect(x: target.width / max(natural.width, 1), y: target.height / max(natural.height, 1),
                         anchor: .topLeading)
            .frame(width: target.width, height: target.height, alignment: .topLeading)
    }

    @ViewBuilder private var face: some View {
        if item.isMemo {
            MemoCardSnapshotView(text: item.memoText, color: item.memoColor, isDone: item.isDone,
                                 aspectRatio: item.aspectRatio, createdAt: item.createdAt)
                .padding(Frame.inset)
                .glassFrame(cornerRadius: Frame.radius)
                .shadow(color: .black.opacity(lifted ? 0.26 : 0.18), radius: lifted ? 14 : 10, y: lifted ? 8 : 5)
                .opacity(item.isDone ? 0.82 : 1)
        } else {
            let photo = PeggedView.photoSize(for: item.thumb.size)
            Image(nsImage: item.thumb)
                .resizable()
                .interpolation(.high)
                .frame(width: photo.width, height: photo.height)
                .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .padding(Frame.inset)
                .glassFrame(cornerRadius: Frame.radius)
                .shadow(color: .black.opacity(lifted ? 0.26 : 0.18), radius: lifted ? 14 : 10, y: lifted ? 8 : 5)
        }
    }
}

// MARK: - Tether (拉绳、夹子与吊环，全部由 HeroGeometry 推出)

/// A rope that sags a little under its own weight, like the clothesline's.
private struct HeroCordShape: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let d = hypot(end.x - start.x, end.y - start.y)
        guard d > 0.5 else { return path }
        let sag = min(16, 0.05 * d)
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2,
                                                    y: (start.y + end.y) / 2 + 2 * sag))
        return path
    }
}

/// Draws the clothespin on the rope, the cord, and the pin and ring riding on the card.
private struct HeroTetherLayer: View, Animatable {
    var progress: Double
    var previewW: CGFloat
    var previewH: CGFloat
    let geo: HeroGeometry

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(previewW, previewH)) }
        set {
            progress = newValue.first
            previewW = newValue.second.first
            previewH = newValue.second.second
        }
    }

    var body: some View {
        let size = CGSize(width: previewW, height: previewH)
        let p = progress
        let degrees = geo.flies ? geo.tilt * (1 - p) : 0
        let pinPoint = geo.cardPoint(dy: geo.pinTopDY(p), p, previewSize: size)
        let ring = geo.cardPoint(dy: geo.ringDY(p), p, previewSize: size)
        let jaw = geo.jaw
        let length = Double(hypot(ring.x - jaw.x, ring.y - jaw.y))
        // Nothing pokes out of the pin while the card is still on the line.
        let cordAlpha = geo.flies ? Motion.smoothstep(2, 6, length) : 0
        let pegAlpha = geo.flies ? Motion.smoothstep(0, 0.15, p) : min(max(p, 0), 1)
        let cord = HeroCordShape(start: jaw, end: ring)
        let round = StrokeStyle(lineWidth: 1.2, lineCap: .round)

        ZStack(alignment: .topLeading) {
            // The pin that holds the card, riding on it.
            Clothespin()
                .rotationEffect(.degrees(degrees), anchor: .top)
                .offset(x: pinPoint.x - 4.5, y: pinPoint.y)
                .opacity(pegAlpha)

            if geo.flies {
                // Same material as the clothesline's rope.
                ZStack {
                    cord.stroke(Color.black.opacity(0.22), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .offset(y: 1.2).blur(radius: 1.2)
                    cord.stroke(Color(white: 0.55), style: round)
                    cord.stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 0.4, lineCap: .round))
                        .offset(y: -0.35)
                }
                .opacity(cordAlpha)
            }

            // Eyelet ring, drawn over the end of the cord so it reads as threaded through.
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), Color.gray.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: 7, height: 7)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                .offset(x: ring.x - 3.5, y: ring.y - 3.5)
                .opacity(pegAlpha)

            if geo.flies {
                // The line's own pin, redrawn exactly over it so it stays bright under the backdrop.
                Clothespin(shadowed: false)
                    .rotationEffect(.degrees(geo.tilt), anchor: .top)
                    .offset(x: geo.pinTop.x - 4.5, y: geo.pinTop.y)

                // Knot where the cord is tied to the pin.
                Circle()
                    .fill(Color(white: 0.46))
                    .overlay(Circle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 1).offset(x: -0.4, y: -0.4))
                    .frame(width: 2.4, height: 2.4)
                    .offset(x: jaw.x - 1.2, y: jaw.y - 1.2)
                    .opacity(cordAlpha)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Hero Preview Container View (卡片从绳上飞到屏幕中央，绳子始终系在夹子上)

struct HeroPreviewHostView: View {
    @ObservedObject var line: Line
    let itemID: UUID
    let screen: NSScreen
    let originProvider: () -> CGRect?
    let onClose: () -> Void
    let onRegisterDismiss: (@escaping (@escaping () -> Void) -> Void) -> Void
    let onEditMemo: () -> Void
    let onMarkupImage: () -> Void
    let onDiscard: () -> Void
    let onTrash: () -> Void
    let startEditing: Bool

    /// 0 = the card as it hangs on the line, 1 = the expanded preview. The only animated value.
    @State private var progress: Double = 0
    @State private var placement: HeroPlacement
    @State private var flies: Bool
    @State private var closing = false
    @State private var copied: Bool = false
    @State private var isEditingMemo: Bool

    @MainActor
    init(line: Line, itemID: UUID, screen: NSScreen,
         startEditing: Bool = false,
         originProvider: @escaping () -> CGRect?,
         onClose: @escaping () -> Void,
         onRegisterDismiss: @escaping (@escaping (@escaping () -> Void) -> Void) -> Void,
         onEditMemo: @escaping () -> Void,
         onMarkupImage: @escaping () -> Void,
         onDiscard: @escaping () -> Void,
         onTrash: @escaping () -> Void) {
        self.line = line
        self.itemID = itemID
        self.screen = screen
        self.startEditing = startEditing
        self.originProvider = originProvider
        self.onClose = onClose
        self.onRegisterDismiss = onRegisterDismiss
        self.onEditMemo = onEditMemo
        self.onMarkupImage = onMarkupImage
        self.onDiscard = onDiscard
        self.onTrash = onTrash
        _placement = State(initialValue: Self.placement(line: line, itemID: itemID, screen: screen,
                                                        origin: originProvider()))
        _flies = State(initialValue: !Motion.shouldReduceMotion)
        _isEditingMemo = State(initialValue: startEditing)
    }

    private var item: Pegged? {
        line.items.first(where: { $0.id == itemID && !$0.falling })
    }

    private var memoRatio: MemoAspectRatio {
        guard let item else { return .wide }
        return MemoAspectRatio(rawValue: item.aspectRatio) ?? .wide
    }

    private var cardSize: CGSize {
        guard let item else { return memoRatio.previewSize }
        if item.isMemo {
            return memoRatio.previewSize
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

    private var geo: HeroGeometry {
        HeroGeometry(lineFrame: placement.frame,
                     pinTop: placement.pinTop,
                     tilt: item?.tilt ?? 0,
                     center: CGPoint(x: screen.frame.width / 2, y: screen.frame.height / 2 - 8),
                     flies: flies)
    }

    /// Where the card hangs now, from the line's own layout (global, y up) into this panel's
    /// view coordinates, with the hover lift: the card is scaled about its clothespin.
    @MainActor
    private static func placement(line: Line, itemID: UUID, screen: NSScreen, origin: CGRect?) -> HeroPlacement {
        let item = line.items.first(where: { $0.id == itemID })
        let size = item.map(PeggedView.lineCardSize(for:)) ?? CGSize(width: 150, height: 100)
        let lifted = line.hoveredID == itemID && !Motion.shouldReduceMotion
        let s = lifted ? Motion.hoverLift : 1
        let pinTop: CGPoint
        if let origin {
            pinTop = CGPoint(x: origin.midX - screen.frame.minX,
                             y: screen.frame.maxY - origin.maxY - PeggedView.cardOffsetBelowTop)
        } else {
            pinTop = CGPoint(x: screen.frame.width / 2, y: 30)
        }
        let frame = CGRect(x: pinTop.x - size.width * s / 2,
                           y: pinTop.y + PeggedView.cardOffsetBelowTop * s,
                           width: size.width * s, height: size.height * s)
        return HeroPlacement(frame: frame, pinTop: pinTop, lifted: lifted)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Soft translucent backdrop (clicking outside closes preview)
            HeroBackdrop(progress: progress)
                .onTapGesture {
                    if isEditingMemo {
                        withAnimation(Motion.snappy) {
                            isEditingMemo = false
                        }
                    } else {
                        dismissWithAnimation()
                    }
                }

            if let item {
                heroCard(item)
                    .position(geo.center)

                HeroTetherLayer(progress: progress, previewW: cardSize.width, previewH: cardSize.height, geo: geo)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height, alignment: .topLeading)
        .ignoresSafeArea()
        .onAppear {
            MemoPreviewWindowController.shared.isEditingActive = isEditingMemo
            MemoPreviewWindowController.shared.triggerInPlaceEdit = {
                withAnimation(Motion.snappy) {
                    isEditingMemo = true
                }
            }
            MemoPreviewWindowController.shared.cancelEditing = {
                withAnimation(Motion.snappy) {
                    isEditingMemo = false
                }
            }

            onRegisterDismiss { completion in
                animateOut(completion)
            }
            if flies {
                withAnimation(Motion.heroOpen) {
                    progress = 1
                }
            } else {
                withAnimation(Motion.heroFade) {
                    progress = 1
                }
                // Once the preview is fully up the card underneath can go.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if !closing { line.previewingID = itemID }
                }
            }
        }
        .onChange(of: isEditingMemo) { editing in
            MemoPreviewWindowController.shared.isEditingActive = editing
        }
    }

    /// The card, drawn once in two faces inside one transformed frame: the card as it hangs
    /// on the line and the full preview, crossfaded by the shared progress.
    private func heroCard(_ item: Pegged) -> some View {
        let size = cardSize
        return ZStack(alignment: .topLeading) {
            if flies {
                HeroLineFace(item: item, lifted: placement.lifted, target: size)
                    .modifier(HeroFade(progress: progress, from: 0.05, to: 0.35, inverted: true))
                    .allowsHitTesting(false)
            }
            Group {
                if item.isMemo {
                    if isEditingMemo {
                        QuickMemoView(
                            editingID: item.id,
                            initialText: item.memoText,
                            initialColor: item.memoColor,
                            initialAspectRatio: item.aspectRatio,
                            onEdit: { text, color, ratio in
                                if ratio != item.aspectRatio {
                                    line.updateMemoAspectRatio(id: item.id, aspectRatio: ratio)
                                }
                            },
                            onSave: { text, color, ratio in
                                line.updateMemo(id: item.id, text: text, color: color, aspectRatio: ratio)
                                dismissWithAnimation()
                            },
                            onCancel: {
                                withAnimation(Motion.snappy) {
                                    isEditingMemo = false
                                }
                            }
                        )
                    } else {
                        previewMemoCard(item)
                    }
                } else {
                    photoPreviewCard(item)
                }
            }
            .modifier(HeroFade(progress: progress, from: flies ? 0.10 : 0, to: flies ? 0.45 : 1))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .modifier(HeroCardEffect(progress: progress, previewW: size.width, previewH: size.height, geo: geo))
    }

    /// Runs the way back: the same path in reverse, finishing only once it has actually settled.
    private func animateOut(_ completion: @escaping () -> Void) {
        guard !closing else { return }
        closing = true
        // The line may have moved on, and the hover is gone: land where the card hangs now.
        placement = Self.placement(line: line, itemID: itemID, screen: screen, origin: originProvider())

        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            completion()
        }

        guard flies else {
            line.previewingID = nil
            withAnimation(Motion.heroFade) {
                progress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: finish)
            return
        }

        if #available(macOS 14.0, *) {
            withAnimation(Motion.heroClose, completionCriteria: .logicallyComplete) {
                progress = 0
            } completion: {
                finish()
            }
            // Safety net in case the completion never fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: finish)
        } else {
            withAnimation(Motion.heroClose) {
                progress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.heroCloseFallback, execute: finish)
        }
    }

    private func dismissWithAnimation() {
        onClose()
    }

    // MARK: - Memo Preview Card (多比例智能适配便签大卡片)
    private func previewMemoCard(_ item: Pegged) -> some View {
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

                // Real-time aspect ratio selector pills
                HStack(spacing: 2) {
                    ForEach(MemoAspectRatio.allCases, id: \.rawValue) { ratio in
                        Button {
                            withAnimation(Motion.snappy) {
                                line.updateMemoAspectRatio(id: item.id, aspectRatio: ratio.rawValue)
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
                                memoRatio == ratio ? Color.black.opacity(0.12) : Color.white.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .foregroundStyle(memoRatio == ratio ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

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

            // Markdown Body with interactive checkboxes (Adaptive height per ratio)
            MarkdownPreviewScrollView(text: item.memoText) { lineIndex in
                line.toggleMemoTodoLine(id: item.id, lineIndex: lineIndex)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(height: memoRatio.previewBodyHeight)

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
                        withAnimation(Motion.snappy) {
                            isEditingMemo = true
                        }
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
        .frame(width: memoRatio.previewSize.width, height: memoRatio.previewSize.height)
        .background(memoBackground(for: item.memoColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 34, y: 16)
        .onTapGesture(count: 2) {
            withAnimation(Motion.snappy) {
                isEditingMemo = true
            }
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
