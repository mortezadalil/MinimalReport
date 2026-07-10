import AppKit
import Combine

/// A single captured clipboard entry — either text or an image.
struct ClipboardItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let text: String?          // non-nil when kind == .text
    let image: NSImage?        // non-nil when kind == .image
    let approxBytes: Int       // rough footprint, used for the size budget

    enum Kind { case text, image }

    /// Short single-line preview for the list UI.
    var preview: String {
        switch kind {
        case .text:
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "(empty)" }
            return trimmed.replacingOccurrences(of: "\n", with: " ⏎ ")
        case .image:
            return "🖼 Image"
        }
    }
}

/// In-memory clipboard history. Polls the system pasteboard ~1x/second,
/// records up to 100 items within a size budget (in MB), and exposes the
/// current list to SwiftUI.
///
/// Persistence is intentionally **in-memory only** — history is cleared when
/// the app quits (by design, matching the user's preference).
final class ClipboardHistoryManager: ObservableObject {

    @Published private(set) var items: [ClipboardItem] = []

    /// Maximum number of items kept, regardless of size.
    static let maxCount = 100

    private var timer: Timer?
    private var lastChangeCount: Int

    // UserDefaults keys (mirror the keys used elsewhere in the app).
    private let enabledKey = "minimalReport.clipboardHistoryEnabled"
    private let sizeMBKey = "minimalReport.clipboardHistorySizeMB"

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        // Re-sync the changeCount so we don't immediately re-capture whatever is
        // currently on the pasteboard as a "new" item on launch.
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Config (read live so Settings changes apply immediately)

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    var sizeLimitBytes: Int {
        let mb = UserDefaults.standard.object(forKey: sizeMBKey) as? Int ?? 50
        return max(1, mb) * 1_048_576
    }

    // MARK: - Polling

    private func poll() {
        guard isEnabled else { return }
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if let item = capture(from: pb) {
            insert(item)
        }
    }

    /// Builds a `ClipboardItem` from the current pasteboard contents, preferring
    /// image data when present, otherwise text. Returns nil for content types
    /// we don't track (e.g. files, URLs-only).
    private func capture(from pb: NSPasteboard) -> ClipboardItem? {
        // Image first — screenshots/copied images come through as TIFF/PNG.
        if pb.types?.contains(where: { $0 == .png || $0 == .tiff || $0 == NSPasteboard.PasteboardType(rawValue: "public.tiff") }) == true,
           let data = pb.data(forType: .tiff) ?? pb.data(forType: .png),
           let image = NSImage(data: data) {
            return ClipboardItem(
                timestamp: Date(),
                kind: .image,
                text: nil,
                image: image,
                approxBytes: data.count
            )
        }

        if let types = pb.types, types.contains(.string),
           let text = pb.string(forType: .string), !text.isEmpty {
            return ClipboardItem(
                timestamp: Date(),
                kind: .text,
                text: text,
                image: nil,
                approxBytes: text.utf8.count
            )
        }
        return nil
    }

    // MARK: - Mutation

    private func insert(_ item: ClipboardItem) {
        // De-dupe: skip if identical to the most recent entry.
        if let first = items.first, sameContent(first, item) { return }

        items.insert(item, at: 0)
        enforceLimits()
    }

    private func enforceLimits() {
        // Count cap.
        if items.count > Self.maxCount {
            items = Array(items.prefix(Self.maxCount))
        }
        // Size cap — drop oldest (end of array) until within budget.
        var bytes = items.reduce(0) { $0 + $1.approxBytes }
        while bytes > sizeLimitBytes && items.count > 1 {
            let removed = items.removeLast()
            bytes -= removed.approxBytes
        }
    }

    private func sameContent(_ a: ClipboardItem, _ b: ClipboardItem) -> Bool {
        guard a.kind == b.kind else { return false }
        switch a.kind {
        case .text:  return a.text == b.text
        case .image: return a.approxBytes == b.approxBytes // good enough for de-dupe
        }
    }

    // MARK: - Public actions

    /// Loads the given item back onto the system pasteboard so it can be pasted,
    /// and keeps our polling changeCount in sync so we don't re-capture it.
    func putOnPasteboard(_ item: ClipboardItem) {
        lastChangeCount = PasteHelper.putOnPasteboard(item)
    }

    func clear() {
        items.removeAll()
    }
}
