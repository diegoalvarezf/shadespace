import Foundation
import IOKit.ps

struct SystemStats: Equatable {
    var cpuPct: Double = 0
    var ramUsedBytes: UInt64 = 0
    var ramTotalBytes: UInt64 = 1
    var batteryPct: Double? = nil
    var batteryCharging: Bool = false
    var ramPct: Double { Double(ramUsedBytes) / Double(ramTotalBytes) }
}

@MainActor
final class SystemStatsMonitor: ObservableObject {
    @Published private(set) var stats = SystemStats()
    private var timer: Timer?
    private var prevTicks: (UInt32, UInt32, UInt32, UInt32)?

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        stats = SystemStats(
            cpuPct: readCPU(),
            ramUsedBytes: readRAMUsed(),
            ramTotalBytes: ProcessInfo.processInfo.physicalMemory,
            batteryPct: readBatteryPct(),
            batteryCharging: readBatteryCharging()
        )
    }

    private func readCPU() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let ticks = (info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3)
        defer { prevTicks = ticks }
        guard let prev = prevTicks else { return 0 }
        let user = Double(ticks.0 &- prev.0)
        let sys  = Double(ticks.1 &- prev.1)
        let idle = Double(ticks.2 &- prev.2)
        let nice = Double(ticks.3 &- prev.3)
        let total = user + sys + idle + nice
        return total > 0 ? min((user + sys + nice) / total, 1) : 0
    }

    private func readRAMUsed() -> UInt64 {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let pageSize = UInt64(vm_kernel_page_size)
        return (UInt64(vmStats.active_count) + UInt64(vmStats.wire_count) + UInt64(vmStats.compressor_page_count)) * pageSize
    }

    private func readBatteryPct() -> Double? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              let cur = desc[kIOPSCurrentCapacityKey] as? Int,
              let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        return Double(cur) / Double(max)
    }

    private func readBatteryCharging() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { return false }
        return desc[kIOPSIsChargingKey] as? Bool ?? false
    }
}
