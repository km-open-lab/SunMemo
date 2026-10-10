import AppKit
import Carbon

@MainActor
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    // Defaults:
    // ⌃ ⌥ T (Toggle Line, T = 17)
    // ⌃ ⌥ N (New Memo, N = 45)
    // ⌃ ⌥ V (Hang Clipboard, V = 9)
    static let defaultToggleKey = 17
    static let defaultToggleMods = controlKey | optionKey
    static let defaultMemoKey = 45
    static let defaultMemoMods = controlKey | optionKey
    static let defaultPasteKey = 9
    static let defaultPasteMods = controlKey | optionKey

    private let toggleKeyKey = "custom_toggle_key"
    private let toggleModsKey = "custom_toggle_mods"
    private let memoKeyKey = "custom_memo_key"
    private let memoModsKey = "custom_memo_mods"
    private let pasteKeyKey = "custom_paste_key"
    private let pasteModsKey = "custom_paste_mods"

    @Published var toggleKey: Int {
        didSet { UserDefaults.standard.set(toggleKey, forKey: toggleKeyKey); rebind() }
    }
    @Published var toggleMods: Int {
        didSet { UserDefaults.standard.set(toggleMods, forKey: toggleModsKey); rebind() }
    }
    @Published var memoKey: Int {
        didSet { UserDefaults.standard.set(memoKey, forKey: memoKeyKey); rebind() }
    }
    @Published var memoMods: Int {
        didSet { UserDefaults.standard.set(memoMods, forKey: memoModsKey); rebind() }
    }
    @Published var pasteKey: Int {
        didSet { UserDefaults.standard.set(pasteKey, forKey: pasteKeyKey); rebind() }
    }
    @Published var pasteMods: Int {
        didSet { UserDefaults.standard.set(pasteMods, forKey: pasteModsKey); rebind() }
    }

    var onToggle: (() -> Void)?
    var onNewMemo: (() -> Void)?
    var onHangClipboard: (() -> Void)?

    private var toggleHotKey: HotKey?
    private var memoHotKey: HotKey?
    private var pasteHotKey: HotKey?

    private init() {
        let ud = UserDefaults.standard
        let savedToggleKey = ud.object(forKey: toggleKeyKey) as? Int
        let savedToggleMods = ud.object(forKey: toggleModsKey) as? Int
        let savedMemoKey = ud.object(forKey: memoKeyKey) as? Int
        let savedMemoMods = ud.object(forKey: memoModsKey) as? Int
        let savedPasteKey = ud.object(forKey: pasteKeyKey) as? Int
        let savedPasteMods = ud.object(forKey: pasteModsKey) as? Int

        self.toggleKey = savedToggleKey ?? Self.defaultToggleKey
        self.toggleMods = savedToggleMods ?? Self.defaultToggleMods
        self.memoKey = savedMemoKey ?? Self.defaultMemoKey
        self.memoMods = savedMemoMods ?? Self.defaultMemoMods
        self.pasteKey = savedPasteKey ?? Self.defaultPasteKey
        self.pasteMods = savedPasteMods ?? Self.defaultPasteMods
    }

    func start(onToggle: @escaping () -> Void, onNewMemo: @escaping () -> Void, onHangClipboard: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onNewMemo = onNewMemo
        self.onHangClipboard = onHangClipboard
        rebind()
    }

    func rebind() {
        toggleHotKey = nil
        memoHotKey = nil
        pasteHotKey = nil

        toggleHotKey = HotKey(keyCode: toggleKey, modifiers: toggleMods) { [weak self] in
            self?.onToggle?()
        }

        memoHotKey = HotKey(keyCode: memoKey, modifiers: memoMods) { [weak self] in
            self?.onNewMemo?()
        }

        pasteHotKey = HotKey(keyCode: pasteKey, modifiers: pasteMods) { [weak self] in
            self?.onHangClipboard?()
        }
    }

    func resetToDefaults() {
        toggleKey = Self.defaultToggleKey
        toggleMods = Self.defaultToggleMods
        memoKey = Self.defaultMemoKey
        memoMods = Self.defaultMemoMods
        pasteKey = Self.defaultPasteKey
        pasteMods = Self.defaultPasteMods
    }
}
