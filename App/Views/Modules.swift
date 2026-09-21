import Charts
import JuicyCore
import JuicySystem
import SwiftUI

// MARK: - Overview

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            hero
            if let headsUp = model.headsUp { headsUpCard(headsUp) }
            cards
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.score.verdict).displayStyle()
                Text(summary)
                    .bodyStyle()
                    .frame(maxWidth: 440, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                squeezeControls
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            scoreDial
        }
        .frame(height: 250)
    }

    private var summary: String {
        var parts = ["CPU \(Fmt.percent(model.snapshot.cpu.usage))"]
        if let gpu = model.snapshot.gpu.usage { parts.append("GPU \(Fmt.percent(gpu))") }
        parts.append("memory \(model.snapshot.memory.pressure.label)")
        if let temperature = model.snapshot.cpuTemperature {
            parts.append("\(Fmt.temperature(temperature, fahrenheit: model.preferences.fahrenheit)) on the die")
        }
        if let fan = model.snapshot.fans.map(\.rpm).max() {
            parts.append(fan < 1 ? "fans asleep" : "fans at \(Fmt.rpm(fan))")
        }
        return parts.joined(separator: ", ") + "."
    }

    private var scoreDial: some View {
        ZStack {
            RingGauge(fraction: Double(model.score.value) / 100, lineWidth: 12)
                .frame(width: 250, height: 250)
            JuicyIcon(name: "icon-juice", size: 186, hueShift: model.preferences.flavor.hueShift)
            VStack(spacing: 0) {
                Text("\(model.score.value)").font(JuicyFont.readout(28)).monospacedDigit()
                Text("Juice score").font(JuicyFont.eyebrow).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .juicyGlass(radius: 20)
            .offset(y: 96)
        }
        .frame(width: 270, height: 270)
    }

    private var squeezeControls: some View {
        HStack(spacing: 14) {
            Button { model.startSqueeze() } label: {
                Text(model.isSqueezing ? "Squeezing…" : "Squeeze test")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .frame(height: 42)
                    .background(.white.opacity(model.isSqueezing ? 0.55 : 1), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(model.isSqueezing)

            if model.isSqueezing {
                ProgressView(value: model.squeezeProgress).frame(width: 150).tint(.white)
            } else if let result = model.squeeze {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cooling grade \(result.grade) · peak \(Fmt.temperature(result.peakCPUTemp, fahrenheit: model.preferences.fahrenheit))")
                        .font(.system(size: 13, weight: .semibold))
                    Text(result.summary).captionStyle()
                }
            } else {
                Text("30 seconds of full load, to hear the fans and watch the heat")
                    .captionStyle()
                    .frame(maxWidth: 230, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }

    // MARK: Heads-up

    private func headsUpCard(_ text: String) -> some View {
        HStack(spacing: 12) {
            JuicyIcon(name: "icon-bolt", size: 32).padding(-4)
            Text(text).bodyStyle()
            Spacer(minLength: 8)
            // The quit button only shows when the heads-up is actually about a process.
            if let top = model.topProcess, text.hasPrefix(top.name) {
                Button("Quit \(top.name)") { model.quit(pid: top.pid) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(.white, in: .capsule)
                    .foregroundStyle(.black)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(.horizontal, Space.card)
        .frame(height: 56)
        .juicyGlass(radius: 18)
    }

    // MARK: Cards

    private var cards: some View {
        HStack(spacing: Space.gap) {
            StatCard(module: .cpu, value: Fmt.percent(model.snapshot.cpu.usage), unit: nil,
                     footer: "\(model.snapshot.cpu.performanceCores) performance · \(model.snapshot.cpu.efficiencyCores) efficiency cores",
                     action: { model.selectedModule = .cpu }) {
                CoreBars(cores: model.snapshot.cpu.cores, performanceCores: model.snapshot.cpu.performanceCores, height: 52)
            }
            StatCard(module: .memory, value: Fmt.memory(model.snapshot.memory.used),
                     unit: "of \(Fmt.memory(model.snapshot.memory.total))",
                     footer: memoryLegend,
                     action: { model.selectedModule = .memory }) {
                SegmentBar(segments: memorySegments, height: 14)
            }
            StatCard(module: .disk, value: Fmt.bytes(model.snapshot.disk.available), unit: "free",
                     footer: "Write \(Fmt.rate(model.snapshot.disk.writePerSecond)) · Read \(Fmt.rate(model.snapshot.disk.readPerSecond))",
                     action: { model.selectedModule = .disk }) {
                MetricChart(points: model.points(.diskWrite, range: .quarter), unit: "B/s", maximum: nil,
                            height: 52, showsAxes: false)
            }
            StatCard(module: .battery, value: batteryHeadline.value, unit: batteryHeadline.unit,
                     footer: batteryFooter,
                     action: { model.selectedModule = .battery }) {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)
                    SegmentBar(segments: [(model.snapshot.battery?.level ?? 0, 1)], height: 14)
                    Text(batteryState).captionStyle()
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var memorySegments: [(Double, Double)] {
        let total = Double(max(1, model.snapshot.memory.total))
        let m = model.snapshot.memory
        return [
            (Double(m.app) / total, 1),
            (Double(m.wired) / total, 0.72),
            (Double(m.compressed) / total, 0.48),
            (Double(m.cached) / total, 0.28),
        ]
    }

    private var memoryLegend: String {
        let m = model.snapshot.memory
        return "Apps \(Fmt.memory(m.app)) · Wired \(Fmt.memory(m.wired)) · pressure \(m.pressure.label)"
    }

    private var batteryHeadline: (value: String, unit: String?) {
        guard let battery = model.snapshot.battery else { return ("–", nil) }
        if let health = battery.health { return (Fmt.percent(health), "health") }
        return (Fmt.percent(battery.level), "charge")
    }

    private var batteryState: String {
        guard let battery = model.snapshot.battery else { return "–" }
        if battery.isCharging { return "Charging" }
        return battery.isPluggedIn ? "Plugged in, not charging" : "On battery"
    }

    private var batteryFooter: String {
        guard let battery = model.snapshot.battery else { return "No battery on this Mac" }
        var parts: [String] = [Fmt.percent(battery.level) + " charge"]
        if let cycles = battery.cycleCount { parts.append("\(cycles) cycles") }
        parts.append(Fmt.watts(model.snapshot.power.systemWatts ?? battery.watts))
        return parts.joined(separator: " · ")
    }
}

// MARK: - CPU

struct CPUView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(icon: "icon-cpu", eyebrow: "CPU · \(SystemInfo.chipName)",
                         title: Fmt.percent(model.snapshot.cpu.usage),
                         subtitle: "\(model.snapshot.cpu.performanceCores) performance and \(model.snapshot.cpu.efficiencyCores) efficiency cores. Load average \(loadAverage).")
            HStack(spacing: 14) {
                GlassCard(title: "Usage", trailing: model.range.rawValue) {
                    MetricChart(points: model.points(.cpu), unit: "%", maximum: 100, height: 190)
                }
                GlassCard(title: "Cores") {
                    CoreBars(cores: model.snapshot.cpu.cores, performanceCores: model.snapshot.cpu.performanceCores, height: 150)
                    HStack {
                        Text("Efficiency").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("Performance").font(.system(size: 11)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(width: 330)
            }
            HStack(spacing: 14) {
                GlassCard(title: "GPU", icon: "icon-cpu", trailing: model.snapshot.gpu.usage.map { Fmt.percent($0) } ?? "–") {
                    MetricChart(points: model.points(.gpu), unit: "%", maximum: 100, height: 110)
                }
                GlassCard(title: "User vs system") {
                    KeyValues(rows: [
                        ("User", Fmt.percent(model.snapshot.cpu.user)),
                        ("System", Fmt.percent(model.snapshot.cpu.system)),
                        ("Load 1 / 5 / 15 min", loadAverage),
                        ("Uptime", uptime),
                    ])
                }
                .frame(width: 330)
            }
            GlassCard(title: "Thirstiest processes") { ProcessList(limit: 6) }
        }
    }

    private var loadAverage: String {
        model.snapshot.cpu.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " / ")
    }

    private var uptime: String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        return "\(seconds / 86400) d \((seconds % 86400) / 3600) h"
    }
}

// MARK: - Memory

struct MemoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let m = model.snapshot.memory
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(icon: "icon-memory", eyebrow: "Memory · \(Fmt.memory(m.total)) installed",
                         title: Fmt.memory(m.used),
                         subtitle: "Pressure is \(m.pressure.label). Swap in use: \(Fmt.memory(m.swapUsed)) of \(Fmt.memory(m.swapTotal)).")
            GlassCard(title: "In use", trailing: Fmt.percent(m.usedFraction)) {
                SegmentBar(segments: [
                    (Double(m.app) / Double(max(1, m.total)), 1),
                    (Double(m.wired) / Double(max(1, m.total)), 0.72),
                    (Double(m.compressed) / Double(max(1, m.total)), 0.48),
                    (Double(m.cached) / Double(max(1, m.total)), 0.28),
                ], height: 18)
                HStack(spacing: 18) {
                    legend("Apps", Fmt.memory(m.app), 1)
                    legend("Wired", Fmt.memory(m.wired), 0.72)
                    legend("Compressed", Fmt.memory(m.compressed), 0.48)
                    legend("Cached files", Fmt.memory(m.cached), 0.28)
                }
            }
            GlassCard(title: "Usage", trailing: model.range.rawValue) {
                MetricChart(points: model.points(.memory), unit: "%", maximum: 100, height: 200)
            }
            GlassCard(title: "Biggest footprints") { ProcessList(limit: 5) }
        }
    }

    private func legend(_ title: String, _ value: String, _ opacity: Double) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(opacity)).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
    }
}

// MARK: - Disk

struct DiskView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.snapshot.disk
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(icon: "icon-disk", eyebrow: "Disk · Macintosh HD",
                         title: "\(Fmt.bytes(d.available)) free",
                         subtitle: "\(Fmt.bytes(d.total - d.available)) used of \(Fmt.bytes(d.total)). macOS counts purgeable space as available.")
            GlassCard(title: "Capacity", trailing: Fmt.percent(d.freeFraction) + " free") {
                SegmentBar(segments: [(1 - d.freeFraction, 0.95)], height: 18)
            }
            HStack(spacing: 14) {
                GlassCard(title: "Write", trailing: Fmt.rate(d.writePerSecond)) {
                    MetricChart(points: model.points(.diskWrite), unit: "B/s", maximum: nil, height: 170)
                }
                GlassCard(title: "Read", trailing: Fmt.rate(d.readPerSecond)) {
                    MetricChart(points: model.points(.diskRead), unit: "B/s", maximum: nil, height: 170)
                }
            }
        }
    }
}

// MARK: - Network

struct NetworkView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let n = model.snapshot.network
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(icon: "icon-disk", eyebrow: "Network · physical interfaces",
                         title: "↓ \(Fmt.rate(n.downPerSecond))",
                         subtitle: "Up \(Fmt.rate(n.upPerSecond)). Since boot: \(Fmt.bytes(n.totalDown)) in, \(Fmt.bytes(n.totalUp)) out.")
            HStack(spacing: 14) {
                GlassCard(title: "Download", trailing: Fmt.rate(n.downPerSecond)) {
                    MetricChart(points: model.points(.netDown), unit: "B/s", maximum: nil, height: 190)
                }
                GlassCard(title: "Upload", trailing: Fmt.rate(n.upPerSecond)) {
                    MetricChart(points: model.points(.netUp), unit: "B/s", maximum: nil, height: 190)
                }
            }
            GlassCard(title: "Totals") {
                KeyValues(rows: [
                    ("Received since boot", Fmt.bytes(n.totalDown)),
                    ("Sent since boot", Fmt.bytes(n.totalUp)),
                ])
            }
        }
    }
}

// MARK: - Battery

struct BatteryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let battery = model.snapshot.battery {
                ModuleHeader(icon: "icon-battery", eyebrow: state(battery),
                             title: Fmt.percent(battery.level),
                             subtitle: subtitle(battery))
                HStack(spacing: 14) {
                    GlassCard(title: "Charge", trailing: model.range.rawValue) {
                        MetricChart(points: model.points(.battery), unit: "%", maximum: 100, height: 190)
                    }
                    GlassCard(title: "Health") {
                        KeyValues(rows: healthRows(battery))
                    }
                    .frame(width: 340)
                }
                GlassCard(title: "Power draw", trailing: Fmt.watts(model.snapshot.power.systemWatts ?? battery.watts)) {
                    MetricChart(points: model.points(.power), unit: "W", maximum: nil, height: 150)
                }
            } else {
                ModuleHeader(icon: "icon-battery", eyebrow: "Battery", title: "No battery",
                             subtitle: "This Mac runs on wall power only.")
            }
        }
    }

    private func state(_ battery: BatteryStats) -> String {
        battery.isCharging ? "Battery · charging" : battery.isPluggedIn ? "Battery · plugged in" : "Battery · on battery"
    }

    private func subtitle(_ battery: BatteryStats) -> String {
        var parts: [String] = []
        if let time = Fmt.duration(minutes: battery.minutesRemaining) {
            parts.append(battery.isCharging ? "\(time) to full" : "\(time) left")
        }
        if let health = battery.health { parts.append("health \(Fmt.percent(health))") }
        if let cycles = battery.cycleCount { parts.append("\(cycles) cycles") }
        parts.append(Fmt.temperature(battery.temperature, fahrenheit: model.preferences.fahrenheit))
        return parts.joined(separator: " · ")
    }

    private func healthRows(_ battery: BatteryStats) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let health = battery.health { rows.append(("Maximum capacity", Fmt.percent(health))) }
        if let design = battery.designCapacity { rows.append(("Design capacity", "\(design) mAh")) }
        if let maximum = battery.maxCapacity { rows.append(("Full charge capacity", "\(maximum) mAh")) }
        if let cycles = battery.cycleCount { rows.append(("Cycles", "\(cycles)")) }
        if let voltage = battery.voltage { rows.append(("Voltage", String(format: "%.2f V", voltage))) }
        if let amperage = battery.amperage { rows.append(("Current", String(format: "%.2f A", amperage))) }
        if let adapter = battery.adapterWatts { rows.append(("Adapter", "\(adapter) W")) }
        rows.append(("Temperature", Fmt.temperature(battery.temperature, fahrenheit: model.preferences.fahrenheit)))
        return rows
    }
}
