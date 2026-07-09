import SwiftUI
import AppKit

struct AIAnalysisView: View {
    @StateObject private var state = AIAnalysisState()

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.12)
    private let cardBg = Color(red: 0.13, green: 0.13, blue: 0.16)

    var body: some View {
        ZStack {
            bg
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .idle:
            idleView
        case .sampling(let progress, let label):
            samplingView(progress: progress, label: label)
        case .analyzing:
            analyzingView
        case .done:
            reportView
        case .failed(let msg):
            failedView(message: msg)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.25))

            VStack(spacing: 8) {
                Text("AI System Analysis")
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Text("Samples CPU, memory, and disk activity over 10 seconds, then asks the AI to identify unnecessary processes, memory hogs, and what you can safely remove.")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Text("Requires a GLM API key — set it via Settings below.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.35))

            Button(action: { state.startAnalysis() }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Start Analysis")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }

    // MARK: - Sampling

    private func samplingView(progress: Double, label: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 36))
                .foregroundColor(.accentColor.opacity(0.7))

            VStack(spacing: 10) {
                Text("Collecting System Data")
                    .font(.headline)
                    .foregroundColor(.white)

                ProgressView(value: progress)
                    .tint(.accentColor)
                    .frame(maxWidth: 340)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
                    .animation(.default, value: label)
            }
        }
        .padding(32)
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)

            Text("Analyzing with AI…")
                .font(.headline)
                .foregroundColor(.white)

            Text("This may take 20–40 seconds.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(32)
    }

    // MARK: - Report

    private var reportView: some View {
        VStack(spacing: 0) {
            reportHeader
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                reportContent
                    .padding(16)
            }
        }
    }

    private var reportHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("AI Analysis Report")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.report, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Copy report to clipboard")

            Button {
                state.reset()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Run analysis again")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var reportContent: some View {
        MarkdownResponseView(text: state.report)
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Analysis Failed")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(message)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button(action: { state.reset() }) {
                Text("Try Again")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }
}
