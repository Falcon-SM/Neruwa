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

    private let moods: [SleepMood] = [.bad, .flat, .good, .great]
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
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("今日の気分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsDismissal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if sleepStore.session(id: sessionID) != nil {
                        Button(allowsDismissal ? "保存" : "次へ", action: saveReflection)
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
            VStack(spacing: 14) {
                SleepDurationClockDial(
                    elapsed: TimeInterval(session.durationMinutes * 60),
                    displaysSecondHand: false
                )
                .frame(width: 190, height: 190)

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
            .padding(.vertical, 8)
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
            Picker("今朝の気分", selection: $selectedMood) {
                Text("選択してください")
                    .tag(SleepMood?.none)

                ForEach(moods) { mood in
                    Text("\(mood.emoji)  \(mood.label)")
                        .tag(Optional(mood))
                }
            }
            .pickerStyle(.navigationLink)
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
                .lineLimit(4...8)
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
