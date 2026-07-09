import Foundation

@MainActor
final class CleanupService {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    // MARK: - Scan orchestration

    func scanAll(into state: CleanupState) async {
        async let a: Void = scanTrash(into: state)
        async let b: Void = scanTempCache(into: state)
        async let c: Void = scanApplications(into: state)
        async let d: Void = scanPackages(into: state)
        _ = await (a, b, c, d)
    }

    /// Resolve sizes for all items off the main thread, patching each row as it completes.
    /// Package items use item.sizePaths if non-empty; items with no resolvable path are skipped.
    private func resolveSizes(_ items: [CleanupItem], cat: CleanupCategory, into state: CleanupState) async {
        await withTaskGroup(of: (UUID, Int64).self) { group in
            for item in items {
                let paths: [String]
                switch item.action {
                case .removePaths(let p), .removePathsPrivileged(let p):
                    paths = p
                case .shellUninstall:
                    guard !item.sizePaths.isEmpty else { continue }
                    paths = item.sizePaths
                }
                let id = item.id
                group.addTask { (id, DirectorySizer.size(ofAny: paths)) }
            }
            for await (id, size) in group {
                state.updateSize(itemID: id, cat: cat, size: size)
            }
        }
    }

    // MARK: - Trash

    func scanTrash(into state: CleanupState) async {
        state.setScanning(true, for: .trash)
        var items: [CleanupItem] = []

        let userTrash = "\(home)/.Trash"
        items.append(CleanupItem(
            displayName: "Home Trash",
            detail: userTrash,
            sizeBytes: -1,
            category: .trash,
            needsAdmin: false,
            action: .removePaths([userTrash])
        ))

        // Per-volume trash for the current user id.
        let uid = getuid()
        for vol in fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [] {
            let trashes = vol.appendingPathComponent(".Trashes/\(uid)").path
            if fm.fileExists(atPath: trashes) {
                items.append(CleanupItem(
                    displayName: "Trash — \(vol.lastPathComponent)",
                    detail: trashes,
                    sizeBytes: -1,
                    category: .trash,
                    needsAdmin: true,
                    action: .removePathsPrivileged([trashes])
                ))
            }
        }

        state.setItems(items, for: .trash)
        await resolveSizes(items, cat: .trash, into: state)
        state.setScanning(false, for: .trash)
    }

    // MARK: - Temp / Cache

    private struct CachePath {
        let name: String
        let path: String
        let admin: Bool
    }

    func scanTempCache(into state: CleanupState) async {
        state.setScanning(true, for: .tempCache)
        var items: [CleanupItem] = []

        // Break out the largest immediate children of ~/Library/Caches as rows.
        let userCaches = "\(home)/Library/Caches"
        if let children = try? fm.contentsOfDirectory(atPath: userCaches) {
            for child in children where !child.hasPrefix(".") {
                let full = "\(userCaches)/\(child)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
                items.append(CleanupItem(
                    displayName: "Cache: \(child)",
                    detail: full,
                    sizeBytes: -1,
                    category: .tempCache,
                    needsAdmin: false,
                    action: .removePaths([full])
                ))
            }
        }

        let tmpdir = ProcessInfo.processInfo.environment["TMPDIR"]
            .map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }

        let fixed: [CachePath] = [
            CachePath(name: "User Logs", path: "\(home)/Library/Logs", admin: false),
            CachePath(name: "Temp ($TMPDIR)", path: tmpdir ?? "", admin: false),
            CachePath(name: "Xcode DerivedData", path: "\(home)/Library/Developer/Xcode/DerivedData", admin: false),
            CachePath(name: "npm cache", path: "\(home)/.npm/_cacache", admin: false),
            CachePath(name: "Generic ~/.cache", path: "\(home)/.cache", admin: false),
            CachePath(name: "Cargo registry cache", path: "\(home)/.cargo/registry/cache", admin: false),
            CachePath(name: "System Caches", path: "/Library/Caches", admin: true),
            CachePath(name: "System temp (var/folders)", path: "/private/var/folders", admin: true),
        ]

        for c in fixed where !c.path.isEmpty && fm.fileExists(atPath: c.path) {
            items.append(CleanupItem(
                displayName: c.name,
                detail: c.path,
                sizeBytes: -1,
                category: .tempCache,
                needsAdmin: c.admin,
                action: c.admin ? .removePathsPrivileged([c.path]) : .removePaths([c.path])
            ))
        }

        state.setItems(items, for: .tempCache)
        await resolveSizes(items, cat: .tempCache, into: state)
        state.setScanning(false, for: .tempCache)
    }

    // MARK: - Applications

    private let appSupportDirs = [
        "Application Support", "Caches", "Preferences",
        "Logs", "Containers", "Saved Application State",
    ]

    func scanApplications(into state: CleanupState) async {
        state.setScanning(true, for: .applications)
        var items: [CleanupItem] = []

        let appDirs = ["/Applications", "\(home)/Applications"]
        for dir in appDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appPath = "\(dir)/\(entry)"
                let bundleID = bundleIdentifier(atAppPath: appPath)
                let nameStem = entry.replacingOccurrences(of: ".app", with: "")

                var paths = [appPath]
                paths.append(contentsOf: leftoverPaths(bundleID: bundleID, nameStem: nameStem))

                // Root-owned app in /Applications may require admin to delete.
                let needsAdmin = !fm.isWritableFile(atPath: appPath)
                let action: CleanupAction = needsAdmin
                    ? .removePathsPrivileged(paths)
                    : .removePaths(paths)

                items.append(CleanupItem(
                    displayName: entry,
                    detail: bundleID ?? appPath,
                    sizeBytes: -1,
                    category: .applications,
                    needsAdmin: needsAdmin,
                    action: action
                ))
            }
        }

        items.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        state.setItems(items, for: .applications)
        await resolveSizes(items, cat: .applications, into: state)
        state.setScanning(false, for: .applications)
    }

    private func bundleIdentifier(atAppPath appPath: String) -> String? {
        let plist = "\(appPath)/Contents/Info.plist"
        guard let data = fm.contents(atPath: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    /// Existing leftover support files for a given app, matched by bundle id then name.
    private func leftoverPaths(bundleID: String?, nameStem: String) -> [String] {
        var results: [String] = []
        let library = "\(home)/Library"
        for sub in appSupportDirs {
            let base = "\(library)/\(sub)"
            for candidate in [bundleID, nameStem].compactMap({ $0 }) {
                let full = "\(base)/\(candidate)"
                if fm.fileExists(atPath: full) { results.append(full) }
            }
        }
        return Array(Set(results))
    }

    // MARK: - Packages

    private let rustupShims: Set<String> = [
        "cargo", "rustc", "rustup", "rust-gdb", "rust-lldb", "rustfmt",
        "clippy-driver", "cargo-clippy", "cargo-fmt", "rust-analyzer", "cargo-miri",
    ]

    func scanPackages(into state: CleanupState) async {
        state.setScanning(true, for: .packages)

        let items: [CleanupItem] = await Task.detached { [weak self] in
            guard let self else { return [] }
            var result: [CleanupItem] = []
            result.append(contentsOf: self.scanBrewFormulae())
            result.append(contentsOf: self.scanBrewCasks())
            result.append(contentsOf: self.scanNpm())
            result.append(contentsOf: self.scanCargo())
            result.append(contentsOf: self.scanPip())
            result.append(contentsOf: self.scanGem())
            return result
        }.value

        state.setItems(items, for: .packages)
        await resolveSizes(items, cat: .packages, into: state)
        state.setScanning(false, for: .packages)
    }

    private nonisolated func packageItem(
        _ mgr: PackageManager, name: String, detail: String,
        sizePaths: [String] = [],
        excluded: Bool = false, note: String = ""
    ) -> CleanupItem {
        CleanupItem(
            displayName: name,
            detail: detail,
            sizeBytes: sizePaths.isEmpty ? 0 : -1,
            category: .packages,
            needsAdmin: false,
            action: .shellUninstall(mgr, name: name),
            sizePaths: sizePaths,
            isExcluded: excluded,
            exclusionNote: note
        )
    }

    private nonisolated func scanBrewFormulae() -> [CleanupItem] {
        guard let out = try? Shell.runShell("brew list --versions") else { return [] }
        let cellar = (try? Shell.runShell("brew --cellar"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard let name = parts.first else { return nil }
            let version = parts.dropFirst().joined(separator: " ")
            let paths = cellar.isEmpty ? [] : ["\(cellar)/\(name)"]
            return packageItem(.brewFormula, name: String(name), detail: "brew · \(version)", sizePaths: paths)
        }
    }

    private nonisolated func scanBrewCasks() -> [CleanupItem] {
        guard let out = try? Shell.runShell("brew list --cask") else { return [] }
        let prefix = (try? Shell.runShell("brew --prefix"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.split(separator: "\n").map { name in
            let paths = prefix.isEmpty ? [] : ["\(prefix)/Caskroom/\(name)"]
            return packageItem(.brewCask, name: String(name), detail: "brew cask", sizePaths: paths)
        }
    }

    private nonisolated func scanNpm() -> [CleanupItem] {
        guard let out = try? Shell.runShell("npm ls -g --depth=0 --json 2>/dev/null"),
              let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deps = obj["dependencies"] as? [String: Any] else { return [] }
        let npmRoot = (try? Shell.runShell("npm root -g"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return deps.keys.sorted().compactMap { name in
            if name == "npm" { return nil }
            let version = (deps[name] as? [String: Any])?["version"] as? String ?? ""
            let paths = npmRoot.isEmpty ? [] : ["\(npmRoot)/\(name)"]
            return packageItem(.npm, name: name, detail: "npm · \(version)", sizePaths: paths)
        }
    }

    private nonisolated func scanCargo() -> [CleanupItem] {
        guard let out = try? Shell.runShell("cargo install --list 2>/dev/null") else { return [] }
        let cargoHome = home + "/.cargo"
        var items: [CleanupItem] = []
        var pendingCrate: (name: String, detail: String)?
        var pendingBinaries: [String] = []

        func flush() {
            guard let crate = pendingCrate else { return }
            let paths = pendingBinaries.map { "\(cargoHome)/bin/\($0)" }
            if rustupShims.contains(crate.name) {
                items.append(packageItem(.cargo, name: crate.name, detail: "cargo",
                                         excluded: true, note: "rustup component — not removable via cargo"))
            } else {
                items.append(packageItem(.cargo, name: crate.name, detail: crate.detail, sizePaths: paths))
            }
        }

        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            let str = String(line)
            if let first = str.first, first != " " && first != "\t", str.hasSuffix(":") {
                // New crate header — flush previous
                flush()
                let header = String(str.dropLast())
                let name = String(header.split(separator: " ").first ?? "")
                let versionPart = header.split(separator: " ").dropFirst().joined(separator: " ")
                pendingCrate = (name, "cargo · \(versionPart)")
                pendingBinaries = []
            } else if str.hasPrefix("    ") || str.hasPrefix("\t") {
                // Binary name line under current crate
                let binary = str.trimmingCharacters(in: .whitespaces)
                if !binary.isEmpty { pendingBinaries.append(binary) }
            }
        }
        flush()
        return items
    }

    private nonisolated func scanPip() -> [CleanupItem] {
        guard let out = try? Shell.runShell("pip3 list --format=json 2>/dev/null"),
              let data = out.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let siteDir = (try? Shell.runShell(
            "python3 -c \"import site; print(site.getsitepackages()[0])\" 2>/dev/null"
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return arr.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let version = entry["version"] as? String ?? ""
            let paths = siteDir.isEmpty ? [] : ["\(siteDir)/\(name.lowercased())"]
            return packageItem(.pip3, name: name, detail: "pip3 · \(version)", sizePaths: paths)
        }
    }

    private nonisolated func scanGem() -> [CleanupItem] {
        guard let out = try? Shell.runShell("gem list --local 2>/dev/null") else { return [] }
        let rawGemDir = try? Shell.runShell("gem environment gemdir 2>/dev/null")
        let gemDir = rawGemDir?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.split(separator: "\n").compactMap { line -> CleanupItem? in
            let str = String(line)
            let parts = str.split(separator: " ")
            guard let name = parts.first else { return nil }
            // Extract first version from "(1.2.3, ...)"
            let versionRaw = parts.dropFirst().joined(separator: " ")
            let version = versionRaw
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .split(separator: ",").first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            let paths = (gemDir.isEmpty || version.isEmpty) ? [] : ["\(gemDir)/gems/\(name)-\(version)"]
            return packageItem(.gem, name: String(name), detail: "gem · \(versionRaw)", sizePaths: paths)
        }
    }

    private nonisolated func uninstallCommand(_ mgr: PackageManager, _ name: String) -> String {
        let q = Shell.shellQuote(name)
        switch mgr {
        case .brewFormula: return "brew uninstall \(q)"
        case .brewCask:    return "brew uninstall --cask \(q)"
        case .npm:         return "npm rm -g \(q)"
        case .cargo:       return "cargo uninstall \(q)"
        case .pip3:        return "pip3 uninstall -y \(q)"
        case .gem:         return "gem uninstall -x -a -I \(q)"
        }
    }

    // MARK: - Execute

    /// Deletes/uninstalls every provided item. Returns a human-readable log.
    func execute(_ items: [CleanupItem]) async -> String {
        var log = ""

        // 1. Non-privileged path removals — one batched rm off-main.
        let userPaths = items.flatMap { item -> [String] in
            if case let .removePaths(p) = item.action { return p } else { return [] }
        }
        if !userPaths.isEmpty {
            let cmd = "rm -rf " + userPaths.map(Shell.shellQuote).joined(separator: " ")
            let ok = await Task.detached {
                do { try Shell.runShell(cmd); return true } catch { return false }
            }.value
            log += ok ? "✓ Removed \(userPaths.count) user path(s)\n"
                      : "✗ Some user paths could not be removed\n"
        }

        // 2. Privileged removals — ONE admin prompt for everything.
        let adminPaths = items.flatMap { item -> [String] in
            if case let .removePathsPrivileged(p) = item.action { return p } else { return [] }
        }
        if !adminPaths.isEmpty {
            let cmd = "rm -rf " + adminPaths.map(Shell.shellQuote).joined(separator: " ")
            do {
                try Shell.runPrivileged(cmd)
                log += "✓ Removed \(adminPaths.count) system path(s)\n"
            } catch let e as ShellError {
                switch e {
                case .userCancelled: log += "✗ System removal cancelled (password prompt dismissed)\n"
                default: log += "✗ System removal failed: \(e)\n"
                }
            } catch {
                log += "✗ System removal failed: \(error)\n"
            }
        }

        // 3. Package uninstalls — sequential, off-main, per-item result.
        for item in items {
            guard case let .shellUninstall(mgr, name) = item.action else { continue }
            let cmd = uninstallCommand(mgr, name)
            let line = await Task.detached { () -> String in
                do { try Shell.runShell(cmd); return "✓ \(mgr.label): \(name)" }
                catch { return "✗ \(mgr.label): \(name) — \(error)" }
            }.value
            log += line + "\n"
        }

        return log.isEmpty ? "Nothing to do." : log
    }
}
