import SwiftUI

struct MorningReflectionView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var noteIsFocused: Bool

    let sessionID: UUID
    private let onSaved: ((UUID) -> Void)?
    private let allowsDismissal: Bool
    private let dismissesOnSave: Bool

    @State private var selectedMood: SleepMood?
    @State private var note = ""
    @State private var didLoad = false

    private let noteLimit = 240

    init(
        sessionID: UUID,
        allowsDismissal: Bool = true,
        dismissesOnSave: Bool = true,
        onSaved: ((UUID) -> Void)? = nil
    ) {
        self.sessionID = sessionID
        self.allowsDismissal = allowsDismissal
        self.dismissesOnSave = dismissesOnSave
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            List {
                if let session = sleepStore.session(id: sessionID) {
                    sessionSection(session)
                    moodSection
                    noteSection
                } else {
                    Section {
                        ContentUnavailableView {
                            Label("記録が見つかりません", systemImage: "exclamationmark.magnifyingglass")
                        } description: {
                            Text("睡眠記録が削除されたか、まだ同期されていない可能性があります。")
                        } actions: {
                            if allowsDismissal {
                                Button("閉じる") {
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("今日の気分")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !allowsDismissal,
                   sleepStore.session(id: sessionID) != nil {
                    VStack {
                        Button(action: saveReflection) {
                            Text("次へ")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(selectedMood == nil)
                        .accessibilityHint("気分を保存して朝の点字テストへ進みます")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
            .toolbar {
                if allowsDismissal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") {
                            dismiss()
                        }
                    }
                }

                if allowsDismissal {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存", action: saveReflection)
                            .fontWeight(.semibold)
                            .disabled(selectedMood == nil)
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        noteIsFocused = false
                    }
                }
            }
        }
        .onAppear(perform: loadSession)
        .onChange(of: note) { _, newValue in
            if newValue.count > noteLimit {
                note = String(newValue.prefix(noteLimit))
            }
        }
    }

    private func sessionSection(_ session: SleepSession) -> some View {
        Section {
            VStack(spacing: 10) {
                SleepDurationClockDial(
                    elapsed: TimeInterval(session.durationMinutes * 60),
                    displaysSecondHand: false
                )
                .frame(width: 150, height: 150)

                VStack(spacing: 3) {
                    Text(SleepDurationFormatter.summary(minutes: session.durationMinutes))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text("昨夜の睡眠時間")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "昨夜の睡眠時間、\(SleepDurationFormatter.summary(minutes: session.durationMinutes))"
            )

            LabeledContent("就寝") {
                Text(session.startDate, format: .dateTime.hour().minute())
                    .monospacedDigit()
            }

            LabeledContent("起床") {
                Text(session.endDate, format: .dateTime.hour().minute())
                    .monospacedDigit()
            }

            ProgressView(
                value: Double(min(session.durationMinutes, session.targetMinutes)),
                total: Double(max(session.targetMinutes, 1))
            ) {
                Text("睡眠目標")
            } currentValueLabel: {
                Text(targetMessage(for: session))
                    .font(.caption)
            }
            .tint(session.shortageMinutes > 0 ? .orange : .green)
        } header: {
            Text("昨夜の睡眠")
        }
    }

    private var moodSection: some View {
        Section {
            MorningMoodPicker(selection: $selectedMood)
        } header: {
            Text("今朝の気分")
        } footer: {
            Text("起きた瞬間にいちばん近いものを選んでください。")
        }
    }

    private var noteSection: some View {
        Section {
            TextField("夢、体の軽さ、目覚めたときのことなど", text: $note, axis: .vertical)
                .focused($noteIsFocused)
                .lineLimit(3...5)
                .accessibilityLabel("ひとこと")
        } header: {
            Text("ひとこと")
        } footer: {
            HStack {
                Text("最大\(noteLimit)文字")
                Spacer()
                Text("\(note.count) / \(noteLimit)")
                    .monospacedDigit()
            }
        }
    }

    private func targetMessage(for session: SleepSession) -> String {
        if session.shortageMinutes > 0 {
            return "目標まであと\(SleepDurationFormatter.summary(minutes: session.shortageMinutes))でした"
        }
        return "目標の\(SleepDurationFormatter.summary(minutes: session.targetMinutes))を達成しました"
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
        onSaved?(sessionID)
        if dismissesOnSave {
            dismiss()
        }
    }
}

/// A compact, in-place mood control shared by the regular reflection screen and
/// the mandatory morning flow. Keeping the choices on one row avoids a second
/// navigation step while retaining the native segmented-control interaction.
struct MorningMoodPicker: View {
    @Binding var selection: SleepMood?

    private let moods: [SleepMood] = [.bad, .flat, .good, .great]

    var body: some View {
        VStack(spacing: 6) {
            Picker("今朝の気分", selection: $selection) {
                ForEach(moods) { mood in
                    Text(mood.emoji)
                        .tag(Optional(mood))
                        .accessibilityLabel(mood.label)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            HStack(spacing: 0) {
                ForEach(moods) { mood in
                    Text(mood.label)
                        .font(.caption2)
                        .fontWeight(selection == mood ? .semibold : .regular)
                        .foregroundStyle(selection == mood ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
