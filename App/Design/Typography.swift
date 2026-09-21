import SwiftUI

/// One type scale for the whole app. Every screen picks from here, nothing sets its own sizes.
enum JuicyFont {
    /// Screen headline: "Pretty fresh."
    static let display = Font.system(size: 40, weight: .heavy)
    /// Card and section titles.
    static let title = Font.system(size: 17, weight: .semibold)
    /// Big numbers (SF Rounded, tabular).
    static func readout(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    /// Running text.
    static let body = Font.system(size: 14)
    /// Secondary text under a value.
    static let caption = Font.system(size: 12)
    /// Uppercase label above a value.
    static let eyebrow = Font.system(size: 11, weight: .semibold)
    /// Numbers in tables and trailing slots.
    static let mono = Font.system(size: 12, design: .monospaced)
}

extension View {
    func displayStyle() -> some View {
        font(JuicyFont.display).kerning(-0.8).foregroundStyle(.white)
    }

    func titleStyle() -> some View {
        font(JuicyFont.title).foregroundStyle(.white)
    }

    func bodyStyle() -> some View {
        font(JuicyFont.body).foregroundStyle(.white.opacity(0.85))
    }

    func captionStyle() -> some View {
        font(JuicyFont.caption).foregroundStyle(.white.opacity(0.72))
    }

    func monoStyle() -> some View {
        font(JuicyFont.mono).monospacedDigit().foregroundStyle(.white.opacity(0.85))
    }
}

/// Spacing scale, so every screen breathes the same way.
enum Space {
    static let card: CGFloat = 16
    static let gap: CGFloat = 14
    static let section: CGFloat = 20
    static let radius: CGFloat = 22
}
