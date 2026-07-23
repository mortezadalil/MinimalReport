import Foundation
import Darwin

struct CPUSample {
    // 64-bit accumulators: each core's cpu_ticks are UInt32 and grow since boot,
    // so summing them across many cores in a UInt32 would overflow on long
    // uptimes (≈50 days on a 10-core machine). UInt64 removes that risk.
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var total: UInt64 { user + system + idle + nice }
    var used: UInt64 { user + system + nice }
}

enum CPUMemoryService {
    static func readCPUSample() -> CPUSample? {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let err = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard err == KERN_SUCCESS else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        let cpuLoadInfo = cpuInfo.withMemoryRebound(
            to: processor_cpu_load_info.self,
            capacity: Int(numCPUs)
        ) { $0 }

        for i in 0..<Int(numCPUs) {
            user   += UInt64(cpuLoadInfo[i].cpu_ticks.0)
            system += UInt64(cpuLoadInfo[i].cpu_ticks.1)
            idle   += UInt64(cpuLoadInfo[i].cpu_ticks.2)
            nice   += UInt64(cpuLoadInfo[i].cpu_ticks.3)
        }

        return CPUSample(user: user, system: system, idle: idle, nice: nice)
    }

    static func cpuUsagePercent(previous: CPUSample, current: CPUSample) -> Double {
        let totalDelta = Int(current.total) - Int(previous.total)
        let usedDelta = Int(current.used) - Int(previous.used)
        guard totalDelta > 0 else { return 0 }
        return min(100, max(0, Double(usedDelta) / Double(totalDelta) * 100))
    }

    static func memoryUsagePercent() -> Double {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard total > 0, let vm = SystemStatsService.vmStats() else { return 0 }

        let pageSize = Int64(vm_page_size)
        let available = (Int64(vm.free_count) + Int64(vm.inactive_count)) * pageSize
        let used = total - available
        return min(100, max(0, Double(used) / Double(total) * 100))
    }
}
