import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState = AppState()
    private var pollingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var cleanupWindowController: CleanupWindowController?
    private var settingsWindowController: SettingsWindowController?

    /// How often IP + system stats are auto-refreshed.
    private static let pollInterval: UInt64 = 10_000_000_000 // 10s in nanoseconds

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeState()
        Task { await performRefresh() }
        startPolling()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🏳 Fetching..."
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 300)
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                appState: appState,
                onRefresh: { [weak self] in Task { await self?.performRefresh() } },
                onOpenCleanup: { [weak self] in Task { @MainActor in self?.openCleanup() } },
                onOpenSettings: { [weak self] in Task { @MainActor in self?.openSettings() } }
            )
        )
    }

    private func observeState() {
        appState.$ipAddress
            .combineLatest(appState.$countryFlag)
            .receive(on: RunLoop.main)
            .sink { [weak self] ip, flag in
                self?.statusItem.button?.title = "\(flag) \(ip)"
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh

    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                guard !Task.isCancelled else { break }
                await performRefresh()
            }
        }
    }

    private func performRefresh() async {
        await MainActor.run { appState.isRefreshing = true }

        async let ipFetch = IPService.fetch()
        async let statsFetch = Task.detached(priority: .userInitiated) {
            SystemStatsService.fetch()
        }.value

        let (ip, stats) = await (ipFetch, statsFetch)

        await MainActor.run {
            if let r = ip {
                self.appState.updateIP(address: r.ip, countryCode: r.countryCode)
            }
            self.appState.updateSystemStats(
                diskTotal: stats.diskTotal,
                diskAvailable: stats.diskAvailable,
                ramTotal: stats.ramTotal,
                ramAvailable: stats.ramAvailable
            )
            self.appState.isRefreshing = false
        }
    }

    // MARK: - Disk Cleanup window

    @MainActor
    private func openCleanup() {
        popover.performClose(nil)
        if cleanupWindowController == nil {
            let wc = CleanupWindowController()
            wc.onClose = { [weak self] in self?.cleanupWindowController = nil }
            cleanupWindowController = wc
        }
        cleanupWindowController?.showFocused()
    }

    // MARK: - Settings window

    @MainActor
    private func openSettings() {
        popover.performClose(nil)
        if settingsWindowController == nil {
            let wc = SettingsWindowController()
            wc.onClose = { [weak self] in self?.settingsWindowController = nil }
            settingsWindowController = wc
        }
        settingsWindowController?.showFocused()
    }

    // MARK: - Popover toggle

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }
}
