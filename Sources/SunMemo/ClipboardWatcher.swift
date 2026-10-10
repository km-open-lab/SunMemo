import AppKit
import Foundation

/// Watches the macOS system clipboard for new screenshots or provides
/// on-demand hanging of clipboard items (images or text) via shortcut or button.
@MainActor
final class ClipboardWatcher: ObservableObject {
    static let shared = ClipboardWatcher()

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastImageHash: Int = 0
    private var onNewImage: ((URL) -> Void)?
    private weak var line: Line?

    private let autoHangKey = "autoHangClipboard"

    /// Whether to automatically hang new screenshot images from clipboard.
    /// Default is false to prevent accidental copies from clogging the clothesline.
    var isAutoHangEnabled: Bool {
        get { Demo.defaults.bool(forKey: autoHangKey) }
        set {
            Demo.defaults.set(newValue, forKey: autoHangKey)
            objectWillChange.send()
        }
    }

    private init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func setup(line: Line, onNewImage: @escaping (URL) -> Void) {
        self.line = line
        self.onNewImage = onNewImage
        start()
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.poll()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called manually (e.g. by shortcut ⌃ ⌥ V or button) to hang whatever is currently on the clipboard.
    @discardableResult
    func hangCurrentClipboard() -> Bool {
        guard let line else { return false }
        let pb = NSPasteboard.general

        // 1. Check for image
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff), !data.isEmpty {
            let pngData: Data?
            if pb.data(forType: .png) != nil {
                pngData = data
            } else if let rep = NSBitmapImageRep(data: data) {
                pngData = rep.representation(using: .png, properties: [:])
            } else {
                pngData = data
            }

            if let validPng = pngData, !validPng.isEmpty {
                let folder = Inbox.folder
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let fileURL = folder.appendingPathComponent("QuickShot_\(formatter.string(from: Date()))_\(Int.random(in: 100...999)).png")
                do {
                    try validPng.write(to: fileURL)
                    onNewImage?(fileURL)
                    return true
                } catch {
                    NSLog("Failed to write clipboard image: \(error.localizedDescription)")
                }
            }
        }

        // 2. Check for text
        if let string = pb.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            line.addMemo(text: string)
            NotificationCenter.default.post(name: .tendederoRevealLine, object: nil)
            return true
        }

        return false
    }

    private func poll() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // If Tendedero itself just copied something, skip it.
        if let line, line.isInternalCopy {
            line.isInternalCopy = false
            return
        }

        // Only proceed if auto-hang is enabled by user
        guard isAutoHangEnabled else { return }

        // Check types
        guard let types = pb.types,
              types.contains(where: { $0 == .png || $0 == .tiff || $0.rawValue.contains("image") }) else {
            return
        }

        // Smart Filter: If clipboard contains HTML or browser source URL, it's a web copy, not a pure screenshot!
        let hasWebOrigin = types.contains(where: {
            $0.rawValue.contains("html") ||
            $0.rawValue.contains("source-url") ||
            $0.rawValue.contains("webarchive")
        })
        if hasWebOrigin {
            return
        }

        // Extract PNG or TIFF data
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff), !data.isEmpty else { return }

        let currentHash = data.hashValue
        guard currentHash != lastImageHash else { return }
        lastImageHash = currentHash

        let pngData: Data?
        if pb.data(forType: .png) != nil {
            pngData = data
        } else if let rep = NSBitmapImageRep(data: data) {
            pngData = rep.representation(using: .png, properties: [:])
        } else {
            pngData = data
        }

        guard let validPng = pngData, !validPng.isEmpty else { return }

        let folder = Inbox.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileURL = folder.appendingPathComponent("QuickShot_\(timestamp)_\(Int.random(in: 100...999)).png")

        do {
            try validPng.write(to: fileURL)
            DispatchQueue.main.async { [weak self] in
                self?.onNewImage?(fileURL)
            }
        } catch {
            NSLog("ClipboardWatcher: failed to write screenshot image: \(error.localizedDescription)")
        }
    }
}
