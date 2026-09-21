import SwiftUI

/// A juice flavor: the palette behind the glass. Flavors tint the popover, Overview and menubar.
enum Flavor: String, CaseIterable, Codable, Identifiable {
    case orange, lime, grape, cherry, blueberry, ripe

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .orange: "The house blend. Warm, loud, awake."
        case .lime: "Fresh greens for long coding nights."
        case .grape: "Deep violet, calm on dark desktops."
        case .cherry: "Red and bold. Alarms read even louder."
        case .blueberry: "Cool blues that sit next to macOS defaults."
        case .ripe: "Follows the battery: lime when full, cherry when low."
        }
    }

    /// Hue shift applied to the 3D juice glass so it matches the flavor.
    var hueShift: Angle {
        switch self {
        case .orange: .degrees(0)
        case .lime: .degrees(70)
        case .grape: .degrees(250)
        case .cherry: .degrees(330)
        case .blueberry: .degrees(190)
        case .ripe: .degrees(40)
        }
    }

    func palette(batteryLevel: Double = 1) -> Palette {
        switch self {
        case .orange: Palette(base: "2A0B3D", glow: ["FF8A1F", "FF3D7F", "7A2BFF"])
        case .lime: Palette(base: "062A2E", glow: ["B7E34A", "16C79A", "0A7BD6"])
        case .grape: Palette(base: "160B3A", glow: ["B06CFF", "5B3CFF", "FF4FB8"])
        case .cherry: Palette(base: "2E0616", glow: ["FF4B5C", "FF9A3D", "B0147A"])
        case .blueberry: Palette(base: "0A1236", glow: ["4FA3FF", "7A5CFF", "23D5E8"])
        case .ripe: Flavor.ripePalette(level: batteryLevel)
        }
    }

    /// Lime when the battery is full, orange in the middle, cherry when it is low.
    private static func ripePalette(level: Double) -> Palette {
        switch level {
        case 0.66...: Palette(base: "0B2A20", glow: ["B7E34A", "3ED598", "12A5C8"])
        case 0.3..<0.66: Palette(base: "2A1206", glow: ["FFB02E", "FF7A1A", "C93DAF"])
        default: Palette(base: "2E0616", glow: ["FF4B5C", "FF2D6E", "8B1046"])
        }
    }
}

struct Palette: Equatable {
    var base: Color
    var glow: [Color]

    init(base: String, glow: [String]) {
        self.base = Color(hex: base)
        self.glow = glow.map(Color.init(hex:))
    }

    var accent: Color { glow[0] }
}

/// Modules carry their own colour, the way CleanMyMac gives each tool its own world.
enum Module: String, CaseIterable, Identifiable, Codable {
    case overview, cpu, memory, disk, network, battery, fans, sensors, alerts, flavors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .battery: "Battery"
        case .fans: "Fans"
        case .sensors: "Sensors"
        case .alerts: "Alerts"
        case .flavors: "Flavors"
        }
    }

    /// 3D icon rendered in Blender, from the asset catalog.
    var icon: String {
        switch self {
        case .overview: "icon-juice"
        case .cpu: "icon-cpu"
        case .memory: "icon-memory"
        case .disk: "icon-disk"
        case .network: "icon-disk"
        case .battery: "icon-battery"
        case .fans: "icon-fan"
        case .sensors: "icon-temp"
        case .alerts: "icon-bolt"
        case .flavors: "icon-slice"
        }
    }

    func palette(flavor: Flavor, batteryLevel: Double) -> Palette {
        switch self {
        case .overview, .flavors: flavor.palette(batteryLevel: batteryLevel)
        case .cpu: Palette(base: "190B3A", glow: ["7A5CFF", "3B2BD9", "FF4FB8"])
        case .memory: Palette(base: "062A22", glow: ["5BE3A1", "0FA36B", "1C8CE9"])
        case .disk: Palette(base: "071B3A", glow: ["38C8FF", "0C8CE9", "6C8CFF"])
        case .network: Palette(base: "042A2E", glow: ["23D5E8", "1C8CE9", "7A5CFF"])
        case .battery: Palette(base: "0C2A12", glow: ["B6F36A", "23C55E", "0FA36B"])
        case .fans: Palette(base: "1B0B35", glow: ["18C8FF", "FF4FA3", "8A7BFF"])
        case .sensors: Palette(base: "2A0A14", glow: ["FF7A45", "FF2D55", "FFB800"])
        case .alerts: Palette(base: "2A1A06", glow: ["FFB800", "FF5A1F", "B0147A"])
        }
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(clean, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
