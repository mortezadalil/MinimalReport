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

    // Network speed monitoring
    private var prevCounters: NetCounters = .zero
    private var prevCounterTime: Date = Date()
    private var downSamples: [Double] = Array(repeating: 0, count: 5)
    private var upSamples: [Double]   = Array(repeating: 0, count: 5)
    private var networkTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeState()
        startNetworkMonitor()
        Task { await performRefresh() }
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        networkTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🏳 Fetching..."
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 365)
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
            .sink { [weak self] _, _ in self?.updateMenuTitle() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuTitle),
            name: NSNotification.Name("minimalReport.ipSettingChanged"),
            object: nil
        )
    }

    @objc private func updateMenuTitle() {
        let ip = appState.ipAddress
        let flag = appState.countryFlag
        let showIp = UserDefaults.standard.object(forKey: Self.showIpKey) as? Bool ?? true
        statusItem.button?.title = showIp ? "\(flag) \(ip)" : flag
    }

    // MARK: - Network speed

    private static let networkSpeedKey = "minimalReport.showNetworkSpeed"
    private static let showIpKey = "minimalReport.showIpInMenuBar"

    private var networkSpeedEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.networkSpeedKey) as? Bool ?? true
    }

    private func startNetworkMonitor() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyNetworkSpeedVisibility),
            name: NSNotification.Name("minimalReport.networkSpeedSettingChanged"),
            object: nil
        )
        prevCounters = NetworkSpeedService.readCounters()
        prevCounterTime = Date()
        networkTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(tickNetworkSpeed),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(networkTimer!, forMode: .common)
    }

    @objc private func applyNetworkSpeedVisibility() {
        if !networkSpeedEnabled {
            statusItem.button?.image = nil
        }
    }

    @objc private func tickNetworkSpeed() {
        let now = Date()
        let counters = NetworkSpeedService.readCounters()
        let dt = now.timeIntervalSince(prevCounterTime)

        if dt > 0.5 && dt < 5 {
            let downBytes = counters.bytesIn >= prevCounters.bytesIn
                ? Double(counters.bytesIn - prevCounters.bytesIn) : 0
            let upBytes = counters.bytesOut >= prevCounters.bytesOut
                ? Double(counters.bytesOut - prevCounters.bytesOut) : 0

            let downBps = downBytes / dt
            let upBps   = upBytes   / dt

            downSamples.removeFirst(); downSamples.append(Self.normalizeSpeed(downBps))
            upSamples.removeFirst();   upSamples.append(Self.normalizeSpeed(upBps))

            appState.updateNetworkSpeed(download: downBps, upload: upBps)

            if networkSpeedEnabled {
                statusItem.button?.image = Self.makeNetworkImage(
                    downBps: downBps, upBps: upBps,
                    downSamples: downSamples, upSamples: upSamples)
            }
        }

        prevCounters = counters
        prevCounterTime = now
    }

    private static func normalizeSpeed(_ bps: Double) -> Double {
        guard bps > 0 else { return 0 }
        // Log scale: 0 at 0 bps, 1.0 at ~100 MB/s
        return min(1.0, log10(1.0 + bps / 1000.0) / 5.0)
    }

    private static func formatSpeedShort(_ bps: Double) -> String {
        if bps < 1024       { return "0 KB/s" }
        if bps < 1_048_576  { return String(format: "%.1f KB/s", bps / 1024) }
        return String(format: "%.1f MB/s", bps / 1_048_576)
    }

    private static func makeNetworkImage(
        downBps: Double, upBps: Double,
        downSamples: [Double], upSamples: [Double]
    ) -> NSImage {
        let rowH: CGFloat  = 11      // height of each speed row
        let imgH: CGFloat  = rowH * 2
        let barW: CGFloat  = 3
        let barGap: CGFloat = 1
        let n = 5
        let barsW = CGFloat(n) * barW + CGFloat(n - 1) * barGap   // 19pt
        let textGap: CGFloat = 4

        let greenColor  = NSColor(red: 0.2,  green: 0.85, blue: 0.45, alpha: 1.0)
        let yellowColor = NSColor(red: 1.0,  green: 0.80, blue: 0.1,  alpha: 1.0)

        let font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
        let downText = formatSpeedShort(downBps) as NSString
        let upText   = formatSpeedShort(upBps)   as NSString

        let downAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: greenColor]
        let upAttrs:   [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: yellowColor]

        let textW = max(downText.size(withAttributes: downAttrs).width,
                        upText.size(withAttributes: upAttrs).width)
        let imgW = ceil(textW) + textGap + barsW

        let image = NSImage(size: NSSize(width: imgW, height: imgH), flipped: false) { _ in
            // ── Top row: download (green) ──────────────────────────────
            let downSz = downText.size(withAttributes: downAttrs)
            downText.draw(at: NSPoint(x: 0, y: rowH + (rowH - downSz.height) / 2),
                          withAttributes: downAttrs)

            let barX = ceil(textW) + textGap
            greenColor.setFill()
            for i in 0..<n {
                let norm = CGFloat(i < downSamples.count ? downSamples[i] : 0)
                let h = max(1.5, norm * (rowH - 1))
                let x = barX + CGFloat(i) * (barW + barGap)
                NSBezierPath(roundedRect: NSRect(x: x, y: rowH + (rowH - h) / 2,
                                                  width: barW, height: h),
                             xRadius: 0.5, yRadius: 0.5).fill()
            }

            // ── Bottom row: upload (yellow) ────────────────────────────
            let upSz = upText.size(withAttributes: upAttrs)
            upText.draw(at: NSPoint(x: 0, y: (rowH - upSz.height) / 2),
                        withAttributes: upAttrs)

            yellowColor.setFill()
            for i in 0..<n {
                let norm = CGFloat(i < upSamples.count ? upSamples[i] : 0)
                let h = max(1.5, norm * (rowH - 1))
                let x = barX + CGFloat(i) * (barW + barGap)
                NSBezierPath(roundedRect: NSRect(x: x, y: (rowH - h) / 2,
                                                  width: barW, height: h),
                             xRadius: 0.5, yRadius: 0.5).fill()
            }

            return true
        }
        image.isTemplate = false
        return image
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
            checkForUpdates()
        }
    }

    // MARK: - Update check

    private func checkForUpdates() {
        Task { @MainActor in
            if case .checking = appState.updateStatus { return }
            appState.updateStatus = .checking
            let status = await UpdateChecker.check()
            appState.updateStatus = status
        }
    }
}
