import JuicyCore
import SwiftUI

/// What drops down from the menubar: charge, four tiles, fan modes, thirsty apps, flavors.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            header
            tiles
            fanCard
            processes
            footer
        }
        .padding(18)
        .frame(width: 400)
        .background(FlavorBackground(palette: model.flavorPalette))
        .foregroundStyle(.white)
        .onAppear { model.isPopoverOpen = true }
        .onDisappear { model.isPopoverOpen = false }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                JuicyIcon(name: "icon-juice", size: 76, hueShift: model.preferences.flavor.hueShift)
                if model.snapshot.battery?.isCharging == true {
                    Bubbles().frame(width: 40, height: 50).offset(y: 6)
                }
            }
            .padding(.leading, -8)

            VStack(alignment: .leading, spacing: 2) {
                Readout(value: Fmt.percent(model.snapshot.battery?.level ?? 1).replacingOccurrences(of: "%", with: ""),
                        unit: "%", size: 38)
                Text(chargeSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button {
                open(.overview)
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Open Juicy Mac")
        }
    }

    private var chargeSubtitle: String {
        guard let battery = model.snapshot.battery else { return "No battery on this Mac" }
        if let time = Fmt.duration(minutes: battery.minutesRemaining) {
            return battery.isCharging ? "\(time) to full" : "\(time) of juice left"
        }
        return battery.isPluggedIn ? "Plugged in" : "On battery"
    }

    // MARK: Tiles

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile(.cpu, "icon-cpu", Fmt.percent(model.snapshot.cpu.usage),
                 "\(model.snapshot.cpu.performanceCores)P + \(model.snapshot.cpu.efficiencyCores)E cores", .cpu, 100)
            tile(.memory, "icon-memory", Fmt.memory(model.snapshot.memory.used),
                 "of \(Fmt.memory(model.snapshot.memory.total)) · \(model.snapshot.memory.pressure.label)", .memory, 100)
            tile(.disk, "icon-disk", Fmt.bytes(model.snapshot.disk.available),
                 "free of \(Fmt.bytes(model.snapshot.disk.total))", .diskWrite, nil)
            tile(.sensors, "icon-temp", Fmt.temperature(model.snapshot.cpuTemperature, fahrenheit: model.preferences.fahrenheit),
                 gpuSubtitle, .cpuTemp, 100)
        }
    }

    private var gpuSubtitle: String {
        if let gpu = model.snapshot.gpu.usage { return "CPU die · GPU \(Fmt.percent(gpu))" }
        return "hottest CPU sensor"
    }

    private func tile(_ module: Module, _ icon: String, _ value: String, _ subtitle: String,
                      _ metric: Metric, _ scale: Double?) -> some View {
        Button {
            open(module)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    JuicyIcon(name: icon, size: 34).padding(-4)
                    Text(module.title).eyebrow()
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                chart(metric, scale)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .juicyGlass(radius: 18)
    }

    private func chart(_ metric: Metric, _ scale: Double?) -> some View {
        let values = model.points(metric, range: .quarter).map(\.value)
        return ZStack {
            SparkArea(points: values, scale: scale ?? 1).fill(.white.opacity(0.16))
            Sparkline(points: values, scale: scale ?? 1).stroke(.white, lineWidth: 1.6)
        }
        .frame(height: 26)
    }

    // MARK: Fans

    private var fanCard: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                JuicyIcon(name: "icon-fan", size: 34).padding(-4)
                Text("Fans").eyebrow()
                Spacer()
                Text(fanSummary)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Picker("", selection: $model.preferences.fanMode) {
                ForEach([FanMode.auto, .chill, .blast]) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!model.fans.status.isReady)

            Text(model.fans.status.isReady ? model.fanCommandDescription : model.fans.status.label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .juicyGlass(radius: 18)
    }

    private var fanSummary: String {
        let fans = model.snapshot.fans
        guard !fans.isEmpty else { return "no fans" }
        return fans.map { Fmt.rpm($0.rpm).replacingOccurrences(of: " rpm", with: "") }.joined(separator: " · ") + " rpm"
    }

    // MARK: Processes

    private var processes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thirstiest apps").eyebrow()
            ForEach(model.snapshot.processes.prefix(3)) { process in
                HStack(spacing: 10) {
                    Text(process.name).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 8)
                    SegmentBar(segments: [(min(1, process.cpuPercent / 200), 1)], height: 6).frame(width: 70)
                    Text("\(Int(process.cpuPercent))%")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 42, alignment: .trailing)
                }
            }
            if model.snapshot.processes.isEmpty {
                Text("Measuring…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Footer

    private var footer: some View {
        @Bindable var model = model
        return HStack {
            HStack(spacing: 7) {
                ForEach(Flavor.allCases) { flavor in
                    Button {
                        model.preferences.flavor = flavor
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: flavor.palette().glow, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(.white, lineWidth: model.preferences.flavor == flavor ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(flavor.title)
                }
            }
            Spacer()
            Button("Open Juicy Mac") { open(.overview) }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(.black)
        }
    }

    private func open(_ module: Module) {
        model.selectedModule = module
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// Bubbles rising in the glass while the Mac charges.
struct Bubbles: View {
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            Canvas { canvas, size in
                let t = context.date.timeIntervalSinceReferenceDate
                for i in 0..<5 {
                    let seed = Double(i) * 0.37
                    let progress = ((t * 0.35 + seed).truncatingRemainder(dividingBy: 1))
                    let radius = 1.2 + Double(i % 3) * 0.7
                    let x = size.width * (0.25 + 0.5 * ((seed * 7).truncatingRemainder(dividingBy: 1)))
                    let y = size.height * (1 - progress)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    canvas.fill(Circle().path(in: rect), with: .color(.white.opacity(0.45 * (1 - progress))))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
