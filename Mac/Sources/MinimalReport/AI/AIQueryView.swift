import SwiftUI
import AppKit

enum AIQueryType {
    case deletionSafety
    case findCache
}

struct AIQueryRequest: Identifiable {
    let id = UUID()
    let item: CleanupItem
    let type: AIQueryType
}

struct AIQueryView: View {
    let request: AIQueryRequest
    let onClose: () -> Void

    @State private var isLoading = true
    @State private var result: String = ""
    @State private var errorMessage: String? = nil

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.12)

    var body: some View {
        ZStack {
            bg
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.1))
                bodyContent
                Divider().overlay(Color.white.opacity(0.1))
                footerBar
            }
        }
        .frame(minWidth: 540, minHeight: 400)
        .task { await performQuery() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: request.type == .deletionSafety ? "sparkles" : "doc.text.magnifyingglass")
                .foregroundColor(.accentColor)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(request.type == .deletionSafety ? "Deletion Safety Check" : "Find Cache")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(request.item.displayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        if isLoading {
            loadingView
        } else if let err = errorMessage {
            errorView(message: err)
        } else {
            responseView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.1).tint(.white)
            Text("Asking AI…")
                .font(.callout)
                .foregroundColor(.white.opacity(0.5))
            Text("This may take 10–30 seconds.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var responseView: some View {
        ScrollView {
            MarkdownResponseView(text: result)
                .padding(16)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if !result.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy All")
                    }
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("Close") { onClose() }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Query

    private func performQuery() async {
        let messages = buildMessages()
        do {
            let text = try await GLMService.complete(messages: messages)
            result = text
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func buildMessages() -> [[String: Any]] {
        let item = request.item
        let sizeStr = item.sizeResolved ? formatBytes(item.sizeBytes) : "unknown size"

        let userPrompt: String
        switch request.type {
        case .deletionSafety:
            userPrompt = """
            I have a macOS item called "\(item.displayName)".
            Path / detail: \(item.detail)
            Category: \(item.category.title)
            Disk usage: \(sizeStr)

            Please answer clearly and concisely:
            1. What exactly is this — a user app, system component, developer tool, or third-party service?
            2. Is it SAFE to permanently delete it? Will macOS or other apps break without it?
            3. What will I lose if I delete it?
            4. Are there any leftover files to clean after deletion?
            5. YOUR VERDICT on its own line:
               ✅ SAFE TO DELETE
               — or —
               ⚠️ DELETE WITH CAUTION (explain why)
               — or —
               🚫 DO NOT DELETE (explain why)

            Be direct. A non-technical user will act on your answer.
            """

        case .findCache:
            userPrompt = """
            I have a macOS application or package called "\(item.displayName)".
            Path / bundle / detail: \(item.detail)
            Category: \(item.category.title)

            Answer these three questions:

            ## Question 1 — Where are the caches?
            List every path where this app or package stores cache, temp, or log files on macOS.
            Use exact paths with ~/Library/... notation. Include all known locations such as:
            ~/Library/Caches/, ~/Library/Application Support/, ~/Library/Logs/, /Library/Caches/, and any app-specific hidden locations.

            ## Question 2 — Will deleting the cache break anything?
            For each path listed above answer: safe to delete YES/NO/ONLY-IF-APP-IS-CLOSED, and what is the side-effect (e.g. "app re-downloads assets", "you will be signed out", "settings reset").

            ## Question 3 — Terminal commands to clean
            Provide exact, ready-to-run Terminal commands using `rm -rf` to safely delete each cache path.
            Put ALL commands together in a single ```bash code block so the user can copy and run them at once.
            If the app must be quit first, say so before the code block.

            Be specific and accurate. If this app is unknown to you, say so clearly rather than guessing paths.
            """
        }

        let system = """
        You are an expert macOS system analyst. Give concise, accurate, actionable answers about macOS applications and files. \
        Format your response using Markdown: use ## headings, **bold** for important terms, and ```bash code blocks for all Terminal commands. \
        Always distinguish between safe-to-remove items and system-critical ones.
        """

        return [
            ["role": "system", "content": system],
            ["role": "user", "content": userPrompt]
        ]
    }
}
