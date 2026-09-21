import AppIntents
import Foundation
import JuicyCore
import JuicySystem

/// Shortcuts and Spotlight: "Juice score", "Mac temperature", "Set fans to Blast".
struct JuiceScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Juice score"
    static let description = IntentDescription("How the Mac is doing right now, from 0 to 100.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let snapshot = await SamplingEngine().sample()
        let score = JuiceScore.compute(.init(
            sustainedCPUTemp: snapshot.cpuTemperature,
            sustainedCPU: snapshot.cpu.usage,
            memoryPressure: snapshot.memory.pressure,
            swapUsed: snapshot.memory.swapUsed,
            diskFreeFraction: snapshot.disk.freeFraction,
            batteryHealth: snapshot.battery?.health
        ))
        return .result(value: score.value, dialog: IntentDialog(stringLiteral: "\(score.value) out of 100. \(score.verdict)"))
    }
}

struct MacTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Mac temperature"
    static let description = IntentDescription("The hottest CPU sensor, in degrees Celsius.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let snapshot = await SamplingEngine().sample()
        guard let temperature = snapshot.cpuTemperature else {
            return .result(value: 0, dialog: "No temperature sensors are readable on this Mac.")
        }
        let fans = snapshot.fans.map { Fmt.rpm($0.rpm) }.joined(separator: ", ")
        let suffix = fans.isEmpty ? "" : " Fans: \(fans)."
        return .result(value: temperature,
                       dialog: IntentDialog(stringLiteral: "\(Int(temperature))°C.\(suffix)"))
    }
}

enum FanModeAppValue: String, AppEnum {
    case auto, chill, blast

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Fan mode")
    static let caseDisplayRepresentations: [FanModeAppValue: DisplayRepresentation] = [
        .auto: "Auto", .chill: "Chill", .blast: "Blast",
    ]

    var mode: FanMode {
        switch self {
        case .auto: .auto
        case .chill: .chill
        case .blast: .blast
        }
    }
}

struct SetFanModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set fan mode"
    static let description = IntentDescription("Switches Juicy Mac between Auto, Chill and Blast.")
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Mode")
    var mode: FanModeAppValue

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = AppDelegate.shared?.model else {
            return .result(dialog: "Juicy Mac is not running.")
        }
        model.preferences.fanMode = mode.mode
        return .result(dialog: IntentDialog(stringLiteral: "Fans set to \(mode.mode.title)."))
    }
}

struct JuicyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: JuiceScoreIntent(), phrases: ["Juice score in \(.applicationName)"],
                    shortTitle: "Juice score", systemImageName: "gauge.with.dots.needle.67percent")
        AppShortcut(intent: MacTemperatureIntent(), phrases: ["Mac temperature in \(.applicationName)"],
                    shortTitle: "Temperature", systemImageName: "thermometer.medium")
        AppShortcut(intent: SetFanModeIntent(), phrases: ["Set fans in \(.applicationName)"],
                    shortTitle: "Fan mode", systemImageName: "fan")
    }
}
