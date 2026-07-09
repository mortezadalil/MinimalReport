import SwiftUI
import AppKit

struct CleanupView: View {
    @ObservedObject var state: CleanupState
    let service: CleanupService
    let onAIQuery: (AIQueryRequest) -> Void

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.selectedTab) {
                ForEach(CleanupCategory.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider().overlay(Color.white.opacity(0.12))

            if state.selectedTab == .aiAnalysis {
                AIAnalysisView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                checklist
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .background(bg)
        .task { await service.scanAll(into: state) }
    }

    // MARK: - Checklist

    private var sortIcon: String {
        switch state.sizeSort {
        case .none:       return "↕"
        case .descending: return "↓"
        case .ascending:  return "↑"
        }
    }

    private var checklist: some View {
        let cat = state.selectedTab
        let items = state.sortedItems(for: cat)
        return VStack(spacing: 0) {
            listHeader(cat: cat, items: items)
            Divider().overlay(Color.white.opacity(0.08))
            if items.isEmpty {
                emptyState(cat: cat)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item, cat: cat)
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
    }

    private func listHeader(cat: CleanupCategory, items: [CleanupItem]) -> some View {
        HStack(spacing: 10) {
            Button(action: { state.setAllSelected(true, for: cat) }) {
                Text("Select all").font(.caption)
            }.buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
            Button(action: { state.setAllSelected(false, for: cat) }) {
                Text("None").font(.caption)
            }.buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
            Spacer()
            if state.scanning(cat) {
                ProgressView().scaleEffect(0.5).frame(width: 14, height: 14).tint(.white)
                Text("Scanning…").font(.caption2).foregroundColor(.white.opacity(0.4))
            } else {
                Button(action: { state.cycleSizeSort() }) {
                    HStack(spacing: 3) {
                        Text("Size")
                        Text(sortIcon)
                            .opacity(state.sizeSort == .none ? 0.35 : 1)
                    }
                    .font(.caption)
                    .foregroundColor(state.sizeSort == .none ? .white.opacity(0.5) : .white)
                }
                .buttonStyle(.plain)
                Text("· \(items.count)")
                    .font(.caption2).foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func emptyState(cat: CleanupCategory) -> some View {
        VStack {
            Spacer()
            Text(state.scanning(cat) ? "Scanning…" : "Nothing found here.")
                .font(.callout).foregroundColor(.white.opacity(0.4))
            Spacer()
        }
    }

    private func row(_ item: CleanupItem, cat: CleanupCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(item.isExcluded ? .white.opacity(0.2)
                                 : (item.isSelected ? .accentColor : .white.opacity(0.5)))
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(.callout, design: .default))
                        .foregroundColor(item.isExcluded ? .white.opacity(0.35) : .white)
                    if item.needsAdmin {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9)).foregroundColor(.orange.opacity(0.8))
                    }
                }
                Text(item.isExcluded && !item.exclusionNote.isEmpty ? item.exclusionNote : item.detail)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            if !item.isExcluded {
                aiButtons(item: item)
            }

            if item.sizeResolved {
                Text(formatBytes(item.sizeBytes))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(minWidth: 52, alignment: .trailing)
            } else {
                ProgressView().scaleEffect(0.45).frame(width: 12, height: 12).tint(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { if !item.isExcluded { state.toggle(itemID: item.id, cat: cat) } }
        .opacity(item.isExcluded ? 0.6 : 1)
    }

    private func aiButtons(item: CleanupItem) -> some View {
        HStack(spacing: 4) {
            aiButton(icon: "sparkles", tooltip: "Ask AI: is it safe to permanently delete this?") {
                onAIQuery(AIQueryRequest(item: item, type: .deletionSafety))
            }
            aiButton(icon: "doc.text.magnifyingglass", tooltip: "Find Cache: where this app stores caches and how to clean them") {
                onAIQuery(AIQueryRequest(item: item, type: .findCache))
            }
        }
    }

    private func aiButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.7))
            .frame(width: 26, height: 22)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.12))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected: \(formatBytes(state.totalSelectedSize))")
                        .font(.system(.callout, design: .monospaced)).foregroundColor(.white)
                    Text("\(state.selectedItems.count) item(s)\(state.anyNeedsAdmin ? " · admin required" : "")")
                        .font(.caption2).foregroundColor(.white.opacity(0.45))
                }
                Spacer()
                if state.isExecuting {
                    ProgressView().scaleEffect(0.6).tint(.white).padding(.trailing, 6)
                }
                Button(action: confirmAndClean) {
                    Text("Clean Selected")
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(state.selectedItems.isEmpty ? Color.white.opacity(0.08) : Color.red.opacity(0.85))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(state.selectedItems.isEmpty || state.isExecuting)
            }
            .padding(16)
        }
    }

    // MARK: - Confirm + execute

    private func confirmAndClean() {
        let selected = state.selectedItems
        guard !selected.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Permanently delete \(selected.count) item(s)?"
        var info = "This will PERMANENTLY delete \(formatBytes(state.totalSelectedSize)). "
        info += "Items are NOT moved to Trash and cannot be recovered."
        if state.anyNeedsAdmin {
            info += "\n\nYou will be asked for your administrator password."
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            state.isExecuting = true
            let log = await service.execute(selected)
            state.lastResultLog = log
            state.isExecuting = false
            await service.scanAll(into: state)
            showResult(log)
        }
    }

    private func showResult(_ log: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Cleanup complete"
        alert.informativeText = log
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
