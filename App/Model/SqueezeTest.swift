import Foundation
import JuicyCore

/// Loads every core for a fixed time so the fans and sensors have something to say.
/// The work is pure arithmetic on background threads; it stops on cancel or when the time is up.
actor SqueezeRunner {
    private var running = false

    func run(seconds: TimeInterval) async {
        guard !running else { return }
        running = true
        defer { running = false }

        let cores = ProcessInfo.processInfo.activeProcessorCount
        let deadline = Date.now.addingTimeInterval(seconds)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<cores {
                group.addTask(priority: .userInitiated) {
                    var x = 1.000_001
                    while Date.now < deadline, !Task.isCancelled {
                        // A few million flops between clock checks keeps the loop hot but interruptible.
                        for _ in 0..<200_000 { x = (x * 1.000_000_1).squareRoot() + 0.000_001 }
                        if x.isNaN || x.isInfinite { x = 1.000_001 }
                    }
                }
            }
            await group.waitForAll()
        }
    }
}

/// Collects readings while the test runs and grades the result.
struct SqueezeCollector {
    var started = Date.now
    var peakTemp: Double?
    var temps: [Double] = []
    var peakFan: Double?
    var peakWatts: Double?
    var loads: [Double] = []

    mutating func add(_ snapshot: Snapshot) {
        if let t = snapshot.cpuTemperature {
            peakTemp = max(peakTemp ?? 0, t)
            temps.append(t)
        }
        if let fan = snapshot.fans.map(\.rpm).max() { peakFan = max(peakFan ?? 0, fan) }
        if let w = snapshot.power.systemWatts { peakWatts = max(peakWatts ?? 0, w) }
        loads.append(snapshot.cpu.usage)
    }

    func result() -> SqueezeResult {
        SqueezeResult(
            duration: Date.now.timeIntervalSince(started),
            peakCPUTemp: peakTemp,
            averageCPUTemp: temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count),
            peakFanRPM: peakFan,
            peakWatts: peakWatts,
            averageLoad: loads.isEmpty ? 0 : loads.reduce(0, +) / Double(loads.count)
        )
    }
}
