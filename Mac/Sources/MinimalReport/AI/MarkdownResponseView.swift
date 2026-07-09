import SwiftUI
import AppKit

// MARK: - Public entry-point

struct MarkdownResponseView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parseDocument(text).enumerated()), id: \.offset) { i, seg in
                segmentView(seg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func segmentView(_ seg: DocSegment) -> some View {
        switch seg {
        case .heading(let lvl, let txt):
            HeadingView(level: lvl, text: txt)
                .padding(.top, 14).padding(.bottom, 6)

        case .paragraph(let txt):
            InlineMarkdown(txt)
                .padding(.bottom, 8)

        case .bullet(let txt, let lvl):
            BulletRow(text: txt, level: lvl)
                .padding(.bottom, 3)

        case .warningBox(let txt):
            WarningBox(text: txt)
                .padding(.bottom, 10)

        case .commandCard(let desc, let cmd):
            CommandCard(description: desc, command: cmd)
                .padding(.bottom, 8)

        case .spacer:
            Spacer().frame(height: 4)
        }
    }
}

// MARK: - Segment types

private enum DocSegment {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(text: String, level: Int)
    case warningBox(text: String)
    case commandCard(description: String?, command: String)
    case spacer
}

// MARK: - Parser

private func parseDocument(_ raw: String) -> [DocSegment] {
    var out: [DocSegment] = []
    let lines = raw.components(separatedBy: "\n")
    var i = 0

    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // ── blank
        if trimmed.isEmpty {
            i += 1
            continue
        }

        // ── code fence
        if trimmed.hasPrefix("```") {
            let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var codeLines: [String] = []
            i += 1
            while i < lines.count {
                let cl = lines[i].trimmingCharacters(in: .whitespaces)
                if cl.hasPrefix("```") { i += 1; break }
                codeLines.append(lines[i])
                i += 1
            }
            out.append(contentsOf: parseCommandCards(codeLines, language: lang))
            continue
        }

        // ── headings
        if trimmed.hasPrefix("### ") {
            out.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            i += 1; continue
        }
        if trimmed.hasPrefix("## ") {
            out.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            i += 1; continue
        }
        if trimmed.hasPrefix("# ") {
            out.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            i += 1; continue
        }

        // ── bullet (*, -, or indented)
        if let (txt, lvl) = bulletMatch(trimmed, original: line) {
            out.append(.bullet(text: txt, level: lvl))
            i += 1; continue
        }

        // ── warning / note box
        if isWarningLine(trimmed) {
            var block = [line]
            i += 1
            while i < lines.count {
                let nl = lines[i].trimmingCharacters(in: .whitespaces)
                if nl.isEmpty || nl.hasPrefix("#") || nl.hasPrefix("```") ||
                   nl.hasPrefix("* ") || nl.hasPrefix("- ") { break }
                block.append(lines[i])
                i += 1
            }
            out.append(.warningBox(text: block.joined(separator: " ")))
            continue
        }

        // ── paragraph: collect until blank / heading / fence / bullet / warning
        var para = [line]
        i += 1
        while i < lines.count {
            let nl = lines[i].trimmingCharacters(in: .whitespaces)
            if nl.isEmpty || nl.hasPrefix("#") || nl.hasPrefix("```") ||
               bulletMatch(nl, original: lines[i]) != nil || isWarningLine(nl) { break }
            para.append(lines[i])
            i += 1
        }
        out.append(.paragraph(text: para.joined(separator: "\n")))
    }

    return out
}

// Splits bash code lines into individual CommandCard segments.
// Groups: comment lines → description, non-empty non-comment lines → command.
private func parseCommandCards(_ lines: [String], language: String?) -> [DocSegment] {
    var result: [DocSegment] = []
    var descLines: [String] = []
    var cmdLines: [String] = []

    func flush() {
        guard !cmdLines.isEmpty else { return }
        let desc = descLines.isEmpty ? nil : descLines.joined(separator: " ")
        let cmd  = cmdLines.joined(separator: "\n")
        result.append(.commandCard(description: desc, command: cmd))
        descLines = []; cmdLines = []
    }

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            flush()
        } else if trimmed.hasPrefix("#") {
            if !cmdLines.isEmpty { flush() }
            let comment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !comment.isEmpty { descLines.append(comment) }
        } else {
            cmdLines.append(trimmed)
        }
    }
    flush()

    // Fallback: no recognisable structure → single code block
    if result.isEmpty {
        let allCode = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        if !allCode.isEmpty {
            result.append(.commandCard(description: nil, command: allCode))
        }
    }
    return result
}

private func bulletMatch(_ trimmed: String, original: String) -> (text: String, level: Int)? {
    let indent = original.prefix(while: { $0 == " " }).count
    let level = indent / 2
    for prefix in ["* ", "- ", "• "] {
        if trimmed.hasPrefix(prefix) {
            return (String(trimmed.dropFirst(prefix.count)), level)
        }
    }
    return nil
}

private func isWarningLine(_ text: String) -> Bool {
    let l = text.lowercased()
    return l.hasPrefix("**warning") || l.hasPrefix("warning:") || l.hasPrefix("⚠️") ||
           l.hasPrefix("🚨") || l.hasPrefix("**caution") || l.hasPrefix("**note:")
}

// MARK: - Sub-views

// Heading with accent bar for level 2, plain bold for others
private struct HeadingView: View {
    let level: Int
    let text: String

    var body: some View {
        switch level {
        case 1:
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Rectangle().fill(Color.accentColor.opacity(0.45)).frame(height: 1)
            }
        case 2:
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 18)
                    .cornerRadius(1.5)
                Text(text)
                    .font(.headline.bold())
                    .foregroundColor(.white)
            }
        default:
            Text(text)
                .font(.subheadline.bold())
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// Inline markdown (bold / italic / code)
private struct InlineMarkdown: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Group {
            if let attr = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            ) {
                Text(attr)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct BulletRow: View {
    let text: String
    let level: Int

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(level == 0 ? "●" : "○")
                .font(.system(size: 7))
                .foregroundColor(.accentColor.opacity(0.8))
                .padding(.top, 5)
            InlineMarkdown(text)
        }
        .padding(.leading, CGFloat(level) * 14)
    }
}

private struct WarningBox: View {
    let text: String

    // Strip common leading warning tokens so the icon conveys the severity
    private var cleanedText: String {
        var s = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["**WARNING:**", "**WARNING**:", "WARNING:", "**CAUTION:**",
                       "**NOTE:**", "⚠️", "🚨"] {
            if s.uppercased().hasPrefix(prefix.uppercased()) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return s
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))
                .padding(.top, 1)
            InlineMarkdown(cleanedText)
                .foregroundColor(.orange.opacity(0.95))
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }
}

// Each terminal command gets its own card: description label above, command + copy button.
private struct CommandCard: View {
    let description: String?
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let desc = description, !desc.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.38))
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                        .textSelection(.enabled)
                }
            }
            HStack(spacing: 0) {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(Color(red: 0.45, green: 0.92, blue: 0.58))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation { copied = false }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(copied ? .green : .white.opacity(0.55))
                    .frame(width: 50)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color(red: 0.08, green: 0.10, blue: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )
        }
    }
}

// Keep CodeBlockView public for potential reuse (e.g. AIAnalysisView)
struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                        Text(copied ? "Copied!" : "Copy").font(.caption2)
                    }
                    .foregroundColor(copied ? .green : .white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.05))
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(Color(red: 0.45, green: 0.92, blue: 0.58))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(red: 0.08, green: 0.10, blue: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}
