import Carbon.HIToolbox

/// Registers a system-wide shortcut through Carbon, which needs no Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1

    /// - Parameters:
    ///   - keyCode: A `kVK_*` virtual key code.
    ///   - modifiers: Carbon modifier mask such as `optionKey | cmdKey`.
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        let id = Self.nextID
        Self.nextID += 1
        Self.registry[id] = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let hotKey = HotKey.registry[hkID.id] {
                DispatchQueue.main.async { hotKey.action() }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        let hkID = EventHotKeyID(signature: OSType(0x424B484C), id: id) // "BKHL"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
