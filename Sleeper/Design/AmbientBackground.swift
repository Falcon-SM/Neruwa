import SwiftUI

private struct AmbientSceneEnvironmentKey: EnvironmentKey {
    static let defaultValue = AmbientScene.timeFallback()
}

private struct AmbientBackgroundActiveEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var ambientScene: AmbientScene {
        get { self[AmbientSceneEnvironmentKey.self] }
        set { self[AmbientSceneEnvironmentKey.self] = newValue }
    }

    var isAmbientBackgroundActive: Bool {
        get { self[AmbientBackgroundActiveEnvironmentKey.self] }
        set { self[AmbientBackgroundActiveEnvironmentKey.self] = newValue }
    }
}

extension View {
    func ambientScreenBackground() -> some View {
        modifier(AmbientScreenBackgroundModifier())
    }
}

private struct AmbientScreenBackgroundModifier: ViewModifier {
    @Environment(\.ambientScene) private var scene
    @Environment(\.isAmbientBackgroundActive) private var isActive

    func body(content: Content) -> some View {
        content.background {
            if isActive {
                AmbientBackground(scene: scene)
            }
        }
    }
}

/// A single, noninteractive background layer for the app's main container.
/// It has no timeline, blur, material, or continuously running animation.
struct AmbientBackground: View {
    let scene: AmbientScene

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            atmosphere
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var palette: [Color] {
        switch (scene, colorScheme) {
        case (.night, _):
            [
                Color(red: 0.025, green: 0.055, blue: 0.18),
                Color(red: 0.008, green: 0.024, blue: 0.09),
                Color(red: 0.004, green: 0.010, blue: 0.035)
            ]
        case (.morning, .light):
            [
                Color(red: 0.72, green: 0.86, blue: 1.00),
                Color(red: 1.00, green: 0.86, blue: 0.72),
                Color(red: 1.00, green: 0.95, blue: 0.88)
            ]
        case (.morning, .dark):
            [
                Color(red: 0.10, green: 0.19, blue: 0.32),
                Color(red: 0.30, green: 0.20, blue: 0.22),
                Color(red: 0.17, green: 0.12, blue: 0.16)
            ]
        case (.clear, .light):
            [
                Color(red: 0.56, green: 0.80, blue: 1.00),
                Color(red: 0.79, green: 0.91, blue: 1.00),
                Color(red: 0.94, green: 0.97, blue: 1.00)
            ]
        case (.clear, .dark):
            [
                Color(red: 0.055, green: 0.16, blue: 0.29),
                Color(red: 0.08, green: 0.20, blue: 0.34),
                Color(red: 0.045, green: 0.11, blue: 0.20)
            ]
        case (.cloudy, .light):
            [
                Color(red: 0.67, green: 0.73, blue: 0.80),
                Color(red: 0.82, green: 0.85, blue: 0.88),
                Color(red: 0.93, green: 0.94, blue: 0.95)
            ]
        case (.cloudy, .dark):
            [
                Color(red: 0.11, green: 0.15, blue: 0.20),
                Color(red: 0.17, green: 0.21, blue: 0.27),
                Color(red: 0.09, green: 0.12, blue: 0.17)
            ]
        case (.rain, .light):
            [
                Color(red: 0.38, green: 0.52, blue: 0.66),
                Color(red: 0.62, green: 0.70, blue: 0.78),
                Color(red: 0.83, green: 0.87, blue: 0.90)
            ]
        case (.rain, .dark):
            [
                Color(red: 0.055, green: 0.10, blue: 0.16),
                Color(red: 0.09, green: 0.15, blue: 0.22),
                Color(red: 0.035, green: 0.065, blue: 0.11)
            ]
        case (.snow, .light):
            [
                Color(red: 0.72, green: 0.83, blue: 0.91),
                Color(red: 0.88, green: 0.93, blue: 0.97),
                Color(red: 0.97, green: 0.98, blue: 1.00)
            ]
        case (.snow, .dark):
            [
                Color(red: 0.11, green: 0.18, blue: 0.25),
                Color(red: 0.15, green: 0.23, blue: 0.31),
                Color(red: 0.08, green: 0.12, blue: 0.18)
            ]
        case (.storm, .light):
            [
                Color(red: 0.24, green: 0.28, blue: 0.39),
                Color(red: 0.43, green: 0.47, blue: 0.57),
                Color(red: 0.68, green: 0.70, blue: 0.76)
            ]
        case (.storm, .dark):
            [
                Color(red: 0.035, green: 0.040, blue: 0.09),
                Color(red: 0.08, green: 0.08, blue: 0.15),
                Color(red: 0.025, green: 0.025, blue: 0.055)
            ]
        case (.fog, .light):
            [
                Color(red: 0.72, green: 0.76, blue: 0.77),
                Color(red: 0.84, green: 0.86, blue: 0.85),
                Color(red: 0.94, green: 0.94, blue: 0.91)
            ]
        case (.fog, .dark):
            [
                Color(red: 0.12, green: 0.15, blue: 0.16),
                Color(red: 0.18, green: 0.20, blue: 0.20),
                Color(red: 0.09, green: 0.11, blue: 0.12)
            ]
        @unknown default:
            [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
        }
    }

    @ViewBuilder
    private var atmosphere: some View {
        switch scene {
        case .night:
            NightStars()
        case .morning:
            SunGlow(
                color: Color(red: 1.0, green: 0.74, blue: 0.42),
                center: UnitPoint(x: 0.82, y: 0.18)
            )
        case .clear:
            SunGlow(
                color: Color(red: 1.0, green: 0.89, blue: 0.54),
                center: UnitPoint(x: 0.82, y: 0.13)
            )
        case .cloudy:
            WeatherTexture(kind: .clouds, colorScheme: colorScheme)
        case .rain:
            WeatherTexture(kind: .rain, colorScheme: colorScheme)
        case .snow:
            WeatherTexture(kind: .snow, colorScheme: colorScheme)
        case .storm:
            WeatherTexture(kind: .storm, colorScheme: colorScheme)
        case .fog:
            WeatherTexture(kind: .fog, colorScheme: colorScheme)
        }
    }
}

private struct SunGlow: View {
    let color: Color
    let center: UnitPoint

    var body: some View {
        RadialGradient(
            colors: [color.opacity(0.44), color.opacity(0.10), .clear],
            center: center,
            startRadius: 4,
            endRadius: 260
        )
    }
}

private struct AmbientParticle: Sendable {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
}

private struct NightStars: View {
    private let stars: [AmbientParticle] = [
        .init(x: 0.08, y: 0.10, size: 2.2, opacity: 0.48),
        .init(x: 0.23, y: 0.17, size: 1.4, opacity: 0.35),
        .init(x: 0.42, y: 0.08, size: 2.0, opacity: 0.45),
        .init(x: 0.61, y: 0.14, size: 1.6, opacity: 0.32),
        .init(x: 0.84, y: 0.07, size: 2.4, opacity: 0.50),
        .init(x: 0.94, y: 0.23, size: 1.4, opacity: 0.38),
        .init(x: 0.13, y: 0.31, size: 1.6, opacity: 0.35),
        .init(x: 0.34, y: 0.28, size: 2.2, opacity: 0.50),
        .init(x: 0.55, y: 0.36, size: 1.4, opacity: 0.30),
        .init(x: 0.77, y: 0.30, size: 1.8, opacity: 0.42),
        .init(x: 0.07, y: 0.49, size: 1.4, opacity: 0.27),
        .init(x: 0.27, y: 0.45, size: 2.0, opacity: 0.41),
        .init(x: 0.48, y: 0.53, size: 1.6, opacity: 0.32),
        .init(x: 0.69, y: 0.47, size: 2.4, opacity: 0.45),
        .init(x: 0.91, y: 0.55, size: 1.6, opacity: 0.34),
        .init(x: 0.16, y: 0.66, size: 2.0, opacity: 0.37),
        .init(x: 0.38, y: 0.72, size: 1.4, opacity: 0.28),
        .init(x: 0.59, y: 0.64, size: 1.8, opacity: 0.43),
        .init(x: 0.81, y: 0.74, size: 2.2, opacity: 0.38),
        .init(x: 0.05, y: 0.86, size: 1.6, opacity: 0.30),
        .init(x: 0.29, y: 0.91, size: 2.4, opacity: 0.39),
        .init(x: 0.51, y: 0.84, size: 1.4, opacity: 0.29),
        .init(x: 0.73, y: 0.94, size: 1.8, opacity: 0.36),
        .init(x: 0.95, y: 0.88, size: 1.4, opacity: 0.27)
    ]

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            for star in stars {
                let rect = CGRect(
                    x: size.width * star.x - star.size / 2,
                    y: size.height * star.y - star.size / 2,
                    width: star.size,
                    height: star.size
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(star.opacity))
                )
            }
        }
    }
}

private struct WeatherTexture: View {
    enum Kind {
        case clouds
        case rain
        case snow
        case storm
        case fog
    }

    let kind: Kind
    let colorScheme: ColorScheme

    private let particles: [AmbientParticle] = [
        .init(x: 0.10, y: 0.17, size: 3.0, opacity: 0.26),
        .init(x: 0.25, y: 0.31, size: 2.2, opacity: 0.20),
        .init(x: 0.39, y: 0.12, size: 3.6, opacity: 0.24),
        .init(x: 0.53, y: 0.42, size: 2.6, opacity: 0.22),
        .init(x: 0.68, y: 0.25, size: 3.2, opacity: 0.25),
        .init(x: 0.83, y: 0.38, size: 2.0, opacity: 0.19),
        .init(x: 0.92, y: 0.14, size: 3.4, opacity: 0.24),
        .init(x: 0.16, y: 0.58, size: 2.4, opacity: 0.20),
        .init(x: 0.34, y: 0.72, size: 3.4, opacity: 0.25),
        .init(x: 0.47, y: 0.61, size: 2.0, opacity: 0.18),
        .init(x: 0.63, y: 0.82, size: 3.0, opacity: 0.23),
        .init(x: 0.78, y: 0.67, size: 2.4, opacity: 0.20),
        .init(x: 0.91, y: 0.88, size: 3.2, opacity: 0.24),
        .init(x: 0.08, y: 0.91, size: 2.0, opacity: 0.18)
    ]

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            switch kind {
            case .clouds:
                drawClouds(in: &context, size: size, opacity: 0.14)
            case .rain:
                drawClouds(in: &context, size: size, opacity: 0.12)
                drawRain(in: &context, size: size)
            case .snow:
                drawSnow(in: &context, size: size)
            case .storm:
                drawClouds(in: &context, size: size, opacity: 0.16)
                drawStorm(in: &context, size: size)
            case .fog:
                drawFog(in: &context, size: size)
            }
        }
    }

    private var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    private func drawClouds(
        in context: inout GraphicsContext,
        size: CGSize,
        opacity: Double
    ) {
        let cloudRects = [
            CGRect(x: size.width * 0.56, y: size.height * 0.08, width: size.width * 0.42, height: 80),
            CGRect(x: -size.width * 0.10, y: size.height * 0.28, width: size.width * 0.48, height: 92),
            CGRect(x: size.width * 0.48, y: size.height * 0.63, width: size.width * 0.54, height: 104)
        ]
        for rect in cloudRects {
            context.fill(
                Path(roundedRect: rect, cornerRadius: rect.height / 2),
                with: .color(foreground.opacity(opacity))
            )
        }
    }

    private func drawRain(in context: inout GraphicsContext, size: CGSize) {
        for (index, particle) in particles.enumerated() {
            var path = Path()
            let x = size.width * particle.x
            let y = size.height * particle.y
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 7, y: y + 18 + CGFloat(index % 3) * 3))
            context.stroke(
                path,
                with: .color(Color.white.opacity(0.18 + particle.opacity / 3)),
                lineWidth: 1
            )
        }
    }

    private func drawSnow(in context: inout GraphicsContext, size: CGSize) {
        for particle in particles {
            let diameter = particle.size + 1
            let rect = CGRect(
                x: size.width * particle.x - diameter / 2,
                y: size.height * particle.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color.white.opacity(0.34 + particle.opacity / 2))
            )
        }
    }

    private func drawStorm(in context: inout GraphicsContext, size: CGSize) {
        var bolt = Path()
        bolt.move(to: CGPoint(x: size.width * 0.76, y: size.height * 0.18))
        bolt.addLine(to: CGPoint(x: size.width * 0.67, y: size.height * 0.34))
        bolt.addLine(to: CGPoint(x: size.width * 0.73, y: size.height * 0.34))
        bolt.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.52))
        context.stroke(
            bolt,
            with: .color(Color(red: 1.0, green: 0.90, blue: 0.50).opacity(0.25)),
            lineWidth: 2
        )
    }

    private func drawFog(in context: inout GraphicsContext, size: CGSize) {
        for index in 0..<7 {
            let y = size.height * (0.14 + CGFloat(index) * 0.12)
            let inset = index.isMultiple(of: 2) ? size.width * 0.06 : size.width * 0.18
            var path = Path()
            path.move(to: CGPoint(x: inset, y: y))
            path.addLine(to: CGPoint(x: size.width - inset, y: y))
            context.stroke(
                path,
                with: .color(foreground.opacity(0.10)),
                style: StrokeStyle(lineWidth: 9, lineCap: .round)
            )
        }
    }
}
