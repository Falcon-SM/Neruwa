import SwiftUI

private enum EveningJournalStep: Int, CaseIterable, Identifiable {
    case today
    case letGo
    case tomorrow

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .letGo: "手放す"
        case .tomorrow: "明日"
        }
    }
}

struct EveningJournalView: View {
    private enum FocusField: Hashable {
        case today
        case letGo
        case tomorrow(Int)
    }

    @EnvironmentObject private var eveningStore: EveningStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusField?

    let day: Date
    let onCompleted: () -> Void
    private let allowsDismissal: Bool
    private let dismissesOnCompletion: Bool

    @State private var step: EveningJournalStep = .today
    @State private var todayNote = ""
    @State private var letGoNote = ""
    @State private var tomorrowItems = Array(
        repeating: "",
        count: EveningStore.maximumTomorrowItems
    )
    @State private var didLoad = false
    @State private var didComplete = false

    init(
        day: Date = Date(),
        allowsDismissal: Bool = true,
        dismissesOnCompletion: Bool = true,
        onCompleted: @escaping () -> Void = {}
    ) {
        self.day = day
        self.allowsDismissal = allowsDismissal
        self.dismissesOnCompletion = dismissesOnCompletion
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationStack {
            Form {
                flowProgressSection
                stepSelectorSection
                mascotPromptSection
                currentStepSection
                navigationSection
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("今日を閉じる")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsDismissal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") {
                            dismiss()
                        }
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        focusedField = nil
                    }
                }
            }
        }
        .onAppear(perform: loadEntry)
        .onChange(of: todayNote) { _, newValue in
            todayNote = limited(
                newValue,
                maximumCharacters: EveningStore.todayNoteCharacterLimit
            )
        }
        .onChange(of: letGoNote) { _, newValue in
            letGoNote = limited(
                newValue,
                maximumCharacters: EveningStore.letGoNoteCharacterLimit
            )
        }
        .onChange(of: step) { _, _ in
            focusedField = nil
        }
    }

    private var flowProgressSection: some View {
        Section {
            LabeledContent {
                Text("1 / 4")
                    .monospacedDigit()
            } label: {
                Label("夜の流れ・日記", systemImage: "moon.stars.fill")
            }

            ProgressView(value: 1, total: 4)
                .tint(.indigo)
                .accessibilityLabel("夜の流れ")
                .accessibilityValue("4ステップ中1ステップ目、日記")
        }
    }

    private var stepSelectorSection: some View {
        Section {
            Picker("日記の項目", selection: $step) {
                ForEach(EveningJournalStep.allCases) { step in
                    Text(step.title).tag(step)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityValue("\(step.rawValue + 1) / \(EveningJournalStep.allCases.count)、\(step.title)")
        }
    }

    private var mascotPromptSection: some View {
        Section {
            MascotPromptView(
                message: mascotMessage,
                detail: mascotDetail,
                imageSize: 72
            )
            .listRowInsets(
                EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
            )
            .listRowBackground(Color.clear)
        }
    }

    private var mascotMessage: String {
        switch step {
        case .today:
            "今日あったことを、少しだけ聞かせて"
        case .letGo:
            "今夜はここに置いて、いったん休もう"
        case .tomorrow:
            "明日の自分に、小さな予定を3つまで"
        }
    }

    private var mascotDetail: String {
        switch step {
        case .today:
            "短いひとことでも、空欄でも大丈夫です。"
        case .letGo:
            "今すぐ答えを出さなくてよいことを書けます。"
        case .tomorrow:
            "全部埋めなくても、そのまま次へ進めます。"
        }
    }

    @ViewBuilder
    private var currentStepSection: some View {
        switch step {
        case .today:
            Section {
                TextField(
                    "今日は…",
                    text: $todayNote,
                    axis: .vertical
                )
                .focused($focusedField, equals: .today)
                .lineLimit(4...6)
                .accessibilityLabel("今日あったこと")
            } header: {
                Label("今日あったこと", systemImage: "square.and.pencil")
            } footer: {
                characterCount(
                    todayNote,
                    maximum: EveningStore.todayNoteCharacterLimit
                )
            }

        case .letGo:
            Section {
                TextField(
                    "いったん手放すこと…",
                    text: $letGoNote,
                    axis: .vertical
                )
                .focused($focusedField, equals: .letGo)
                .lineLimit(4...6)
                .accessibilityLabel("明日に回してよいこと")
            } header: {
                Label("明日に回してよいこと", systemImage: "wind")
            } footer: {
                characterCount(
                    letGoNote,
                    maximum: EveningStore.letGoNoteCharacterLimit
                )
            }

        case .tomorrow:
            Section {
                ForEach(tomorrowItems.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 20, alignment: .trailing)

                        TextField(
                            tomorrowPlaceholder(at: index),
                            text: tomorrowItemBinding(at: index),
                            axis: .vertical
                        )
                        .focused($focusedField, equals: .tomorrow(index))
                        .lineLimit(1...2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("明日の\(index + 1)つ目")
                }
            } header: {
                Label("明日の3つ", systemImage: "list.number")
            } footer: {
                Text("小さな予定でも大丈夫です。空欄のまま保存することもできます。各項目は最大\(EveningStore.tomorrowItemCharacterLimit)文字です。")
            }
        }
    }

    private var navigationSection: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    previousButton
                    forwardButton
                }

                VStack(spacing: 10) {
                    forwardButton
                    previousButton
                }
            }
        } footer: {
            Text("どの項目も任意です。無理に書かず、今日を静かに閉じるために使ってください。")
        }
    }

    private var previousButton: some View {
        Button {
            moveBackward()
        } label: {
            Text("前へ")
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(step == .today)
        .accessibilityLabel("前の日記項目へ")
    }

    private var forwardButton: some View {
        Button {
            moveForward()
        } label: {
            Text(step == .tomorrow ? "保存して次へ" : "次へ")
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(didComplete)
        .accessibilityLabel(step == .tomorrow ? "日記を保存して次へ" : "次の日記項目へ")
    }

    private func characterCount(_ text: String, maximum: Int) -> some View {
        HStack {
            Text("入力は任意です")
            Spacer()
            Text("\(text.count) / \(maximum)")
                .monospacedDigit()
        }
    }

    private func tomorrowPlaceholder(at index: Int) -> String {
        switch index {
        case 0: "いちばん大切なこと"
        case 1: "できたら進めたいこと"
        default: "自分のためにしたいこと"
        }
    }

    private func tomorrowItemBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard tomorrowItems.indices.contains(index) else { return "" }
                return tomorrowItems[index]
            },
            set: { newValue in
                guard tomorrowItems.indices.contains(index) else { return }
                tomorrowItems[index] = limited(
                    newValue,
                    maximumCharacters: EveningStore.tomorrowItemCharacterLimit
                )
            }
        )
    }

    private func limited(_ text: String, maximumCharacters: Int) -> String {
        guard text.count > maximumCharacters else { return text }
        return String(text.prefix(maximumCharacters))
    }

    private func moveBackward() {
        guard let previousStep = EveningJournalStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy) {
            step = previousStep
        }
    }

    private func moveForward() {
        if let nextStep = EveningJournalStep(rawValue: step.rawValue + 1) {
            withAnimation(.snappy) {
                step = nextStep
            }
            return
        }

        completeJournal()
    }

    private func loadEntry() {
        guard !didLoad else { return }
        didLoad = true
        guard let entry = eveningStore.entry(for: day) else { return }

        todayNote = entry.todayNote
        letGoNote = entry.letGoNote
        for (index, value) in entry.tomorrowItems.enumerated()
            where tomorrowItems.indices.contains(index) {
            tomorrowItems[index] = value
        }
    }

    private func completeJournal() {
        guard !didComplete else { return }
        guard eveningStore.save(
            day: day,
            todayNote: todayNote,
            letGoNote: letGoNote,
            tomorrowItems: tomorrowItems,
            completed: true
        ) != nil else {
            return
        }

        didComplete = true
        focusedField = nil
        onCompleted()
        if dismissesOnCompletion {
            dismiss()
        }
    }
}

#Preview {
    EveningJournalView()
        .environmentObject(EveningStore())
}
