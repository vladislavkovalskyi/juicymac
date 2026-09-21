import Foundation
import Testing
@testable import JuicyCore

@Suite("RingBuffer")
struct RingBufferTests {
    @Test func keepsNewestElementsInOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { buffer.append(i) }
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.last == 5)
        #expect(buffer.count == 3)
    }

    @Test func partiallyFilled() {
        var buffer = RingBuffer<Int>(capacity: 4)
        buffer.append(7)
        #expect(buffer.elements == [7])
    }
}

@Suite("MetricHistory")
struct MetricHistoryTests {
    let start = Date(timeIntervalSinceReferenceDate: 600_000) // aligned to a minute

    @Test func fineRangeReturnsRawSamples() {
        var history = MetricHistory()
        for i in 0..<120 { history.append(Double(i), at: start.addingTimeInterval(Double(i))) }
        let now = start.addingTimeInterval(119)
        let lastMinute = history.points(in: .minute, now: now)
        #expect(lastMinute.count == 61)
        #expect(lastMinute.last?.value == 119)
    }

    @Test func coarseRangeAveragesPerMinute() {
        var history = MetricHistory()
        // Minute 0: values 0...59 (mean 29.5); minute 1: all 100.
        for i in 0..<60 { history.append(Double(i), at: start.addingTimeInterval(Double(i))) }
        for i in 60..<120 { history.append(100, at: start.addingTimeInterval(Double(i))) }
        let points = history.points(in: .hour, now: start.addingTimeInterval(119))
        #expect(points.count == 2)
        #expect(points[0].value == 29.5)
        #expect(points[1].value == 100) // current, still open bucket
    }

    @Test func averageOverWindow() {
        var history = MetricHistory()
        for i in 0..<10 { history.append(i < 5 ? 0 : 10, at: start.addingTimeInterval(Double(i))) }
        #expect(history.average(overLast: 4.5, now: start.addingTimeInterval(9)) == 10)
    }
}

@Suite("JuiceScore")
struct JuiceScoreTests {
    func inputs(temp: Double? = 55, cpu: Double = 0.2, pressure: MemoryPressure = .normal, swap: UInt64 = 0,
                disk: Double = 0.4, health: Double? = 0.95) -> JuiceScore.Inputs {
        .init(sustainedCPUTemp: temp, sustainedCPU: cpu, memoryPressure: pressure, swapUsed: swap,
              diskFreeFraction: disk, batteryHealth: health)
    }

    @Test func healthyMacScores100() {
        let score = JuiceScore.compute(inputs())
        #expect(score.value == 100)
        #expect(score.biggestDrag == nil)
        #expect(score.verdict == "Your Mac is juicy.")
    }

    @Test func heatPenaltyScalesAndIsBiggestDrag() {
        let score = JuiceScore.compute(inputs(temp: 85)) // halfway 70→100 = 15 points
        #expect(score.value == 85)
        #expect(score.biggestDrag == .heat)
    }

    @Test func worstCaseBottomsOut() {
        let score = JuiceScore.compute(inputs(temp: 110, cpu: 1, pressure: .critical, swap: 10 << 30, disk: 0.01, health: 0.5))
        #expect(score.value == 0)
        #expect(score.verdict == "Running dry.")
    }

    @Test func missingSensorsDoNotPenalize() {
        #expect(JuiceScore.compute(inputs(temp: nil, health: nil)).value == 100)
    }
}

@Suite("AlertEngine")
struct AlertEngineTests {
    let rule = AlertRule(metric: .cpuUsage, comparator: .above, threshold: 80, duration: 5, actions: [.notify])
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func snapshot(cpu: Double, at seconds: Double) -> Snapshot {
        Snapshot(date: t0.addingTimeInterval(seconds), cpu: CPUStats(usage: cpu))
    }

    @Test func firesOnceAfterDurationThenRearms() {
        var engine = AlertEngine()
        #expect(engine.evaluate([rule], snapshot: snapshot(cpu: 0.9, at: 0)).isEmpty)
        #expect(engine.evaluate([rule], snapshot: snapshot(cpu: 0.9, at: 4)).isEmpty)
        #expect(engine.evaluate([rule], snapshot: snapshot(cpu: 0.9, at: 5)).count == 1)
        #expect(engine.active.contains(rule.id))
        #expect(engine.evaluate([rule], snapshot: snapshot(cpu: 0.95, at: 9)).isEmpty) // no repeat

        // 79% is inside the 3% hysteresis band: stays latched.
        _ = engine.evaluate([rule], snapshot: snapshot(cpu: 0.79, at: 10))
        #expect(engine.active.contains(rule.id))
        _ = engine.evaluate([rule], snapshot: snapshot(cpu: 0.5, at: 11))
        #expect(!engine.active.contains(rule.id))

        _ = engine.evaluate([rule], snapshot: snapshot(cpu: 0.9, at: 20))
        #expect(engine.evaluate([rule], snapshot: snapshot(cpu: 0.9, at: 25)).count == 1)
    }

    @Test func interruptedConditionRestartsTimer() {
        var engine = AlertEngine()
        _ = engine.evaluate([rule], snapshot: snapshot(cpu: 0.9, at: 0))
        _ = engine.evaluate([rule], snapshot: snapshot(cpu: 0.2, at: 3))
        #expect(engine.evaluate([rule], snapshot: snapshot(cpu: 0.9, at: 6)).isEmpty)
    }

    @Test func disabledRuleNeverFires() {
        var engine = AlertEngine()
        var off = rule
        off.isEnabled = false
        off.duration = 0
        #expect(engine.evaluate([off], snapshot: snapshot(cpu: 1, at: 0)).isEmpty)
    }

    @Test func belowComparatorForBattery() {
        var engine = AlertEngine()
        let low = AlertRule(metric: .batteryLevel, comparator: .below, threshold: 15, duration: 0, actions: [.notify])
        var s = Snapshot(date: t0)
        s.battery = BatteryStats(level: 0.12, isCharging: false, isPluggedIn: false)
        #expect(engine.evaluate([low], snapshot: s).count == 1)
    }

    @Test func conditionTextReadsNaturally() {
        #expect(rule.conditionText == "CPU load above 80% for 5 s")
        var instant = rule
        instant.duration = 0
        #expect(instant.conditionText == "CPU load above 80%")
        #expect(AlertRule.defaults[0].conditionText == "CPU heat above 90°C for 30 s")
    }
}

@Suite("Fans")
struct FanTests {
    @Test func curveInterpolatesAndClamps() {
        let curve = FanCurve.standard
        #expect(curve.rpm(at: 30) == 1200)
        #expect(curve.rpm(at: 50) == 1500)
        #expect(curve.rpm(at: 58) == 1740)
        #expect(curve.rpm(at: 120) == 6000)
    }

    @Test func movingStopKeepsOrder() {
        var curve = FanCurve.standard
        curve.move(stopAt: 1, celsius: 90, rpm: 100)
        #expect(curve.stops[1].celsius == 74) // capped below next stop (75)
        #expect(curve.stops[1].rpm == 1200)   // not below previous stop
    }

    @Test func chillHandsBackWhenHot() {
        #expect(FanPolicy.command(for: .chill, cpuTemperature: 60, curve: .standard) == .target(rpm: 2500))
        #expect(FanPolicy.command(for: .chill, cpuTemperature: 86, curve: .standard) == .auto)
        #expect(FanPolicy.command(for: .chill, cpuTemperature: nil, curve: .standard) == .auto)
    }

    @Test func customFollowsCurve() {
        #expect(FanPolicy.command(for: .custom, cpuTemperature: 58, curve: .standard) == .target(rpm: 1740))
        #expect(FanPolicy.command(for: .auto, cpuTemperature: 99, curve: .standard) == .auto)
    }

    @Test func squeezeGrades() {
        func r(_ t: Double?) -> SqueezeResult {
            SqueezeResult(duration: 30, peakCPUTemp: t, averageCPUTemp: t, peakFanRPM: nil, peakWatts: nil, averageLoad: 1)
        }
        #expect(r(75).grade == "A")
        #expect(r(85).grade == "B")
        #expect(r(95).grade == "C")
        #expect(r(104).grade == "D")
        #expect(r(nil).grade == "–")
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test func rates() {
        #expect(Fmt.rate(512) == "512 B/s")
        #expect(Fmt.rate(48_000_000) == "48.0 MB/s")
    }

    @Test func bytesAndTemps() {
        #expect(Fmt.bytes(412_000_000_000) == "412 GB")
        #expect(Fmt.temperature(58.4) == "58°C")
        #expect(Fmt.temperature(100, fahrenheit: true) == "212°F")
        #expect(Fmt.duration(minutes: 252) == "4 h 12 min")
        #expect(Fmt.duration(minutes: nil) == nil)
    }
}
