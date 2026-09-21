import Foundation

/// Fixed-capacity FIFO; appending past capacity drops the oldest element.
public struct RingBuffer<Element>: Sequence {
    private var storage: [Element?]
    private var head = 0
    public private(set) var count = 0
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer needs a positive capacity")
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    public mutating func append(_ element: Element) {
        storage[(head + count) % capacity] = element
        if count < capacity {
            count += 1
        } else {
            head = (head + 1) % capacity
        }
    }

    public var last: Element? {
        count == 0 ? nil : storage[(head + count - 1) % capacity]
    }

    public var elements: [Element] { Array(self) }

    public func makeIterator() -> AnyIterator<Element> {
        var i = 0
        return AnyIterator {
            guard i < count else { return nil }
            defer { i += 1 }
            return storage[(head + i) % capacity]
        }
    }
}

extension RingBuffer: Sendable where Element: Sendable {}

public struct Point: Sendable, Equatable, Identifiable {
    public var date: Date
    public var value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Metrics kept in history and charted across the app.
public enum Metric: String, Sendable, CaseIterable, Codable {
    case cpu, gpu, memory, cpuTemp, gpuTemp, diskRead, diskWrite, netDown, netUp, battery, power, fan
}

public enum TimeRange: String, Sendable, CaseIterable, Identifiable, Codable {
    case minute = "1 min"
    case quarter = "15 min"
    case hour = "1 h"
    case day = "24 h"

    public var id: String { rawValue }

    public var seconds: TimeInterval {
        switch self {
        case .minute: 60
        case .quarter: 15 * 60
        case .hour: 3600
        case .day: 24 * 3600
        }
    }
}

/// Two-tier history: raw samples for the last 15 minutes, minute averages for the last 24 hours.
public struct MetricHistory: Sendable {
    public static let fineCapacity = 15 * 60
    public static let coarseCapacity = 24 * 60

    private var fine = RingBuffer<Point>(capacity: fineCapacity)
    private var coarse = RingBuffer<Point>(capacity: coarseCapacity)
    private var bucketStart: Date?
    private var bucketSum = 0.0
    private var bucketCount = 0

    public init() {}

    public mutating func append(_ value: Double, at date: Date) {
        fine.append(Point(date: date, value: value))

        let minute = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        if let start = bucketStart, start != minute {
            flushBucket()
        }
        if bucketStart == nil { bucketStart = minute }
        bucketSum += value
        bucketCount += 1
    }

    private mutating func flushBucket() {
        if let start = bucketStart, bucketCount > 0 {
            coarse.append(Point(date: start, value: bucketSum / Double(bucketCount)))
        }
        bucketStart = nil
        bucketSum = 0
        bucketCount = 0
    }

    public var latest: Double? { fine.last?.value }

    /// Points covering `range`, ending at `now`.
    public func points(in range: TimeRange, now: Date = .now) -> [Point] {
        let cutoff = now.addingTimeInterval(-range.seconds)
        switch range {
        case .minute, .quarter:
            return fine.filter { $0.date >= cutoff }
        case .hour, .day:
            var points = coarse.filter { $0.date >= cutoff }
            if let start = bucketStart, bucketCount > 0 {
                points.append(Point(date: start, value: bucketSum / Double(bucketCount)))
            }
            return points
        }
    }

    /// Mean of raw samples newer than `seconds` ago.
    public func average(overLast seconds: TimeInterval, now: Date = .now) -> Double? {
        let cutoff = now.addingTimeInterval(-seconds)
        let values = fine.filter { $0.date >= cutoff }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// History for every metric.
public struct HistoryStore: Sendable {
    private var series: [Metric: MetricHistory] = [:]

    public init() {}

    public mutating func record(_ snapshot: Snapshot) {
        let d = snapshot.date
        put(.cpu, snapshot.cpu.usage * 100, d)
        put(.memory, snapshot.memory.usedFraction * 100, d)
        put(.diskRead, snapshot.disk.readPerSecond, d)
        put(.diskWrite, snapshot.disk.writePerSecond, d)
        put(.netDown, snapshot.network.downPerSecond, d)
        put(.netUp, snapshot.network.upPerSecond, d)
        if let gpu = snapshot.gpu.usage { put(.gpu, gpu * 100, d) }
        if let t = snapshot.cpuTemperature { put(.cpuTemp, t, d) }
        if let t = snapshot.gpuTemperature { put(.gpuTemp, t, d) }
        if let b = snapshot.battery { put(.battery, b.level * 100, d) }
        if let w = snapshot.power.systemWatts ?? snapshot.battery?.watts.map(abs) { put(.power, w, d) }
        if let fan = snapshot.fans.map(\.rpm).max() { put(.fan, fan, d) }
    }

    private mutating func put(_ metric: Metric, _ value: Double, _ date: Date) {
        series[metric, default: MetricHistory()].append(value, at: date)
    }

    public subscript(metric: Metric) -> MetricHistory {
        series[metric] ?? MetricHistory()
    }
}
