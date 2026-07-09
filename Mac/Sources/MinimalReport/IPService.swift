import Foundation

struct IPResult {
    let ip: String
    let countryCode: String?
}

enum IPService {
    static func fetch() async -> IPResult? {
        await withTaskGroup(of: IPResult?.self) { group in
            group.addTask { await fetchFromIPAPI() }
            group.addTask { await fetchFromIPInfo() }
            group.addTask { await fetchFromIPify() }

            var fallback: IPResult? = nil
            for await result in group {
                guard let r = result else { continue }
                if r.countryCode != nil {
                    group.cancelAll()
                    return r
                }
                if fallback == nil { fallback = r }
            }
            return fallback
        }
    }

    private static func fetchFromIPAPI() async -> IPResult? {
        guard let url = URL(string: "http://ip-api.com/json/?fields=query,countryCode") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["query"] as? String else { return nil }
        return IPResult(ip: ip, countryCode: json["countryCode"] as? String)
    }

    private static func fetchFromIPInfo() async -> IPResult? {
        guard let url = URL(string: "https://ipinfo.io/json") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["ip"] as? String else { return nil }
        return IPResult(ip: ip, countryCode: json["country"] as? String)
    }

    private static func fetchFromIPify() async -> IPResult? {
        guard let url = URL(string: "https://api.ipify.org?format=json") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = json["ip"] as? String else { return nil }
        return IPResult(ip: ip, countryCode: nil)
    }
}
