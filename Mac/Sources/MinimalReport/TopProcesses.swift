import SwiftUI
import AppKit
import Foundation
import Darwin

/// Samples the top resource-consuming processes for the hover modals shown on
/// the RAM and Net rows of the popover.
enum TopProcesses {

    enum Kind { case memory, network }

    struct Row: Identifiable {
        let id = UUID()
        let pid: Int32
        let name: String
        let value: Int64     // bytes (memory) or bytes/sec (network)
        let display: String  // preformatted for the UI
    }

    /// Fetches the top 10 processes for the given resource, sorted high → low.
    static func fetch(_ kind: Kind) async -> [Row] {
        await Task.detached(priority: .userInitiated) {
            switch kind {
            case .memory:  return memory()
            case .network: return network()
            }
        }.value
    }

    /// Sends SIGTERM (graceful quit) or SIGKILL (force) to a process.
    static func terminate(pid: Int32, force: Bool) {
        guard pid > 0 else { return }
        _ = kill(pid, force ? SIGKILL : SIGTERM)
    }

    // MARK: - Memory (RSS via ps)

    private static func memory() -> [Row] {
        let out = run("/bin/ps", ["-Aceo", "pid,rss,comm", "-m"])
        var rows: [Row] = []
        for line in out.split(separator: "\n").dropFirst() {   // drop header
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2,
                                      omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let rssKB = Int64(parts[1]), rssKB > 0 else { continue }
            let name = String(parts[2]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let bytes = rssKB * 1024
            rows.append(Row(pid: pid, name: name, value: bytes, display: formatBytes(bytes)))
            if rows.count >= 20 { break }
        }
        return rows
    }

    // MARK: - Network (per-process rate via two nettop samples)

    private static func network() -> [Row] {
        let first = nettopSample()
        Thread.sleep(forTimeInterval: 0.8)
        let second = nettopSample()
        let perSecond = 1.0 / 0.8

        var rows: [Row] = []
        for (token, bytes) in second {
            let prev = first[token] ?? bytes
            let delta = max(0, bytes - prev)
            guard delta > 0 else { continue }
            let bps = Int64(Double(delta) * perSecond)
            rows.append(Row(pid: pid(from: token),
                            name: displayName(token),
                            value: bps,
                            display: formatRate(bps)))
        }
        return Array(rows.sorted { $0.value > $1.value }.prefix(20))
    }

    /// Returns [process.pid : cumulative bytes_in + bytes_out].
    private static func nettopSample() -> [String: Int64] {
        let out = run("/usr/bin/nettop", ["-P", "-x", "-l", "1", "-n"])
        var totals: [String: Int64] = [:]
        for line in out.split(separator: "\n") {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 4 else { continue }
            let proc = String(tokens[1])
            guard let bin = Int64(tokens[2]), let bout = Int64(tokens[3]) else { continue }
            totals[proc, default: 0] += bin + bout
        }
        return totals
    }

    private static func pid(from token: String) -> Int32 {
        if let dot = token.lastIndex(of: "."),
           let value = Int32(token[token.index(after: dot)...]) {
            return value
        }
        return -1
    }

    private static func displayName(_ token: String) -> String {
        if let dot = token.lastIndex(of: "."),
           token[token.index(after: dot)...].allSatisfy(\.isNumber) {
            return String(token[token.startIndex..<dot])
        }
        return token
    }

    // MARK: - Today's network totals (persisted daily baseline)

    /// Total bytes down / up since the first sample of the current day. Handles
    /// day rollover and counter resets (reboot) by re-baselining.
    static func todayNetTotals() -> (down: Int64, up: Int64) {
        let c = NetworkSpeedService.readCounters()
        let inNow = Int64(bitPattern: c.bytesIn)
        let outNow = Int64(bitPattern: c.bytesOut)

        let d = UserDefaults.standard
        let dayKey = Self.todayString()
        let inKey = "minimalReport.netBaseIn"
        let outKey = "minimalReport.netBaseOut"
        let dateKey = "minimalReport.netBaseDay"

        var baseIn = d.object(forKey: inKey) as? Int64 ?? inNow
        var baseOut = d.object(forKey: outKey) as? Int64 ?? outNow
        let storedDay = d.string(forKey: dateKey)

        // New day, first-ever run, or a counter reset (reboot) → re-baseline.
        if storedDay != dayKey || inNow < baseIn || outNow < baseOut {
            baseIn = inNow; baseOut = outNow
            d.set(baseIn, forKey: inKey)
            d.set(baseOut, forKey: outKey)
            d.set(dayKey, forKey: dateKey)
        }
        return (max(0, inNow - baseIn), max(0, outNow - baseOut))
    }

    private static func todayString() -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    // MARK: - Subprocess

    private static func run(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Formatting

    static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    private static func formatRate(_ bps: Int64) -> String {
        if bps < 1024 { return "\(bps) B/s" }
        if bps < 1_048_576 { return String(format: "%.0f KB/s", Double(bps) / 1024) }
        return String(format: "%.1f MB/s", Double(bps) / 1_048_576)
    }
}

// MARK: - Hover modal view

/// Modern card listing the top 10 processes for a resource, high → low.
struct TopProcessesView: View {
    let kind: TopProcesses.Kind
    /// Reports pointer enter/exit on the modal so the parent keeps it open
    /// while the mouse is over the card.
    var onHover: (Bool) -> Void = { _ in }

    @State private var rows: [TopProcesses.Row] = []
    @State private var loading = true
    @State private var todayDown: Int64 = 0
    @State private var todayUp: Int64 = 0

    private let bg = Color(red: 0.12, green: 0.12, blue: 0.14)

    private var title: String { kind == .memory ? "Top Memory" : "Top Network" }
    private var icon: String { kind == .memory ? "memorychip" : "network" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            content
        }
        .frame(width: 340)
        .background(bg)
        .onHover { onHover($0) }
        .task { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundColor(.accentColor)
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Spacer()
            }
            // Today's totals — only for the network modal.
            if kind == .network {
                HStack(spacing: 10) {
                    Text("Today")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                    Label {
                        Text(TopProcesses.formatBytes(todayDown))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    } icon: {
                        Image(systemName: "arrow.down")
                            .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.45))
                    }
                    Label {
                        Text(TopProcesses.formatBytes(todayUp))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    } icon: {
                        Image(systemName: "arrow.up")
                            .foregroundColor(Color(red: 1.0, green: 0.80, blue: 0.1))
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack { Spacer(); ProgressView().scaleEffect(0.7).tint(.white); Spacer() }
                .frame(height: 120)
        } else if rows.isEmpty {
            Text("No data")
                .font(.caption).foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        rowView(idx: idx, row: row)
                        if idx < rows.count - 1 {
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            // Default height ≈ 10 rows; the remaining items scroll.
            .frame(height: 360)
        }
    }

    private var maxValue: Double { Double(rows.map(\.value).max() ?? 1) }

    private func rowView(idx: Int, row: TopProcesses.Row) -> some View {
        HStack(spacing: 9) {
            Text("\(idx + 1)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 14, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.caption).foregroundColor(.white)
                    .lineLimit(1).truncationMode(.middle)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06)).frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.5)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * CGFloat(Double(row.value) / maxValue)),
                                   height: 4)
                    }
                }
                .frame(height: 4)
            }

            Text(row.display)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 60, alignment: .trailing)

            // Close / force-close (hold ⌥ to force) — quits the process.
            Button {
                let force = NSEvent.modifierFlags.contains(.option)
                TopProcesses.terminate(pid: row.pid, force: force)
                rows.removeAll { $0.id == row.id }          // optimistic
                Task { try? await Task.sleep(nanoseconds: 500_000_000); await reload() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Quit \(row.name) — hold ⌥ to force quit")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func reload() async {
        if kind == .network {
            let totals = TopProcesses.todayNetTotals()
            todayDown = totals.down
            todayUp = totals.up
        }
        let fetched = await TopProcesses.fetch(kind)
        rows = fetched
        loading = false
    }
}
