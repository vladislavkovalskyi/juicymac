import Foundation

/// One 0...100 number for "how is my Mac doing". Weights come from the concept doc:
/// heat 30, memory 25, CPU 20, disk 15, battery 10. Heat and CPU only count when sustained,
/// so a one-second spike never drops the score.
public struct JuiceScore: Sendable, Equatable {
    public struct Inputs: Sendable, Equatable {
        /// Mean CPU temperature over the last 60 s.
        public var sustainedCPUTemp: Double?
        /// Mean CPU usage (0...1) over the last 5 minutes.
        public var sustainedCPU: Double
        public var memoryPressure: MemoryPressure
        /// Swap in use, bytes.
        public var swapUsed: UInt64
        public var diskFreeFraction: Double
        public var batteryHealth: Double?

        public init(sustainedCPUTemp: Double?, sustainedCPU: Double, memoryPressure: MemoryPressure, swapUsed: UInt64,
                    diskFreeFraction: Double, batteryHealth: Double?) {
            self.sustainedCPUTemp = sustainedCPUTemp
            self.sustainedCPU = sustainedCPU
            self.memoryPressure = memoryPressure
            self.swapUsed = swapUsed
            self.diskFreeFraction = diskFreeFraction
            self.batteryHealth = batteryHealth
        }
    }

    public enum Factor: String, Sendable, CaseIterable {
        case heat, memory, cpu, disk, battery

        public var weight: Double {
            switch self {
            case .heat: 30
            case .memory: 25
            case .cpu: 20
            case .disk: 15
            case .battery: 10
            }
        }
    }

    public var value: Int
    /// Points lost per factor, 0...weight.
    public var penalties: [Factor: Double]

    public init(value: Int, penalties: [Factor: Double]) {
        self.value = value
        self.penalties = penalties
    }

    public static func compute(_ inputs: Inputs) -> JuiceScore {
        var penalties: [Factor: Double] = [:]

        // Heat: nothing below 70°C, full penalty at 100°C.
        if let t = inputs.sustainedCPUTemp {
            penalties[.heat] = ramp(t, from: 70, to: 100) * Factor.heat.weight
        }

        // Memory: pressure dominates, swap adds a little on top.
        let pressure: Double = switch inputs.memoryPressure {
        case .normal: 0
        case .warning: 0.6
        case .critical: 1
        }
        let swapGB = Double(inputs.swapUsed) / 1_073_741_824
        let swapPart = ramp(swapGB, from: 1, to: 8) * 0.4
        penalties[.memory] = min(1, pressure + swapPart) * Factor.memory.weight

        // CPU: nothing below 60% sustained, full at 100%.
        penalties[.cpu] = ramp(inputs.sustainedCPU, from: 0.6, to: 1) * Factor.cpu.weight

        // Disk: full penalty below 5% free, none above 20%.
        penalties[.disk] = (1 - ramp(inputs.diskFreeFraction, from: 0.05, to: 0.2)) * Factor.disk.weight

        // Battery: none above 90% health, full at 60%.
        if let health = inputs.batteryHealth {
            penalties[.battery] = (1 - ramp(health, from: 0.6, to: 0.9)) * Factor.battery.weight
        }

        let lost = penalties.values.reduce(0, +)
        return JuiceScore(value: Int((100 - lost).rounded()), penalties: penalties)
    }

    /// The factor costing the most points, if it costs at least 3.
    public var biggestDrag: Factor? {
        guard let worst = penalties.max(by: { $0.value < $1.value }), worst.value >= 3 else { return nil }
        return worst.key
    }

    public var verdict: String {
        switch value {
        case 90...: "Your Mac is juicy."
        case 75..<90: "Pretty fresh."
        case 50..<75: "Getting a bit pulpy."
        default: "Running dry."
        }
    }

    /// 0 at `from`, 1 at `to`, clamped. Works for descending ranges too.
    static func ramp(_ x: Double, from a: Double, to b: Double) -> Double {
        guard a != b else { return x >= b ? 1 : 0 }
        return max(0, min(1, (x - a) / (b - a)))
    }
}
