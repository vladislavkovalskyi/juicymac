import Darwin
import Foundation
import IOKit
import IOKit.ps
import JuicyCore

public final class BatterySampler {
    public init() {}

    public func sample() -> BatteryStats? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (description[minutesKey] as? Int).flatMap { $0 > 0 ? $0 : nil }

            var stats = BatteryStats(
                level: maximum > 0 ? Double(current) / Double(maximum) : 0,
                isCharging: charging,
                isPluggedIn: pluggedIn,
                minutesRemaining: pluggedIn && !charging ? nil : minutes
            )
            fillRegistry(&stats)
            if pluggedIn, let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
                stats.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
            }
            return stats
        }
        return nil
    }

    private func fillRegistry(_ stats: inout BatteryStats) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }

        // Apple silicon keeps the capacities in a nested "BatteryData" dictionary.
        let data = dict["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> NSNumber? { (dict[key] ?? data[key]) as? NSNumber }
        stats.cycleCount = number("CycleCount")?.intValue
        stats.designCapacity = number("DesignCapacity")?.intValue
        stats.maxCapacity = (number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity") ?? number("FullChargeCapacity"))?.intValue
        if let t = number("Temperature")?.doubleValue { stats.temperature = t / 100 }
        if let v = number("Voltage")?.doubleValue { stats.voltage = v / 1000 }
        // Amperage is signed but IOKit may hand it back as a large unsigned value.
        if let a = (number("InstantAmperage") ?? number("Amperage"))?.int64Value { stats.amperage = Double(a) / 1000 }
    }
}

public final class GPUSampler {
    public init() {}

    public func sample() -> GPUStats {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return GPUStats()
        }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let utilization = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, utilization / 100)
        }
        return GPUStats(usage: best.map { min(1, max(0, $0)) })
    }
}

public final class ProcessSampler {
    private var previous: [Int32: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private var names: [Int32: String] = [:]
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(1, info.denom)))
    }()

    public init() {}

    /// Top processes by CPU since the previous call. Processes of other users are skipped (no permission).
    public func sample(limit: Int = 8) -> [ProcessUsage] {
        let now = mach_absolute_time()
        let elapsedNs = Double((now - previousTime) * timebase.numer / timebase.denom)
        let first = previousTime == 0
        previousTime = now

        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }

        var current: [Int32: UInt64] = [:]
        var usage: [ProcessUsage] = []
        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard ok == 0 else { continue }
            let cpu = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
            current[pid] = cpu
            guard !first, elapsedNs > 0, let old = previous[pid], cpu >= old else { continue }
            let percent = Double(cpu - old) / elapsedNs * 100
            usage.append(ProcessUsage(pid: pid, name: name(of: pid), cpuPercent: percent, memoryBytes: info.ri_phys_footprint))
        }
        previous = current
        names = names.filter { current[$0.key] != nil }
        return Array(usage.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
    }

    private func name(of pid: Int32) -> String {
        if let cached = names[pid] { return cached }
        let resolved = Self.resolveName(pid)
        names[pid] = resolved
        return resolved
    }

    /// Prefers the innermost ".app" bundle name ("Google Chrome Helper (Renderer)"), else the executable name.
    static func resolveName(_ pid: Int32) -> String {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            let path = SystemInfo.string(pathBuffer)
            if let app = path.split(separator: "/").last(where: { $0.hasSuffix(".app") }) {
                return String(app.dropLast(4))
            }
            if let last = path.split(separator: "/").last { return String(last) }
        }
        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let name = SystemInfo.string(nameBuffer)
        return name.isEmpty ? "pid \(pid)" : name
    }
}
