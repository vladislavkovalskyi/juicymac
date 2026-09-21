import Foundation
import JuicyCore

/// Temperatures, fans and system power, all from the SMC.
public final class SensorSampler {
    private let smc: SMC
    private let temperatureKeys: [(key: String, name: String, group: SensorGroup)]
    private let fanCount: Int
    private let hasSystemPower: Bool
    /// Reading all 200+ keys every second costs real CPU, so only these are polled on every tick.
    private let fastKeys: Set<String>
    private var cached: [String: Double] = [:]

    public init(smc: SMC) {
        self.smc = smc
        let chip = SystemInfo.chipName
        let keys = smc.allKeys()
        var found: [(String, SensorGroup)] = []
        for key in keys where key.hasPrefix("T") {
            guard smc.type(of: key) == "flt ", let value = smc.double(key), SensorSampler.plausible(value) else { continue }
            found.append((key, SensorSampler.group(for: key, chip: chip)))
        }
        temperatureKeys = SensorSampler.name(found)
        fanCount = Int(smc.double("FNum") ?? 0)
        hasSystemPower = smc.double("PSTR") != nil
        fastKeys = SensorSampler.fastSet(temperatureKeys)
    }

    /// A few sensors per group: enough for the readouts, alerts and the fan curve.
    static func fastSet(_ keys: [(key: String, name: String, group: SensorGroup)]) -> Set<String> {
        var result: Set<String> = []
        for group in SensorGroup.allCases {
            let limit = group == .cpu ? 4 : 2
            result.formUnion(keys.filter { $0.group == group }.prefix(limit).map(\.key))
        }
        return result
    }

    /// `full: false` refreshes only the fast set and reuses the last value for everything else.
    public func sensors(full: Bool = true) -> [Sensor] {
        temperatureKeys.compactMap { entry in
            if full || fastKeys.contains(entry.key) {
                if let value = smc.double(entry.key), SensorSampler.plausible(value) {
                    cached[entry.key] = value
                } else {
                    cached[entry.key] = nil
                }
            }
            guard let value = cached[entry.key] else { return nil }
            return Sensor(key: entry.key, name: entry.name, group: entry.group, celsius: value)
        }
    }

    public func fans() -> [Fan] {
        (0..<fanCount).compactMap { i in
            guard let rpm = smc.double("F\(i)Ac") else { return nil }
            let mode = smc.double("F\(i)Md") ?? 0
            return Fan(
                index: i,
                rpm: max(0, rpm),
                minRPM: smc.double("F\(i)Mn") ?? 0,
                maxRPM: smc.double("F\(i)Mx") ?? 0,
                targetRPM: smc.double("F\(i)Tg"),
                isForced: mode == 1
            )
        }
    }

    public func power() -> PowerStats {
        guard hasSystemPower, let watts = smc.double("PSTR"), watts.isFinite, watts >= 0, watts < 1000 else { return .init() }
        return PowerStats(systemWatts: watts)
    }

    static func plausible(_ celsius: Double) -> Bool {
        celsius.isFinite && celsius > 1 && celsius < 130
    }

    /// Groups a temperature key by its prefix. M3-family chips put GPU sensors under Tf1*/Tf2*.
    public static func group(for key: String, chip: String) -> SensorGroup {
        let p2 = String(key.prefix(2))
        let p3 = String(key.prefix(3))
        switch p2 {
        case "Tp", "Te", "TC": return .cpu
        case "Tg": return .gpu
        case "Tf":
            if chip.contains("M3"), p3 == "Tf1" || p3 == "Tf2" { return .gpu }
            return .cpu
        case "TB": return .battery
        case "TH", "TN", "TS": return .storage
        case "Tm", "TM": return .memory
        case "Ts", "TA", "Ta", "TW": return .ambient
        case "TP", "TV", "TD", "TR", "TL": return .power
        default: return .other
        }
    }

    /// Human names per group: "CPU 1", "CPU 2", "Battery 1"…
    static func name(_ found: [(String, SensorGroup)]) -> [(key: String, name: String, group: SensorGroup)] {
        var counters: [SensorGroup: Int] = [:]
        return found.sorted { $0.0 < $1.0 }.map { key, group in
            counters[group, default: 0] += 1
            let base: String = switch group {
            case .cpu: key.hasPrefix("Te") ? "Efficiency core" : "CPU die"
            case .gpu: "GPU"
            case .memory: "Memory"
            case .storage: "SSD"
            case .battery: "Battery"
            case .power: "Power delivery"
            case .ambient: "Chassis"
            case .other: "Sensor"
            }
            return (key, "\(base) \(counters[group]!)", group)
        }
    }
}
