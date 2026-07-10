import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey (Cmd+Option+V by default) using the Carbon
/// Event Hot Key API. Fires `onTrigger` when the key is pressed anywhere on the
/// system, even when the app is not frontmost.
///
/// Uses Carbon because AppKit has no public global-hotkey API and this app is
/// not sandboxed (so registration works without entitlements).
final class GlobalHotkeyManager {

    /// Called on the main thread when the hotkey is pressed.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType
    private let hotKeyId: UInt32 = 1
    private let keyCode: UInt32
    private let modifiers: UInt32

    /// `keyCode` is a virtual key code; `modifiers` is a Carbon modifier mask.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_V),
         modifiers: UInt32 = UInt32(cmdKey | optionKey),
         signature: OSType = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.signature = signature
    }

    deinit {
        unregister()
    }

    func register() {
        guard hotKeyRef == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        // `self` pointer carried into the C callback.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                // Hop to the main thread — handlers fire on the main run loop,
                // but be explicit so UI work is safe.
                DispatchQueue.main.async {
                    manager.onTrigger?()
                }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )

        let id = EventHotKeyID(signature: signature, id: hotKeyId)
        RegisterEventHotKey(keyCode, modifiers, id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
