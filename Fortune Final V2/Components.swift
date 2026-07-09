//
//  Components.swift
//  Fortune
//
//  The Small shared Things and items used across all the screens.
//

import SwiftUI

// MARK: - Logo

struct LogoView: View {
    var size: CGFloat = 32

    var body: some View {
        if let image = UIImage(named: "FortuneLogo") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.62, weight: .semibold))
                .foregroundStyle(Theme.brandGradient)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - PnL badge

struct PnlBadge: View {
    let change: Double
    let pct: Double

    private var up: Bool { change >= 0 }
    private var tint: Color { up ? Theme.emerald : Theme.red }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: up ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
            Text("\(up ? "+" : "")\(pct.money())%")
                .font(.mono(11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15))
        .foregroundStyle(tint)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Section label

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(Theme.mutedForeground)
    }
}

// MARK: - Pulsing live dot

struct PulsingDot: View {
    var color: Color = Theme.emerald
    var size: CGFloat = 6
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

// MARK: - Immersive background

struct ImmersiveBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x0A1628), location: 0),
                        .init(color: Color(hex: 0x0C1235), location: 0.25),
                        .init(color: Color(hex: 0x0E0C2E), location: 0.55),
                        .init(color: Color(hex: 0x080820), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Cyan corona, top right
                glow(Theme.primary, opacity: 0.20)
                    .frame(width: 280, height: 280)
                    .position(x: geo.size.width - 20, y: 10)

                // Purple haze, bottom left
                glow(Theme.accent, opacity: 0.16)
                    .frame(width: 260, height: 260)
                    .position(x: 10, y: geo.size.height - 70)

                // Subtle mid-screen glow
                glow(Theme.primary, opacity: 0.05)
                    .frame(width: 180, height: 180)
                    .position(x: geo.size.width * 0.42, y: geo.size.height * 0.45)

                // Top edge highlight
                Rectangle()
                    .fill(Theme.primary.opacity(0.20))
                    .frame(height: 1)
                    .position(x: geo.size.width / 2, y: 0.5)
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color, opacity: Double) -> some View {
        Circle().fill(
            RadialGradient(
                colors: [color.opacity(opacity), color.opacity(opacity * 0.25), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 140
            )
        )
    }
}

// MARK: - Gradient divider

struct GradientDivider: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: Theme.primary.opacity(0.15), location: 0.3),
                .init(color: Theme.accent.opacity(0.15), location: 0.7),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

// MARK: - Footer

struct FortuneFooter: View {
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                LogoView(size: 14).opacity(0.5)
                Text("Futures + Prediction Markets")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.22))
            }
            Spacer()
            Text("fortune.app")
                .font(.mono(9))
                .foregroundStyle(.white.opacity(0.14))
        }
    }
}

// MARK: - Pressable button style

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? max(x - spacing, 0) : maxWidth,
                      height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Test

