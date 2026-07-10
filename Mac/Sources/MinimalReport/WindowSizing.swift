import AppKit

/// Shared helpers that keep windows inside the visible screen area and bound
/// them to a sensible default size, so no window can exceed the screen or grow
/// unbounded.
enum WindowSizing {

    /// The screen's visible frame (excludes menu bar and Dock). Falls back to a
    /// generous default if no screen is available (e.g. headless).
    static var visibleFrame: NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }

    /// Bounds `size` to the visible frame so a window never exceeds ~90% of the
    /// screen, while never going below `minSize`.
    static func clamped(size: NSSize, minSize: NSSize) -> NSSize {
        let visible = visibleFrame
        let maxWidth = min(size.width, visible.width * 0.9)
        let maxHeight = min(size.height, visible.height * 0.9)
        return NSSize(
            width: max(minSize.width, maxWidth),
            height: max(minSize.height, maxHeight)
        )
    }

    /// Applies default + max size constraints to a resizable window so it can't
    /// be dragged larger than the screen. `preferred` is the desired default
    /// content size; `minSize` is the minimum content size.
    static func constrain(_ window: NSWindow, preferred: NSSize, minSize: NSSize) {
        let clamped = clamped(size: preferred, minSize: minSize)

        window.minSize = minSize
        // maxSize is in window-frame coordinates; use a value safely above the
        // content size so it can still resize but never escapes the screen.
        let visible = visibleFrame
        window.maxSize = NSSize(
            width: min(visible.width, max(clamped.width, minSize.width)),
            height: min(visible.height, max(clamped.height, minSize.height))
        )

        window.setContentSize(clamped)
    }

    /// Clamps a candidate top-left origin so the given window size stays fully
    /// on screen.
    static func clampedOrigin(for size: NSSize, near point: NSPoint) -> NSPoint {
        let visible = visibleFrame
        let x = max(visible.minX, min(point.x, visible.maxX - size.width))
        let y = max(visible.minY, min(point.y, visible.maxY - size.height))
        return NSPoint(x: x, y: y)
    }
}
