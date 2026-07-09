import Foundation
import Combine

class AppState: ObservableObject {
    @Published var ipAddress: String = "Fetching..."
    @Published var countryFlag: String = "🏳"
    @Published var diskTotal: Int64 = 0
    @Published var diskAvailable: Int64 = 0
    @Published var ramTotal: Int64 = 0
    @Published var ramAvailable: Int64 = 0
    @Published var isRefreshing: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var updateStatus: UpdateStatus = .idle

    var menuBarTitle: String { "\(countryFlag) \(ipAddress)" }

    var diskDisplay: String {
        guard diskTotal > 0 else { return "—" }
        return "\(formatBytes(diskAvailable)) free / \(formatBytes(diskTotal))"
    }

    var ramDisplay: String {
        guard ramTotal > 0 else { return "—" }
        return "\(formatBytes(ramAvailable)) free / \(formatBytes(ramTotal))"
    }

    func updateIP(address: String, countryCode: String?) {
        ipAddress = address
        countryFlag = countryCode.flatMap(flagEmoji) ?? "🏳"
        lastUpdated = Date()
    }

    func updateSystemStats(diskTotal: Int64, diskAvailable: Int64,
                           ramTotal: Int64, ramAvailable: Int64) {
        self.diskTotal = diskTotal
        self.diskAvailable = diskAvailable
        self.ramTotal = ramTotal
        self.ramAvailable = ramAvailable
    }

    private func flagEmoji(from code: String) -> String? {
        let base: UInt32 = 127397
        var result = ""
        for scalar in code.uppercased().unicodeScalars {
            guard let s = Unicode.Scalar(base + scalar.value) else { return nil }
            result.unicodeScalars.append(s)
        }
        return result.isEmpty ? nil : result
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
