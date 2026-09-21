import JuicyCore
import JuicySystem
import SwiftUI

// MARK: - Sensors

struct SensorsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(icon: "icon-temp", eyebrow: "Sensors · \(model.snapshot.sensors.count) readable",
                         title: Fmt.temperature(model.snapshot.cpuTemperature, fahrenheit: model.preferences.fahrenheit),
                         subtitle: subtitle)
            HStack {
                TextField("Filter by name or SMC key", text: $search)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .juicyGlass(radius: 12)
                    .frame(width: 320)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(SensorGroup.allCases, id: \.self) { group in
                        let sensors = filtered(group)
                        if !sensors.isEmpty {
                            GlassCard(title: group.title, trailing: hottest(sensors)) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 8) {
                                    ForEach(sensors) { sensor in
                                        HStack(spacing: 8) {
                                            Text(sensor.key)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.6))
                                                .frame(width: 38, alignment: .leading)
                                            Text(sensor.name).font(.system(size: 12.5)).lineLimit(1)
                                            Spacer(minLength: 4)
                                            Text(Fmt.temperature(sensor.celsius, fahrenheit: model.preferences.fahrenheit))
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .monospacedDigit()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        var parts = ["Hottest CPU sensor"]
        if let gpu = model.snapshot.gpuTemperature {
            parts.append("GPU \(Fmt.temperature(gpu, fahrenheit: model.preferences.fahrenheit))")
        }
        if let watts = model.snapshot.power.systemWatts { parts.append("system draw \(Fmt.watts(watts))") }
        return parts.joined(separator: " · ") + ". Read straight from the SMC."
    }

    private func filtered(_ group: SensorGroup) -> [Sensor] {
        model.snapshot.sensors
            .filter { $0.group == group }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.key.localizedCaseInsensitiveContains(search) }
            .sorted { $0.celsius > $1.celsius }
    }

    private func hottest(_ sensors: [Sensor]) -> String {
        Fmt.temperature(sensors.map(\.celsius).max(), fahrenheit: model.preferences.fahrenheit)
    }
}

// MARK: - Alerts

struct AlertsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(icon: "icon-bolt", eyebrow: "Alerts · \(model.preferences.rules.filter(\.isEnabled).count) active",
                         title: "When something's off.",
                         subtitle: "Every rule watches one number. When it holds past the threshold for long enough, Juicy Mac acts.")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($model.preferences.rules) { $rule in
                        RuleCard(rule: $rule)
                    }
                    Button {
                        model.preferences.rules.append(
                            AlertRule(metric: .cpuTemperature, comparator: .above, threshold: 95, duration: 60, actions: [.notify])
                        )
                    } label: {
                        Label("Add rule", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .juicyGlass(radius: 18)

                    if !model.firedAlerts.isEmpty {
                        GlassCard(title: "Recently fired") {
                            ForEach(Array(model.firedAlerts.enumerated()), id: \.offset) { _, event in
                                HStack {
                                    Text(event.rule.conditionText).font(.system(size: 13))
                                    Spacer()
                                    Text("\(Int(event.value))\(event.rule.metric.unit)")
                                        .font(.system(size: 12, design: .monospaced))
                                    Text(event.date, style: .time)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct RuleCard: View {
    @Environment(AppModel.self) private var model
    @Binding var rule: AlertRule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("", isOn: $rule.isEnabled).labelsHidden().toggleStyle(.switch)
                Picker("", selection: $rule.metric) {
                    ForEach(AlertRule.Metric.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
                Picker("", selection: $rule.comparator) {
                    Text("above").tag(AlertRule.Comparator.above)
                    Text("below").tag(AlertRule.Comparator.below)
                }
                .labelsHidden()
                .frame(width: 100)
                TextField("", value: $rule.threshold, format: .number)
                    .textFieldStyle(.plain)
                    .frame(width: 60)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: 8))
                Text(rule.metric.unit).font(.system(size: 13))
                Text("for").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                Picker("", selection: $rule.duration) {
                    Text("instantly").tag(TimeInterval(0))
                    Text("30 s").tag(TimeInterval(30))
                    Text("1 min").tag(TimeInterval(60))
                    Text("5 min").tag(TimeInterval(300))
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer(minLength: 4)
                Button {
                    model.preferences.rules.removeAll { $0.id == rule.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.glass)
            }
            HStack(spacing: 8) {
                ForEach(AlertRule.Action.allCases) { action in
                    Button {
                        if rule.actions.contains(action) { rule.actions.remove(action) } else { rule.actions.insert(action) }
                    } label: {
                        Text(action.title)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(rule.actions.contains(action) ? .black : .white)
                    .background(rule.actions.contains(action) ? Color.white.opacity(0.92) : Color.white.opacity(0.14),
                                in: .capsule)
                }
                Spacer()
                if let value = rule.value(in: model.snapshot) {
                    Text("now \(Int(value))\(rule.metric.unit)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .padding(14)
        .juicyGlass(radius: 20)
    }
}

// MARK: - Flavors

struct FlavorsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            ModuleHeader(icon: "icon-slice", eyebrow: "Flavors",
                         title: "Pick a juice.",
                         subtitle: "A flavor tints the wallpaper, the glass in the menubar and the juice icon. Module colours stay their own.",
                         hueShift: model.preferences.flavor.hueShift)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(Flavor.allCases) { flavor in
                    Button {
                        model.preferences.flavor = flavor
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            ZStack {
                                FlavorBackground(palette: flavor.palette(batteryLevel: model.snapshot.battery?.level ?? 1))
                                    .clipShape(.rect(cornerRadius: 18))
                                JuicyIcon(name: "icon-juice", size: 130, hueShift: flavor.hueShift)
                            }
                            .frame(height: 170)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(flavor.title).font(.system(size: 16, weight: .bold))
                                Text(flavor.blurb)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 4)
                        }
                        .padding(6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .juicyGlass(radius: 24)
                    .overlay {
                        if model.preferences.flavor == flavor {
                            RoundedRectangle(cornerRadius: 24).stroke(.white, lineWidth: 2)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Menubar") {
                Picker("Style", selection: $model.preferences.menubarStyle) {
                    ForEach(MenubarStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show time remaining instead of percent", isOn: $model.preferences.showTimeRemaining)
                Text(model.preferences.menubarStyle.blurb)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("General") {
                Picker("Flavor", selection: $model.preferences.flavor) {
                    ForEach(Flavor.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show temperatures in Fahrenheit", isOn: $model.preferences.fahrenheit)
                Toggle("Launch at login", isOn: $model.preferences.launchAtLogin)
                Toggle("Keep the Mac awake", isOn: $model.preferences.keepAwake)
            }
            Section("Sampling") {
                Picker("While open", selection: $model.preferences.refreshSeconds) {
                    Text("Every second").tag(1.0)
                    Text("Every 2 seconds").tag(2.0)
                    Text("Every 5 seconds").tag(5.0)
                }
                Picker("In the background", selection: $model.preferences.backgroundRefreshSeconds) {
                    Text("Every 3 seconds").tag(3.0)
                    Text("Every 10 seconds").tag(10.0)
                    Text("Every 30 seconds").tag(30.0)
                }
            }
            Section("Fan helper") {
                LabeledContent("Status", value: model.fans.status.label)
                HStack {
                    Button("Install…") { model.fans.install() }
                        .disabled(model.fans.status.isReady)
                    Button("Remove") { Task { await model.fans.uninstall() } }
                        .disabled(!model.fans.status.isReady)
                }
                if let error = model.fans.lastError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Section("Shortcut") {
                Text("⌥⌘J opens the popover from anywhere.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}
