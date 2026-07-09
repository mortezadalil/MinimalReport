import Foundation

enum GLMError: Error, LocalizedError {
    case noKey
    case httpError(Int, String)
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "No API key configured. Open Settings and enter your API key."
        case .httpError(let code, let body):
            return "Server returned HTTP \(code). Check your API key in Settings.\n\(body)"
        case .apiError(let msg):
            return "API error: \(msg)"
        case .parseError:
            return "Could not parse the AI response. Try again."
        }
    }
}

enum GLMService {
    static func complete(messages: [[String: Any]]) async throws -> String {
        let settings = AISettings.shared
        let key = settings.activeApiKey
        guard !key.isEmpty else { throw GLMError.noKey }

        guard let url = URL(string: settings.provider.baseURL) else {
            throw GLMError.parseError
        }

        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenRouter attribution headers (optional but good practice)
        if settings.provider == .openrouter {
            req.setValue("https://github.com/morteza/MinimalReport", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("MinimalReport", forHTTPHeaderField: "X-Title")
        }

        var body: [String: Any] = [
            "model": settings.activeModel,
            "temperature": 0.3,
            "messages": messages
        ]

        // GLM-specific: disable chain-of-thought to avoid reasoning token overhead
        if settings.provider == .glm {
            body["thinking"] = ["type": "disabled"]
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw GLMError.httpError(statusCode, bodyStr)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = json?["error"] { throw GLMError.apiError("\(err)") }

        guard
            let choices = json?["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw GLMError.parseError }

        return content
    }
}
