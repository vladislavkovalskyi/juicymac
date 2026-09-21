import Foundation

public struct AlertRule: Sendable, Codable, Equatable, Identifiable {
    public enum Metric: String, Sendable, Codable, CaseIterable, Identifiable {
        case cpuTemperature, cpuUsage, gpuUsage, memoryPressure, batteryLevel, diskFree

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .cpuTemperature: "CPU heat"
            case .cpuUsage: "CPU load"
            case .gpuUsage: "GPU load"
            case .memoryPressure: "Memory pressure"
            case .batteryLevel: "Battery"
            case .diskFree: "Free disk"
            }
        }

        public var unit: String {
            switch self {
            case .cpuTemperature: "°C"
            case .memoryPressure: ""
            default: "%"
            }
        }
    }

    public enum Comparator: String, Sendable, Codable, CaseIterable {
        case above, below
    }

    public enum Action: String, Sendable, Codable, CaseIterable, Identifiable {
        case notify, blastFans, redMenubar
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .notify: "Notify me"
            case .blastFans: "Blast the fans"
            case .redMenubar: "Turn the glass red"
            }
        }
    }

    public var id: UUID
    public var isEnabled: Bool
    public var metric: Metric
    public var comparator: Comparator
    /// °C for temperature, percent for usage/levels, pressure level (1, 2, 4) for memory pressure.
    public var threshold: Double
    /// Seconds the condition must hold before firing.
    public var duration: TimeInterval
    public var actions: Set<Action>

    public init(id: UUID = UUID(), isEnabled: Bool = true, metric: Metric, comparator: Comparator, threshold: Double,
                duration: TimeInterval, actions: Set<Action>) {
        self.id = id
        self.isEnabled = isEnabled
        self.metric = metric
        self.comparator = comparator
        self.threshold = threshold
        self.duration = duration
        self.actions = actions
    }

    public var conditionText: String {
        if metric == .memoryPressure {
            let level = MemoryPressure(rawValue: Int(threshold))?.label ?? "elevated"
            return "Memory pressure \(comparator == .above ? "reaches" : "drops below") \(level)"
        }
        let value = threshold.formatted(.number.precision(.fractionLength(0)).locale(Fmt.locale))
        guard duration > 0 else { return "\(metric.title) \(comparator.rawValue) \(value)\(metric.unit)" }
        let time = duration >= 60 ? "\(Int(duration / 60)) min" : "\(Int(duration)) s"
        return "\(metric.title) \(comparator.rawValue) \(value)\(metric.unit) for \(time)"
    }

    public var actionText: String {
        Action.allCases.filter(actions.contains).map(\.title).joined(separator: ", ")
    }

    /// Current value of the rule's metric, in the rule's units.
    public func value(in snapshot: Snapshot) -> Double? {
        switch metric {
        case .cpuTemperature: snapshot.cpuTemperature
        case .cpuUsage: snapshot.cpu.usage * 100
        case .gpuUsage: snapshot.gpu.usage.map { $0 * 100 }
        case .memoryPressure: Double(snapshot.memory.pressure.rawValue)
        case .batteryLevel: snapshot.battery.map { $0.level * 100 }
        case .diskFree: snapshot.disk.freeFraction * 100
        }
    }

    public static let defaults: [AlertRule] = [
        AlertRule(metric: .cpuTemperature, comparator: .above, threshold: 90, duration: 30, actions: [.blastFans, .redMenubar, .notify]),
        AlertRule(metric: .cpuUsage, comparator: .above, threshold: 80, duration: 300, actions: [.notify]),
        AlertRule(metric: .batteryLevel, comparator: .below, threshold: 15, duration: 0, actions: [.notify, .redMenubar]),
        AlertRule(isEnabled: false, metric: .memoryPressure, comparator: .above, threshold: 2, duration: 60, actions: [.notify]),
    ]
}

public struct AlertEvent: Sendable, Equatable {
    public var rule: AlertRule
    public var value: Double
    public var date: Date
}

/// Evaluates rules against snapshots. A rule fires once when its condition has held for `duration`,
/// and re-arms after the value moves back past the threshold by a 3% margin.
public struct AlertEngine: Sendable {
    private var since: [UUID: Date] = [:]
    private var fired: Set<UUID> = []

    public init() {}

    /// Rules currently firing (condition held long enough and not yet cleared).
    public private(set) var active: Set<UUID> = []

    public mutating func evaluate(_ rules: [AlertRule], snapshot: Snapshot) -> [AlertEvent] {
        var events: [AlertEvent] = []
        let now = snapshot.date
        let ids = Set(rules.map(\.id))
        since = since.filter { ids.contains($0.key) }
        fired.formIntersection(ids)
        active.formIntersection(ids)

        for rule in rules {
            guard rule.isEnabled, let value = rule.value(in: snapshot) else {
                reset(rule.id)
                continue
            }
            if holds(rule, value) {
                let start = since[rule.id] ?? now
                since[rule.id] = start
                if now.timeIntervalSince(start) >= rule.duration, !fired.contains(rule.id) {
                    fired.insert(rule.id)
                    active.insert(rule.id)
                    events.append(AlertEvent(rule: rule, value: value, date: now))
                }
            } else {
                since[rule.id] = nil
                if cleared(rule, value) {
                    fired.remove(rule.id)
                    active.remove(rule.id)
                }
            }
        }
        return events
    }

    private mutating func reset(_ id: UUID) {
        since[id] = nil
        fired.remove(id)
        active.remove(id)
    }

    private func holds(_ rule: AlertRule, _ value: Double) -> Bool {
        switch rule.comparator {
        case .above: value >= rule.threshold
        case .below: value <= rule.threshold
        }
    }

    private func cleared(_ rule: AlertRule, _ value: Double) -> Bool {
        let margin = rule.metric == .memoryPressure ? 0 : abs(rule.threshold) * 0.03
        switch rule.comparator {
        case .above: return value < rule.threshold - margin
        case .below: return value > rule.threshold + margin
        }
    }
}
