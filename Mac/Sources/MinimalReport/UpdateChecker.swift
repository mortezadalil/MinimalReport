import Foundation

enum UpdateStatus {
    case idle
    case checking
    case upToDate
    case available(String) // latest version tag
}

enum UpdateChecker {
    static func check() async -> UpdateStatus {
        guard let url = URL(string: "https://api.github.com/repos/mortezadalil/MinimalReport/releases/latest") else {
            return .upToDate
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            return .upToDate
        }

        let latest  = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        return isNewer(latest, than: current) ? .available(latest) : .upToDate
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(av.count, bv.count) {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}
