import AppKit
import Combine
import SwiftUI
import os

let log = Logger(subsystem: "com.zhangkaiming.SunMemo", category: "line")

/// Represents saved memo metadata in a JSON file.
struct MemoData: Codable {
    let id: UUID
    var text: String
    var color: String
    var isDone: Bool
    var createdAt: Date
    var aspectRatio: String?
    var customWidth: CGFloat?
    var customHeight: CGFloat?
}

/// One screenshot or memo hanging on the line.
struct Pegged: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var thumb: NSImage
    /// Every photo/card hangs a little crooked, like on a real line.
    let tilt: Double
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false

    // Memo support
    var isMemo: Bool = false
    var memoText: String = ""
    var memoColor: String = "yellow"
    var isDone: Bool = false
    var createdAt: Date = Date()
    var aspectRatio: String = "wide" // "wide" (16:10), "square" (1:1), "tall" (3:4)
    var customWidth: CGFloat? = nil
    var customHeight: CGFloat? = nil

    init(id: UUID = UUID(), url: URL, thumb: NSImage,
         tilt: Double = Double.random(in: -2.5...2.5),
         flying: Bool = false,
         isMemo: Bool = false, memoText: String = "",
         memoColor: String = "yellow", isDone: Bool = false,
         createdAt: Date = Date(),
         aspectRatio: String = "wide",
         customWidth: CGFloat? = nil,
         customHeight: CGFloat? = nil) {
        self.id = id
        self.url = url
        self.thumb = thumb
        self.tilt = tilt
        self.flying = flying
        self.isMemo = isMemo
        self.memoText = memoText
        self.memoColor = memoColor
        self.isDone = isDone
        self.createdAt = createdAt
        self.aspectRatio = aspectRatio
        self.customWidth = customWidth
        self.customHeight = customHeight
    }

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying
            && a.isMemo == b.isMemo && a.memoText == b.memoText
            && a.isDone == b.isDone && a.memoColor == b.memoColor
            && a.aspectRatio == b.aspectRatio
            && a.customWidth == b.customWidth
            && a.customHeight == b.customHeight
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    @Published var pressedID: UUID?
    @Published var revealed = false {
        didSet {
            if revealed {
                resumeGust()
            } else {
                pauseGust()
            }
        }
    }

    /// Inline adding/editing memo state
    @Published var isAddingMemo = false
    @Published var editingID: UUID?
    @Published var hoveredID: UUID?
    @Published var wobbledID: UUID?
    /// The card currently flown off the line into the preview. Its body is hidden
    /// here so there is only one copy of it on screen; the clothespin stays.
    @Published var previewingID: UUID?

    private var hoverWorkItem: DispatchWorkItem?
    private var unhoverWorkItem: DispatchWorkItem?
    private var pendingHoverID: UUID?
    private var gustWorkItem: DispatchWorkItem?

    func setHovered(_ id: UUID, hovering: Bool) {
        if hovering {
            unhoverWorkItem?.cancel()
            unhoverWorkItem = nil
            if hoveredID == id { return }
            pendingHoverID = id
            hoverWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pendingHoverID == id else { return }
                self.hoveredID = id
            }
            hoverWorkItem = work
            // Hover dwell delay (~60ms) before parting cards to avoid jitter when sweeping across
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        } else {
            if pendingHoverID == id {
                pendingHoverID = nil
                hoverWorkItem?.cancel()
                hoverWorkItem = nil
            }
            if hoveredID == id {
                unhoverWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.hoveredID == id else { return }
                    self.hoveredID = nil
                }
                unhoverWorkItem = work
                // Delayed exit before collapsing cards back
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
            }
        }
    }

    /// Triggers a gentle tactile wobble on the specified card (e.g. when preview closes back onto line)
    func wobble(_ id: UUID) {
        wobbledID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if self?.wobbledID == id {
                self?.wobbledID = nil
            }
        }
    }

    /// Physical vibration & tap shock tokens
    @Published private(set) var shockToken = 0
    @Published private(set) var shockIntensity: Double = 1.0
    @Published private(set) var hardSlapToken = 0

    /// Light tap on laptop or desk: physical shock sway across cards
    func triggerTapShock(intensity: Double = 1.0) {
        shockIntensity = min(max(intensity, 0.6), 2.4)
        shockToken += 1
        play("Tink", volume: 0.16)
    }

    /// Hard slap on laptop: gusty strong sway and wind whoosh
    func triggerHardSlap() {
        hardSlapToken += 1
        play("Blow", volume: 0.32)
    }

    /// Flag to prevent ClipboardWatcher from reacting to our own copy operations
    var isInternalCopy = false

    /// Card frames in window coordinates, reported by the views.
    var hitRects: [UUID: CGRect] = [:]
    let addMemoButtonID = UUID()

    var maxItems = 35

    var soundOn: Bool {
        get { !Demo.defaults.bool(forKey: "soundOff") }
        set { Demo.defaults.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }

    private let storeKey = "pegged"

    static let memosFolder: URL = {
        if Demo.isActive { return Demo.folder.appendingPathComponent("Memos", isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newURL = base.appendingPathComponent("SunMemo/Memos", isDirectory: true)
        let oldURL = base.appendingPathComponent("Tendedero/Memos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: newURL.path), FileManager.default.fileExists(atPath: oldURL.path) {
            try? FileManager.default.copyItem(at: oldURL, to: newURL)
        }
        return newURL
    }()

    init() {
        restore()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false) -> UUID? {
        guard !items.contains(where: { $0.url == url && !$0.falling }) else { return nil }

        var item: Pegged
        if url.pathExtension.lowercased() == "json" {
            guard let memo = Self.readMemo(at: url) else { return nil }
            let ratio = memo.aspectRatio ?? "wide"
            let customW = memo.customWidth
            let customH = memo.customHeight
            let thumb = makeMemoThumbnail(text: memo.text, color: memo.color, isDone: memo.isDone, aspectRatio: ratio, createdAt: memo.createdAt, customWidth: customW, customHeight: customH)
            item = Pegged(id: memo.id, url: url, thumb: thumb, isMemo: true,
                          memoText: memo.text, memoColor: memo.color,
                          isDone: memo.isDone, createdAt: memo.createdAt,
                          aspectRatio: ratio,
                          customWidth: customW, customHeight: customH)
        } else {
            guard let thumb = makeThumbnail(url) else { return nil }
            item = Pegged(url: url, thumb: thumb, flying: flying)
        }

        item.flying = flying
        items.append(item)

        // Only drop oldest screenshot if capacity is exceeded. Never auto-drop memos!
        while liveCount > maxItems, let oldest = items.first(where: { !$0.falling && !$0.isMemo }) {
            drop(oldest.id, quietly: true)
        }
        save()
        if !quietly { play("Tink", volume: 0.35) }
        return item.id
    }

    // MARK: Memo Operations

    @discardableResult
    func addMemo(text: String, color: String = "yellow", aspectRatio: String = "wide", flying: Bool = false) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let id = UUID()
        let now = Date()
        let fileURL = Self.memosFolder.appendingPathComponent("memo_\(id.uuidString).json")
        let thumb = makeMemoThumbnail(text: trimmed, color: color, isDone: false, aspectRatio: aspectRatio, createdAt: now)
        let item = Pegged(id: id, url: fileURL, thumb: thumb, flying: flying, isMemo: true,
                          memoText: trimmed, memoColor: color,
                          isDone: false, createdAt: now,
                          aspectRatio: aspectRatio)
        // Hung even if the write fails: the text stays visible on the line,
        // and the next edit tries to save it again.
        writeMemo(item)
        items.append(item)

        // Memos are never auto-dropped! Cards stack and overlap smoothly.
        save()
        if !flying {
            play("Tink", volume: 0.35)
        }
        return id
    }

    func updateMemo(id: UUID, text: String, color: String? = nil, aspectRatio: String? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isMemo }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[i].memoText = trimmed
        if let color {
            items[i].memoColor = color
        }
        if let aspectRatio {
            items[i].aspectRatio = aspectRatio
        }
        items[i].thumb = makeMemoThumbnail(text: trimmed, color: items[i].memoColor, isDone: items[i].isDone, aspectRatio: items[i].aspectRatio, createdAt: items[i].createdAt, customWidth: items[i].customWidth, customHeight: items[i].customHeight)
        writeMemo(items[i])
        save()
    }

    func updateMemoAspectRatio(id: UUID, aspectRatio: String) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isMemo }) else { return }
        items[i].aspectRatio = aspectRatio
        items[i].customWidth = nil
        items[i].customHeight = nil
        items[i].thumb = makeMemoThumbnail(text: items[i].memoText, color: items[i].memoColor, isDone: items[i].isDone, aspectRatio: aspectRatio, createdAt: items[i].createdAt)
        writeMemo(items[i])
        save()
        play("Tink", volume: 0.25)
    }

    func updateMemoCustomSize(id: UUID, width: CGFloat?, height: CGFloat?) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isMemo }) else { return }
        items[i].customWidth = width
        items[i].customHeight = height
        items[i].thumb = makeMemoThumbnail(text: items[i].memoText, color: items[i].memoColor, isDone: items[i].isDone, aspectRatio: items[i].aspectRatio, createdAt: items[i].createdAt, customWidth: width, customHeight: height)
        writeMemo(items[i])
        save()
    }

    func toggleMemoDone(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isMemo }) else { return }
        items[i].isDone.toggle()
        items[i].thumb = makeMemoThumbnail(text: items[i].memoText, color: items[i].memoColor, isDone: items[i].isDone, aspectRatio: items[i].aspectRatio, createdAt: items[i].createdAt, customWidth: items[i].customWidth, customHeight: items[i].customHeight)

        writeMemo(items[i])
        save()
        if items[i].isDone { play("Pop", volume: 0.25) }
    }

    /// Toggles a specific `- [ ]` / `- [x]` todo checklist item inside a memo.
    func toggleMemoTodoLine(id: UUID, lineIndex: Int) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isMemo }) else { return }
        let result = MemoSyncManager.toggleTodoLine(in: items[i].memoText, lineIndex: lineIndex)
        items[i].memoText = result.newText
        items[i].isDone = result.allDone
        items[i].thumb = makeMemoThumbnail(text: result.newText, color: items[i].memoColor, isDone: items[i].isDone, aspectRatio: items[i].aspectRatio, createdAt: items[i].createdAt, customWidth: items[i].customWidth, customHeight: items[i].customHeight)

        writeMemo(items[i])
        save()
        play("Pop", volume: 0.25)
    }

    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    var onFall: ((Pegged) -> Void)?

    func drop(_ id: UUID, quietly: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        onFall?(items[i])
        items[i].falling = true
        hitRects[id] = nil
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func clear() {
        let live = items.filter { !$0.falling }
        for item in live where item.isMemo {
            MemoSyncManager.shared.archiveTornDown(memo: item)
            try? FileManager.default.removeItem(at: item.url)
        }
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.drop(item.id, quietly: n > 0)
            }
        }
    }

    func prune() {
        for item in items where !item.falling && !FileManager.default.fileExists(atPath: item.url.path) {
            drop(item.id, quietly: true)
        }
    }

    // MARK: Actions on one photo or memo

    func copy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        isInternalCopy = true

        let pb = NSPasteboard.general
        pb.clearContents()

        if item.isMemo {
            pb.setString(item.memoText, forType: .string)
        } else {
            let entry = NSPasteboardItem()
            if let png = pngData(item.url) { entry.setData(png, forType: .png) }
            entry.setString(item.url.absoluteString, forType: .fileURL)
            pb.writeObjects([entry])
        }

        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.isMemo {
            QuickMemoWindowController.shared.show(line: self, editingMemoID: id)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func trash(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.isMemo {
            MemoSyncManager.shared.archiveTornDown(memo: item)
            try? FileManager.default.removeItem(at: item.url)
            drop(id, quietly: true)
            return
        }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn { Line.trashSound?.play() }
            drop(id, quietly: true)
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    func isInInbox(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    func discard(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.isMemo {
            MemoSyncManager.shared.archiveTornDown(memo: item)
            try? FileManager.default.removeItem(at: item.url)
            drop(id)
        } else if isInInbox(id) {
            trash(id)
        } else {
            drop(id)
        }
    }

    func saveToDesktop(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let target = uniqueURL(in: desktop, for: item.url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            drop(id, quietly: true)
        } catch {
            log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    func markup(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), !item.isMemo else { return }
        Markup.shared.edit(item.url)
    }

    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return }
        items[i].thumb = thumb
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Breeze

    private func resumeGust() {
        guard gustWorkItem == nil else { return }
        scheduleGust()
    }

    private func pauseGust() {
        gustWorkItem?.cancel()
        gustWorkItem = nil
    }

    private func scheduleGust() {
        gustWorkItem?.cancel()
        guard revealed else {
            gustWorkItem = nil
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.revealed else { return }
            if !Motion.shouldReduceMotion && !self.items.isEmpty && self.draggingID == nil {
                self.gust += 1
            }
            self.scheduleGust()
        }
        gustWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16), execute: work)
    }

    // MARK: Persistence

    private func save() {
        let paths = items.filter { !$0.falling }.map(\.url.path)
        Demo.defaults.set(paths, forKey: storeKey)
        MemoSyncManager.shared.sync(items: items)
    }

    private func restore() {
        let paths = Demo.defaults.stringArray(forKey: storeKey) ?? []
        var loadedPaths = Set<String>()
        for path in paths where FileManager.default.fileExists(atPath: path) {
            hang(URL(fileURLWithPath: path), quietly: true)
            loadedPaths.insert(path)
        }

        // Crash-recovery: scan Memos folder in case app crashed before save() or UserDefaults was lost
        if let memoFiles = try? FileManager.default.contentsOfDirectory(at: Self.memosFolder, includingPropertiesForKeys: nil) {
            for file in memoFiles where Self.isMemoFile(file) && !loadedPaths.contains(file.path) {
                hang(file, quietly: true)
            }
        }

        MemoSyncManager.shared.sync(items: items)
    }

    // MARK: Memo files

    /// Writes a memo's file atomically, so a crash mid-write never leaves half
    /// a file behind. A failure is reported instead of silently ignored.
    @discardableResult
    private func writeMemo(_ item: Pegged) -> Bool {
        let memo = MemoData(id: item.id, text: item.memoText, color: item.memoColor,
                            isDone: item.isDone, createdAt: item.createdAt,
                            aspectRatio: item.aspectRatio,
                            customWidth: item.customWidth,
                            customHeight: item.customHeight)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: Self.memosFolder, withIntermediateDirectories: true)
            try encoder.encode(memo).write(to: item.url, options: .atomic)
            return true
        } catch {
            log.error("Could not save memo \(item.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            Self.warn(L("Could not save the memo"),
                      L("Your text is still on the line. Check that there is free disk space, then edit the memo to save it again.")
                        + "\n\n" + error.localizedDescription)
            return false
        }
    }

    /// Our own memo files: memo_<id>.json in the memos folder. Anything else
    /// there, such as the archive, is never read as a memo or moved.
    static func isMemoFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
            && url.lastPathComponent.hasPrefix("memo_")
            && url.deletingLastPathComponent().standardizedFileURL.path == memosFolder.standardizedFileURL.path
    }

    /// Reads a memo file. One that exists but cannot be decoded is moved
    /// aside and reported, instead of silently disappearing from the line.
    private static func readMemo(at url: URL) -> MemoData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(MemoData.self, from: data)
        } catch {
            log.error("Could not read memo \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            guard isMemoFile(url) else { return nil }
            let damaged = memosFolder.appendingPathComponent("Damaged", isDirectory: true)
            let stamp = Int(Date().timeIntervalSince1970)
            let target = damaged.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(stamp).json")
            do {
                try FileManager.default.createDirectory(at: damaged, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: url, to: target)
                warn(L("A memo could not be read"),
                     String(format: L("The damaged file was moved to %@ so nothing is lost."), target.path))
            } catch {
                log.error("Could not move damaged memo aside: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    private static var lastWarning = Date.distantPast

    /// Shows a problem to the user, at most once every half minute so a
    /// failing disk does not bury them in alerts.
    static func warn(_ message: String, _ info: String) {
        let now = Date()
        guard now.timeIntervalSince(lastWarning) > 30 else { return }
        lastWarning = now
        // After the current change has finished, never in the middle of it.
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = info
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: Helpers

    func play(_ name: String, volume: Float = 0.5) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

func makeThumbnail(_ url: URL, maxPixels: Int = 480) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

// MARK: - High-fidelity Memo Card Snapshot for Flight and Drop Animations

struct MemoCardSnapshotView: View {
    let text: String
    let color: String
    let isDone: Bool
    let aspectRatio: String
    let createdAt: Date
    var customWidth: CGFloat? = nil
    var customHeight: CGFloat? = nil

    private var memoRatio: MemoAspectRatio {
        MemoAspectRatio(rawValue: aspectRatio) ?? .wide
    }

    var body: some View {
        let config = MemoTypography.config(for: text)
        VStack(alignment: .leading, spacing: 4) {
            if config.isSingleShortLine {
                Spacer(minLength: 0)
            }
            snapshotBody

            Spacer(minLength: 2)

            HStack(alignment: .center) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isDone ? Color.green : Color.secondary)

                let stats = MemoSyncManager.calculateTodoStats(text: text)
                if stats.total > 0 {
                    Text("\(stats.completed)/\(stats.total) 完成")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(stats.completed == stats.total ? Color.green : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.06), in: Capsule())
                }

                Spacer()

                Text(timeAgoString(from: createdAt))
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
        .padding(10)
        .frame(width: customWidth.map(MemoLimits.clampWidth) ?? memoRatio.cardContentSize.width,
               height: customHeight.map(MemoLimits.clampHeight) ?? memoRatio.cardContentSize.height)
        .background(memoBackground(for: color))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var snapshotBody: some View {
        let config = MemoTypography.config(for: text)
        let lines = text.components(separatedBy: "\n")
        let maxLines = memoRatio == .tall ? 7 : (memoRatio == .square ? 5 : 4)
        let visibleLines = Array(lines.prefix(maxLines).enumerated())

        return VStack(alignment: .leading, spacing: config.lineSpacing) {
            ForEach(visibleLines, id: \.offset) { _, rawLine in
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") || trimmed.hasPrefix("[ ] ") {
                    let content = String(trimmed.dropFirst(trimmed.hasPrefix("[ ] ") ? 4 : 6))
                    HStack(alignment: .center, spacing: config.fontSize > 16 ? 7 : 5) {
                        Image(systemName: "square")
                            .font(.system(size: config.todoBoxSize - 1, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                        Text(LocalizedStringKey(content))
                            .font(.system(size: config.fontSize, weight: config.fontWeight, design: .rounded))
                            .foregroundStyle(Color.primary)
                            .lineLimit(config.isSingleShortLine ? 2 : 1)
                    }
                } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") ||
                          trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") ||
                          trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
                    let content = String(trimmed.dropFirst(trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") ? 4 : 6))
                    HStack(alignment: .center, spacing: config.fontSize > 16 ? 7 : 5) {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: config.todoBoxSize - 1, weight: .semibold))
                            .foregroundStyle(Color.green)
                        Text(LocalizedStringKey(content))
                            .font(.system(size: config.fontSize, weight: config.fontWeight, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .strikethrough(true, color: .secondary)
                            .lineLimit(config.isSingleShortLine ? 2 : 1)
                    }
                } else if trimmed.hasPrefix("#") {
                    let header = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    Text(LocalizedStringKey(header))
                        .font(.system(size: max(12, config.fontSize), weight: .bold, design: .rounded))
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(config.isSingleShortLine ? 2 : 1)
                } else {
                    Text(LocalizedStringKey(trimmed))
                        .font(.system(size: config.fontSize, weight: config.fontWeight, design: .rounded))
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(config.isSingleShortLine ? 2 : 1)
                }
            }
            if lines.count > maxLines {
                Text("... 还有 \(lines.count - maxLines) 项")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: config.isSingleShortLine ? .center : .topLeading)
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
}

@MainActor
func makeMemoThumbnail(text: String, color: String, isDone: Bool, aspectRatio: String = "wide", createdAt: Date = Date(), customWidth: CGFloat? = nil, customHeight: CGFloat? = nil) -> NSImage {
    let view = MemoCardSnapshotView(text: text, color: color, isDone: isDone, aspectRatio: aspectRatio, createdAt: createdAt, customWidth: customWidth, customHeight: customHeight)
    let renderer = ImageRenderer(content: view)
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
    if let image = renderer.nsImage {
        return image
    }
    let ratio = MemoAspectRatio(rawValue: aspectRatio) ?? .wide
    let w = customWidth.map(MemoLimits.clampWidth) ?? ratio.cardContentSize.width
    let h = customHeight.map(MemoLimits.clampHeight) ?? ratio.cardContentSize.height
    return NSImage(size: CGSize(width: w, height: h))
}
