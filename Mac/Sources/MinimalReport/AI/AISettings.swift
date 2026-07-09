import Foundation

enum AIProvider: String {
    case glm, openrouter

    var displayName: String {
        switch self {
        case .glm: return "GLM (Z.ai)"
        case .openrouter: return "OpenRouter"
        }
    }

    var baseURL: String {
        switch self {
        case .glm: return "https://api.z.ai/api/coding/paas/v4/chat/completions"
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .glm: return "glm-4.7"
        case .openrouter: return "z-ai/glm-5.2"
        }
    }
}

final class AISettings {
    static let shared = AISettings()
    private let defaults = UserDefaults.standard

    // Keychain keys for secrets
    private enum KeychainKey {
        static let glmApiKey         = "glmApiKey"
        static let openrouterApiKey  = "openrouterApiKey"
    }

    // UserDefaults keys for non-sensitive preferences
    private enum DefaultsKey {
        static let provider          = "minimalReport.aiProvider"
        static let glmModel          = "minimalReport.glmModel"
        static let openrouterModel   = "minimalReport.openrouterModel"
    }

    // MARK: - Provider (non-sensitive — UserDefaults)

    var provider: AIProvider {
        get {
            AIProvider(rawValue: defaults.string(forKey: DefaultsKey.provider) ?? "") ?? .glm
        }
        set { defaults.set(newValue.rawValue, forKey: DefaultsKey.provider) }
    }

    // MARK: - GLM

    /// API key stored in Keychain, never in UserDefaults.
    var glmApiKey: String {
        get { KeychainHelper.read(key: KeychainKey.glmApiKey) ?? "" }
        set {
            if newValue.isEmpty { KeychainHelper.delete(key: KeychainKey.glmApiKey) }
            else { KeychainHelper.write(key: KeychainKey.glmApiKey, value: newValue) }
        }
    }

    var glmModel: String {
        get { defaults.string(forKey: DefaultsKey.glmModel) ?? "glm-4.7" }
        set { defaults.set(newValue, forKey: DefaultsKey.glmModel) }
    }

    // MARK: - OpenRouter

    var openrouterApiKey: String {
        get { KeychainHelper.read(key: KeychainKey.openrouterApiKey) ?? "" }
        set {
            if newValue.isEmpty { KeychainHelper.delete(key: KeychainKey.openrouterApiKey) }
            else { KeychainHelper.write(key: KeychainKey.openrouterApiKey, value: newValue) }
        }
    }

    var openrouterModel: String {
        get { defaults.string(forKey: DefaultsKey.openrouterModel) ?? "z-ai/glm-5.2" }
        set { defaults.set(newValue, forKey: DefaultsKey.openrouterModel) }
    }

    // MARK: - Active (convenience)

    var activeApiKey: String {
        provider == .glm ? glmApiKey : openrouterApiKey
    }

    var activeModel: String {
        provider == .glm ? glmModel : openrouterModel
    }
}
