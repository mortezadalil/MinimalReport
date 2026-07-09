import Foundation

enum CleanupCategory: String, CaseIterable, Identifiable {
    case trash, tempCache, applications, packages, aiAnalysis
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trash: return "Trash"
        case .tempCache: return "Temp / Cache"
        case .applications: return "Applications"
        case .packages: return "Packages"
        case .aiAnalysis: return "AI Analysis"
        }
    }
}

enum PackageManager: String {
    case brewFormula, brewCask, npm, cargo, pip3, gem

    var label: String {
        switch self {
        case .brewFormula: return "brew"
        case .brewCask: return "brew cask"
        case .npm: return "npm"
        case .cargo: return "cargo"
        case .pip3: return "pip3"
        case .gem: return "gem"
        }
    }
}

/// How a given item is removed. Stored on the item so the executor is a pure switch.
enum CleanupAction {
    case removePaths([String])              // rm -rf, user-owned
    case removePathsPrivileged([String])    // rm -rf via admin (sudo)
    case shellUninstall(PackageManager, name: String)
}

struct CleanupItem: Identifiable {
    let id = UUID()
    let displayName: String
    let detail: String
    var sizeBytes: Int64            // -1 == still scanning
    let category: CleanupCategory
    let needsAdmin: Bool
    let action: CleanupAction
    var sizePaths: [String] = []    // for packages: paths to measure on disk
    var isSelected: Bool = false
    var isExcluded: Bool = false    // shown but not selectable (e.g. rustup shims)
    var exclusionNote: String = ""

    var sizeResolved: Bool { sizeBytes >= 0 }
}
