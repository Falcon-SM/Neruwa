import SwiftUI

enum SleepLearningPhase: String, CaseIterable, Hashable {
    case study
    case audio
    case test

    var title: String {
        switch self {
        case .study: "学ぶ"
        case .audio: "睡眠音声"
        case .test: "朝テスト"
        }
    }

}

private struct LearningQuizOption: Identifiable {
    let id: UUID
    let text: String
}

private struct LearningQuizQuestion: Identifiable {
    let id = UUID()
    let cardID: UUID
    let prompt: String
    let brailleCells: [[Int]]?
    let options: [LearningQuizOption]
    let correctOptionID: UUID
}

struct SleepLearningView: View {
    @EnvironmentObject private var learningStore: SleepLearningStore

    @Binding private var phase: SleepLearningPhase
    @State private var studyIndex = 0
    @State private var isStudyAnswerVisible = false
    @State private var isPresentingAddCard = false
    @State private var pendingDeletionID: UUID?
    @State private var draftVolume: Float = 0.35
    @State private var isAdjustingVolume = false

    @State private var quizQuestions: [LearningQuizQuestion] = []
    @State private var quizIndex = 0
    @State private var selectedQuizOptionID: UUID?
    @State private var correctQuizAnswers = 0
    @State private var isQuizComplete = false

    private let intervalOptions: [Double] = [30, 60, 120, 300]
    private let durationOptions = [15, 30, 60, 90, 390]

    private let targetSleepSessionID: UUID?
    private let onContinueToSleep: (() -> Void)?
    private let onOpenHistory: (() -> Void)?
    private let onTestCompleted: (() -> Void)?
    private let showsPhaseSelector: Bool
    private let allowsTestSkipping: Bool

    init(
        phase: Binding<SleepLearningPhase> = .constant(.study),
        targetSleepSessionID: UUID? = nil,
        showsPhaseSelector: Bool = true,
        allowsTestSkipping: Bool = true,
        onContinueToSleep: (() -> Void)? = nil,
        onOpenHistory: (() -> Void)? = nil,
        onTestCompleted: (() -> Void)? = nil
    ) {
        _phase = phase
        self.targetSleepSessionID = targetSleepSessionID
        self.showsPhaseSelector = showsPhaseSelector
        self.allowsTestSkipping = allowsTestSkipping
        self.onContinueToSleep = onContinueToSleep
        self.onOpenHistory = onOpenHistory
        self.onTestCompleted = onTestCompleted
    }

    var body: some View {
        NavigationStack {
            List {
                statusMessages

                if showsPhaseSelector {
                    Section("学習フェーズ") {
                        phaseSelector
                    }
                }

                switch phase {
                case .study:
                    studySection
                case .audio:
                    audioSection
                case .test:
                    testSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("睡眠学習")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            draftVolume = learningStore.settings.volume
        }
        .onDisappear {
            commitDraftVolume()
        }
        .onChange(of: learningStore.settings.volume) { _, newVolume in
            if !isAdjustingVolume {
                draftVolume = newVolume
            }
        }
        .onChange(of: learningStore.cards.map(\.id)) { _, _ in
            normalizeStudyIndex()
            if quizQuestions.contains(where: { question in
                !learningStore.cards.contains(where: { $0.id == question.cardID })
            }) {
                resetQuiz()
            }
        }
        .onChange(of: targetSleepSessionID) { _, _ in
            resetQuiz()
        }
        .sheet(isPresented: $isPresentingAddCard) {
            AddLearningCardSheet { prompt, answer, speechText, languageCode in
                learningStore.addCard(
                    prompt: prompt,
                    answer: answer,
                    speechText: speechText,
                    languageCode: languageCode,
                    brailleCells: nil
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "学習カードを削除",
            isPresented: Binding(
                get: { pendingDeletionID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionID = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let cardID = pendingDeletionID {
                Button("削除", role: .destructive) {
                    learningStore.deleteCard(id: cardID)
                    pendingDeletionID = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                pendingDeletionID = nil
            }
        } message: {
            Text("このカードを学習・音声・テストから削除します。")
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let errorMessage = learningStore.errorMessage, !errorMessage.isEmpty {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } else if let statusMessage = learningStore.statusMessage, !statusMessage.isEmpty {
            Section {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var phaseSelector: some View {
        Picker("学習フェーズ", selection: $phase) {
            ForEach(SleepLearningPhase.allCases, id: \.rawValue) { phase in
                Text(phase.title)
                    .tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("睡眠学習のフェーズ")
    }

    @ViewBuilder
    private var studySection: some View {
        Section {
            if let card = currentStudyCard {
                Button {
                    withAnimation(.snappy) {
                        isStudyAnswerVisible.toggle()
                    }
                } label: {
                    VStack(spacing: 16) {
                        HStack {
                            Text("\(studyIndex + 1) / \(learningStore.cards.count)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                            Spacer()
                            Text(card.languageCode)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        studyPrompt(card)
                        Divider()

                        if isStudyAnswerVisible {
                            studyAnswer(card)
                                .transition(.blurReplace.combined(with: .opacity))
                        } else {
                            Label("答えを見る", systemImage: "hand.tap.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 72)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isStudyAnswerVisible ? "答えを隠します" : "答えを表示します")
            } else {
                emptyCardsRow
            }
        } header: {
            HStack {
                Text("学習カード")
                Spacer()
                Text("\(learningStore.cards.count)枚")
                    .monospacedDigit()
            }
        } footer: {
            Text("カードをタップすると答えを表示します。")
        }

        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    previousStudyButton
                    nextStudyButton
                }

                VStack(spacing: 10) {
                    previousStudyButton
                    nextStudyButton
                }
            }

            Button {
                isPresentingAddCard = true
            } label: {
                Label("自分のカードを追加", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                withAnimation(.snappy) {
                    phase = .audio
                }
            } label: {
                Label("次は睡眠音声", systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var previousStudyButton: some View {
        Button(action: previousStudyCard) {
            Label("前へ", systemImage: "chevron.left")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(studyIndex == 0 || learningStore.cards.isEmpty)
    }

    private var nextStudyButton: some View {
        Button(action: nextStudyCard) {
            Label("次へ", systemImage: "chevron.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(studyIndex >= learningStore.cards.count - 1)
    }

    @ViewBuilder
    private func studyPrompt(_ card: LearningCard) -> some View {
        if let cells = card.brailleCells, !cells.isEmpty {
            VStack(spacing: 13) {
                Text("この点字は？")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                BrailleCellsView(cells: cells)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(card.prompt)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 116)
                .accessibilityLabel("問題、\(card.prompt)")
        }
    }

    @ViewBuilder
    private func studyAnswer(_ card: LearningCard) -> some View {
        if let cells = card.brailleCells, !cells.isEmpty {
            VStack(spacing: 6) {
                Text(card.prompt)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.tint)
                Text(card.answer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 72)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("答え、\(card.prompt)、\(card.answer)")
        } else {
            VStack(spacing: 7) {
                Text(card.answer)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if card.speechText != card.answer {
                    Label(card.speechText, systemImage: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 72)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("答え、\(card.answer)")
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        Section {
            LabeledContent {
                Text(learningStore.isPlaying ? "再生中" : "待機中")
                    .foregroundStyle(playbackTint)
            } label: {
                Label(
                    "状態",
                    systemImage: learningStore.isPlaying ? "waveform.circle.fill" : "moon.zzz.fill"
                )
            }

            Text(playbackDetail)
                .foregroundStyle(.secondary)

            if let currentCard = learningStore.currentSpokenCard {
                LearningInlineCard(card: currentCard)
            }

            Button(action: togglePlayback) {
                Label(
                    learningStore.isPlaying ? "睡眠音声を停止" : "睡眠音声を開始",
                    systemImage: learningStore.isPlaying ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(learningStore.isPlaying ? Color.red : Color.accentColor)
            .disabled(!learningStore.isPlaying && learningStore.settings.selectedCardIDs.isEmpty)
            .accessibilityHint(
                learningStore.isPlaying
                    ? "読み上げを停止します"
                    : "選択したカードの読み上げを開始します"
            )

            if let onContinueToSleep {
                Button(action: onContinueToSleep) {
                    Label("睡眠記録へ", systemImage: "moon.zzz.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("睡眠中の音声")
        } footer: {
            Text("選んだカードを設定した間隔で読み上げます。")
        }

        Section {
            settingPickerRow(
                title: "再生間隔",
                symbol: "timer",
                selection: settingsBinding(\.intervalSeconds),
                options: intervalOptions,
                label: intervalLabel
            )

            settingPickerRow(
                title: "再生時間",
                symbol: "clock.fill",
                selection: settingsBinding(\.durationMinutes),
                options: durationOptions,
                label: durationLabel
            )

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent {
                    Text("\(Int((draftVolume * 100).rounded()))%")
                        .monospacedDigit()
                } label: {
                    Label("音量", systemImage: "speaker.wave.2.fill")
                }

                Slider(
                    value: $draftVolume,
                    in: Float(0)...Float(1),
                    step: Float(0.05),
                    label: {
                        Text("音量")
                    },
                    minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    },
                    maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    },
                    onEditingChanged: volumeEditingChanged
                )
            }

            Toggle(isOn: settingsBinding(\.shuffle)) {
                Label("順番をシャッフル", systemImage: "shuffle")
            }

            Toggle(isOn: settingsBinding(\.autoStartWithSleepTimer)) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("睡眠タイマーと一緒に開始", systemImage: "moon.fill")
                    Text("睡眠計測を始めると自動再生")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("再生設定")
        } footer: {
            Text("眠りを妨げない小さな音量から試してください。学習効果を保証する機能ではなく、端末負荷を抑えるため再生は最大120回です。")
        }

        Section {
            Button {
                isPresentingAddCard = true
            } label: {
                Label("カードを追加", systemImage: "plus")
            }

            if learningStore.cards.isEmpty {
                emptyCardsRow
            } else {
                ForEach(learningStore.cards, id: \.id) { card in
                    audioSelectionRow(card)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletionID = card.id
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                learningStore.toggleSelection(cardID: card.id)
                            } label: {
                                let selected = learningStore.settings.selectedCardIDs.contains(card.id)
                                Label(
                                    selected ? "選択を解除" : "再生に追加",
                                    systemImage: selected ? "minus.circle" : "plus.circle"
                                )
                            }

                            Button(role: .destructive) {
                                pendingDeletionID = card.id
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            HStack {
                Text("再生するカード")
                Spacer()
                Text("\(learningStore.settings.selectedCardIDs.count)枚を選択中")
                    .monospacedDigit()
            }
        }
    }

    private func audioSelectionRow(_ card: LearningCard) -> some View {
        let selected = learningStore.settings.selectedCardIDs.contains(card.id)

        return Button {
            learningStore.toggleSelection(cardID: card.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.prompt)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(card.speechText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let cells = card.brailleCells, !cells.isEmpty {
                    BrailleCellsView(cells: cells, compact: true)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.prompt)、\(selected ? "選択中" : "未選択")")
    }

    @ViewBuilder
    private var testSection: some View {
        if isQuizComplete {
            Section("テスト結果") {
                VStack(spacing: 10) {
                    Image(systemName: resultSymbol)
                        .font(.largeTitle)
                        .foregroundStyle(resultTint)
                    Text("\(quizScorePercent)%")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(resultTint)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("テスト完了、\(quizQuestions.count)問中\(correctQuizAnswers)問正解、\(quizScorePercent)パーセント")

                LabeledContent("正解数") {
                    Text("\(correctQuizAnswers) / \(quizQuestions.count)問")
                        .monospacedDigit()
                }

                Button(action: startQuiz) {
                    Label("もう一度テスト", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let onOpenHistory {
                    Button(action: onOpenHistory) {
                        Label("記録を見る", systemImage: "chart.bar.xaxis")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if let question = currentQuizQuestion {
            Section {
                ProgressView(value: Double(quizIndex + 1), total: Double(quizQuestions.count))
                    .accessibilityLabel("テストの進み具合")
                    .accessibilityValue("\(quizIndex + 1)問目、全\(quizQuestions.count)問")

                if let cells = question.brailleCells, !cells.isEmpty {
                    VStack(spacing: 10) {
                        Text("この点字はどのかな？")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        BrailleCellsView(cells: cells)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(question.prompt)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 90)
                }
            } header: {
                HStack {
                    Text("問題")
                    Spacer()
                    Text("\(quizIndex + 1) / \(quizQuestions.count)")
                        .monospacedDigit()
                }
            }

            Section("答え") {
                ForEach(question.options) { option in
                    quizOptionButton(option, for: question)
                }
            }

            if selectedQuizOptionID != nil {
                Section {
                    Button(action: advanceQuiz) {
                        Label(
                            quizIndex == quizQuestions.count - 1 ? "結果を見る" : "次の問題",
                            systemImage: "arrow.right.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            Section {
                Label("朝の記憶をチェック", systemImage: "sun.horizon.fill")
                    .font(.headline)

                Text("2枚以上のカードから、最大10問を出題します。")
                    .foregroundStyle(.secondary)

                Button(action: startQuiz) {
                    Label("テストを始める", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(quizDeck.count < 2)

                if quizDeck.count < 2 {
                    Label("テストにはカードが2枚以上必要です。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let onOpenHistory,
                   allowsTestSkipping || quizDeck.count < 2 {
                    Button {
                        skipMorningTest(then: onOpenHistory)
                    } label: {
                        Label(
                            quizDeck.count < 2
                                ? "カードが足りないため記録へ"
                                : "テストをスキップして記録へ",
                            systemImage: "arrow.right"
                        )
                    }
                }
            } header: {
                Text("朝の確認テスト")
            } footer: {
                Text("昨日覚えたカードを思い出して確認します。")
            }
        }
    }

    private func quizOptionButton(
        _ option: LearningQuizOption,
        for question: LearningQuizQuestion
    ) -> some View {
        let isSelected = selectedQuizOptionID == option.id
        let isCorrect = option.id == question.correctOptionID
        let hasAnswered = selectedQuizOptionID != nil

        return Button {
            selectQuizOption(option, for: question)
        } label: {
            HStack(spacing: 10) {
                Text(option.text)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer()
                if hasAnswered && (isCorrect || isSelected) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isCorrect ? Color.green : Color.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(hasAnswered)
        .accessibilityLabel(option.text)
        .accessibilityValue(quizOptionAccessibilityValue(isSelected: isSelected, isCorrect: isCorrect, hasAnswered: hasAnswered))
    }

    private var emptyCardsRow: some View {
        ContentUnavailableView {
            Label("カードがありません", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("自分の言葉や覚えたい内容を追加できます。")
        }
    }

    private func settingPickerRow<Value: Hashable>(
        title: String,
        symbol: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        Picker(selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option))
                    .tag(option)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
        .pickerStyle(.menu)
    }

    private var currentStudyCard: LearningCard? {
        guard learningStore.cards.indices.contains(studyIndex) else { return nil }
        return learningStore.cards[studyIndex]
    }

    private var playbackTint: Color {
        learningStore.isPlaying ? .green : .secondary
    }

    private var playbackDetail: String {
        if let current = learningStore.currentSpokenCard {
            return current.speechText
        }
        let count = learningStore.settings.selectedCardIDs.count
        return count == 0 ? "下から再生するカードを選んでください" : "\(count)枚のカードを再生します"
    }

    private var quizDeck: [LearningCard] {
        let selected = learningStore.cards.filter {
            learningStore.settings.selectedCardIDs.contains($0.id)
        }
        return selected.count >= 2 ? selected : learningStore.cards
    }

    private var currentQuizQuestion: LearningQuizQuestion? {
        guard quizQuestions.indices.contains(quizIndex) else { return nil }
        return quizQuestions[quizIndex]
    }

    private var quizScorePercent: Int {
        guard !quizQuestions.isEmpty else { return 0 }
        return Int((Double(correctQuizAnswers) / Double(quizQuestions.count) * 100).rounded())
    }

    private var resultTint: Color {
        switch quizScorePercent {
        case 80...: .green
        case 50...: .orange
        default: .red
        }
    }

    private var resultSymbol: String {
        switch quizScorePercent {
        case 80...: "sparkles"
        case 50...: "sun.max.fill"
        default: "arrow.up.heart.fill"
        }
    }

    private func settingsBinding<Value>(
        _ keyPath: WritableKeyPath<SleepLearningSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { learningStore.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = learningStore.settings
                settings[keyPath: keyPath] = newValue
                learningStore.updateSettings(settings)
            }
        )
    }

    private func volumeEditingChanged(_ isEditing: Bool) {
        isAdjustingVolume = isEditing
        if !isEditing {
            commitDraftVolume()
        }
    }

    private func commitDraftVolume() {
        guard learningStore.settings.volume != draftVolume else { return }
        var settings = learningStore.settings
        settings.volume = draftVolume
        learningStore.updateSettings(settings)
    }

    private func intervalLabel(_ interval: Double) -> String {
        switch interval {
        case 60: "1分"
        case 120: "2分"
        case 300: "5分"
        default: "\(Int(interval))秒"
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)分" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)時間" : "\(hours)時間\(remainder)分"
    }

    private func normalizeStudyIndex() {
        if learningStore.cards.isEmpty {
            studyIndex = 0
        } else {
            studyIndex = min(max(studyIndex, 0), learningStore.cards.count - 1)
        }
        isStudyAnswerVisible = false
    }

    private func previousStudyCard() {
        guard studyIndex > 0 else { return }
        withAnimation(.snappy) {
            studyIndex -= 1
            isStudyAnswerVisible = false
        }
    }

    private func nextStudyCard() {
        guard studyIndex < learningStore.cards.count - 1 else { return }
        withAnimation(.snappy) {
            studyIndex += 1
            isStudyAnswerVisible = false
        }
    }

    private func togglePlayback() {
        if learningStore.isPlaying {
            learningStore.stopSleepPlayback()
        } else {
            learningStore.startSleepPlayback()
        }
    }

    private func startQuiz() {
        let sourceDeck = quizDeck
        guard sourceDeck.count >= 2 else { return }

        var orderedCards = sourceDeck
        if learningStore.settings.shuffle {
            orderedCards.shuffle()
        }
        let questionCards = Array(orderedCards.prefix(10))

        quizQuestions = questionCards.map { card in
            makeQuizQuestion(for: card, from: sourceDeck)
        }
        quizIndex = 0
        selectedQuizOptionID = nil
        correctQuizAnswers = 0
        isQuizComplete = false
    }

    private func makeQuizQuestion(
        for card: LearningCard,
        from deck: [LearningCard]
    ) -> LearningQuizQuestion {
        let correctText = quizAnswer(for: card)
        let correctID = UUID()
        var seen = Set([correctText])
        var distractors: [String] = []

        for candidate in deck.shuffled() where candidate.id != card.id {
            let answer = quizAnswer(for: candidate)
            if seen.insert(answer).inserted {
                distractors.append(answer)
            }
            if distractors.count == 3 { break }
        }

        var options = [LearningQuizOption(id: correctID, text: correctText)]
        options.append(contentsOf: distractors.map { LearningQuizOption(id: UUID(), text: $0) })
        options.shuffle()

        return LearningQuizQuestion(
            cardID: card.id,
            prompt: card.prompt,
            brailleCells: card.brailleCells,
            options: options,
            correctOptionID: correctID
        )
    }

    private func quizAnswer(for card: LearningCard) -> String {
        if let cells = card.brailleCells, !cells.isEmpty {
            return card.prompt
        }
        return card.answer
    }

    private func selectQuizOption(
        _ option: LearningQuizOption,
        for question: LearningQuizQuestion
    ) {
        guard selectedQuizOptionID == nil else { return }
        withAnimation(.snappy) {
            selectedQuizOptionID = option.id
            if option.id == question.correctOptionID {
                correctQuizAnswers += 1
            }
        }
    }

    private func advanceQuiz() {
        guard selectedQuizOptionID != nil else { return }

        if quizIndex < quizQuestions.count - 1 {
            withAnimation(.snappy) {
                quizIndex += 1
                selectedQuizOptionID = nil
            }
        } else {
            guard learningStore.saveTestResult(
                correctAnswers: correctQuizAnswers,
                totalQuestions: quizQuestions.count,
                sleepSessionID: targetSleepSessionID
            ) != nil else {
                return
            }
            onTestCompleted?()
            withAnimation(.snappy) {
                isQuizComplete = true
            }
        }
    }

    private func resetQuiz() {
        quizQuestions = []
        quizIndex = 0
        selectedQuizOptionID = nil
        correctQuizAnswers = 0
        isQuizComplete = false
    }

    private func skipMorningTest(then completion: () -> Void) {
        guard learningStore.saveTestResult(
            correctAnswers: 0,
            totalQuestions: 0,
            sleepSessionID: targetSleepSessionID,
            wasSkipped: true
        ) != nil else {
            return
        }
        onTestCompleted?()
        completion()
    }

    private func quizOptionAccessibilityValue(
        isSelected: Bool,
        isCorrect: Bool,
        hasAnswered: Bool
    ) -> String {
        guard hasAnswered else { return "未選択" }
        if isCorrect { return "正解" }
        if isSelected { return "選択、不正解" }
        return "未選択"
    }
}

private struct LearningInlineCard: View {
    let card: LearningCard

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(card.prompt)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(card.speechText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } label: {
            Label("再生中", systemImage: "speaker.wave.2.fill")
                .foregroundStyle(.green)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("再生中、\(card.speechText)")
    }
}

private struct BrailleCellsView: View {
    let cells: [[Int]]
    var compact = false

    private var visibleCells: ArraySlice<[Int]> {
        cells.prefix(compact ? 2 : 4)
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 13) {
            ForEach(Array(visibleCells.enumerated()), id: \.offset) { _, activeDots in
                BrailleCell(activeDots: Set(activeDots), compact: compact)
            }

            if cells.count > visibleCells.count {
                Text("+\(cells.count - visibleCells.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let descriptions = cells.map { cell in
            cell.sorted().map(String.init).joined(separator: "、")
        }
        return "点字。点 \(descriptions.joined(separator: "、次の文字は "))"
    }
}

private struct BrailleCell: View {
    let activeDots: Set<Int>
    var compact = false

    private let rows = [[1, 4], [2, 5], [3, 6]]

    var body: some View {
        VStack(spacing: compact ? 5 : 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: compact ? 5 : 9) {
                    ForEach(row, id: \.self) { dot in
                        Circle()
                            .fill(
                                activeDots.contains(dot)
                                    ? Color.accentColor
                                    : Color(uiColor: .tertiarySystemFill)
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        activeDots.contains(dot)
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.42),
                                        lineWidth: compact ? 0.75 : 1
                                    )
                                    .allowsHitTesting(false)
                            }
                            .frame(width: compact ? 9 : 22, height: compact ? 9 : 22)
                    }
                }
            }
        }
        .padding(compact ? 1 : 9)
    }
}

private struct AddLearningCardSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, String, String, String) -> Void

    @State private var prompt = ""
    @State private var answer = ""
    @State private var speechText = ""
    @State private var languageCode = "ja-JP"

    private var normalizedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedAnswer: String {
        answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedPrompt.isEmpty && !normalizedAnswer.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例：TLSとは？", text: $prompt, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("問題")
                }

                Section {
                    TextField("例：通信を暗号化する仕組み", text: $answer, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("答え")
                }

                Section {
                    TextField("空欄なら答えを読み上げます", text: $speechText, axis: .vertical)
                        .lineLimit(1...3)

                    Picker(selection: $languageCode) {
                        Text("日本語").tag("ja-JP")
                        Text("英語").tag("en-US")
                    } label: {
                        Label("読み上げ言語", systemImage: "globe")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("読み上げ")
                } footer: {
                    Text("点字カードは初期デッキに含まれます。追加したカードは通常の問題カードとして使えます。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("カードを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let spoken = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            normalizedPrompt,
            normalizedAnswer,
            spoken.isEmpty ? normalizedAnswer : spoken,
            languageCode
        )
        dismiss()
    }
}
