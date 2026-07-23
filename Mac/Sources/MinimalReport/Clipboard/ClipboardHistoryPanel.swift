import AppKit
import SwiftUI

/// Standalone borderless panel that shows the clipboard history list and lets
/// the user pick an item to paste. Dismisses on Esc, selection, or loss of focus.
@MainActor
final class ClipboardHistoryPanel: NSWindowController, NSWindowDelegate {

    private var history: ClipboardHistoryManager!

    /// Minimum / initial content size — roughly 5 standard rows plus the header.
    /// The panel never opens or resizes smaller than this (width and height).
    static let defaultSize = NSSize(width: 380, height: 400)

    init(history: ClipboardHistoryManager) {
        self.history = history

        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = "Minimal Report Clipboard History"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        // Keep the panel up while another app stays frontmost (needed for the
        // non-activating paste-back flow).
        panel.hidesOnDeactivate = false
        panel.level = .floating
        // Never let the panel shrink below ~5 standard rows (width + height).
        panel.minSize = Self.defaultSize
        panel.contentMinSize = Self.defaultSize

        super.init(window: panel)
        panel.delegate = self

        panel.contentViewController = NSHostingController(
            rootView: ClipboardHistoryView(
                history: history,
                onSelect: { [weak self] item in self?.handleSelect(item) },
                onTogglePin: { [weak history] item in history?.togglePin(item) },
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
        // Guarantee the panel opens at a usable size (never the collapsed tiny
        // window). Grow to the default if a previous resize left it smaller.
        if let window {
            let s = window.frame.size
            if s.width < Self.defaultSize.width || s.height < Self.defaultSize.height {
                window.setContentSize(Self.defaultSize)
            }
        }
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
        // Capture the target app before closing, then restore its focus.
        let target = previousApp
        close()
        target?.activate()

        // Attempt the paste. When Accessibility is granted the keystroke lands
        // in the focused field; otherwise macOS drops it silently (the item is
        // still on the clipboard for a manual ⌘V). A slightly longer delay lets
        // focus finish returning to the target app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            PasteHelper.synthesizePaste()
        }

        // If auto-paste can't work (not trusted), surface why — once per launch,
        // so a permission that went stale after an app update is discoverable
        // instead of silently failing.
        if !trusted { promptAccessibilityIfNeeded() }
    }

    /// Shown at most once per app launch when Accessibility isn't granted.
    private static var hintShownThisLaunch = false

    private func promptAccessibilityIfNeeded() {
        guard !Self.hintShownThisLaunch else { return }
        Self.hintShownThisLaunch = true

        // Fire the system permission dialog so the app appears in the list.
        PasteHelper.ensureTrusted(prompt: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Enable automatic paste"
        alert.informativeText = """
            The item is on your clipboard — press ⌘V to paste it now.

            For automatic paste, grant Accessibility access to MinimalReport in \
            System Settings ▸ Privacy & Security ▸ Accessibility, then QUIT and \
            reopen the app once. (After an app update you may need to remove and \
            re-add it.)
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - SwiftUI list

private struct ClipboardHistoryView: View {
    @ObservedObject var history: ClipboardHistoryManager
    let onSelect: (ClipboardItem) -> Void
    let onTogglePin: (ClipboardItem) -> Void
    let onClear: () -> Void
    let onClose: () -> Void

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.12)
    private let rowBg = Color.white.opacity(0.05)

    /// The image item currently hovered — drives the preview modal.
    @State private var hoveredImageID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            content
        }
        .frame(minWidth: 380, minHeight: 400, maxHeight: .infinity)
        .background(bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 18, height: 18)
            Text("Minimal Report Clipboard History")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)
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
            let pinned = history.items.filter { $0.isPinned }
            let unpinned = history.items.filter { !$0.isPinned }
            VStack(spacing: 0) {
                // Pinned items are fixed at the top and never scroll.
                if !pinned.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(pinned) { item in
                            row(item)
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                    .background(Color.accentColor.opacity(0.06))
                    Divider().overlay(Color.white.opacity(0.15))
                }
                // Recent (unpinned) items scroll below the pinned section.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(unpinned) { item in
                            row(item)
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: ClipboardItem) -> some View {
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

            // Pin toggle — its own button so it doesn't trigger a paste.
            Button { onTogglePin(item) } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundColor(item.isPinned ? .accentColor : .white.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "Unpin" : "Pin")

            Image(systemName: "arrow.down.to.line")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // Tapping anywhere else on the row pastes the item.
        .onTapGesture { onSelect(item) }
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
                    // Hovering the thumbnail shows the full image in a modal;
                    // leaving the thumbnail dismisses it.
                    .onHover { inside in
                        if inside {
                            hoveredImageID = item.id
                        } else if hoveredImageID == item.id {
                            hoveredImageID = nil
                        }
                    }
                    .popover(
                        isPresented: Binding(
                            get: { hoveredImageID == item.id },
                            set: { if !$0, hoveredImageID == item.id { hoveredImageID = nil } }
                        ),
                        arrowEdge: .trailing
                    ) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 420, maxHeight: 420)
                            .padding(10)
                    }
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
