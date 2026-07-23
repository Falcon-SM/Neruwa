import SwiftUI

struct MascotPromptView: View {
    let message: String
    var detail: String?
    var imageSize: CGFloat = 78

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("ChickMascot")
                .resizable()
                .scaledToFit()
                .frame(width: imageSize, height: imageSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct MascotInlinePrompt: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image("ChickMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 20) {
        MascotPromptView(
            message: "おはよう。今朝の気分を教えてね",
            detail: "無理に元気を選ばなくて大丈夫です。"
        )
        MascotInlinePrompt(message: "この点字はどのかな？")
    }
    .padding()
}
