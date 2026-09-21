import JuicyCore
import SwiftUI

struct FansView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                JuicyIcon(name: "icon-fan", size: 140).padding(-16)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fans · \(model.snapshot.fans.count) detected").eyebrow()
                    Text("Keep it cool.").font(.system(size: 42, weight: .heavy)).kerning(-1)
                    Text(model.fanCommandDescription)
                        .bodyStyle()
                }
                Spacer(minLength: 0)
                ForEach(model.snapshot.fans) { fan in
                    dial(fan)
                }
            }
            .frame(height: 170)

            if !model.fans.status.isReady {
                installCard
            }

            HStack(spacing: 14) {
                ForEach(FanMode.allCases) { mode in
                    modeCard(mode)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                GlassCard(title: "Custom curve", trailing: curveTrailing) {
                    CurveEditor(curve: $model.preferences.fanCurve, currentTemperature: model.snapshot.cpuTemperature)
                        .frame(height: 260)
                }
                GlassCard(title: "When something's off", icon: "icon-bolt") {
                    ForEach($model.preferences.rules) { $rule in
                        VStack(spacing: 0) {
                            Divider().overlay(.white.opacity(0.14))
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.conditionText).font(.system(size: 13.5, weight: .semibold))
                                    Text(rule.actionText).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                                }
                                Spacer(minLength: 8)
                                Toggle("", isOn: $rule.isEnabled).labelsHidden().toggleStyle(.switch)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .frame(width: 380)
            }
        }
    }

    private var curveTrailing: String {
        guard let temperature = model.snapshot.cpuTemperature else { return "no sensor" }
        let rpm = model.preferences.fanCurve.rpm(at: temperature)
        return "now \(Int(temperature))°C → \(Fmt.rpm(rpm))"
    }

    private func dial(_ fan: Fan) -> some View {
        ZStack {
            RingGauge(fraction: fan.fraction, lineWidth: 8).padding(13)
            VStack(spacing: 0) {
                Text(Fmt.rpm(fan.rpm).replacingOccurrences(of: " rpm", with: ""))
                    .font(JuicyFont.readout(26))
                    .monospacedDigit()
                Text(fan.name).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 150, height: 150)
        .juicyGlass(radius: 75)
    }

    private var installCard: some View {
        GlassCard(radius: 18) {
            HStack(spacing: 12) {
                JuicyIcon(name: "icon-bolt", size: 34).padding(-4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fan control needs the Juicy Mac helper").font(.system(size: 14, weight: .semibold))
                    Text("Writing fan speeds requires root, so it runs in a tiny privileged service you approve once in System Settings.")
                        .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 8)
                Button(model.fans.status == .needsApproval ? "Open Login Items" : "Install helper") {
                    model.fans.install()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).frame(height: 30)
                .background(.white, in: .capsule)
                .foregroundStyle(.black)
                .font(.system(size: 13, weight: .semibold))
            }
        }
    }

    private func modeCard(_ mode: FanMode) -> some View {
        @Bindable var model = model
        let isOn = model.preferences.fanMode == mode
        return Button {
            model.preferences.fanMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(mode.title).font(.system(size: 17, weight: .bold))
                    Spacer()
                    Circle()
                        .strokeBorder(isOn ? .clear : .white.opacity(0.7), lineWidth: 1.5)
                        .background(Circle().fill(isOn ? Color.black : .clear))
                        .frame(width: 12, height: 12)
                }
                Text(mode.blurb)
                    .font(.system(size: 12.5))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? .black : .white)
        .background {
            if isOn {
                RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.92))
            }
        }
        .juicyGlass(radius: 20)
        .disabled(!model.fans.status.isReady && mode != .auto)
    }
}

/// Temperature → rpm curve with draggable stops.
struct CurveEditor: View {
    @Binding var curve: FanCurve
    var currentTemperature: Double?

    private let tempRange = 40.0...100.0
    private let rpmRange = 0.0...6000.0

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: 34, y: 8, width: geo.size.width - 44, height: geo.size.height - 30)
            ZStack(alignment: .topLeading) {
                grid(plot)
                curveShape(plot)
                stops(plot)
                if let temperature = currentTemperature {
                    marker(plot, temperature)
                }
                labels(plot)
            }
        }
    }

    private func x(_ celsius: Double, _ plot: CGRect) -> CGFloat {
        plot.minX + plot.width * (celsius - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)
    }

    private func y(_ rpm: Double, _ plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * (rpm - rpmRange.lowerBound) / (rpmRange.upperBound - rpmRange.lowerBound)
    }

    private func celsius(_ px: CGFloat, _ plot: CGRect) -> Double {
        tempRange.lowerBound + (px - plot.minX) / plot.width * (tempRange.upperBound - tempRange.lowerBound)
    }

    private func rpm(_ py: CGFloat, _ plot: CGRect) -> Double {
        rpmRange.lowerBound + (plot.maxY - py) / plot.height * (rpmRange.upperBound - rpmRange.lowerBound)
    }

    private func grid(_ plot: CGRect) -> some View {
        Path { path in
            for value in stride(from: 0.0, through: 6000, by: 2000) {
                path.move(to: CGPoint(x: plot.minX, y: y(value, plot)))
                path.addLine(to: CGPoint(x: plot.maxX, y: y(value, plot)))
            }
        }
        .stroke(.white.opacity(0.14), lineWidth: 1)
    }

    private func curveShape(_ plot: CGRect) -> some View {
        let points = curve.stops.map { CGPoint(x: x($0.celsius, plot), y: y($0.rpm, plot)) }
        return ZStack {
            Path { path in
                guard let first = points.first, let last = points.last else { return }
                path.move(to: CGPoint(x: first.x, y: plot.maxY))
                path.addLine(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
                path.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                path.closeSubpath()
            }
            .fill(.white.opacity(0.14))
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
    }

    private func stops(_ plot: CGRect) -> some View {
        ForEach(Array(curve.stops.enumerated()), id: \.element.id) { index, stop in
            Circle()
                .fill(.black.opacity(0.6))
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .frame(width: 14, height: 14)
                .position(x: x(stop.celsius, plot), y: y(stop.rpm, plot))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            curve.move(stopAt: index, celsius: celsius(value.location.x, plot), rpm: rpm(value.location.y, plot))
                        }
                )
        }
    }

    private func marker(_ plot: CGRect, _ temperature: Double) -> some View {
        let clamped = min(max(temperature, tempRange.lowerBound), tempRange.upperBound)
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: x(clamped, plot), y: plot.minY))
                path.addLine(to: CGPoint(x: x(clamped, plot), y: plot.maxY))
            }
            .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
                .position(x: x(clamped, plot), y: y(curve.rpm(at: clamped), plot))
        }
    }

    private func labels(_ plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([0, 2000, 4000, 6000], id: \.self) { value in
                Text(value >= 1000 ? "\(value / 1000)k" : "0")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .position(x: plot.minX - 16, y: y(Double(value), plot))
            }
            ForEach([40, 55, 70, 85, 100], id: \.self) { value in
                Text("\(value)°")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .position(x: x(Double(value), plot), y: plot.maxY + 12)
            }
        }
    }
}
