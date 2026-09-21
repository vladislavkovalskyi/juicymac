import Foundation
import JuicySystem

public enum HelperConstants {
    public static let label = "com.kovalskyi.JuicyMac.Helper"
    public static let plistName = "com.kovalskyi.JuicyMac.Helper.plist"
    public static let appBundleID = "com.kovalskyi.JuicyMac"
    /// Bump when the XPC interface changes so the app can ask for a helper update.
    public static let version = 1
    /// Without a command for this long the helper hands the fans back to macOS.
    public static let watchdogSeconds: TimeInterval = 30
}

/// XPC interface of the privileged helper. Replies carry `nil` on success or an error message.
@objc(JuicyHelperProtocol)
public protocol JuicyHelperProtocol {
    func version(reply: @escaping @Sendable (Int) -> Void)
    /// Forces `fan` to `rpm`, clamped to the fan's min/max. `rpm` <= 0 returns that fan to automatic.
    func setFan(_ fan: Int, rpm: Double, reply: @escaping @Sendable (String?) -> Void)
    /// Returns every fan to automatic control.
    func resetFans(reply: @escaping @Sendable (String?) -> Void)
}

/// Writes fan control keys. Only works as root; the helper owns the only instance.
public final class FanWriter {
    private let smc: SMC
    public let fanCount: Int
    private let hasTestUnlock: Bool
    private var unlocked = false

    public init() throws {
        smc = try SMC()
        fanCount = Int(smc.double("FNum") ?? 0)
        hasTestUnlock = smc.type(of: "Ftst") != nil
    }

    public func setFan(_ index: Int, rpm: Double) throws {
        guard index >= 0, index < fanCount else { throw SMCError.keyNotFound("F\(index)Tg") }
        if rpm <= 0 {
            try smc.write("F\(index)Md", 0)
            return
        }
        let minimum = smc.double("F\(index)Mn") ?? 0
        let maximum = smc.double("F\(index)Mx") ?? rpm
        let target = FanWriter.clamp(rpm, min: minimum, max: maximum)
        // Newer Apple silicon ignores forced mode until the test flag is raised.
        if hasTestUnlock, !unlocked {
            try smc.write("Ftst", 1)
            unlocked = true
        }
        try smc.write("F\(index)Md", 1)
        try smc.write("F\(index)Tg", target)
    }

    public func resetAll() throws {
        var firstError: Error?
        for i in 0..<fanCount {
            do { try smc.write("F\(i)Md", 0) } catch { firstError = firstError ?? error }
        }
        if hasTestUnlock {
            do { try smc.write("Ftst", 0) } catch { firstError = firstError ?? error }
            unlocked = false
        }
        if let firstError { throw firstError }
    }

    public static func clamp(_ rpm: Double, min lower: Double, max upper: Double) -> Double {
        guard upper > 0 else { return rpm }
        return Swift.min(Swift.max(rpm, lower), upper)
    }
}
