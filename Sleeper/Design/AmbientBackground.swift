import SwiftUI

enum AmbientScene: Equatable, Sendable {
    case night
    case morning
    case day

    var isNight: Bool {
        self == .night
    }

    static func timeFallback(
        at date: Date = .now,
        calendar: Calendar = .current,
        schedule: DailyFlowSchedule = .default
    ) -> AmbientScene {
        guard schedule.period(at: date, calendar: calendar) == .morning else {
            return .night
        }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let currentMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let minutesSinceMorning = (
            currentMinute - schedule.morningStartMinutes + 24 * 60
        ) % (24 * 60)
        let morningDuration = (
            schedule.nightStartMinutes - schedule.morningStartMinutes + 24 * 60
        ) % (24 * 60)

        return minutesSinceMorning < min(4 * 60, morningDuration)
            ? .morning
            : .day
    }
}

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

/// A static, noninteractive background. It uses no timeline, blur, weather,
/// location, or continuously running animation.
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
        switch scene {
        case .night:
            [
                Color(red: 0.025, green: 0.055, blue: 0.18),
                Color(red: 0.008, green: 0.024, blue: 0.09),
                Color(red: 0.004, green: 0.010, blue: 0.035)
            ]
        case .morning where colorScheme == .light:
            [
                Color(red: 0.72, green: 0.86, blue: 1.00),
                Color(red: 1.00, green: 0.86, blue: 0.72),
                Color(red: 1.00, green: 0.95, blue: 0.88)
            ]
        case .morning:
            [
                Color(red: 0.10, green: 0.19, blue: 0.32),
                Color(red: 0.30, green: 0.20, blue: 0.22),
                Color(red: 0.17, green: 0.12, blue: 0.16)
            ]
        case .day where colorScheme == .light:
            [
                Color(red: 0.56, green: 0.80, blue: 1.00),
                Color(red: 0.79, green: 0.91, blue: 1.00),
                Color(red: 0.94, green: 0.97, blue: 1.00)
            ]
        case .day:
            [
                Color(red: 0.055, green: 0.16, blue: 0.29),
                Color(red: 0.08, green: 0.20, blue: 0.34),
                Color(red: 0.045, green: 0.11, blue: 0.20)
            ]
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
        case .day:
            SunGlow(
                color: Color(red: 1.0, green: 0.89, blue: 0.54),
                center: UnitPoint(x: 0.82, y: 0.13)
            )
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
