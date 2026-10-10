import AppKit
import Carbon

@MainActor
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    // Defaults:
    // ⌃ ⌥ ␣ (Toggle Line, Space = 49)
    // ⌃ ⌥ N (New Memo, N = 45)
    // ⌃ ⌥ V (Hang Clipboard, V = 9)
    static let defaultToggleKey = 49
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
        didSet { UserDefaults.standard.set(toggleKey, forKey: toggleKeyKey) }
    }
    @Published var toggleMods: Int {
        didSet { UserDefaults.standard.set(toggleMods, forKey: toggleModsKey) }
    }
    @Published var memoKey: Int {
        didSet { UserDefaults.standard.set(memoKey, forKey: memoKeyKey) }
    }
    @Published var memoMods: Int {
        didSet { UserDefaults.standard.set(memoMods, forKey: memoModsKey) }
    }
    @Published var pasteKey: Int {
        didSet { UserDefaults.standard.set(pasteKey, forKey: pasteKeyKey) }
    }
    @Published var pasteMods: Int {
        didSet { UserDefaults.standard.set(pasteMods, forKey: pasteModsKey) }
    }

    enum Target: CaseIterable {
        case toggle, memo, paste
    }

    /// Shortcuts macOS refused to register, usually because another app
    /// already uses them. Shown in the settings.
    @Published private(set) var unavailable: Set<Target> = []

    var onToggle: (() -> Void)?
    var onNewMemo: (() -> Void)?
    var onHangClipboard: (() -> Void)?

    private var toggleHotKey: HotKey?
    private var fallbackToggleHotKey: HotKey?
    private var memoHotKey: HotKey?
    private var pasteHotKey: HotKey?

    private init() {
        let ud = UserDefaults.standard
        var savedToggleKey = ud.object(forKey: toggleKeyKey) as? Int
        let savedToggleMods = ud.object(forKey: toggleModsKey) as? Int
        let savedMemoKey = ud.object(forKey: memoKeyKey) as? Int
        let savedMemoMods = ud.object(forKey: memoModsKey) as? Int
        let savedPasteKey = ud.object(forKey: pasteKeyKey) as? Int
        let savedPasteMods = ud.object(forKey: pasteModsKey) as? Int

        // Migration: If previously defaulted to 17 (T), migrate to 49 (Space) so ⌃ ⌥ ␣ works out-of-the-box
        if savedToggleKey == 17 {
            savedToggleKey = Self.defaultToggleKey
            ud.set(49, forKey: toggleKeyKey)
        }

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
        fallbackToggleHotKey = nil
        memoHotKey = nil
        pasteHotKey = nil

        toggleHotKey = HotKey(keyCode: toggleKey, modifiers: toggleMods) { [weak self] in
            self?.onToggle?()
        }

        // When toggleKey is 49 (Space), also register 17 (T) as fallback alias so both shortcuts work
        if toggleKey == 49 && toggleMods == (controlKey | optionKey) {
            fallbackToggleHotKey = HotKey(keyCode: 17, modifiers: controlKey | optionKey) { [weak self] in
                self?.onToggle?()
            }
        }

        memoHotKey = HotKey(keyCode: memoKey, modifiers: memoMods) { [weak self] in
            self?.onNewMemo?()
        }

        pasteHotKey = HotKey(keyCode: pasteKey, modifiers: pasteMods) { [weak self] in
            self?.onHangClipboard?()
        }

        var failed = Set<Target>()
        if toggleHotKey?.isRegistered != true { failed.insert(.toggle) }
        if memoHotKey?.isRegistered != true { failed.insert(.memo) }
        if pasteHotKey?.isRegistered != true { failed.insert(.paste) }
        unavailable = failed
    }

    func resetToDefaults() {
        toggleKey = Self.defaultToggleKey
        toggleMods = Self.defaultToggleMods
        memoKey = Self.defaultMemoKey
        memoMods = Self.defaultMemoMods
        pasteKey = Self.defaultPasteKey
        pasteMods = Self.defaultPasteMods
        rebind()
    }

    func shortcut(for target: Target) -> (key: Int, mods: Int) {
        switch target {
        case .toggle: return (toggleKey, toggleMods)
        case .memo: return (memoKey, memoMods)
        case .paste: return (pasteKey, pasteMods)
        }
    }

    /// Why a recorded shortcut cannot be used, or nil if it can.
    ///
    /// A global shortcut takes the keys away from every other app, so it must
    /// include Control or Option: Shift alone would stop capitals from being
    /// typed, and Command alone would take over shortcuts like Copy and Paste.
    func problem(withKey key: Int, mods: Int, for target: Target) -> String? {
        if mods & (controlKey | optionKey) == 0 {
            return L("Include Control or Option, so the shortcut does not take keys away from other apps.")
        }
        for other in Target.allCases where other != target {
            let s = shortcut(for: other)
            if s.key == key && s.mods == mods {
                return L("SunMemo already uses this shortcut for something else.")
            }
        }
        return nil
    }

    /// Sets a shortcut and registers it. If macOS refuses it, the previous
    /// one is put back and false is returned.
    @discardableResult
    func setShortcut(_ target: Target, key: Int, mods: Int) -> Bool {
        let previous = shortcut(for: target)
        assign(target, key: key, mods: mods)
        rebind()
        guard unavailable.contains(target) else { return true }
        assign(target, key: previous.key, mods: previous.mods)
        rebind()
        return false
    }

    private func assign(_ target: Target, key: Int, mods: Int) {
        switch target {
        case .toggle: toggleKey = key; toggleMods = mods
        case .memo: memoKey = key; memoMods = mods
        case .paste: pasteKey = key; pasteMods = mods
        }
    }
}
