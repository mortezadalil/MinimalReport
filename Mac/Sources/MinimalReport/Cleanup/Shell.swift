import Foundation

enum ShellError: Error, CustomStringConvertible {
    case nonZeroExit(Int32, String)
    case scriptError(String)
    case userCancelled

    var description: String {
        switch self {
        case .nonZeroExit(let code, let msg):
            return "exit \(code): \(msg.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .scriptError(let msg):
            return msg
        case .userCancelled:
            return "cancelled"
        }
    }
}

enum Shell {

    /// Run a non-privileged command through a login zsh so PATH includes
    /// /opt/homebrew/bin, ~/.cargo/bin and the npm prefix — exactly as in Terminal.
    @discardableResult
    static func runShell(_ command: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", command]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            throw ShellError.nonZeroExit(proc.terminationStatus, stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }

    /// Run a command with administrator privileges via the native macOS password
    /// dialog (Touch ID capable). NSAppleScript is not thread-safe — call on main.
    @MainActor
    @discardableResult
    static func runPrivileged(_ command: String) throws -> String {
        let escaped = appleScriptEscape(command)
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw ShellError.scriptError("could not compile AppleScript")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let err = errorInfo {
            let number = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
            if number == -128 { throw ShellError.userCancelled }
            let msg = err["NSAppleScriptErrorMessage"] as? String ?? "\(err)"
            throw ShellError.scriptError(msg)
        }
        return result.stringValue ?? ""
    }

    /// Escape a string for embedding inside an AppleScript double-quoted literal.
    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Single-quote a path token so spaces/metacharacters survive the shell.
    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
