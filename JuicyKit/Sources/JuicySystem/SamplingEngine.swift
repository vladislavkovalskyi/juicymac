import Foundation
import JuicyCore

/// Owns every sampler and produces one `Snapshot` per call, off the main thread.
public actor SamplingEngine {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()
    private let battery = BatterySampler()
    private let gpu = GPUSampler()
    private let processes = ProcessSampler()
    private let sensors: SensorSampler?
    private var lastProcesses: [ProcessUsage] = []
    private var tick = 0

    public init() {
        sensors = (try? SMC()).map(SensorSampler.init(smc:))
    }

    public var hasSMC: Bool { sensors != nil }

    /// Processes are the most expensive part, so they refresh every other tick unless forced.
    public func sample(refreshProcesses: Bool = false) -> Snapshot {
        tick += 1
        if refreshProcesses || tick % 2 == 1 {
            lastProcesses = processes.sample()
        }
        let readings = sensors?.sensors(full: tick % 5 == 1) ?? []
        var power = battery.sample()
        // The registry has no battery temperature on Apple silicon; the SMC does.
        if power != nil, power?.temperature == nil { power?.temperature = readings.hottest(in: .battery) }

        return Snapshot(
            date: .now,
            cpu: cpu.sample(),
            memory: memory.sample(),
            disk: disk.sample(),
            network: network.sample(),
            battery: power,
            gpu: gpu.sample(),
            sensors: readings,
            fans: sensors?.fans() ?? [],
            power: sensors?.power() ?? .init(),
            processes: lastProcesses
        )
    }
}
