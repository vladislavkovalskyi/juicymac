import Foundation
import JuicyCore
import Testing
@testable import JuicySystem

@Suite("SMC codec")
struct SMCCodecTests {
    @Test func decodesAppleSiliconFloat() throws {
        let bytes = try SMCCodec.encode(2140.5, type: "flt ")
        #expect(bytes == [0x00, 0xC8, 0x05, 0x45]) // little-endian IEEE 754
        #expect(SMCCodec.decode(type: "flt ", bytes: bytes) == 2140.5)
    }

    @Test func decodesIntelFixedPoint() throws {
        #expect(SMCCodec.decode(type: "fpe2", bytes: [0x21, 0x60]) == 2136)       // 0x2160 / 4
        #expect(try SMCCodec.encode(2136, type: "fpe2") == [0x21, 0x60])
        #expect(SMCCodec.decode(type: "sp78", bytes: [0x3A, 0x80]) == 58.5)        // 0x3A80 / 256
        #expect(SMCCodec.decode(type: "sp78", bytes: [0xFF, 0x00]) == -1)
    }

    @Test func decodesIntegers() {
        #expect(SMCCodec.decode(type: "ui8 ", bytes: [2]) == 2)
        #expect(SMCCodec.decode(type: "ui16", bytes: [0x01, 0x00]) == 256)
        #expect(SMCCodec.decode(type: "ui32", bytes: [0, 0, 0x07, 0xD0]) == 2000)
        #expect(SMCCodec.decode(type: "si16", bytes: [0xFF, 0xFE]) == -2)
        #expect(SMCCodec.decode(type: "ioft", bytes: [0, 0, 1, 0, 0, 0, 0, 0]) == 1)
        #expect(SMCCodec.decode(type: "????", bytes: [1]) == nil)
        #expect(SMCCodec.decode(type: "ui16", bytes: [1]) == nil)
    }

    @Test func fourCCRoundTrip() {
        #expect(FourCC.string(FourCC.code("F0Ac")) == "F0Ac")
        #expect(FourCC.code("#KEY") == 0x234B_4559)
    }

    @Test func rejectsUnknownWriteType() {
        #expect(throws: SMCError.unsupportedType("ch8*")) { try SMCCodec.encode(1, type: "ch8*") }
    }
}

@Suite("Math")
struct MathTests {
    @Test func cpuDeltaWithWraparound() {
        let old = [CoreTicks(user: .max - 9, system: 0, idle: 0, nice: 0), CoreTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let new = [CoreTicks(user: 10, system: 0, idle: 20, nice: 0), CoreTicks(user: 10, system: 10, idle: 80, nice: 0)]
        let result = CPUMath.usage(from: old, to: new)
        #expect(result.cores[0] == 0.5)  // 20 busy of 40 after wrap
        #expect(result.cores[1] == 0.2)
        #expect(abs(result.user - 30.0 / 140) < 1e-9)
    }

    @Test func memoryBreakdownMatchesActivityMonitor() {
        let stats = MemoryMath.stats(internalPages: 100, purgeablePages: 10, externalPages: 50, wiredPages: 20,
                                     compressorPages: 5, pageSize: 16384, total: 16384 * 1000)
        #expect(stats.app == 90 * 16384)
        #expect(stats.cached == 60 * 16384)
        #expect(stats.used == (90 + 20 + 5) * 16384)
    }

    @Test func rateMeterIgnoresCounterReset() {
        var meter = RateMeter()
        _ = meter.update(1000, 500, at: 10)
        let (a, b) = meter.update(3000, 100, at: 12)
        #expect(a == 1000)
        #expect(b == 0)
    }

    @Test func sensorGrouping() {
        #expect(SensorSampler.group(for: "Tp01", chip: "Apple M1") == .cpu)
        #expect(SensorSampler.group(for: "Tg05", chip: "Apple M1") == .gpu)
        #expect(SensorSampler.group(for: "Tf14", chip: "Apple M3 Pro") == .gpu)
        #expect(SensorSampler.group(for: "Tf04", chip: "Apple M3 Pro") == .cpu)
        #expect(SensorSampler.group(for: "TB0T", chip: "Apple M3 Pro") == .battery)
    }
}

/// Real samplers on the machine running the tests.
@Suite("Live sampling", .serialized)
struct LiveSamplingTests {
    @Test func cpuAndMemoryAreSane() async throws {
        let cpu = CPUSampler()
        try await Task.sleep(for: .milliseconds(300))
        let stats = cpu.sample()
        #expect(stats.cores.count == ProcessInfo.processInfo.activeProcessorCount)
        #expect((0...1).contains(stats.usage))

        let memory = MemorySampler().sample()
        #expect(memory.total == ProcessInfo.processInfo.physicalMemory)
        #expect(memory.used > 0 && memory.used <= memory.total)
    }

    @Test func diskAndNetwork() {
        let disk = DiskSampler().sample()
        #expect(disk.total > disk.available)
        #expect(disk.available > 0)
        let (down, up) = NetworkSampler.counters()
        #expect(down > 0 || up > 0)
    }

    @Test func smcReadsFansAndTemperatures() throws {
        let smc = try SMC()
        let sensors = SensorSampler(smc: smc)
        let temps = sensors.sensors()
        #expect(!temps.isEmpty)
        #expect(temps.hottest(in: .cpu) != nil)
        print("SMC: \(temps.count) sensors, CPU max \(temps.hottest(in: .cpu) ?? -1)°C, fans \(sensors.fans()), power \(sensors.power())")
    }

    @Test func processesAndBattery() async throws {
        let processes = ProcessSampler()
        _ = processes.sample()
        try await Task.sleep(for: .milliseconds(300))
        let top = processes.sample()
        #expect(!top.isEmpty)
        print("Top: \(top.prefix(3).map { "\($0.name) \(Int($0.cpuPercent))%" })")
        if let battery = BatterySampler().sample() {
            #expect((0...1).contains(battery.level))
            print("Battery: \(battery)")
        }
        print("GPU: \(GPUSampler().sample())")
    }
}

@Suite("Live battery")
struct LiveBatteryTests {
    @Test func capacitiesAndHealthAreReadable() async {
        let engine = SamplingEngine()
        let snapshot = await engine.sample()
        guard let battery = snapshot.battery else { return } // desktop Mac: nothing to check
        #expect(battery.designCapacity ?? 0 > 0)
        #expect(battery.maxCapacity ?? 0 > 0)
        let health = battery.health ?? 0
        #expect(health > 0.3 && health <= 1)
        #expect(battery.temperature ?? 0 > 0)
        print("Battery health \(Int(health * 100))%, \(battery.cycleCount ?? -1) cycles, \(battery.temperature ?? -1)°C")
    }
}
