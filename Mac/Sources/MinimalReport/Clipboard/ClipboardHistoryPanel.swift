import AppKit
import SwiftUI

/// Standalone borderless panel that shows the clipboard history list and lets
/// the user pick an item to paste. Dismisses on Esc, selection, or loss of focus.
@MainActor
final class ClipboardHistoryPanel: NSWindowController, NSWindowDelegate {

    private var history: ClipboardHistoryManager!

    init(history: ClipboardHistoryManager) {
        self.history = history

        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView]
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
        panel.hidesOnDeactivate = true
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

    /// Shows the panel near the current pointer location, clamped to the screen.
    func showNearCursor() {
        showWindow(nil)
        positionNearCursor()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        let pasted = PasteHelper.paste(item: item)
        close()
        if !pasted {
            // Accessibility not granted: content is on the clipboard, but we
            // couldn't auto-paste. Nudge the user.
            showAccessibilityHint()
        }
    }

    private func showAccessibilityHint() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Item copied — press ⌘V to paste"
        alert.informativeText = """
            To enable automatic paste, grant Accessibility access to MinimalReport \
            in System Settings ▸ Privacy & Security ▸ Accessibility, then try again.
            """
        alert.addButton(withTitle: "OK")
        // Trigger the permission prompt so the user can find us in the list.
        PasteHelper.ensureTrusted(prompt: true)
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
