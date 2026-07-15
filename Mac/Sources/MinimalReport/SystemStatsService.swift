import Foundation
import Darwin

struct SystemStats {
    let diskTotal: Int64
    let diskAvailable: Int64
    let ramTotal: Int64
    let ramAvailable: Int64
}

enum SystemStatsService {
    static func fetch() -> SystemStats {
        let (diskTotal, diskAvail) = diskStats()
        let (ramTotal, ramAvail) = ramStats()
        return SystemStats(diskTotal: diskTotal, diskAvailable: diskAvail,
                           ramTotal: ramTotal, ramAvailable: ramAvail)
    }

    private static func diskStats() -> (Int64, Int64) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") else {
            return (0, 0)
        }
        let total = (attrs[.systemSize] as? Int).map(Int64.init) ?? 0
        let avail = (attrs[.systemFreeSize] as? Int).map(Int64.init) ?? 0
        return (total, avail)
    }

    /// Truly-free memory (free + speculative pages) in bytes. Rises after a
    /// `purge`, so it's the metric used to report how much was freed.
    static func freeMemory() -> Int64 {
        guard let vm = vmStats() else { return 0 }
        let pageSize = Int64(vm_page_size)
        return (Int64(vm.free_count) + Int64(vm.speculative_count)) * pageSize
    }

    static func vmStats() -> vm_statistics64? {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let ret = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return ret == KERN_SUCCESS ? vmStats : nil
    }

    private static func ramStats() -> (Int64, Int64) {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard let vmStats = vmStats() else { return (total, 0) }

        let pageSize = Int64(vm_page_size)
        let avail = (Int64(vmStats.free_count) + Int64(vmStats.inactive_count)) * pageSize
        return (total, avail)
    }
}
