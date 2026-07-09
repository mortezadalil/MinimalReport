import Foundation

enum DirectorySizer {
    /// Returns size in bytes using `du -sk`. Returns 0 if the path is missing or
    /// `du` fails. Permission-denied noise on stderr is swallowed. Blocking —
    /// call off the main thread.
    static func size(of path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        proc.arguments = ["-sk", path]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return 0 }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let str = String(data: data, encoding: .utf8),
              let field = str.split(separator: "\t").first,
              let kb = Int64(field.trimmingCharacters(in: .whitespaces)) else { return 0 }
        return kb * 1024
    }

    /// Sum of sizes of several paths.
    static func size(ofAny paths: [String]) -> Int64 {
        paths.reduce(0) { $0 + size(of: $1) }
    }
}

/// Human-readable byte formatter, shared across the app.
func formatBytes(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "0 B" }
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    let mb = Double(bytes) / 1_048_576
    if mb >= 1 { return String(format: "%.0f MB", mb) }
    let kb = Double(bytes) / 1024
    return String(format: "%.0f KB", kb)
}
