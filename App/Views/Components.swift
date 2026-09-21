import Charts
import JuicyCore
import SwiftUI

/// Every panel in the app is this card: same padding, same radius, same header rhythm.
struct GlassCard<Content: View>: View {
    var title: String?
    var icon: String?
    var trailing: String?
    var radius: CGFloat = Space.radius
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || icon != nil {
                HStack(spacing: 8) {
                    if let icon { JuicyIcon(name: icon, size: 34).padding(-4) }
                    if let title { Text(title).eyebrow() }
                    Spacer(minLength: 4)
                    if let trailing { Text(trailing).monoStyle() }
                }
                .frame(height: 26)
            }
            content
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .juicyGlass(radius: radius)
    }
}

/// The four-across summary card: icon row, one big number, a visual, one line of detail.
/// Fixed slots keep every card on the same baselines.
struct StatCard<Visual: View>: View {
    var module: Module
    var value: String
    var unit: String?
    var footer: String
    var action: (() -> Void)?
    @ViewBuilder var visual: Visual

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    JuicyIcon(name: module.icon, size: 34).padding(-4)
                    Text(module.title).eyebrow()
                    Spacer(minLength: 0)
                }
                .frame(height: 26)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(JuicyFont.readout(26))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit).font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(height: 30, alignment: .bottom)

                visual
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                Text(footer)
                    .captionStyle()
                    .lineLimit(2)
                    .frame(height: 30, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.card)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .juicyGlass(radius: Space.radius)
    }
}

/// Line + area chart over a metric's history.
struct MetricChart: View {
    var points: [Point]
    var unit: String
    var maximum: Double?
    var height: CGFloat = 150
    var showsAxes = true
    var tint: Color = .white

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Time", point.date), y: .value(unit, point.value))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", point.date), y: .value(unit, point.value))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...(maximum ?? max(1, (points.map(\.value).max() ?? 1) * 1.25)))
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.14))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(label(number))
                                .font(JuicyFont.mono)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .chartXAxis {
            if showsAxes {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.system(size: 10))
                }
            }
        }
        .frame(height: height)
    }

    private func label(_ value: Double) -> String {
        switch unit {
        case "%": "\(Int(value))%"
        case "°C": "\(Int(value))°"
        case "rpm": value >= 1000 ? "\(Int(value / 1000))k" : "\(Int(value))"
        case "B/s": Fmt.rate(value)
        default: value.formatted(.number.precision(.fractionLength(0)))
        }
    }
}

/// Title block at the top of a module screen: icon, eyebrow, one big number, one line of context.
struct ModuleHeader: View {
    var icon: String
    var eyebrow: String
    var title: String
    var subtitle: String
    var hueShift: Angle = .zero

    var body: some View {
        HStack(spacing: 16) {
            JuicyIcon(name: icon, size: 116, hueShift: hueShift).padding(-14)
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow).eyebrow()
                Text(title).displayStyle()
                Text(subtitle)
                    .bodyStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 132)
    }
}

/// Label/value rows inside a card.
struct KeyValues: View {
    var rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0).captionStyle()
                    Text(row.1)
                        .monoStyle()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

/// Process list with a quit button, used in Overview and CPU.
struct ProcessList: View {
    @Environment(AppModel.self) private var model
    var limit = 6

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.snapshot.processes.prefix(limit)) { process in
                HStack(spacing: 10) {
                    Text(process.name).font(JuicyFont.body).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.memory(process.memoryBytes)).monoStyle()
                    SegmentBar(segments: [(min(1, process.cpuPercent / 200), 1)], height: 6).frame(width: 80)
                    Text("\(Int(process.cpuPercent))%")
                        .monoStyle()
                        .frame(width: 44, alignment: .trailing)
                    Button("Quit") { model.quit(pid: process.pid) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                .frame(height: 24)
            }
        }
    }
}

/// Core-by-core bars: performance cores solid, efficiency cores dimmed.
struct CoreBars: View {
    var cores: [Double]
    var performanceCores: Int
    var height: CGFloat = 70

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(cores.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(isPerformance(index) ? 0.95 : 0.5))
                    .frame(height: max(4, height * value))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    /// Kernel order puts efficiency cores first on Apple silicon.
    private func isPerformance(_ index: Int) -> Bool {
        index >= cores.count - performanceCores
    }
}
