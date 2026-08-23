import RealityKit
import SwiftUI

struct NerurunStatusCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sessions: [SleepSession]
    let targetMinutes: Int

    private var status: NerurunStatus {
        NerurunStatusEvaluator.evaluate(
            sessions: sessions,
            fallbackTargetMinutes: targetMinutes
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ねるるんの様子")
                        .font(.headline)
                    Label(status.condition.title, systemImage: status.condition.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)
                }

                Spacer()

                if status.condition == .thriving {
                    Text("+\(status.companionCount)")
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.16), in: .capsule)
                        .accessibilityLabel("子どものひよこが\(status.companionCount)羽")
                }
            }

            NerurunRockingModel(
                condition: status.condition,
                companionCount: status.companionCount,
                reduceMotion: reduceMotion
            )
            .frame(height: 205)
            .frame(maxWidth: .infinity)

            Text(status.condition.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ねるるんの様子、\(status.condition.title)。\(status.condition.message)")
    }

    private var statusTint: Color {
        switch status.condition {
        case .normal: .indigo
        case .discouraged: .green
        case .exhausted: .orange
        case .thriving: .green
        }
    }
}

private struct NerurunRockingModel: View {
    let condition: NerurunCondition
    let companionCount: Int
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion {
                model
            } else {
                PhaseAnimator([false, true]) { phase in
                    model
                        .rotationEffect(
                            .degrees(phase ? rockingAngle : -rockingAngle),
                            anchor: .bottom
                        )
                        .offset(y: phase ? -2 : 2)
                } animation: { _ in
                    .easeInOut(duration: rockingDuration)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var model: some View {
        ZStack {
            NerurunRealityView(companionCount: companionCount)

            if condition == .discouraged {
                Text("☘️")
                    .font(.system(size: 28))
                    .rotationEffect(.degrees(16))
                    .offset(x: 62, y: -58)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            }

            if condition == .exhausted {
                HStack(spacing: 29) {
                    Capsule()
                    Capsule()
                }
                .frame(width: 68, height: 8)
                .foregroundStyle(.brown.opacity(0.58))
                .blur(radius: 1.2)
                .offset(y: -5)
            }
        }
    }

    private var rockingAngle: Double {
        switch condition {
        case .discouraged: 2.0
        case .exhausted: 1.2
        case .normal: 3.0
        case .thriving: 4.0
        }
    }

    private var rockingDuration: Double {
        switch condition {
        case .discouraged: 2.1
        case .exhausted: 2.5
        case .normal: 1.8
        case .thriving: 1.35
        }
    }
}

private struct NerurunRealityView: View {
    let companionCount: Int

    var body: some View {
        RealityView { content in
            content.camera = .virtual

            guard let modelURL = Bundle.main.url(
                forResource: "Nerurun",
                withExtension: "usdz"
            ), let source = try? await Entity(contentsOf: modelURL) else {
                return
            }

            let displayRoot = Entity()
            displayRoot.name = "NerurunDisplayRoot"

            source.name = "NerurunMain"
            source.scale = SIMD3<Float>(repeating: 0.78)
            source.position = [0, -0.04, 0]
            displayRoot.addChild(source)
            synchronizeCompanions(
                in: displayRoot,
                source: source,
                count: companionCount
            )

            content.entities.append(displayRoot)
            content.cameraTarget = displayRoot
        } update: { content in
            guard let root = content.entities.first(where: {
                $0.name == "NerurunDisplayRoot"
            }), let source = root.findEntity(named: "NerurunMain") else {
                return
            }
            synchronizeCompanions(
                in: root,
                source: source,
                count: companionCount
            )
        } placeholder: {
            ProgressView("ねるるんを呼んでいます…")
                .font(.caption)
        }
        .allowsHitTesting(false)
    }

    private func synchronizeCompanions(
        in root: Entity,
        source: Entity,
        count: Int
    ) {
        let positions: [SIMD3<Float>] = [
            [-0.25, -0.43, 0.72],
            [0.05, -0.50, 0.78],
            [0.29, -0.41, 0.70]
        ]
        let desiredCount = min(max(count, 0), positions.count)
        let existingChildren = root.children.filter {
            $0.name.hasPrefix("NerurunChild")
        }
        guard existingChildren.count != desiredCount else { return }

        existingChildren.forEach { $0.removeFromParent() }
        for index in 0..<desiredCount {
            let child = source.clone(recursive: true)
            child.name = "NerurunChild\(index)"
            child.scale = SIMD3<Float>(repeating: 0.21)
            child.position = positions[index]
            root.addChild(child)
        }
    }
}

#Preview {
    NerurunStatusCard(sessions: [], targetMinutes: 480)
        .padding()
        .preferredColorScheme(.dark)
}
