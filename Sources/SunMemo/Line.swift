import AppKit
import Combine
import os

let log = Logger(subsystem: "com.zhangkaiming.SunMemo", category: "line")

/// Represents saved memo metadata in a JSON file.
struct MemoData: Codable {
    let id: UUID
    var text: String
    var color: String
    var isDone: Bool
    var createdAt: Date
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

    init(id: UUID = UUID(), url: URL, thumb: NSImage,
         tilt: Double = Double.random(in: -2.5...2.5),
         flying: Bool = false,
         isMemo: Bool = false, memoText: String = "",
         memoColor: String = "yellow", isDone: Bool = false,
         createdAt: Date = Date()) {
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
    }

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying
            && a.isMemo == b.isMemo && a.memoText == b.memoText
            && a.isDone == b.isDone && a.memoColor == b.memoColor
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
    @Published var revealed = false

    /// Inline adding/editing memo state
    @Published var isAddingMemo = false
    @Published var editingID: UUID?

    /// Flag to prevent ClipboardWatcher from reacting to our own copy operations
    var isInternalCopy = false

    /// Card frames in window coordinates, reported by the views.
    var hitRects: [UUID: CGRect] = [:]
    let addMemoButtonID = UUID()

    var maxItems = 35

    var soundOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }

    private let storeKey = "pegged"

    static let memosFolder: URL = {
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
        scheduleGust()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false) -> UUID? {
        guard !items.contains(where: { $0.url == url && !$0.falling }) else { return nil }

        var item: Pegged
        if url.pathExtension.lowercased() == "json",
           let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let memo = try? decoder.decode(MemoData.self, from: data) else { return nil }
            let thumb = makeMemoThumbnail(text: memo.text, color: memo.color, isDone: memo.isDone)
            item = Pegged(id: memo.id, url: url, thumb: thumb, isMemo: true,
                          memoText: memo.text, memoColor: memo.color,
                          isDone: memo.isDone, createdAt: memo.createdAt)
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
    func addMemo(text: String, color: String = "yellow", flying: Bool = false) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let id = UUID()
        let memoData = MemoData(id: id, text: trimmed, color: color, isDone: false, createdAt: Date())
        try? FileManager.default.createDirectory(at: Self.memosFolder, withIntermediateDirectories: true)
        let fileURL = Self.memosFolder.appendingPathComponent("memo_\(id.uuidString).json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(memoData) else { return nil }
        try? data.write(to: fileURL)

        let thumb = makeMemoThumbnail(text: trimmed, color: color, isDone: false)
        var item = Pegged(id: id, url: fileURL, thumb: thumb, flying: flying, isMemo: true,
                          memoText: trimmed, memoColor: color,
                          isDone: false, createdAt: memoData.createdAt)
        item.flying = flying
        items.append(item)

        // Memos are never auto-dropped! Cards stack and overlap smoothly.
        save()
        if !flying {
            play("Tink", volume: 0.35)
        }
        return id
    }

    func updateMemo(id: UUID, text: String, color: String? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isMemo }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[i].memoText = trimmed
        if let color {
            items[i].memoColor = color
        }
        items[i].thumb = makeMemoThumbnail(text: trimmed, color: items[i].memoColor, isDone: items[i].isDone)

        let memoData = MemoData(id: id, text: trimmed, color: items[i].memoColor,
                                isDone: items[i].isDone, createdAt: items[i].createdAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(memoData) {
            try? data.write(to: items[i].url)
        }
        save()
        MemoSyncManager.shared.sync(items: items)
    }

    func toggleMemoDone(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isMemo }) else { return }
        items[i].isDone.toggle()
        items[i].thumb = makeMemoThumbnail(text: items[i].memoText, color: items[i].memoColor, isDone: items[i].isDone)

        let memoData = MemoData(id: id, text: items[i].memoText, color: items[i].memoColor,
                                isDone: items[i].isDone, createdAt: items[i].createdAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(memoData) {
            try? data.write(to: items[i].url)
        }
        save()
        if items[i].isDone { play("Pop", volume: 0.25) }
    }

    /// Toggles a specific `- [ ]` / `- [x]` todo checklist item inside a memo.
    func toggleMemoTodoLine(id: UUID, lineIndex: Int) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isMemo }) else { return }
        let result = MemoSyncManager.toggleTodoLine(in: items[i].memoText, lineIndex: lineIndex)
        items[i].memoText = result.newText
        items[i].isDone = result.allDone
        items[i].thumb = makeMemoThumbnail(text: result.newText, color: items[i].memoColor, isDone: items[i].isDone)

        let memoData = MemoData(id: id, text: result.newText, color: items[i].memoColor,
                                isDone: items[i].isDone, createdAt: items[i].createdAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(memoData) {
            try? data.write(to: items[i].url)
        }
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

    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        let paths = items.filter { !$0.falling }.map(\.url.path)
        UserDefaults.standard.set(paths, forKey: storeKey)
        MemoSyncManager.shared.sync(items: items)
    }

    private func restore() {
        let paths = UserDefaults.standard.stringArray(forKey: storeKey) ?? []
        var loadedPaths = Set<String>()
        for path in paths where FileManager.default.fileExists(atPath: path) {
            hang(URL(fileURLWithPath: path), quietly: true)
            loadedPaths.insert(path)
        }

        // Crash-recovery: scan Memos folder in case app crashed before save() or UserDefaults was lost
        if let memoFiles = try? FileManager.default.contentsOfDirectory(at: Self.memosFolder, includingPropertiesForKeys: nil) {
            for file in memoFiles where file.pathExtension.lowercased() == "json" && !loadedPaths.contains(file.path) {
                hang(file, quietly: true)
            }
        }

        MemoSyncManager.shared.sync(items: items)
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

func makeMemoThumbnail(text: String, color: String, isDone: Bool) -> NSImage {
    let size = NSSize(width: 300, height: 240)
    let image = NSImage(size: size)
    image.lockFocus()

    let bgColor: NSColor
    switch color.lowercased() {
    case "green": bgColor = NSColor(red: 0.85, green: 0.96, blue: 0.85, alpha: 1.0)
    case "pink":  bgColor = NSColor(red: 1.0, green: 0.88, blue: 0.92, alpha: 1.0)
    case "blue":  bgColor = NSColor(red: 0.85, green: 0.93, blue: 1.0, alpha: 1.0)
    default:      bgColor = NSColor(red: 1.0, green: 0.95, blue: 0.68, alpha: 1.0)
    }

    let rect = NSRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
    let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
    bgColor.setFill()
    path.fill()

    NSColor.black.withAlphaComponent(0.08).setStroke()
    path.lineWidth = 1
    path.stroke()

    let para = NSMutableParagraphStyle()
    para.lineBreakMode = .byWordWrapping
    let font = NSFont.systemFont(ofSize: 20, weight: .medium)
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: isDone ? NSColor.secondaryLabelColor : NSColor.labelColor,
        .paragraphStyle: para
    ]
    if isDone {
        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }

    let textRect = rect.insetBy(dx: 16, dy: 16)
    (text as NSString).draw(in: textRect, withAttributes: attrs)

    image.unlockFocus()
    return image
}
