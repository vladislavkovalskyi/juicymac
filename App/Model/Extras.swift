import AppKit
import Carbon.HIToolbox
import Foundation
import IOKit.pwr_mgt
import JuicyCore
import JuicySystem

/// Holds a power assertion so the display stays awake. Handy while a long build runs.
@MainActor
final class Caffeine {
    private var assertion: IOPMAssertionID = 0
    private(set) var isOn = false

    func set(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Juicy Mac is keeping this Mac awake" as CFString,
                &id
            )
            guard result == kIOReturnSuccess else { return }
            assertion = id
            isOn = true
        } else {
            IOPMAssertionRelease(assertion)
            assertion = 0
            isOn = false
        }
    }
}

/// Plain-text snapshot for pasting into a chat or a bug report, and CSV of the recorded history.
enum Report {
    static func text(snapshot: Snapshot, score: JuiceScore, fahrenheit: Bool) -> String {
        var lines = [
            "Juicy Mac report — \(Date.now.formatted(date: .abbreviated, time: .shortened))",
            "\(SystemInfo.chipName) · \(SystemInfo.modelIdentifier) · \(SystemInfo.osVersion)",
            "Juice score: \(score.value) — \(score.verdict)",
            "CPU: \(Fmt.percent(snapshot.cpu.usage)) (\(snapshot.cpu.performanceCores)P + \(snapshot.cpu.efficiencyCores)E)",
            "Memory: \(Fmt.memory(snapshot.memory.used)) of \(Fmt.memory(snapshot.memory.total)), pressure \(snapshot.memory.pressure.label), swap \(Fmt.memory(snapshot.memory.swapUsed))",
            "Disk: \(Fmt.bytes(snapshot.disk.available)) free of \(Fmt.bytes(snapshot.disk.total))",
            "Network: ↓ \(Fmt.rate(snapshot.network.downPerSecond)) ↑ \(Fmt.rate(snapshot.network.upPerSecond))",
        ]
        if let gpu = snapshot.gpu.usage { lines.append("GPU: \(Fmt.percent(gpu))") }
        lines.append("CPU temperature: \(Fmt.temperature(snapshot.cpuTemperature, fahrenheit: fahrenheit))")
        if let watts = snapshot.power.systemWatts { lines.append("System power: \(Fmt.watts(watts))") }
        if let battery = snapshot.battery {
            let health = battery.health.map { " · health \(Fmt.percent($0))" } ?? ""
            let cycles = battery.cycleCount.map { " · \($0) cycles" } ?? ""
            lines.append("Battery: \(Fmt.percent(battery.level))\(health)\(cycles) · \(Fmt.temperature(battery.temperature, fahrenheit: fahrenheit))")
        }
        if !snapshot.fans.isEmpty {
            lines.append("Fans: " + snapshot.fans.map { "\($0.name) \(Fmt.rpm($0.rpm))" }.joined(separator: ", "))
        }
        if !snapshot.processes.isEmpty {
            lines.append("Thirstiest: " + snapshot.processes.prefix(5).map { "\($0.name) \(Int($0.cpuPercent))%" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    static func csv(_ history: HistoryStore, range: TimeRange) -> String {
        let metrics = Metric.allCases
        var rows: [Date: [Metric: Double]] = [:]
        for metric in metrics {
            for point in history[metric].points(in: range) {
                rows[point.date, default: [:]][metric] = point.value
            }
        }
        let header = (["time"] + metrics.map(\.rawValue)).joined(separator: ",")
        let body = rows.keys.sorted().map { date in
            let values = metrics.map { rows[date]?[$0].map { String(format: "%.2f", $0) } ?? "" }
            return ([ISO8601DateFormatter().string(from: date)] + values).joined(separator: ",")
        }
        return ([header] + body).joined(separator: "\n")
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @MainActor
    static func saveCSV(_ csv: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "juicy-mac-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// ⌥⌘J from anywhere opens the popover.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (() -> Void)?

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_J),
                  modifiers: UInt32 = UInt32(cmdKey | optionKey),
                  action: @escaping () -> Void) {
        unregister()
        Self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &eventType, nil, &handler)

        let id = EventHotKeyID(signature: OSType(0x4A554943), id: 1) // 'JUIC'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}
