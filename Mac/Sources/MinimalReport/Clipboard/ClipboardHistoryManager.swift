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
    var isPinned: Bool = false  // pinned items stay on top and persist to disk

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
        // Restore pinned items saved on disk so they survive quit / restart.
        items = loadPins()
    }

    // MARK: - Display

    /// Items shown in the panel: pinned first (persisted), then recent history.
    var displayItems: [ClipboardItem] {
        items.filter { $0.isPinned } + items.filter { !$0.isPinned }
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
        // Pinned items are never evicted and never count against the caps.
        let pinned = items.filter { $0.isPinned }
        var unpinned = items.filter { !$0.isPinned }

        // Count cap (unpinned only).
        if unpinned.count > Self.maxCount {
            unpinned = Array(unpinned.prefix(Self.maxCount))
        }
        // Size cap — drop oldest unpinned (end of array) until within budget.
        var bytes = unpinned.reduce(0) { $0 + $1.approxBytes }
        while bytes > sizeLimitBytes && unpinned.count > 1 {
            let removed = unpinned.removeLast()
            bytes -= removed.approxBytes
        }

        items = pinned + unpinned
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

    /// Clears the recent history but keeps pinned items.
    func clear() {
        items.removeAll { !$0.isPinned }
    }

    /// Toggles the pinned state of an item, re-sorts, and persists the pins.
    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isPinned.toggle()
        // Re-sort so pinned float to the top, then persist.
        items = items.filter { $0.isPinned } + items.filter { !$0.isPinned }
        savePins()
    }

    // MARK: - Pin persistence (survives quit / restart)

    /// On-disk representation of a pinned item.
    private struct PinnedDTO: Codable {
        let timestamp: Date
        let kind: String        // "text" | "image"
        let text: String?
        let imagePNG: Data?
    }

    private var pinsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MinimalReport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pins.json")
    }

    private func savePins() {
        let dtos: [PinnedDTO] = items.filter { $0.isPinned }.map { item in
            PinnedDTO(
                timestamp: item.timestamp,
                kind: item.kind == .text ? "text" : "image",
                text: item.text,
                imagePNG: item.kind == .image ? item.image.flatMap(Self.pngData) : nil
            )
        }
        if let data = try? JSONEncoder().encode(dtos) {
            try? data.write(to: pinsURL, options: .atomic)
        }
    }

    private func loadPins() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: pinsURL),
              let dtos = try? JSONDecoder().decode([PinnedDTO].self, from: data) else {
            return []
        }
        return dtos.compactMap { dto in
            if dto.kind == "text", let t = dto.text {
                return ClipboardItem(timestamp: dto.timestamp, kind: .text, text: t,
                                     image: nil, approxBytes: t.utf8.count, isPinned: true)
            } else if dto.kind == "image", let d = dto.imagePNG, let img = NSImage(data: d) {
                return ClipboardItem(timestamp: dto.timestamp, kind: .image, text: nil,
                                     image: img, approxBytes: d.count, isPinned: true)
            }
            return nil
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
