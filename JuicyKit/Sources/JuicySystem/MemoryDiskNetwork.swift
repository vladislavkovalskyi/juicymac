import Darwin
import Foundation
import IOKit
import JuicyCore

public enum MemoryMath {
    /// Activity Monitor's breakdown from raw page counts.
    public static func stats(internalPages: UInt64, purgeablePages: UInt64, externalPages: UInt64, wiredPages: UInt64,
                             compressorPages: UInt64, pageSize: UInt64, total: UInt64) -> MemoryStats {
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return MemoryStats(
            total: total,
            app: app * pageSize,
            wired: wiredPages * pageSize,
            compressed: compressorPages * pageSize,
            cached: (externalPages + purgeablePages) * pageSize
        )
    }
}

public final class MemorySampler {
    private let pageSize = UInt64(getpagesize())
    private let total = ProcessInfo.processInfo.physicalMemory

    public init() {}

    public func sample() -> MemoryStats {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return MemoryStats(total: total) }

        var result = MemoryMath.stats(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            externalPages: UInt64(stats.external_page_count),
            wiredPages: UInt64(stats.wire_count),
            compressorPages: UInt64(stats.compressor_page_count),
            pageSize: pageSize,
            total: total
        )

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            result.swapUsed = swap.xsu_used
            result.swapTotal = swap.xsu_total
        }
        if let level = SystemInfo.sysctlInt("kern.memorystatus_vm_pressure_level") {
            result.pressure = MemoryPressure(rawValue: level) ?? .normal
        }
        return result
    }
}

/// Converts monotonically growing byte counters into per-second rates.
public struct RateMeter: Sendable {
    private var last: (read: UInt64, write: UInt64, time: TimeInterval)?

    public init() {}

    /// Returns (first per second, second per second). A counter that goes backwards (device reset) yields 0.
    public mutating func update(_ a: UInt64, _ b: UInt64, at time: TimeInterval) -> (Double, Double) {
        defer { last = (a, b, time) }
        guard let last, time > last.time else { return (0, 0) }
        let dt = time - last.time
        let da = a >= last.read ? Double(a - last.read) : 0
        let db = b >= last.write ? Double(b - last.write) : 0
        return (da / dt, db / dt)
    }
}

public final class DiskSampler {
    private var meter = RateMeter()

    public init() {}

    public func sample() -> DiskStats {
        var stats = DiskStats()
        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            stats.total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            stats.available = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        }
        let (read, write) = Self.ioCounters()
        (stats.readPerSecond, stats.writePerSecond) = meter.update(read, write, at: ProcessInfo.processInfo.systemUptime)
        return stats
    }

    static func ioCounters() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }
}

public final class NetworkSampler {
    private var meter = RateMeter()

    public init() {}

    public func sample() -> NetworkStats {
        let (down, up) = Self.counters()
        let (downRate, upRate) = meter.update(down, up, at: ProcessInfo.processInfo.systemUptime)
        return NetworkStats(downPerSecond: downRate, upPerSecond: upRate, totalDown: down, totalUp: up)
    }

    /// Total received and sent bytes on physical interfaces (en*), from 64-bit counters.
    static func counters() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var down: UInt64 = 0, up: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil,
                       SystemInfo.string(nameBuffer).hasPrefix("en") {
                        down += message.ifm_data.ifi_ibytes
                        up += message.ifm_data.ifi_obytes
                    }
                }
                offset += messageLength
            }
        }
        return (down, up)
    }
}
