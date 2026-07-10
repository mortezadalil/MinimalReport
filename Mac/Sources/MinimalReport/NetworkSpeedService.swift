import Foundation
import Darwin

struct NetCounters {
    let bytesIn: UInt64
    let bytesOut: UInt64
    static let zero = NetCounters(bytesIn: 0, bytesOut: 0)
}

enum NetworkSpeedService {
    static func readCounters() -> NetCounters {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return .zero }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr?.pointee {
            defer { ptr = current.ifa_next }
            guard let addr = current.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: current.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("eth") else { continue }
            guard let raw = current.ifa_data else { continue }

            let stats = raw.assumingMemoryBound(to: if_data.self).pointee
            totalIn  += UInt64(stats.ifi_ibytes)
            totalOut += UInt64(stats.ifi_obytes)
        }

        return NetCounters(bytesIn: totalIn, bytesOut: totalOut)
    }
}
