import SwiftUI

struct MorningReflectionView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var noteIsFocused: Bool

    let sessionID: UUID

    @State private var selectedMood: SleepMood?
    @State private var note = ""
    @State private var didLoad = false

    private let moods: [SleepMood] = [.bad, .flat, .good, .great]
    private let noteLimit = 240

    var body: some View {
        ZStack {
            NightSkyBackground()

            ScrollView {
                VStack(spacing: 20) {
                    closeButton

                    FlowHeader(
                        eyebrow: "Morning · Reflection",
                        title: "今朝の気分",
                        subtitle: "眠りの数字と、起きたときの感覚を一緒に残しましょう。",
                        symbol: "sun.horizon.fill",
                        completedSteps: 1,
                        totalSteps: 4
                    )

                    if let session = sleepStore.session(id: sessionID) {
                        sessionSummary(session)
                        moodPicker
                        noteEditor
                        saveButton
                    } else {
                        missingSession
                    }
                }
            }
            .sleepScreenScroll(
                bottomContentMargin: SleepScreenLayout.sheetBottomContentMargin
            )
        }
        .foregroundStyle(SleepPalette.text)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadSession)
        .onChange(of: note) { _, newValue in
            if newValue.count > noteLimit {
                note = String(newValue.prefix(noteLimit))
            }
        }
    }

    private var closeButton: some View {
        HStack {
            Label("ねるわ", systemImage: "moon.stars.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SleepPalette.warmGold)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(Color.white.opacity(0.08))
            .accessibilityLabel("閉じる")
        }
    }

    private func sessionSummary(_ session: SleepSession) -> some View {
        SurfaceCard(tint: SleepPalette.sunrise.opacity(0.10), padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("昨夜の睡眠", systemImage: "moon.zzz.fill")
                        .font(.headline)
                    Spacer()
                    Text(session.wakeDay, format: .dateTime.month().day().weekday(.abbreviated))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SleepPalette.secondaryText)
                }

                HStack(spacing: 0) {
                    reflectionMetric(
                        title: "寝た時間",
                        value: session.startDate.formatted(date: .omitted, time: .shortened),
                        symbol: "moon.fill"
                    )

                    reflectionDivider

                    reflectionMetric(
                        title: "睡眠",
                        value: SleepDurationFormatter.compact(minutes: session.durationMinutes),
                        symbol: "clock.fill"
                    )

                    reflectionDivider

                    reflectionMetric(
                        title: "起きた時間",
                        value: session.endDate.formatted(date: .omitted, time: .shortened),
                        symbol: "sunrise.fill"
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: session.shortageMinutes > 0 ? "chart.line.downtrend.xyaxis" : "checkmark.seal.fill")
                        .foregroundStyle(session.shortageMinutes > 0 ? SleepPalette.sunrise : SleepPalette.mint)
                    Text(targetMessage(for: session))
                        .font(.caption)
                        .foregroundStyle(SleepPalette.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func reflectionMetric(title: String, value: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(SleepPalette.warmGold)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(SleepPalette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var reflectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 44)
            .accessibilityHidden(true)
    }

    private var moodPicker: some View {
        SurfaceCard(tint: SleepPalette.warmGold.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("起きた瞬間、どうだった？")
                        .font(.headline)
                    Text("考えすぎず、いちばん近いものを選んでください。")
                        .font(.caption)
                        .foregroundStyle(SleepPalette.secondaryText)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 68, maximum: 110), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(Array(moods.enumerated()), id: \.offset) { _, mood in
                        moodButton(mood)
                    }
                }
            }
        }
    }

    private func moodButton(_ mood: SleepMood) -> some View {
        let selected = isSelected(mood)
        let color = moodColor(mood)

        return Button {
            withAnimation(.snappy) {
                selectedMood = mood
            }
        } label: {
            VStack(spacing: 7) {
                Text(mood.emoji)
                    .font(.system(size: 29))
                Text(mood.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .foregroundStyle(SleepPalette.text)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular
                .tint(selected ? color.opacity(0.28) : Color.white.opacity(0.045))
                .interactive(),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? color.opacity(0.78) : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 0.75)
        }
        .scaleEffect(selected ? 1.025 : 1)
        .accessibilityLabel("\(mood.label)、\(mood.emoji)")
        .accessibilityValue(selected ? "選択中" : "未選択")
    }

    private var noteEditor: some View {
        SurfaceCard(tint: SleepPalette.chartBlue.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("ひとこと", systemImage: "quote.bubble.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(note.count) / \(noteLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SleepPalette.secondaryText)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SleepPalette.night.opacity(0.48))

                    if note.isEmpty {
                        Text("夢、体の軽さ、目覚めたときのこと…")
                            .font(.body)
                            .foregroundStyle(SleepPalette.secondaryText.opacity(0.78))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $note)
                        .focused($noteIsFocused)
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(minHeight: 126)
                        .foregroundStyle(SleepPalette.text)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(noteIsFocused ? 0.20 : 0.08), lineWidth: 1)
                }
            }
        }
    }

    private var saveButton: some View {
        Button(action: saveReflection) {
            Label("朝の振り返りを保存", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .tint(SleepPalette.warmGold)
        .foregroundStyle(SleepPalette.night)
        .disabled(selectedMood == nil)
        .accessibilityHint(selectedMood == nil ? "先に今朝の気分を選んでください" : "気分とひとことを保存して閉じます")
    }

    private var missingSession: some View {
        SurfaceCard(tint: SleepPalette.danger.opacity(0.12)) {
            ContentUnavailableView {
                Label("記録が見つかりません", systemImage: "exclamationmark.magnifyingglass")
            } description: {
                Text("睡眠記録が削除されたか、まだ同期されていない可能性があります。")
            } actions: {
                Button("閉じる") {
                    dismiss()
                }
                .buttonStyle(.glass)
            }
            .foregroundStyle(SleepPalette.text)
        }
    }

    private func targetMessage(for session: SleepSession) -> String {
        if session.shortageMinutes > 0 {
            return "目標まであと\(SleepDurationFormatter.summary(minutes: session.shortageMinutes))でした"
        }
        return "目標の\(SleepDurationFormatter.summary(minutes: session.targetMinutes))を達成しました"
    }

    private func isSelected(_ mood: SleepMood) -> Bool {
        switch (selectedMood, mood) {
        case (.bad?, .bad), (.flat?, .flat), (.good?, .good), (.great?, .great):
            true
        default:
            false
        }
    }

    private func moodColor(_ mood: SleepMood) -> Color {
        switch mood {
        case .bad: SleepPalette.danger
        case .flat: SleepPalette.secondaryText
        case .good: SleepPalette.mint
        case .great: SleepPalette.warmGold
        }
    }

    private func loadSession() {
        guard !didLoad, let session = sleepStore.session(id: sessionID) else { return }
        selectedMood = session.mood
        note = session.note
        didLoad = true
    }

    private func saveReflection() {
        guard let selectedMood else { return }
        sleepStore.updateReflection(
            id: sessionID,
            mood: selectedMood,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }
}
