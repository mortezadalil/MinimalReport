import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var appState: AppState
    let onRefresh: () -> Void
    let onOpenCleanup: () -> Void
    let onOpenMemoryCleanup: () -> Void
    let onOpenSettings: () -> Void

    /// Which stat row is hovered (drives the top-processes modal).
    private enum HoverRow { case cpu, ram, net }
    @State private var hoveredRow: HoverRow?
    @State private var closeWork: DispatchWorkItem?

    /// Hover on the stat row itself.
    private func setHover(_ row: HoverRow, _ inside: Bool) {
        if inside {
            cancelClose()
            hoveredRow = row
        } else {
            scheduleClose()
        }
    }

    /// Hover reported by the modal — keeps it open while the pointer is over it.
    private func modalHover(_ inside: Bool) {
        if inside { cancelClose() } else { scheduleClose() }
    }

    private func cancelClose() {
        closeWork?.cancel()
        closeWork = nil
    }

    /// Close after a short grace period so the pointer can travel from the row
    /// onto the modal without it disappearing.
    private func scheduleClose() {
        closeWork?.cancel()
        let work = DispatchWorkItem { hoveredRow = nil }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func hoverBinding(_ row: HoverRow) -> Binding<Bool> {
        Binding(
            get: { hoveredRow == row },
            set: { if !$0, hoveredRow == row { hoveredRow = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            separator
            statRow(label: "IP", value: "\(appState.countryFlag)  \(appState.ipAddress)")
            statRow(label: "Disk", value: appState.diskDisplay)
            statRow(label: "CPU", value: appState.cpuDisplay)
                .contentShape(Rectangle())
                .onHover { inside in setHover(.cpu, inside) }
                .popover(isPresented: hoverBinding(.cpu), arrowEdge: .trailing) {
                    TopProcessesView(kind: .cpu, onHover: modalHover)
                }
            statRow(label: "RAM", value: "\(appState.memoryUsedDisplay) used · \(appState.ramDisplay)")
                .contentShape(Rectangle())
                .onHover { inside in setHover(.ram, inside) }
                .popover(isPresented: hoverBinding(.ram), arrowEdge: .trailing) {
                    TopProcessesView(kind: .memory, onHover: modalHover)
                }
            netRow
                .contentShape(Rectangle())
                .onHover { inside in setHover(.net, inside) }
                .popover(isPresented: hoverBinding(.net), arrowEdge: .trailing) {
                    TopProcessesView(kind: .network, onHover: modalHover)
                }
            Spacer(minLength: 8)
            refreshButton
            cleanupButton
            memoryCleanupButton
            settingsButton
            quitButton
            footerRow
        }
        .padding(20)
        .frame(width: 280, height: 475)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 18, height: 18)
            Text("Minimal Report")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            if let date = appState.lastUpdated {
                Text(date, style: .time)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
    }

    private var netRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Net")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 32, alignment: .leading)
            HStack(spacing: 6) {
                Text("↓")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.45))
                Text(appState.downloadSpeedDisplay)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.white)
                Text("↑")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundColor(Color(red: 1.0, green: 0.80, blue: 0.1))
                Text(appState.uploadSpeedDisplay)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            HStack(spacing: 6) {
                if appState.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 12, height: 12)
                        .tint(.white)
                }
                Text(appState.isRefreshing ? "Refreshing..." : "Refresh")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(appState.isRefreshing)
    }

    private var cleanupButton: some View {
        Button(action: onOpenCleanup) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("Disk Cleanup")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var memoryCleanupButton: some View {
        Button(action: onOpenMemoryCleanup) {
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                Text("Memory Cleanup")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                Text("Settings")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var quitButton: some View {
        Button { NSApp.terminate(nil) } label: {
            HStack(spacing: 6) {
                Image(systemName: "power")
                Text("Quit")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.red.opacity(0.18))
            .foregroundColor(.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    @ViewBuilder
    private var footerRow: some View {
        VStack(spacing: 4) {
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
            updateStatusLabel
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var updateStatusLabel: some View {
        switch appState.updateStatus {
        case .idle:
            Text("").font(.caption2)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.4).frame(width: 8, height: 8).tint(.white.opacity(0.5))
                Text("Checking…")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
        case .upToDate:
            Text("✓ App is up to date")
                .font(.caption2)
                .foregroundColor(.green.opacity(0.8))
        case .available(let latest):
            if let url = URL(string: "https://github.com/mortezadalil/MinimalReport/releases/latest") {
                Link(destination: url) {
                    Text("↑ New version available (\(latest))")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                        .underline()
                }
            } else {
                Text("↑ New version available (\(latest))")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 32, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}