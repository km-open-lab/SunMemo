import Carbon

/// Global shortcut through the Carbon hot key API. Unlike a global
/// key monitor, it needs no Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var isHandlerInstalled = false
    private static var nextId: UInt32 = 1

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        let currentId = HotKey.nextId
        HotKey.nextId += 1
        self.id = currentId
        HotKey.handlers[currentId] = action

        if !HotKey.isHandlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                }
                DispatchQueue.main.async {
                    HotKey.handlers[hotKeyID.id]?()
                }
                return noErr
            }, 1, &spec, nil, nil)
            HotKey.isHandlerInstalled = true
        }

        let eventHotKeyID = EventHotKeyID(signature: OSType(0x5445_4E44), id: currentId) // "TEND"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), eventHotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        HotKey.handlers.removeValue(forKey: id)
        if let ref { UnregisterEventHotKey(ref) }
    }
}

