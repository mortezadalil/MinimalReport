import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let onDone: () -> Void

    // Provider
    @State private var provider: AIProvider = AISettings.shared.provider

    // GLM
    @State private var glmApiKey: String = AISettings.shared.glmApiKey
    @State private var glmModel: String = AISettings.shared.glmModel

    // OpenRouter
    @State private var orApiKey: String = AISettings.shared.openrouterApiKey
    @State private var orModel: String = AISettings.shared.openrouterModel

    // UI state
    @State private var showKey: Bool = false
    @State private var testState: TestState = .idle
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var loginItemError: String? = nil

    private enum TestState: Equatable { case idle, testing, ok, failed(String) }

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.12)
    private let fieldBg = Color(red: 0.15, green: 0.15, blue: 0.18)

    private let openRouterSuggestions: [String] = [
        "z-ai/glm-5.2",
        "z-ai/glm-4.5-air",
        "anthropic/claude-sonnet-4-5",
        "openai/gpt-4o",
        "google/gemini-2.5-flash",
        "meta-llama/llama-3.3-70b-instruct"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            Divider().overlay(Color.white.opacity(0.1))
            form
            Divider().overlay(Color.white.opacity(0.1))
            buttonBar
        }
        .frame(width: 440, height: dynamicHeight)
        .background(bg)
    }

    private var dynamicHeight: CGFloat {
        provider == .openrouter ? 410 : 350
    }

    // MARK: - Title

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.fill")
                .foregroundColor(.white.opacity(0.6))
            Text("Settings")
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Provider picker
            fieldRow(label: "Provider") {
                Picker("", selection: $provider) {
                    Text(AIProvider.glm.displayName).tag(AIProvider.glm)
                    Text(AIProvider.openrouter.displayName).tag(AIProvider.openrouter)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: provider) { _ in testState = .idle }
            }

            // API Key
            fieldRow(label: "API Key") {
                HStack(spacing: 6) {
                    Group {
                        if showKey {
                            TextField(keyPlaceholder, text: activeKeyBinding)
                        } else {
                            SecureField(keyPlaceholder, text: activeKeyBinding)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.white)

                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            // Model
            fieldRow(label: "Model") {
                TextField(modelPlaceholder, text: activeModelBinding)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            // OpenRouter model suggestions
            if provider == .openrouter {
                HStack(spacing: 12) {
                    Spacer().frame(width: 60)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Popular models — tap to fill:")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(openRouterSuggestions, id: \.self) { model in
                                    Button(model) { orModel = model }
                                        .buttonStyle(.plain)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(orModel == model ? .white : .white.opacity(0.65))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(orModel == model
                                            ? Color.accentColor.opacity(0.35)
                                            : Color.white.opacity(0.07))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(
                                            orModel == model ? Color.accentColor.opacity(0.6) : Color.clear,
                                            lineWidth: 1))
                                }
                            }
                        }
                    }
                }
            }

            // Launch at Login
            HStack(spacing: 12) {
                Spacer().frame(width: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $launchAtLogin) {
                        Text("Launch at Login")
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { enabled in setLaunchAtLogin(enabled) }

                    if let err = loginItemError {
                        Text(err).font(.caption2).foregroundColor(.red.opacity(0.8))
                    }
                }
            }

            // Feedback / Support
            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 12) {
                Spacer().frame(width: 60)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report a bug or suggest a feature")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                    Button {
                        if let url = URL(string: "https://support.bodoapp.com/minimalreport/") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope")
                            Text("Open Support Page")
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.18), value: provider)
    }

    private var keyPlaceholder: String {
        provider == .glm ? "Enter your GLM API key…" : "Enter your OpenRouter API key…"
    }

    private var modelPlaceholder: String {
        provider == .glm ? "e.g. glm-4.7" : "e.g. z-ai/glm-5.2"
    }

    private var activeKeyBinding: Binding<String> {
        provider == .glm ? $glmApiKey : $orApiKey
    }

    private var activeModelBinding: Binding<String> {
        provider == .glm ? $glmModel : $orModel
    }

    private func fieldRow<F: View>(label: String, @ViewBuilder field: () -> F) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 60, alignment: .trailing)
            field()
        }
    }

    // MARK: - Buttons

    private var buttonBar: some View {
        HStack(spacing: 10) {
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.18))
                .foregroundColor(.red.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            testResultView
            Spacer()

            Button(action: runTest) {
                HStack(spacing: 4) {
                    if case .testing = testState {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12).tint(.white)
                    }
                    Text("Test")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(activeKeyBinding.wrappedValue.isEmpty || testState == .testing)

            Button("Save") { saveAndClose() }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var testResultView: some View {
        switch testState {
        case .idle, .testing:
            EmptyView()
        case .ok:
            Label("OK", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundColor(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundColor(.red)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 160)
        }
    }

    // MARK: - Save

    private func saveAndClose() {
        AISettings.shared.provider = provider
        AISettings.shared.glmApiKey = glmApiKey
        AISettings.shared.glmModel = glmModel.isEmpty ? "glm-4.7" : glmModel
        AISettings.shared.openrouterApiKey = orApiKey
        AISettings.shared.openrouterModel = orModel.isEmpty ? "z-ai/glm-5.2" : orModel
        onDone()
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = !enabled
            loginItemError = error.localizedDescription
        }
    }

    // MARK: - Test Connection

    private func runTest() {
        testState = .testing
        // Temporarily apply in-flight values so GLMService sees them
        let saved = (AISettings.shared.provider,
                     AISettings.shared.glmApiKey, AISettings.shared.glmModel,
                     AISettings.shared.openrouterApiKey, AISettings.shared.openrouterModel)
        AISettings.shared.provider = provider
        AISettings.shared.glmApiKey = glmApiKey
        AISettings.shared.glmModel = glmModel.isEmpty ? "glm-4.7" : glmModel
        AISettings.shared.openrouterApiKey = orApiKey
        AISettings.shared.openrouterModel = orModel.isEmpty ? "z-ai/glm-5.2" : orModel

        Task {
            do {
                _ = try await GLMService.complete(messages: [
                    ["role": "user", "content": "Reply with only the word: OK"]
                ])
                testState = .ok
            } catch {
                testState = .failed(error.localizedDescription)
                // Restore original values on failure
                AISettings.shared.provider = saved.0
                AISettings.shared.glmApiKey = saved.1
                AISettings.shared.glmModel = saved.2
                AISettings.shared.openrouterApiKey = saved.3
                AISettings.shared.openrouterModel = saved.4
            }
        }
    }
}
