import SwiftUI

/// An analog representation of elapsed sleep time shared by recording and reflection screens.
struct SleepDurationClockDial: View {
    let elapsed: TimeInterval
    let displaysSecondHand: Bool

    init(
        elapsed: TimeInterval,
        displaysSecondHand: Bool = true
    ) {
        self.elapsed = max(0, elapsed)
        self.displaysSecondHand = displaysSecondHand
    }

    private var hourAngle: Angle {
        .degrees(elapsed.truncatingRemainder(dividingBy: 43_200) / 43_200 * 360)
    }

    private var minuteAngle: Angle {
        .degrees(elapsed.truncatingRemainder(dividingBy: 3_600) / 3_600 * 360)
    }

    private var secondAngle: Angle {
        .degrees(elapsed.truncatingRemainder(dividingBy: 60) / 60 * 360)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2

            ZStack {
                SleepDurationClockFace(radius: radius)
                    .equatable()

                hand(width: 5, length: radius * 0.43, color: .primary, angle: hourAngle)
                hand(width: 3.5, length: radius * 0.62, color: .orange, angle: minuteAngle)

                if displaysSecondHand {
                    hand(width: 1.5, length: radius * 0.70, color: .red, angle: secondAngle)
                }
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    private func hand(
        width: CGFloat,
        length: CGFloat,
        color: Color,
        angle: Angle
    ) -> some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -(length / 2))
            .rotationEffect(angle)
    }
}

/// The face is static, so only the hands redraw while a timer is running.
private struct SleepDurationClockFace: View, Equatable {
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                }

            ForEach(0..<60, id: \.self) { tick in
                Capsule(style: .continuous)
                    .fill(tick.isMultiple(of: 5) ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.30))
                    .frame(
                        width: tick.isMultiple(of: 5) ? 2.4 : 1,
                        height: tick.isMultiple(of: 5) ? 10 : 4
                    )
                    .offset(y: -(radius - 18))
                    .rotationEffect(.degrees(Double(tick) * 6))
            }

            VStack {
                Text("12")
                Spacer()
                Text("6")
            }
            .padding(.vertical, 31)

            HStack {
                Text("9")
                Spacer()
                Text("3")
            }
            .padding(.horizontal, 34)

            Circle()
                .fill(.red)
                .frame(width: 13, height: 13)
                .overlay {
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                        .frame(width: 5, height: 5)
                }
        }
        .allowsHitTesting(false)
    }
}
