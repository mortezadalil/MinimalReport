import AppKit
import SwiftUI

@MainActor
final class AIQueryWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    convenience init(request: AIQueryRequest) {
        let title = request.type == .deletionSafety
            ? "Deletion Safety — \(request.item.displayName)"
            : "Find Cache — \(request.item.displayName)"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self

        let content = AIQueryView(request: request, onClose: { [weak window] in
            window?.close()
        })
        window.contentViewController = NSHostingController(rootView: content)
    }

    func show(centeredIn parent: NSWindow? = nil) {
        showWindow(nil)
        if let parent {
            let pw = parent.frame
            let ww = window?.frame.size ?? NSSize(width: 640, height: 500)
            window?.setFrameOrigin(NSPoint(
                x: pw.minX + (pw.width - ww.width) / 2,
                y: pw.minY + (pw.height - ww.height) / 2
            ))
        } else {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
