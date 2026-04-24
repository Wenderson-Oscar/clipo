import AppKit
import Carbon.HIToolbox

/// Registra um atalho global via Carbon EventHotKey.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    private init() {}

    /// Registra Shift+Cmd+V por padrão.
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_V),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey),
                  handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData, let event = event else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async { mgr.handler?() }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        var hkRef: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x434C504F /* "CLPO" */), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &hkRef)
        self.hotKeyRef = hkRef
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
        if let h = eventHandler { RemoveEventHandler(h) }
        eventHandler = nil
    }
}
