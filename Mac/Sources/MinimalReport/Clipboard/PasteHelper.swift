import AppKit
import ApplicationServices

/// Handles pasting a selected clipboard-history item into the currently focused
/// app. Requires the Accessibility permission; degrades to copy-only otherwise.
enum PasteHelper {

    /// True when the app already has Accessibility trust.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts the user (once) to grant Accessibility access, if not already granted.
    @discardableResult
    static func ensureTrusted(prompt: Bool = true) -> Bool {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Synthesizes a Cmd+V keypress so the focused field pastes whatever is
    /// currently on the clipboard. The caller is responsible for having already
    /// put the desired item on the pasteboard (see `ClipboardHistoryManager`).
    ///
    /// Returns `false` if Accessibility isn't granted (can't post events).
    @discardableResult
    static func synthesizePaste() -> Bool {
        guard isTrusted else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // 0x09 = V
        let cmdUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        cmdDown?.flags = .maskCommand
        cmdUp?.flags = .maskCommand

        cmdDown?.post(tap: .cgSessionEventTap)
        cmdUp?.post(tap: .cgSessionEventTap)
        return true
    }

    /// Writes the item to the system pasteboard and returns the new changeCount,
    /// so callers can keep their own polling in sync.
    @discardableResult
    static func putOnPasteboard(_ item: ClipboardItem) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let tiff = item.image?.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
        return pb.changeCount
    }
}
