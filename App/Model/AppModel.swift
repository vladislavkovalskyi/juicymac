import AppKit
import Foundation
import JuicyCore
import JuicySystem
import Observation
import ServiceManagement
import UserNotifications

/// The app's single source of truth: samples on a timer, keeps history, scores the Mac,
/// runs alert rules and drives the fans.
@MainActor
@Observable
final class AppModel {
    private(set) var snapshot = Snapshot()
    private(set) var history = HistoryStore()
    private(set) var score = JuiceScore(value: 100, penalties: [:])
    private(set) var hasSensors = true
    private(set) var firedAlerts: [AlertEvent] = []
    private(set) var alarmIsOn = false
    /// Rendered once per sample; the menubar view just shows it.
    private(set) var menubarImage: NSImage?
    private(set) var squeeze: SqueezeResult?
    private(set) var isSqueezing = false
    private(set) var squeezeProgress: Double = 0

    var selectedModule: Module = .overview
    var range: TimeRange = .quarter
    var isPopoverOpen = false
    var isWindowOpen = false

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            if preferences.fanMode != oldValue.fanMode || preferences.fanCurve != oldValue.fanCurve {
                Task { await applyFanMode() }
            }
            if preferences.launchAtLogin != oldValue.launchAtLogin {
                LoginItem.set(preferences.launchAtLogin)
            }
            if preferences.refreshSeconds != oldValue.refreshSeconds { restartLoop() }
        }
    }

    let fans = FanClient()
    private let engine = SamplingEngine()
    private var alerts = AlertEngine()
    private let squeezeRunner = SqueezeRunner()
    private var collector: SqueezeCollector?
    private var loop: Task<Void, Never>?
    private var heartbeatCounter = 0

    init() {
        preferences = Preferences.load()
        #if DEBUG
        // QA helper: JUICY_MODULE=fans opens straight to that screen.
        if let name = ProcessInfo.processInfo.environment["JUICY_MODULE"], let module = Module(rawValue: name) {
            selectedModule = module
        }
        #endif
        restartLoop()
        Task { hasSensors = await engine.hasSMC }
    }

    // MARK: - Sampling

    private func restartLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let interval = self.isPopoverOpen || self.isWindowOpen || self.isSqueezing
                    ? self.preferences.refreshSeconds
                    : self.preferences.backgroundRefreshSeconds
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func tick() async {
        let new = await engine.sample(refreshProcesses: isPopoverOpen || isWindowOpen)
        snapshot = new
        history.record(new)
        score = JuiceScore.compute(scoreInputs())
        collector?.add(new)
        runAlerts(new)
        menubarImage = MenubarRenderer.render(self)
        await applyFanMode()

        // Keep the helper's watchdog fed while a forced fan mode is on.
        heartbeatCounter += 1
        if heartbeatCounter % 10 == 0 { await fans.heartbeat() }
    }

    private func scoreInputs() -> JuiceScore.Inputs {
        JuiceScore.Inputs(
            sustainedCPUTemp: history[.cpuTemp].average(overLast: 60) ?? snapshot.cpuTemperature,
            sustainedCPU: (history[.cpu].average(overLast: 300) ?? snapshot.cpu.usage * 100) / 100,
            memoryPressure: snapshot.memory.pressure,
            swapUsed: snapshot.memory.swapUsed,
            diskFreeFraction: snapshot.disk.freeFraction,
            batteryHealth: snapshot.battery?.health
        )
    }

    // MARK: - Alerts

    private func runAlerts(_ snapshot: Snapshot) {
        let events = alerts.evaluate(preferences.rules, snapshot: snapshot)
        for event in events {
            firedAlerts.insert(event, at: 0)
            if firedAlerts.count > 20 { firedAlerts.removeLast() }
            if event.rule.actions.contains(.notify) { notify(event) }
            if event.rule.actions.contains(.blastFans), preferences.fanMode != .blast {
                preferences.fanMode = .blast
            }
        }
        alarmIsOn = preferences.rules.contains { $0.actions.contains(.redMenubar) && alerts.active.contains($0.id) }
    }

    private func notify(_ event: AlertEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.rule.metric.title
        let value = event.rule.metric == .memoryPressure
            ? snapshot.memory.pressure.label
            : "\(Int(event.value))\(event.rule.metric.unit)"
        content.body = "\(event.rule.conditionText). Now \(value)."
        if let top = snapshot.processes.first, event.rule.metric == .cpuUsage {
            content.body += " Thirstiest: \(top.name)."
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: event.rule.id.uuidString + "-\(Int(event.date.timeIntervalSince1970))",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func requestNotificationAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Fans

    private func applyFanMode() async {
        guard fans.status.isReady else { return }
        let command = FanPolicy.command(for: preferences.fanMode, cpuTemperature: snapshot.cpuTemperature,
                                        curve: preferences.fanCurve)
        await fans.apply(command)
    }

    /// What the fans are actually doing — which is "whatever macOS wants" until the helper is installed.
    var fanCommandDescription: String {
        guard fans.status.isReady else {
            return "macOS is driving the fans. Install the helper to take over."
        }
        switch FanPolicy.command(for: preferences.fanMode, cpuTemperature: snapshot.cpuTemperature, curve: preferences.fanCurve) {
        case .auto: return "macOS is driving the fans."
        case .target(let rpm):
            return rpm == .greatestFiniteMagnitude ? "Holding both fans at maximum." : "Holding the fans at \(Fmt.rpm(rpm))."
        }
    }

    // MARK: - Squeeze test

    func startSqueeze(seconds: TimeInterval = 30) {
        guard !isSqueezing else { return }
        isSqueezing = true
        squeezeProgress = 0
        collector = SqueezeCollector()
        Task {
            let start = Date.now
            let progress = Task { @MainActor in
                while isSqueezing, !Task.isCancelled {
                    squeezeProgress = min(1, Date.now.timeIntervalSince(start) / seconds)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            await squeezeRunner.run(seconds: seconds)
            progress.cancel()
            squeeze = collector?.result()
            collector = nil
            isSqueezing = false
            squeezeProgress = 1
        }
    }

    // MARK: - Actions

    /// Asks an app to quit, or signals a plain process. Returns false when the process is gone or protected.
    @discardableResult
    func quit(pid: Int32) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.terminate()
        }
        return kill(pid, SIGTERM) == 0
    }

    var topProcess: ProcessUsage? {
        snapshot.processes.first { $0.cpuPercent > 25 }
    }

    /// The Overview's one-line heads-up, when there is something to say.
    var headsUp: String? {
        if let top = topProcess, let sustained = history[.cpu].average(overLast: 120), sustained > 40 {
            return "\(top.name) has held \(Int(top.cpuPercent))% CPU. Probably worth a look."
        }
        if snapshot.memory.pressure > .normal {
            return "Memory pressure is \(snapshot.memory.pressure.label). macOS is compressing to keep up."
        }
        if snapshot.disk.freeFraction < 0.1 {
            return "Only \(Fmt.percent(snapshot.disk.freeFraction)) of the disk is free."
        }
        if let drag = score.biggestDrag, score.value < 85 {
            return "Biggest drag on the score right now: \(drag.rawValue)."
        }
        return nil
    }

    var palette: Palette {
        selectedModule.palette(flavor: preferences.flavor, batteryLevel: snapshot.battery?.level ?? 1)
    }

    var flavorPalette: Palette {
        preferences.flavor.palette(batteryLevel: snapshot.battery?.level ?? 1)
    }

    /// Chart-ready history. A 15-minute window holds 900 samples; drawing every one of them
    /// costs more than it shows, so the series is thinned to at most 200 points.
    func points(_ metric: Metric, range: TimeRange? = nil, limit: Int = 200) -> [Point] {
        let all = history[metric].points(in: range ?? self.range)
        guard all.count > limit else { return all }
        let step = Int((Double(all.count) / Double(limit)).rounded(.up))
        var thinned = stride(from: 0, to: all.count, by: step).map { all[$0] }
        if let last = all.last, thinned.last?.date != last.date { thinned.append(last) }
        return thinned
    }
}

enum LoginItem {
    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Juicy Mac: login item change failed: \(error.localizedDescription)")
        }
    }
}
