import Foundation
import SwiftUI

enum SleepPalette {
    static let night = Color(red: 0.008, green: 0.024, blue: 0.090)
    static let nightLift = Color(red: 0.020, green: 0.045, blue: 0.180)
    static let text = Color(red: 0.898, green: 0.906, blue: 0.922)
    static let secondaryText = Color(red: 0.580, green: 0.639, blue: 0.722)
    static let warmGold = Color(red: 0.992, green: 0.902, blue: 0.541)
    static let sunrise = Color(red: 0.992, green: 0.729, blue: 0.455)
    static let mint = Color(red: 0.431, green: 0.906, blue: 0.718)
    static let chartBlue = Color(red: 0.320, green: 0.525, blue: 0.930)
    static let danger = Color(red: 0.984, green: 0.510, blue: 0.510)
    static let panel = Color(red: 0.055, green: 0.090, blue: 0.200)
    static let glassTint = Color.white.opacity(0.055)
}

enum SleepScreenLayout {
    static let horizontalContentMargin: CGFloat = 18
    static let topContentMargin: CGFloat = 18
    static let tabBottomContentMargin: CGFloat = 36
    static let sheetBottomContentMargin: CGFloat = 28
}

extension View {
    /// Applies one consistent scroll contract while leaving the container's
    /// safe-area handling to SwiftUI (including the system tab bar and sheets).
    func sleepScreenScroll(
        bottomContentMargin: CGFloat = SleepScreenLayout.tabBottomContentMargin
    ) -> some View {
        contentMargins(
            .horizontal,
            SleepScreenLayout.horizontalContentMargin,
            for: .scrollContent
        )
        .contentMargins(.top, SleepScreenLayout.topContentMargin, for: .scrollContent)
        .contentMargins(.bottom, bottomContentMargin, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.visible)
    }
}

/// Shared backdrop for the sleep flow. The stars are drawn locally so the UI
/// has no image dependency and remains crisp at every Dynamic Type size.
struct NightSkyBackground: View {
    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let opacity: Double
    }

    private let stars: [Star] = [
        .init(x: 0.08, y: 0.10, radius: 1.1, opacity: 0.42),
        .init(x: 0.23, y: 0.17, radius: 0.7, opacity: 0.32),
        .init(x: 0.42, y: 0.08, radius: 1.0, opacity: 0.40),
        .init(x: 0.61, y: 0.14, radius: 0.8, opacity: 0.28),
        .init(x: 0.84, y: 0.07, radius: 1.2, opacity: 0.44),
        .init(x: 0.94, y: 0.23, radius: 0.7, opacity: 0.34),
        .init(x: 0.13, y: 0.31, radius: 0.8, opacity: 0.31),
        .init(x: 0.34, y: 0.28, radius: 1.1, opacity: 0.46),
        .init(x: 0.55, y: 0.36, radius: 0.7, opacity: 0.27),
        .init(x: 0.77, y: 0.30, radius: 0.9, opacity: 0.38),
        .init(x: 0.07, y: 0.49, radius: 0.7, opacity: 0.24),
        .init(x: 0.27, y: 0.45, radius: 1.0, opacity: 0.37),
        .init(x: 0.48, y: 0.53, radius: 0.8, opacity: 0.29),
        .init(x: 0.69, y: 0.47, radius: 1.2, opacity: 0.40),
        .init(x: 0.91, y: 0.55, radius: 0.8, opacity: 0.30),
        .init(x: 0.16, y: 0.66, radius: 1.0, opacity: 0.33),
        .init(x: 0.38, y: 0.72, radius: 0.7, opacity: 0.25),
        .init(x: 0.59, y: 0.64, radius: 0.9, opacity: 0.39),
        .init(x: 0.81, y: 0.74, radius: 1.1, opacity: 0.34),
        .init(x: 0.05, y: 0.86, radius: 0.8, opacity: 0.27),
        .init(x: 0.29, y: 0.91, radius: 1.2, opacity: 0.35),
        .init(x: 0.51, y: 0.84, radius: 0.7, opacity: 0.26),
        .init(x: 0.73, y: 0.94, radius: 0.9, opacity: 0.33),
        .init(x: 0.95, y: 0.88, radius: 0.7, opacity: 0.24)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [SleepPalette.nightLift, SleepPalette.night, .black.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [SleepPalette.chartBlue.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.72, y: 0.12),
                    startRadius: 8,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.58
                )

                Canvas { context, size in
                    for star in stars {
                        let diameter = star.radius * 2
                        let rect = CGRect(
                            x: (size.width * star.x) - star.radius,
                            y: (size.height * star.y) - star.radius,
                            width: diameter,
                            height: diameter
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(SleepPalette.text.opacity(star.opacity))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A lightweight card for repeated, non-primary content. Unlike GlassCard it
/// does not run a live backdrop effect, which keeps long scrolling screens
/// inexpensive while preserving the night-sky atmosphere.
struct SurfaceCard<Content: View>: View {
    private let tint: Color
    private let contentPadding: CGFloat
    private let content: Content

    init(
        tint: Color = SleepPalette.glassTint,
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.contentPadding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(SleepPalette.panel.opacity(0.72))

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

struct GlassCard<Content: View>: View {
    private let tint: Color
    private let contentPadding: CGFloat
    private let content: Content

    init(
        tint: Color = SleepPalette.glassTint,
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.contentPadding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(SleepPalette.panel.opacity(0.28))
                    .allowsHitTesting(false)
            }
            .glassEffect(
                .regular.tint(tint),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

struct FlowHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    var completedSteps: Int = 4
    var totalSteps: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                Text(eyebrow)
                Spacer(minLength: 12)
                Text("\(completedSteps) / \(totalSteps)")
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(SleepPalette.warmGold)

            HStack(spacing: 6) {
                ForEach(0..<max(totalSteps, 1), id: \.self) { step in
                    Capsule(style: .continuous)
                        .fill(step < completedSteps ? SleepPalette.warmGold : Color.white.opacity(0.15))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(SleepPalette.text)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(SleepPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SleepStatusBanner: View {
    enum Kind {
        case success
        case error

        var color: Color {
            switch self {
            case .success: SleepPalette.mint
            case .error: SleepPalette.danger
            }
        }

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }
    }

    let message: String
    let kind: Kind

    var body: some View {
        Label(message, systemImage: kind.symbol)
            .font(.footnote.weight(.medium))
            .foregroundStyle(SleepPalette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(
                .regular.tint(kind.color.opacity(0.20)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .accessibilityLabel(message)
    }
}

enum SleepDurationFormatter {
    static func clock(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func summary(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainder = safeMinutes % 60

        switch (hours, remainder) {
        case (0, _):
            return "\(remainder)分"
        case (_, 0):
            return "\(hours)時間"
        default:
            return "\(hours)時間\(remainder)分"
        }
    }

    static func compact(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        return String(format: "%d:%02d", safeMinutes / 60, safeMinutes % 60)
    }
}
