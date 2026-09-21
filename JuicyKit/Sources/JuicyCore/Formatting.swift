import Foundation

public enum Fmt {
    /// The UI is English, so numbers never pick up the system locale's separators.
    static let locale = Locale(identifier: "en_US")

    public static func percent(_ fraction: Double, digits: Int = 0) -> String {
        (fraction * 100).formatted(.number.precision(.fractionLength(digits)).locale(locale)) + "%"
    }

    /// "11.2 GB", decimal-free for big values like "412 GB".
    public static func bytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_000_000_000
        if gb >= 100 { return gb.formatted(.number.precision(.fractionLength(0)).locale(locale)) + " GB" }
        if gb >= 1 { return gb.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " GB" }
        let mb = Double(value) / 1_000_000
        return mb.formatted(.number.precision(.fractionLength(0)).locale(locale)) + " MB"
    }

    /// Memory in binary gigabytes, as macOS reports RAM ("16 GB").
    public static func memory(_ value: UInt64) -> String {
        let gib = Double(value) / 1_073_741_824
        return gib.formatted(.number.precision(.fractionLength(gib >= 10 ? 1 : 2)).locale(locale)) + " GB"
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        switch v {
        case ..<1_000: return "\(Int(v)) B/s"
        case ..<1_000_000: return (v / 1_000).formatted(.number.precision(.fractionLength(0)).locale(locale)) + " KB/s"
        case ..<1_000_000_000: return (v / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(locale)) + " MB/s"
        default: return (v / 1_000_000_000).formatted(.number.precision(.fractionLength(2)).locale(locale)) + " GB/s"
        }
    }

    public static func temperature(_ celsius: Double?, fahrenheit: Bool = false) -> String {
        guard let celsius else { return "–" }
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°" + (fahrenheit ? "F" : "C")
    }

    public static func rpm(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(locale)) + " rpm"
    }

    public static func watts(_ value: Double?) -> String {
        guard let value else { return "–" }
        return abs(value).formatted(.number.precision(.fractionLength(1)).locale(locale)) + " W"
    }

    public static func duration(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}
