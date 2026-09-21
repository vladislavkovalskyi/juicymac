import CSMC
import Foundation
import IOKit

public enum SMCError: Error, Equatable, CustomStringConvertible {
    case unavailable(kern_return_t)
    case keyNotFound(String)
    case notPrivileged
    case unsupportedType(String)
    case failed(String, kern_return_t)

    public var description: String {
        switch self {
        case .unavailable(let kr): "AppleSMC is not reachable (\(kr))."
        case .keyNotFound(let key): "SMC key \(key) does not exist on this Mac."
        case .notPrivileged: "Writing to the SMC needs the Juicy Mac helper."
        case .unsupportedType(let type): "SMC type '\(type)' is not supported."
        case .failed(let key, let kr): "SMC call for \(key) failed (\(kr))."
        }
    }
}

public enum FourCC {
    public static func code(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public static func string(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Raw value of one SMC key plus its decoded number.
public struct SMCValue: Sendable, Equatable {
    public var key: String
    public var type: String
    public var bytes: [UInt8]

    public init(key: String, type: String, bytes: [UInt8]) {
        self.key = key
        self.type = type
        self.bytes = bytes
    }

    public var double: Double? { SMCCodec.decode(type: type, bytes: bytes) }
}

/// Encoding for the SMC data types Juicy Mac reads and writes.
public enum SMCCodec {
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        func be(_ n: Int) -> UInt64? {
            guard bytes.count >= n else { return nil }
            return bytes.prefix(n).reduce(0) { ($0 << 8) | UInt64($1) }
        }
        func le(_ n: Int) -> UInt64? {
            guard bytes.count >= n else { return nil }
            return bytes.prefix(n).reversed().reduce(0) { ($0 << 8) | UInt64($1) }
        }
        switch type {
        case "flt ":
            guard let raw = le(4) else { return nil }
            return Double(Float(bitPattern: UInt32(raw)))
        case "fpe2":
            return be(2).map { Double($0) / 4 }
        case "sp78":
            return be(2).map { Double(Int16(bitPattern: UInt16($0))) / 256 }
        case "ui8 ", "flag":
            return be(1).map { Double($0) }
        case "ui16":
            return be(2).map { Double($0) }
        case "ui32":
            return be(4).map { Double($0) }
        case "si8 ":
            return be(1).map { Double(Int8(bitPattern: UInt8($0))) }
        case "si16":
            return be(2).map { Double(Int16(bitPattern: UInt16($0))) }
        case "ioft":
            return le(8).map { Double($0) / 65536 }
        default:
            return nil
        }
    }

    public static func encode(_ value: Double, type: String) throws -> [UInt8] {
        switch type {
        case "flt ":
            let bits = Float(value).bitPattern
            return [0, 8, 16, 24].map { UInt8((bits >> UInt32($0)) & 0xFF) }
        case "fpe2":
            let raw = UInt16(clamping: Int((value * 4).rounded()))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        case "ui8 ", "flag":
            return [UInt8(clamping: Int(value.rounded()))]
        case "ui16":
            let raw = UInt16(clamping: Int(value.rounded()))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        default:
            throw SMCError.unsupportedType(type)
        }
    }
}

/// Connection to AppleSMC. Not thread-safe: keep each instance on one actor or thread.
public final class SMC {
    private var connection: io_connect_t = 0

    public init() throws {
        let kr = smc_open(&connection)
        guard kr == kIOReturnSuccess else { throw SMCError.unavailable(kr) }
    }

    deinit { smc_close(connection) }

    public func read(_ key: String) -> SMCValue? {
        var value = smc_value_t()
        guard smc_read(connection, FourCC.code(key), &value) == kIOReturnSuccess else { return nil }
        let size = Int(value.info.size)
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(size)) }
        return SMCValue(key: key, type: FourCC.string(value.info.type), bytes: bytes)
    }

    public func double(_ key: String) -> Double? { read(key)?.double }

    public func type(of key: String) -> String? {
        var info = smc_key_info_t()
        guard smc_key_info(connection, FourCC.code(key), &info) == kIOReturnSuccess else { return nil }
        return FourCC.string(info.type)
    }

    /// Writes `value` using the key's own data type. Needs root.
    public func write(_ key: String, _ value: Double) throws {
        guard let type = type(of: key) else { throw SMCError.keyNotFound(key) }
        let bytes = try SMCCodec.encode(value, type: type)
        let kr = bytes.withUnsafeBufferPointer { smc_write(connection, FourCC.code(key), $0.baseAddress, UInt32($0.count)) }
        switch kr {
        case kIOReturnSuccess: return
        case kIOReturnNotPrivileged: throw SMCError.notPrivileged
        default: throw SMCError.failed(key, kr)
        }
    }

    /// Every key in the SMC table. Takes ~100 ms, so callers cache the result.
    public func allKeys() -> [String] {
        guard let count = double("#KEY"), count > 0 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for index in 0..<UInt32(count) {
            var key: UInt32 = 0
            if smc_key_at_index(connection, index, &key) == kIOReturnSuccess {
                keys.append(FourCC.string(key))
            }
        }
        return keys
    }
}
