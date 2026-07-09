import Foundation
import Combine

enum SizeSort { case none, descending, ascending }

@MainActor
final class CleanupState: ObservableObject {
    @Published var items: [CleanupCategory: [CleanupItem]] = [:]
    @Published var isScanning: [CleanupCategory: Bool] = [:]
    @Published var selectedTab: CleanupCategory = .trash
    @Published var sizeSort: SizeSort = .none
    @Published var isExecuting: Bool = false
    @Published var lastResultLog: String = ""

    func items(for cat: CleanupCategory) -> [CleanupItem] { items[cat] ?? [] }
    func scanning(_ cat: CleanupCategory) -> Bool { isScanning[cat] ?? false }

    func sortedItems(for cat: CleanupCategory) -> [CleanupItem] {
        let arr = items[cat] ?? []
        switch sizeSort {
        case .none:       return arr
        case .descending: return arr.sorted { $0.sizeBytes > $1.sizeBytes }
        case .ascending:  return arr.sorted { $0.sizeBytes < $1.sizeBytes }
        }
    }

    func cycleSizeSort() {
        switch sizeSort {
        case .none:       sizeSort = .descending
        case .descending: sizeSort = .ascending
        case .ascending:  sizeSort = .none
        }
    }

    var selectedItems: [CleanupItem] {
        CleanupCategory.allCases
            .flatMap { items[$0] ?? [] }
            .filter { $0.isSelected && !$0.isExcluded }
    }

    var totalSelectedSize: Int64 {
        selectedItems.reduce(0) { $0 + max(0, $1.sizeBytes) }
    }

    var anyNeedsAdmin: Bool { selectedItems.contains { $0.needsAdmin } }

    // MARK: - Mutation (all on main actor)

    func setItems(_ new: [CleanupItem], for cat: CleanupCategory) {
        items[cat] = new
    }

    func setScanning(_ value: Bool, for cat: CleanupCategory) {
        isScanning[cat] = value
    }

    func updateSize(itemID: UUID, cat: CleanupCategory, size: Int64) {
        guard var arr = items[cat], let i = arr.firstIndex(where: { $0.id == itemID }) else { return }
        arr[i].sizeBytes = size
        items[cat] = arr
    }

    func toggle(itemID: UUID, cat: CleanupCategory) {
        guard var arr = items[cat], let i = arr.firstIndex(where: { $0.id == itemID }) else { return }
        guard !arr[i].isExcluded else { return }
        arr[i].isSelected.toggle()
        items[cat] = arr
    }

    func setAllSelected(_ selected: Bool, for cat: CleanupCategory) {
        guard var arr = items[cat] else { return }
        for i in arr.indices where !arr[i].isExcluded {
            arr[i].isSelected = selected
        }
        items[cat] = arr
    }
}
