import JuicyCore
import JuicySystem
import SwiftUI

/// One background for the whole window; the sidebar is a glass panel floating on it,
/// not a second gradient. Nothing is layered over anything else.
struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 236)
                .padding(10)
            detailColumn
        }
        .background {
            FlavorBackground(palette: model.palette)
                .animation(.easeInOut(duration: 0.5), value: model.selectedModule)
        }
        .frame(minWidth: 1060, minHeight: 720)
        .foregroundStyle(.white)
        .onAppear {
            model.isWindowOpen = true
            model.requestNotificationAccess()
        }
        .onDisappear { model.isWindowOpen = false }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the traffic lights, which sit over this panel.
            Color.clear.frame(height: 26)

            HStack(spacing: 8) {
                JuicyIcon(name: "icon-slice", size: 32).padding(-4)
                Text("Juicy Mac").font(.system(size: 16, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)

            ForEach(Module.allCases) { module in
                sidebarRow(module)
            }

            Spacer(minLength: 12)
            statusCard
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .juicyGlass(radius: 24)
    }

    private func sidebarRow(_ module: Module) -> some View {
        let isSelected = model.selectedModule == module
        return Button {
            model.selectedModule = module
        } label: {
            HStack(spacing: 10) {
                JuicyIcon(name: module.icon, size: 28,
                          hueShift: module == .overview ? model.preferences.flavor.hueShift : .zero)
                    .padding(-2)
                Text(module.title).font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
                if module == .alerts, !model.firedAlerts.isEmpty {
                    Text("\(model.firedAlerts.count)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.28), in: .capsule)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22))
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.fans.status.isReady ? Color(hex: "5CF08A") : Color(hex: "FFB800"))
                    .frame(width: 8, height: 8)
                Text(model.fans.status.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
            }
            Text("\(SystemInfo.chipName) · \(SystemInfo.osVersion)")
                .captionStyle()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.14), in: .rect(cornerRadius: 14))
    }

    // MARK: Detail

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            topBar
            // Modules can be taller than the window; the top bar must never be pushed off-screen.
            ScrollView(.vertical) {
                detail
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(minHeight: 560)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 14)
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .padding(.leading, 10)
    }

    private var topBar: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Text(model.selectedModule.title).titleStyle()
            Spacer()
            if model.selectedModule.showsHistory {
                Picker("Range", selection: $model.range) {
                    ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }
            Menu {
                Button("Copy report") {
                    Report.copyToPasteboard(Report.text(snapshot: model.snapshot, score: model.score,
                                                        fahrenheit: model.preferences.fahrenheit))
                }
                Button("Export history as CSV…") {
                    Report.saveCSV(Report.csv(model.history, range: model.range))
                }
                Divider()
                SettingsLink { Text("Settings…") }
                Button("Quit Juicy Mac") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .frame(width: 44)
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedModule {
        case .overview: OverviewView()
        case .cpu: CPUView()
        case .memory: MemoryView()
        case .disk: DiskView()
        case .network: NetworkView()
        case .battery: BatteryView()
        case .fans: FansView()
        case .sensors: SensorsView()
        case .alerts: AlertsView()
        case .flavors: FlavorsView()
        }
    }
}

extension Module {
    /// Screens that chart history show the range picker; the rest do not.
    var showsHistory: Bool {
        switch self {
        case .flavors, .alerts, .sensors, .fans: false
        default: true
        }
    }
}
