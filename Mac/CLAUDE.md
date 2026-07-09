# CLAUDE.md - MinimalReport

## Overview
**MinimalReport** is a minimal macOS menu bar app showing public IP address, country flag, and system stats (disk/RAM). Includes a powerful Disk Cleanup utility with AI-assisted analysis and per-item decision support via GLM (Z.ai) or OpenRouter LLMs.

## Tech Stack
- **Language**: Swift 5 language mode (with Swift 6 tools to avoid strict concurrency errors)
- **Package manager**: Swift Package Manager (SPM)
- **UI frameworks**: AppKit + SwiftUI hybrid (NSHostingController bridges SwiftUI into AppKit windows)
- **Minimum OS**: macOS 13+
- **App type**: LSUIElement (menu bar only, no dock icon, no app switcher)
- **External APIs**: IP detection (3 concurrent services), SystemPreferences, ServiceManagement, GLM/OpenRouter LLMs

## Build & Run

### Build
```bash
cd /Users/morteza/Documents/GitHub/MinimalReport/Mac   # all macOS sources live under Mac/
./build.sh                # Builds release binary and bundles into MinimalReport.app
./release.sh 1.0.0        # Build + package DMG/ZIP for a GitHub release
swift build -c release    # Manual build (build.sh handles bundling)
```

### Run
```bash
open MinimalReport.app
```

### LSUIElement Focus Trick
Since the app has no dock icon (`LSUIElement=YES`), windows are non-focusable by default. To open a focusable window:
```swift
NSApp.setActivationPolicy(.regular)
NSApp.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil)
```
Then revert in `windowWillClose`:
```swift
NSApp.setActivationPolicy(.accessory)
```

## Key Files & Structure

### Root
- **Package.swift** — SPM manifest (6.0, Swift 5 language mode)
- **Resources/Info.plist** — LSUIElement=YES, CFBundleIdentifier=com.morteza.minimalreport, NSAllowsArbitraryLoads=true
- **build.sh** — pkill prior instance, swift build -c release, bundle into .app
- **.gitignore** — .build/, MinimalReport.app/, .DS_Store, *.o, *.d

### Sources/MinimalReport/
- **main.swift** — NSApplication bootstrap
- **AppDelegate.swift** — status item, popover, polling loop (10s), window management
- **AppState.swift** — ObservableObject holding IP, flag, disk, RAM, refresh state
- **PopoverView.swift** — 280×300 dark SwiftUI popover with stats + Refresh + Disk Cleanup + Settings buttons
- **IPService.swift** — 3 concurrent APIs (ip-api.com, ipinfo.io, ipify.org), country code extraction
- **SystemStatsService.swift** — FileManager for disk, `host_statistics64` Mach call for RAM

### Sources/MinimalReport/Cleanup/
- **CleanupState.swift** — @MainActor state: items per category, sort order, selection, execution progress, AI queries
- **CleanupItem.swift** — struct with displayName, detail, size, category, action (removePaths / removePathsPrivileged / shellUninstall)
- **CleanupService.swift** — @MainActor: scan methods for trash, temp/cache, applications, packages; size resolution; execution with batched privileged deletes
- **CleanupWindowController.swift** — 700×540 window with onAIQuery callback
- **CleanupView.swift** — 5 tabs (Trash, Temp/Cache, Applications, Packages, AI Analysis); per-row sort toggle, size sort, AI buttons; item checklist with per-item copy/delete action icons
- **DirectorySizer.swift** — `du -sk` sizing off main thread, shared `formatBytes()`
- **Shell.swift** — `runShell()` (login zsh), `runPrivileged()` (NSAppleScript admin), shell quoting

### Sources/MinimalReport/AI/
- **AISettings.swift** — provider/model in UserDefaults; **API keys in the macOS Keychain** (never UserDefaults); enum AIProvider (glm, openrouter)
- **KeychainHelper.swift** — thin `Security.framework` wrapper (read/write/delete `kSecClassGenericPassword`) used for API keys
- **GLMService.swift** — URLSession client for both GLM (Z.ai endpoint) and OpenRouter; handles bearer auth, request/response parsing; GLM adds `"thinking":{"type":"disabled"}`, OpenRouter adds HTTP-Referer + X-Title headers
- **AIAnalysisState.swift** — @MainActor state: sampling phase, report text, activity snapshots
- **ActivitySampler.swift** — `top`, `vm_stat`, `df`, `iostat`, `ps`, `launchctl` sampling; formats structured text
- **AIAnalysisView.swift** — 10-second sampler with progress bar; sends to GLM with comprehensive system analyst prompt; renders report via MarkdownResponseView
- **AIQueryView.swift** — deletion safety / find cache queries; loads response into AIQueryWindowController
- **AIQueryWindowController.swift** — draggable NSWindow (isMovableByWindowBackground=true) for AI responses
- **MarkdownResponseView.swift** — modern report renderer: parses segments (headings, paragraphs, bullets, warning boxes, command cards); each command card has individual copy button; strips markdown symbols; renders inline bold/italic

### Sources/MinimalReport/Settings/
- **SettingsView.swift** — API key + model fields per provider, Launch at Login checkbox (SMAppService), Test Connection button, Quit button
- **SettingsWindowController.swift** — 440×360 draggable window for settings

## Architecture Decisions

### Swift 6 Tools + Swift 5 Language Mode
Using `swift-tools-version: 6.0` with `.swiftLanguageMode(.v5)` avoids strict concurrency errors while using modern Swift Package API. Main classes do NOT carry `@MainActor`; instead, `MainActor.run()` wraps updates.

### Cleanup Action Batching
All user-selected deletions are executed in ONE NSAppleScript call (single admin password prompt). Privileged and non-privileged paths are batched separately.

### Package Manager Paths
- Brew formulae: `$(brew --cellar)/<name>` (size resolved via `du -sk`)
- Brew casks: `$(brew --prefix)/Caskroom/<name>` (size resolved via `du -sk`)
- npm global: `$(npm root -g)/<name>` (size resolved via `du -sk`)
- Cargo: `~/.cargo/bin/<binary>` (multiple binaries per crate extracted from `cargo install --list` header lines)
- pip3: `$(python3 -c "import site; print(site.getsitepackages()[0])")/<name>` (size resolved via `du -sk`)
- gem: `$(gem environment gemdir)/gems/<name>-<version>` (size resolved via `du -sk`)
- Cargo rustup shims (rustup, cargo, rustc, etc.) are marked `isExcluded=true` and not deletable

### AI Features
- **Provider agnostic**: GLMService handles both GLM (Z.ai) and OpenRouter with appropriate headers/body differences
- **Per-window AI queries**: Deletion Safety Check and Find Cache open as independent draggable NSWindow instances, not sheets
- **Modern report rendering**: MarkdownResponseView parses response into typed segments and renders each with appropriate styling (headings, command cards, warning boxes)

## Common Commands

### Development
```bash
swift build -c release           # Build release binary
./build.sh                       # Full build + bundle
open MinimalReport.app           # Launch app
pkill -x MinimalReport           # Kill app
```

### Testing
IP Service returns on first-success from 3 APIs. Manually test with:
```bash
curl http://ip-api.com/json/?fields=query,countryCode
curl https://ipinfo.io/json
curl https://api.ipify.org?format=json
```

## Concurrency Notes
- No `@MainActor` on AppState (ObservableObject) — use `MainActor.run()` at update sites
- CleanupState and AIAnalysisState marked `@MainActor final`
- UIModel updates from background tasks: `withTaskGroup`, `Task.detached`
- Sheet/popover sizing is `NSSize`, window sizing is `NSRect`

## Settings
- Launch at Login: `SMAppService.mainApp.register()` / `.unregister()` (macOS 13+ native API)
- Non-sensitive prefs (UserDefaults): `minimalReport.aiProvider`, `minimalReport.glmModel`, `minimalReport.openrouterModel`
- **API keys (Keychain, service `com.morteza.minimalreport`)**: accounts `glmApiKey`, `openrouterApiKey` — never written to UserDefaults or logs
- On app quit: all in-flight windows close cleanly via `onClose` callbacks

## Styling
- Dark theme: background `Color(red:0.10, green:0.10, blue:0.10)`
- Popover/window size: 280×300 (popover), 700×540 (cleanup), 440×360 (settings), dynamic for AI query windows
- Font: system fonts with `.caption` / `.callout` / `.headline` semantic sizing
- Buttons: `.buttonStyle(.plain)` or custom styling
- Warning box: orange tint (`Color.orange.opacity(0.2)`), triangle icon
- Code card: green monospace (`Color(red:0.1, green:0.35, blue:0.1)`), border radius

## Last Active
2026-07-09