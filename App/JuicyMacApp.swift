import AppKit
import JuicyCore
import SwiftUI

@main
struct JuicyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    static let isFirstLaunch = UserDefaults.standard.data(forKey: Preferences.storageKey) == nil

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environment(delegate.model)
        } label: {
            MenubarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        // First run opens the window so the app introduces itself; later runs stay in the menubar.
        Window("Juicy Mac", id: "main") {
            MainWindow()
                .environment(delegate.model)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1180, height: 780)
        .defaultPosition(.center)
        .defaultLaunchBehavior(JuicyMacApp.isFirstLaunch ? .presented : .suppressed)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Copy report") {
                    Report.copyToPasteboard(Report.text(snapshot: delegate.model.snapshot, score: delegate.model.score,
                                                        fahrenheit: delegate.model.preferences.fahrenheit))
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView().environment(delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    let model = AppModel()
    private let hotKey = HotKey()
    private let caffeine = Caffeine()
    private var preferencesObserver: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // A menubar app with no Dock icon until its window opens.
        NSApp.setActivationPolicy(.accessory)

        hotKey.register { [weak self] in
            self?.openPopover()
        }

        // Keep the power assertion in step with the preference.
        preferencesObserver = Task { [weak self] in
            while !Task.isCancelled {
                if let self { caffeine.set(model.preferences.keepAwake) }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        caffeine.set(false)
        // Never leave the fans locked to a forced speed after quitting.
        let fans = model.fans
        Task { await fans.apply(.auto, force: true) }
        RunLoop.current.run(until: .now.addingTimeInterval(0.4))
    }

    /// Clicks the menubar item, which is how a MenuBarExtra popover is opened programmatically.
    private func openPopover() {
        guard let button = NSApp.windows.compactMap({ $0.value(forKey: "statusItem") as? NSStatusItem }).first?.button else {
            NSApp.activate()
            return
        }
        button.performClick(nil)
    }
}

/// Makes the window's own background transparent so the mesh gradient reaches the edges,
/// and switches the app between Dock icon and menubar-only as the window opens and closes.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            // Opaque: the mesh gradient is the background, nothing shows through from behind.
            window.isOpaque = true
            window.backgroundColor = NSColor(red: 0.10, green: 0.04, blue: 0.16, alpha: 1)
            window.appearance = NSAppearance(named: .darkAqua)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        Task { @MainActor in
            // Back to a menubar-only app when the last window goes away.
            if NSApp.windows.allSatisfy({ !$0.isVisible || $0.className.contains("StatusBar") }) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
