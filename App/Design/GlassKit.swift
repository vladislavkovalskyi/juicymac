import SwiftUI

/// The juice glass: a tapered tumbler filled to `level`. Used for the menubar item and small badges.
struct JuiceGlassShape: Shape {
    /// 0...1 fill height.
    var level: Double
    var filled: Bool

    func path(in rect: CGRect) -> Path {
        // Drawn in a 44 x 60 space, then scaled to fit.
        let s = min(rect.width / 44, rect.height / 60)
        let dx = rect.minX + (rect.width - 44 * s) / 2
        let dy = rect.minY + (rect.height - 60 * s) / 2
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: dx + x * s, y: dy + y * s) }

        var path = Path()
        if filled {
            let inset = 3.0
            let y = 55 - 50 * max(0, min(1, level))
            let left = 5 + 4 * (y - 3) / 54 + inset
            let right = 39 - 4 * (y - 3) / 54 - inset
            path.move(to: p(left, y))
            path.addLine(to: p(right, y))
            path.addLine(to: p(35 - inset, 57 - inset))
            path.addLine(to: p(9 + inset, 57 - inset))
            path.closeSubpath()
        } else {
            path.move(to: p(5, 3))
            path.addLine(to: p(39, 3))
            path.addLine(to: p(35, 57))
            path.addLine(to: p(9, 57))
            path.closeSubpath()
        }
        return path
    }
}

/// Outline plus juice, in one view.
struct JuiceGlassIcon: View {
    var level: Double
    var tint: Color = .primary
    var lineWidth: Double = 4.5

    var body: some View {
        ZStack {
            JuiceGlassShape(level: level, filled: true).fill(tint)
            JuiceGlassShape(level: level, filled: false)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
        .aspectRatio(44.0 / 60.0, contentMode: .fit)
    }
}

/// Mesh of the palette's colours: the wallpaper every screen floats on.
struct FlavorBackground: View {
    var palette: Palette

    var body: some View {
        let g = palette.glow
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.55, 0], [1, 0],
                [0, 0.5], [0.45, 0.55], [1, 0.45],
                [0, 1], [0.6, 1], [1, 1],
            ],
            colors: [
                palette.base, g[0].opacity(0.9), g[0],
                g[1].opacity(0.75), palette.base, g[2].opacity(0.85),
                palette.base, g[2], palette.base,
            ]
        )
        .overlay(palette.base.opacity(0.18))
        .ignoresSafeArea()
    }
}

extension View {
    /// Liquid Glass panel.
    func juicyGlass(radius: CGFloat = 22, tint: Color? = nil) -> some View {
        glassEffect(tint.map { .regular.tint($0.opacity(0.25)) } ?? .regular, in: .rect(cornerRadius: radius))
    }

    /// Small caps label above a value.
    func eyebrow() -> some View {
        font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.white.opacity(0.75))
    }
}

/// Big number in SF Rounded, the way the design sets readouts.
struct Readout: View {
    var value: String
    var unit: String?
    var size: CGFloat = 30

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.system(size: size * 0.52, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
    }
}

/// 3D icon from the asset catalog, sized and nudged so its shadow does not push the layout around.
struct JuicyIcon: View {
    var name: String
    var size: CGFloat
    var hueShift: Angle = .zero

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .hueRotation(hueShift)
            .frame(width: size, height: size)
            // Drawn here rather than baked into the render, so it never crops at the image edge.
            .shadow(color: .black.opacity(0.32), radius: size * 0.07, x: 0, y: size * 0.045)
    }
}

/// Ring gauge used for the Juice score and the fan dials.
struct RingGauge: View {
    var fraction: Double
    var lineWidth: CGFloat = 12
    var tint: Color = .white

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Horizontal bar with an optional split into parts (memory breakdown, disk usage).
struct SegmentBar: View {
    var segments: [(fraction: Double, opacity: Double)]
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(.white.opacity(segment.opacity))
                        .frame(width: max(0, geo.size.width * segment.fraction))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(.white.opacity(0.16))
        .clipShape(.rect(cornerRadius: height / 2))
    }
}
