import Foundation
import JuicyCore
import Observation

/// What the menubar item shows.
enum MenubarStyle: String, CaseIterable, Codable, Identifiable {
    case glass, glassPercent, readouts, pulse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .glassPercent: "Glass + number"
        case .readouts: "Readouts"
        case .pulse: "Pulse"
        }
    }

    var blurb: String {
        switch self {
        case .glass: "Juice level is the charge."
        case .glassPercent: "Glass with the percentage beside it."
        case .readouts: "Three metrics, label over value."
        case .pulse: "A live CPU trace."
        }
    }
}

/// Everything the user can change, persisted in UserDefaults as one JSON blob.
struct Preferences: Codable, Equatable {
    var flavor: Flavor = .orange
    var menubarStyle: MenubarStyle = .glassPercent
    var showTimeRemaining = false
    var fahrenheit = false
    var refreshSeconds: Double = 1
    var backgroundRefreshSeconds: Double = 3
    var fanMode: FanMode = .auto
    var fanCurve: FanCurve = .standard
    var rules: [AlertRule] = AlertRule.defaults
    var launchAtLogin = false
    var keepAwake = false

    static let storageKey = "preferences.v1"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

extension Flavor: @unchecked Sendable {}
