import SwiftUI
import AppKit

/// Memory Cleanup window. Runs the system `purge` command (admin) to flush disk
/// caches / release inactive memory, and — more effectively — lets the user
/// quit the biggest memory consumers. The copy is intentionally honest about
/// how little "freeing RAM" usually matters on macOS.
struct MemoryCleanupView: View {
    let onClose: () -> Void

    @State private var freeNow: Int64 = 0
    @State private var lastFreed: Int64? = nil
    @State private var running = false
    @State private var statusMessage: String? = nil
    @State private var topApps: [TopProcesses.Row] = []

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.12)
    private let cardBg = Color(red: 0.15, green: 0.15, blue: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    explanation
                    freeMemoryCard
                    biggestUsers
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 580)
        .background(bg)
        .task { await refresh() }
    }

    // MARK: - Title

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "memorychip.fill").foregroundColor(.accentColor)
            Text("Memory Cleanup").font(.headline).foregroundColor(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Honest explanation (English)

    private var explanation: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.accentColor.opacity(0.9))
                .font(.system(size: 14))
            Text("""
            macOS manages memory automatically with compression and caching, so a low \
            "free memory" number is usually not a problem — inactive and cached memory \
            is already available to apps the moment they need it.

            This tool runs the built-in `purge` command (which needs your admin \
            password) to flush disk caches and release inactive memory. The effect is \
            often small — especially on Apple Silicon — and the caches simply rebuild \
            as you keep working, so this is mostly cosmetic.

            The real way to free memory is to quit the apps using the most of it, \
            listed below.
            """)
            .font(.caption)
            .foregroundColor(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Free memory + purge action

    private var freeMemoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Free memory").font(.caption).foregroundColor(.white.opacity(0.5))
                        Button { Task { await refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help("Refresh free memory")
                    }
                    Text(TopProcesses.formatBytes(freeNow))
                        .font(.system(.title2, design: .monospaced))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: runPurge) {
                    HStack(spacing: 6) {
                        if running {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14).tint(.white)
                            Text("Purging…")
                        } else {
                            Image(systemName: "wand.and.sparkles")
                            Text("Free Inactive Memory")
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(running ? 0.4 : 0.85))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(running)
            }

            if let freed = lastFreed {
                Label(freed > 0
                      ? "Freed ~\(TopProcesses.formatBytes(freed))"
                      : "Little to free — memory was already optimized",
                      systemImage: freed > 0 ? "checkmark.circle.fill" : "info.circle")
                    .font(.caption)
                    .foregroundColor(freed > 0 ? .green : .white.opacity(0.5))
            }
            if let msg = statusMessage {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.orange)
            }
        }
        .padding(14)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Biggest memory users

    private var biggestUsers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Biggest memory users")
                .font(.subheadline.weight(.semibold)).foregroundColor(.white)
            if topApps.isEmpty {
                Text("Loading…").font(.caption).foregroundColor(.white.opacity(0.4))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(topApps.enumerated()), id: \.element.id) { idx, row in
                        appRow(idx: idx, row: row)
                        if idx < topApps.count - 1 {
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
                .background(cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func appRow(idx: Int, row: TopProcesses.Row) -> some View {
        HStack(spacing: 10) {
            Text("\(idx + 1)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.35)).frame(width: 16, alignment: .trailing)
            Text(row.name).font(.caption).foregroundColor(.white)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(row.display)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Button {
                let force = NSEvent.modifierFlags.contains(.option)
                TopProcesses.terminate(pid: row.pid, force: force)
                topApps.removeAll { $0.id == row.id }
                Task { try? await Task.sleep(nanoseconds: 500_000_000); await refresh() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Quit \(row.name) — hold ⌥ to force quit")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    // MARK: - Actions

    private func refresh() async {
        freeNow = SystemStatsService.freeMemory()
        let fetched = await TopProcesses.fetch(.memory)
        topApps = Array(fetched.prefix(20))
    }

    private func runPurge() {
        running = true
        statusMessage = nil
        lastFreed = nil
        let before = SystemStatsService.freeMemory()

        Task { @MainActor in
            do {
                try Shell.runPrivileged("/usr/sbin/purge")
                // Give the kernel a moment, then re-measure.
                try? await Task.sleep(nanoseconds: 400_000_000)
                let after = SystemStatsService.freeMemory()
                freeNow = after
                lastFreed = max(0, after - before)
            } catch let e as ShellError {
                if case .userCancelled = e {
                    statusMessage = "Cancelled — admin password required."
                } else {
                    statusMessage = e.description
                }
            } catch {
                statusMessage = error.localizedDescription
            }
            running = false
        }
    }
}
