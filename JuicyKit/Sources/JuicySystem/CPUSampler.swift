import Darwin
import Foundation
import JuicyCore

public struct CoreTicks: Sendable, Equatable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUMath {
    /// Per-core usage plus user/system split from two tick readings. Counters wrap at 2^32.
    public static func usage(from old: [CoreTicks], to new: [CoreTicks]) -> (cores: [Double], user: Double, system: Double) {
        guard old.count == new.count, !new.isEmpty else { return (Array(repeating: 0, count: new.count), 0, 0) }
        var cores: [Double] = []
        var userSum = 0.0, systemSum = 0.0, totalSum = 0.0
        for (a, b) in zip(old, new) {
            let user = Double(b.user &- a.user) + Double(b.nice &- a.nice)
            let system = Double(b.system &- a.system)
            let idle = Double(b.idle &- a.idle)
            let total = user + system + idle
            cores.append(total > 0 ? (user + system) / total : 0)
            userSum += user
            systemSum += system
            totalSum += total
        }
        guard totalSum > 0 else { return (cores, 0, 0) }
        return (cores, userSum / totalSum, systemSum / totalSum)
    }
}

public final class CPUSampler {
    private var previous: [CoreTicks] = []
    public let performanceCores = SystemInfo.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
    public let efficiencyCores = SystemInfo.sysctlInt("hw.perflevel1.logicalcpu") ?? 0

    public init() {
        previous = Self.readTicks()
    }

    public func sample() -> CPUStats {
        let current = Self.readTicks()
        let (cores, user, system) = CPUMath.usage(from: previous, to: current)
        previous = current
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        return CPUStats(
            usage: min(1, user + system),
            user: user,
            system: system,
            cores: cores,
            performanceCores: performanceCores,
            efficiencyCores: efficiencyCores,
            loadAverage: load
        )
    }

    static func readTicks() -> [CoreTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { i in
            let base = i * stride
            return CoreTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }
}

public enum SystemInfo {
    public static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4: return Int(Int32(truncatingIfNeeded: value))
        default: return Int(value)
        }
    }

    public static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return SystemInfo.string(buffer)
    }

    /// Null-terminated C buffer to String.
    public static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// "Apple M3 Pro"
    public static var chipName: String { sysctlString("machdep.cpu.brand_string") ?? "Apple silicon" }

    /// "Mac15,6"
    public static var modelIdentifier: String { sysctlString("hw.model") ?? "Mac" }

    public static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }
}
