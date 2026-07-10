import AppKit
import SwiftUI

/// Standalone borderless panel that shows the clipboard history list and lets
/// the user pick an item to paste. Dismisses on Esc, selection, or loss of focus.
@MainActor
final class ClipboardHistoryPanel: NSWindowController, NSWindowDelegate {

    private var history: ClipboardHistoryManager!

    init(history: ClipboardHistoryManager) {
        self.history = history

        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = "Clipboard History"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        // Keep the panel up while another app stays frontmost (needed for the
        // non-activating paste-back flow).
        panel.hidesOnDeactivate = false
        panel.level = .floating

        super.init(window: panel)
        panel.delegate = self

        panel.contentViewController = NSHostingController(
            rootView: ClipboardHistoryView(
                history: history,
                onSelect: { [weak self] item in self?.handleSelect(item) },
                onClear: { [weak history] in history?.clear() },
                onClose: { [weak self] in self?.close() }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// The app that was frontmost when the panel opened — so we can paste back
    /// into it, not into ourselves.
    private weak var previousApp: NSRunningApplication?

    /// Shows the panel near the current pointer location, clamped to the screen.
    func showNearCursor() {
        // Remember who was in front so we can restore focus + paste there.
        previousApp = NSWorkspace.shared.frontmostApplication
        showWindow(nil)
        positionNearCursor()
        // A non-activating panel becomes key WITHOUT making our app frontmost,
        // so the user's previous app keeps focus and the synthesized ⌘V lands
        // in the right place.
        window?.makeKeyAndOrderFront(nil)
    }

    private func positionNearCursor() {
        guard let window else { return }
        let cursor = NSEvent.mouseLocation
        let size = window.frame.size
        var origin = NSPoint(x: cursor.x + 8, y: cursor.y - size.height - 8)

        if let visible = NSScreen.main?.visibleFrame {
            origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
            origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        }
        window.setFrameOrigin(origin)
    }

    private func handleSelect(_ item: ClipboardItem) {
        // Put the item on the clipboard THROUGH the manager so its changeCount
        // stays in sync — this is what prevents the just-selected item from
        // being re-captured as a new (duplicate) history record.
        history.putOnPasteboard(item)

        let trusted = PasteHelper.isTrusted
        close()
        // Return focus to the app the user came from, then paste there.
        previousApp?.activate()

        if trusted {
            // Small delay so focus finishes returning before the keystroke.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                PasteHelper.synthesizePaste()
            }
        } else {
            showAccessibilityHint()
        }
    }

    private static let promptedKey = "minimalReport.clipboardAXPrompted"

    private func showAccessibilityHint() {
        // Only fire the system permission dialog ONCE, ever — otherwise it pops
        // up on every selection.
        let alreadyPrompted = UserDefaults.standard.bool(forKey: Self.promptedKey)
        if !alreadyPrompted {
            PasteHelper.ensureTrusted(prompt: true)
            UserDefaults.standard.set(true, forKey: Self.promptedKey)
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Item copied — press ⌘V to paste"
        alert.informativeText = """
            Automatic paste needs Accessibility access. If you just enabled it in \
            System Settings ▸ Privacy & Security ▸ Accessibility, please QUIT and \
            reopen MinimalReport once — macOS only applies the permission to a \
            freshly launched app.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - SwiftUI list

private struct ClipboardHistoryView: View {
    @ObservedObject var history: ClipboardHistoryManager
    let onSelect: (ClipboardItem) -> Void
    let onClear: () -> Void
    let onClose: () -> Void

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.12)
    private let rowBg = Color.white.opacity(0.05)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            content
        }
        .background(bg)
    }

    private var header: some View {
        HStack {
            Text("Clipboard History")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            if !history.items.isEmpty {
                Button(action: onClear) {
                    Text("Clear").font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if history.items.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.25))
                Text("Nothing copied yet")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.4))
                Text("Copy something (⌘C) and it appears here.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(history.items) { item in
                        row(item)
                        Divider().overlay(Color.white.opacity(0.05))
                    }
                }
            }
        }
    }

    private func row(_ item: ClipboardItem) -> some View {
        Button { onSelect(item) } label: {
            HStack(spacing: 10) {
                thumbnail(item)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.preview)
                        .font(.callout)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()
                Image(systemName: "arrow.down.to.line")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(_ item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(rowBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .image:
            if let nsImage = item.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .background(rowBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
