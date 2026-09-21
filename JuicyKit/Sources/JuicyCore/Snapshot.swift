import Foundation

/// One reading of everything Juicy Mac watches. Produced by the sampling engine once per tick.
public struct Snapshot: Sendable, Equatable {
    public var date: Date
    public var cpu: CPUStats
    public var memory: MemoryStats
    public var disk: DiskStats
    public var network: NetworkStats
    public var battery: BatteryStats?
    public var gpu: GPUStats
    public var sensors: [Sensor]
    public var fans: [Fan]
    public var power: PowerStats
    public var processes: [ProcessUsage]

    public init(
        date: Date = .now,
        cpu: CPUStats = .init(),
        memory: MemoryStats = .init(),
        disk: DiskStats = .init(),
        network: NetworkStats = .init(),
        battery: BatteryStats? = nil,
        gpu: GPUStats = .init(),
        sensors: [Sensor] = [],
        fans: [Fan] = [],
        power: PowerStats = .init(),
        processes: [ProcessUsage] = []
    ) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.battery = battery
        self.gpu = gpu
        self.sensors = sensors
        self.fans = fans
        self.power = power
        self.processes = processes
    }

    /// Hottest CPU die sensor, the number fans and alerts react to.
    public var cpuTemperature: Double? { sensors.hottest(in: .cpu) }
    public var gpuTemperature: Double? { sensors.hottest(in: .gpu) }
}

public struct CPUStats: Sendable, Equatable {
    /// 0...1 across all cores.
    public var usage: Double
    public var user: Double
    public var system: Double
    /// 0...1 per logical core, in kernel order.
    public var cores: [Double]
    public var performanceCores: Int
    public var efficiencyCores: Int
    public var loadAverage: [Double]

    public init(usage: Double = 0, user: Double = 0, system: Double = 0, cores: [Double] = [],
                performanceCores: Int = 0, efficiencyCores: Int = 0, loadAverage: [Double] = []) {
        self.usage = usage
        self.user = user
        self.system = system
        self.cores = cores
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.loadAverage = loadAverage
    }
}

public enum MemoryPressure: Int, Sendable, Codable, Comparable {
    case normal = 1, warning = 2, critical = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .normal: "normal"
        case .warning: "elevated"
        case .critical: "critical"
        }
    }
}

public struct MemoryStats: Sendable, Equatable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure

    public init(total: UInt64 = 0, app: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, cached: UInt64 = 0,
                swapUsed: UInt64 = 0, swapTotal: UInt64 = 0, pressure: MemoryPressure = .normal) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressure = pressure
    }

    /// Same definition as Activity Monitor's "Memory Used".
    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
}

public struct DiskStats: Sendable, Equatable {
    public var total: UInt64
    public var available: UInt64
    public var readPerSecond: Double
    public var writePerSecond: Double

    public init(total: UInt64 = 0, available: UInt64 = 0, readPerSecond: Double = 0, writePerSecond: Double = 0) {
        self.total = total
        self.available = available
        self.readPerSecond = readPerSecond
        self.writePerSecond = writePerSecond
    }

    public var freeFraction: Double { total == 0 ? 0 : Double(available) / Double(total) }
}

public struct NetworkStats: Sendable, Equatable {
    public var downPerSecond: Double
    public var upPerSecond: Double
    public var totalDown: UInt64
    public var totalUp: UInt64

    public init(downPerSecond: Double = 0, upPerSecond: Double = 0, totalDown: UInt64 = 0, totalUp: UInt64 = 0) {
        self.downPerSecond = downPerSecond
        self.upPerSecond = upPerSecond
        self.totalDown = totalDown
        self.totalUp = totalUp
    }
}

public struct BatteryStats: Sendable, Equatable {
    /// 0...1
    public var level: Double
    public var isCharging: Bool
    public var isPluggedIn: Bool
    /// Minutes to empty (on battery) or to full (charging). Nil while macOS is still estimating.
    public var minutesRemaining: Int?
    public var cycleCount: Int?
    public var designCapacity: Int?
    public var maxCapacity: Int?
    public var temperature: Double?
    public var voltage: Double?
    public var amperage: Double?
    public var adapterWatts: Int?

    public init(level: Double, isCharging: Bool, isPluggedIn: Bool, minutesRemaining: Int? = nil, cycleCount: Int? = nil,
                designCapacity: Int? = nil, maxCapacity: Int? = nil, temperature: Double? = nil, voltage: Double? = nil,
                amperage: Double? = nil, adapterWatts: Int? = nil) {
        self.level = level
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.designCapacity = designCapacity
        self.maxCapacity = maxCapacity
        self.temperature = temperature
        self.voltage = voltage
        self.amperage = amperage
        self.adapterWatts = adapterWatts
    }

    /// Maximum capacity relative to design capacity, 0...1.
    public var health: Double? {
        guard let design = designCapacity, let max = maxCapacity, design > 0 else { return nil }
        return min(1, Double(max) / Double(design))
    }

    /// Battery power in watts; positive while charging, negative while draining.
    public var watts: Double? {
        guard let voltage, let amperage else { return nil }
        return voltage * amperage
    }
}

public struct GPUStats: Sendable, Equatable {
    /// 0...1
    public var usage: Double?
    public init(usage: Double? = nil) { self.usage = usage }
}

public enum SensorGroup: String, Sendable, Codable, CaseIterable {
    case cpu, gpu, memory, storage, battery, power, ambient, other

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .storage: "Storage"
        case .battery: "Battery"
        case .power: "Power & charging"
        case .ambient: "Chassis & air"
        case .other: "Other"
        }
    }
}

public struct Sensor: Sendable, Equatable, Identifiable {
    public var key: String
    public var name: String
    public var group: SensorGroup
    public var celsius: Double
    public var id: String { key }

    public init(key: String, name: String, group: SensorGroup, celsius: Double) {
        self.key = key
        self.name = name
        self.group = group
        self.celsius = celsius
    }
}

public extension Array where Element == Sensor {
    func hottest(in group: SensorGroup) -> Double? {
        filter { $0.group == group }.map(\.celsius).max()
    }

    func average(in group: SensorGroup) -> Double? {
        let values = filter { $0.group == group }.map(\.celsius)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

public struct Fan: Sendable, Equatable, Identifiable {
    public var index: Int
    public var rpm: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var targetRPM: Double?
    public var isForced: Bool
    public var id: Int { index }

    public init(index: Int, rpm: Double, minRPM: Double, maxRPM: Double, targetRPM: Double? = nil, isForced: Bool = false) {
        self.index = index
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
        self.isForced = isForced
    }

    /// 0...1 of the fan's usable range.
    public var fraction: Double {
        guard maxRPM > 0 else { return 0 }
        return max(0, min(1, rpm / maxRPM))
    }

    public var name: String {
        switch index {
        case 0: "Left fan"
        case 1: "Right fan"
        default: "Fan \(index + 1)"
        }
    }
}

public struct PowerStats: Sendable, Equatable {
    /// Whole-system draw from SMC `PSTR`, when the Mac exposes it.
    public var systemWatts: Double?
    public init(systemWatts: Double? = nil) { self.systemWatts = systemWatts }
}

public struct ProcessUsage: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    /// Percent of one core, like Activity Monitor (can exceed 100).
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}
