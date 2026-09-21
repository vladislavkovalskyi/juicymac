import AppKit
import JuicyCore
import SwiftUI

/// The menubar item itself. Rendered to an NSImage so macOS can tint it like any other status item;
/// the alarm style keeps its own colour instead.
struct MenubarLabel: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: model.menubarImage ?? MenubarRenderer.render(model))
            .renderingMode(model.alarmIsOn ? .original : .template)
            .accessibilityLabel("Juicy Mac")
    }
}

/// Draws the menubar item to an NSImage so macOS can tint it like any other status item.
enum MenubarRenderer {
    @MainActor
    static func render(_ model: AppModel) -> NSImage {
        let renderer = ImageRenderer(content: MenubarContent(model: model))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = !model.alarmIsOn
        return image
    }
}

private struct MenubarContent: View {
    let model: AppModel

    var body: some View { content }

    private var level: Double { model.snapshot.battery?.level ?? 1 }

    @ViewBuilder
    private var content: some View {
        let tint: Color = model.alarmIsOn ? Color(hex: "FF3B4E") : .black
        HStack(spacing: 5) {
            switch model.preferences.menubarStyle {
            case .glass:
                glass(tint)
            case .glassPercent:
                glass(tint)
                Text(chargeText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            case .readouts:
                readout("CPU", Fmt.percent(model.snapshot.cpu.usage))
                readout("MEM", Fmt.percent(model.snapshot.memory.usedFraction))
                readout("HEAT", Fmt.temperature(model.snapshot.cpuTemperature, fahrenheit: model.preferences.fahrenheit))
            case .pulse:
                Sparkline(points: model.points(.cpu, range: .minute).map(\.value), scale: 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 34, height: 13)
                Text(Fmt.percent(model.snapshot.cpu.usage))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            if model.alarmIsOn, model.preferences.menubarStyle != .readouts {
                Text(Fmt.temperature(model.snapshot.cpuTemperature, fahrenheit: model.preferences.fahrenheit))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 1)
        .frame(height: 18)
    }

    private func glass(_ tint: Color) -> some View {
        JuiceGlassIcon(level: level, tint: tint, lineWidth: 5)
            .frame(width: 12, height: 16)
    }

    private var chargeText: String {
        if model.preferences.showTimeRemaining, let minutes = model.snapshot.battery?.minutesRemaining,
           let text = Fmt.duration(minutes: minutes) {
            return text
        }
        return Fmt.percent(level)
    }

    private func readout(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(title).font(.system(size: 7, weight: .bold))
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}

/// A line through a series of values, normalised to `scale`.
struct Sparkline: Shape {
    var points: [Double]
    var scale: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return path
        }
        let maximum = max(scale, points.max() ?? scale)
        for (index, value) in points.enumerated() {
            let x = rect.minX + rect.width * Double(index) / Double(points.count - 1)
            let y = rect.maxY - rect.height * min(1, max(0, value / maximum))
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

/// Filled version of the sparkline for cards.
struct SparkArea: Shape {
    var points: [Double]
    var scale: Double

    func path(in rect: CGRect) -> Path {
        var path = Sparkline(points: points, scale: scale).path(in: rect)
        guard points.count > 1 else { return path }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
