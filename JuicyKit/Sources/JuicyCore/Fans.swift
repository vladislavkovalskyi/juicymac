import Foundation

public enum FanMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case auto, chill, blast, custom
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .chill: "Chill"
        case .blast: "Blast"
        case .custom: "Custom"
        }
    }

    public var blurb: String {
        switch self {
        case .auto: "macOS decides. Juicy only watches."
        case .chill: "Holds fans at 2,500 rpm for quiet work. Hands back to macOS at 85°C."
        case .blast: "Both fans at full speed, right now."
        case .custom: "Your own temperature curve."
        }
    }
}

/// Temperature → rpm curve with linear interpolation between points.
public struct FanCurve: Sendable, Codable, Equatable {
    public struct Stop: Sendable, Codable, Equatable, Identifiable {
        public var celsius: Double
        public var rpm: Double
        public var id: Double { celsius }

        public init(celsius: Double, rpm: Double) {
            self.celsius = celsius
            self.rpm = rpm
        }
    }

    public private(set) var stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops.sorted { $0.celsius < $1.celsius }
    }

    public static let standard = FanCurve(stops: [
        .init(celsius: 40, rpm: 1200),
        .init(celsius: 60, rpm: 1800),
        .init(celsius: 75, rpm: 3000),
        .init(celsius: 85, rpm: 4600),
        .init(celsius: 95, rpm: 6000),
    ])

    public func rpm(at celsius: Double) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if celsius <= first.celsius { return first.rpm }
        if celsius >= last.celsius { return last.rpm }
        for (a, b) in zip(stops, stops.dropFirst()) where celsius <= b.celsius {
            let t = (celsius - a.celsius) / (b.celsius - a.celsius)
            return a.rpm + t * (b.rpm - a.rpm)
        }
        return last.rpm
    }

    /// Moves one stop, keeping stops ordered and rpm non-decreasing.
    public mutating func move(stopAt index: Int, celsius: Double, rpm: Double) {
        guard stops.indices.contains(index) else { return }
        let lowerC = index > 0 ? stops[index - 1].celsius + 1 : 20
        let upperC = index < stops.count - 1 ? stops[index + 1].celsius - 1 : 110
        let lowerR = index > 0 ? stops[index - 1].rpm : 0
        let upperR = index < stops.count - 1 ? stops[index + 1].rpm : 10_000
        stops[index].celsius = min(max(celsius, lowerC), upperC)
        stops[index].rpm = min(max(rpm, lowerR), upperR)
    }
}

/// What the app asks the helper to do for one tick, given the mode and current readings.
public enum FanCommand: Sendable, Equatable {
    case auto
    case target(rpm: Double)
}

public enum FanPolicy {
    public static let chillRPM: Double = 2500
    public static let chillBailoutCelsius: Double = 85

    public static func command(for mode: FanMode, cpuTemperature: Double?, curve: FanCurve) -> FanCommand {
        switch mode {
        case .auto:
            return .auto
        case .blast:
            return .target(rpm: .greatestFiniteMagnitude)
        case .chill:
            // Never hold the fans back on a hot machine.
            guard let t = cpuTemperature, t < chillBailoutCelsius else { return .auto }
            return .target(rpm: chillRPM)
        case .custom:
            guard let t = cpuTemperature else { return .auto }
            return .target(rpm: curve.rpm(at: t))
        }
    }
}

/// Result of a Squeeze test, graded on peak temperature and how well clocks held under load.
public struct SqueezeResult: Sendable, Equatable {
    public var duration: TimeInterval
    public var peakCPUTemp: Double?
    public var averageCPUTemp: Double?
    public var peakFanRPM: Double?
    public var peakWatts: Double?
    /// Average CPU usage while stressed, 0...1. Well below 1 means something else throttled the load.
    public var averageLoad: Double

    public init(duration: TimeInterval, peakCPUTemp: Double?, averageCPUTemp: Double?, peakFanRPM: Double?,
                peakWatts: Double?, averageLoad: Double) {
        self.duration = duration
        self.peakCPUTemp = peakCPUTemp
        self.averageCPUTemp = averageCPUTemp
        self.peakFanRPM = peakFanRPM
        self.peakWatts = peakWatts
        self.averageLoad = averageLoad
    }

    public var grade: String {
        guard let peak = peakCPUTemp else { return "–" }
        switch peak {
        case ..<80: return "A"
        case ..<90: return "B"
        case ..<100: return "C"
        default: return "D"
        }
    }

    public var summary: String {
        switch grade {
        case "A": "Cooling has plenty of headroom."
        case "B": "Cooling keeps up, with some effort."
        case "C": "Running hot under load. Check vents and what's running."
        case "D": "Too hot under load. Something is off with cooling."
        default: "No temperature sensors were readable."
        }
    }
}
