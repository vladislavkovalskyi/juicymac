import Foundation
import JuicyHelperKit
import JuicySystem

/// Privileged helper. Its only job: write fan keys to the SMC on behalf of the signed app,
/// and hand the fans back to macOS when the app stops talking or goes away.
final class HelperService: NSObject, NSXPCListenerDelegate, JuicyHelperProtocol {
    private let queue = DispatchQueue(label: "com.kovalskyi.JuicyMac.Helper.smc")
    private var writer: FanWriter?
    private var watchdog: DispatchWorkItem?
    private var connections = 0

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only the Juicy Mac app, signed by this developer, may talk to the helper.
        let requirement = """
        anchor apple generic and identifier "\(HelperConstants.appBundleID)" \
        and certificate leaf[subject.OU] = "\(teamIdentifier)"
        """
        do {
            try connection.setCodeSigningRequirement(requirement)
        } catch {
            NSLog("JuicyMacHelper: rejected a connection: \(error.localizedDescription)")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: JuicyHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            self?.queue.async {
                guard let self else { return }
                self.connections -= 1
                // The app is gone: never leave the fans locked.
                if self.connections <= 0 { try? self.writer?.resetAll() }
            }
        }
        queue.async { self.connections += 1 }
        connection.resume()
        return true
    }

    private var teamIdentifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "JMTeamIdentifier") as? String) ?? "UNKNOWN"
    }

    // MARK: JuicyHelperProtocol

    func version(reply: @escaping @Sendable (Int) -> Void) {
        reply(HelperConstants.version)
    }

    func setFan(_ fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            do {
                let writer = try openWriter()
                try writer.setFan(fan, rpm: rpm)
                armWatchdog()
                reply(nil)
            } catch {
                reply("\(error)")
            }
        }
    }

    func resetFans(reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            watchdog?.cancel()
            do {
                try openWriter().resetAll()
                reply(nil)
            } catch {
                reply("\(error)")
            }
        }
    }

    // MARK: Internals

    private func openWriter() throws -> FanWriter {
        if let writer { return writer }
        let new = try FanWriter()
        writer = new
        return new
    }

    /// If the app stops sending commands, macOS takes the fans back.
    private func armWatchdog() {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSLog("JuicyMacHelper: no command for \(HelperConstants.watchdogSeconds)s, returning fans to automatic")
            try? writer?.resetAll()
        }
        watchdog = item
        queue.asyncAfter(deadline: .now() + HelperConstants.watchdogSeconds, execute: item)
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: HelperConstants.label)
listener.delegate = service
listener.resume()
RunLoop.main.run()
