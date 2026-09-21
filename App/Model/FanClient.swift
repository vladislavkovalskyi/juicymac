import Foundation
import JuicyCore
import JuicyHelperKit
import Observation
import ServiceManagement

/// Talks to the privileged helper that writes fan keys, and manages its installation.
@MainActor
@Observable
final class FanClient {
    enum Status: Equatable {
        case notInstalled
        case needsApproval
        case ready
        case failed(String)

        var isReady: Bool { self == .ready }

        var label: String {
            switch self {
            case .notInstalled: "Fan helper not installed"
            case .needsApproval: "Waiting for approval in Login Items"
            case .ready: "Fan helper connected"
            case .failed(let message): message
            }
        }
    }

    private(set) var status: Status = .notInstalled
    private(set) var lastError: String?
    private var connection: NSXPCConnection?
    private var lastCommand: FanCommand?
    private var service: SMAppService { .daemon(plistName: HelperConstants.plistName) }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        switch service.status {
        case .enabled: status = .ready
        case .requiresApproval: status = .needsApproval
        case .notRegistered, .notFound: status = .notInstalled
        @unknown default: status = .notInstalled
        }
    }

    /// Registers the daemon. macOS then asks the user to allow it in System Settings.
    func install() {
        do {
            try service.register()
            refreshStatus()
            if status == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func uninstall() async {
        await apply(.auto, force: true)
        try? await service.unregister()
        connection?.invalidate()
        connection = nil
        refreshStatus()
    }

    /// Sends a command, skipping repeats so the helper only hears about real changes.
    /// The helper's own watchdog returns the fans to macOS if the app stops talking.
    func apply(_ command: FanCommand, force: Bool = false) async {
        guard status.isReady else { return }
        if !force, command == lastCommand, case .auto = command { return }
        lastCommand = command

        guard let proxy = makeProxy() else { return }
        switch command {
        case .auto:
            let error = await withCheckedContinuation { continuation in
                proxy.resetFans { continuation.resume(returning: $0) }
            }
            lastError = error
        case .target(let rpm):
            for fan in 0..<4 {
                let error = await withCheckedContinuation { continuation in
                    proxy.setFan(fan, rpm: rpm) { continuation.resume(returning: $0) }
                }
                // Stop at the first fan the Mac does not have.
                if let error { lastError = fan == 0 ? error : nil; break }
                lastError = nil
            }
        }
    }

    /// Keeps the helper's watchdog fed while a forced mode is active.
    func heartbeat() async {
        guard status.isReady, let command = lastCommand, command != .auto else { return }
        await apply(command, force: true)
    }

    private func makeProxy() -> JuicyHelperProtocol? {
        if connection == nil {
            let new = NSXPCConnection(machServiceName: HelperConstants.label, options: .privileged)
            new.remoteObjectInterface = NSXPCInterface(with: JuicyHelperProtocol.self)
            new.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            new.interruptionHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            new.resume()
            connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.lastError = error.localizedDescription
                self?.connection = nil
            }
        } as? JuicyHelperProtocol
    }
}
