import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isImportingCSV = false
    @State private var csvImportMessage: String?
    @State private var selectedFolder = "__all__"
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
    private let onTestCompleted: ((LearningTestResult) -> Void)?
    private let showsPhaseSelector: Bool
    private let showsStudyContinuation: Bool
    private let allowsTestSkipping: Bool

    init(
        phase: Binding<SleepLearningPhase> = .constant(.study),
        targetSleepSessionID: UUID? = nil,
        showsPhaseSelector: Bool = false,
        showsStudyContinuation: Bool = false,
        allowsTestSkipping: Bool = true,
        onContinueToSleep: (() -> Void)? = nil,
        onOpenHistory: (() -> Void)? = nil,
        onTestCompleted: ((LearningTestResult) -> Void)? = nil
    ) {
        _phase = phase
        self.targetSleepSessionID = targetSleepSessionID
        self.showsPhaseSelector = showsPhaseSelector
        self.showsStudyContinuation = showsStudyContinuation
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
                    folderFilterSection
                    studySection
                case .audio:
                    folderFilterSection
                    audioSection
                case .test:
                    testSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle(navigationTitle)
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
            if selectedFolder != "__all__",
               !learningStore.folderNames.contains(selectedFolder) {
                selectedFolder = "__all__"
            }
            normalizeStudyIndex()
            if quizQuestions.contains(where: { question in
                !learningStore.cards.contains(where: { $0.id == question.cardID })
            }) {
                resetQuiz()
            }
        }
        .onChange(of: selectedFolder) { _, _ in
            normalizeStudyIndex()
        }
        .onChange(of: targetSleepSessionID) { _, _ in
            resetQuiz()
        }
        .sheet(isPresented: $isPresentingAddCard) {
            AddLearningCardSheet { prompt, answer, speechText, languageCode, folderName in
                learningStore.addCard(
                    prompt: prompt,
                    answer: answer,
                    speechText: speechText,
                    languageCode: languageCode,
                    brailleCells: nil,
                    folderName: folderName
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
        .fileImporter(
            isPresented: $isImportingCSV,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: importCSV
        )
        .alert(
            "CSVインポート",
            isPresented: Binding(
                get: { csvImportMessage != nil },
                set: { if !$0 { csvImportMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { csvImportMessage = nil }
        } message: {
            Text(csvImportMessage ?? "")
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
    private var folderFilterSection: some View {
        if !learningStore.folderNames.isEmpty {
            Section {
                Picker("フォルダ", selection: $selectedFolder) {
                    Text("すべて").tag("__all__")
                    ForEach(learningStore.folderNames, id: \.self) { folder in
                        Text(folder).tag(folder)
                    }
                }
                .pickerStyle(.menu)
            }
        }
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
                    VStack(spacing: 12) {
                        HStack {
                            Text("\(studyIndex + 1) / \(filteredCards.count)")
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
                                .frame(minHeight: 52)
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
                Text("\(filteredCards.count)枚")
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

            addCardsMenu(title: "自分のカードを追加")

            if showsStudyContinuation {
                Button {
                    withAnimation(.snappy) {
                        phase = .audio
                    }
                } label: {
                    centeredActionLabel("次は睡眠音声", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var previousStudyButton: some View {
        Button(action: previousStudyCard) {
            Text("前へ")
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(studyIndex == 0 || learningStore.cards.isEmpty)
        .accessibilityLabel("前の学習カードへ")
    }

    private var nextStudyButton: some View {
        Button(action: nextStudyCard) {
            Text("次へ")
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(studyIndex >= learningStore.cards.count - 1)
        .accessibilityLabel("次の学習カードへ")
    }

    @ViewBuilder
    private func studyPrompt(_ card: LearningCard) -> some View {
        if let cells = card.brailleCells, !cells.isEmpty {
            VStack(spacing: 10) {
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
                .frame(minHeight: 84)
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
            .frame(minHeight: 52)
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
            .frame(minHeight: 52)
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
                centeredActionLabel(
                    learningStore.isPlaying ? "睡眠音声を停止" : "睡眠音声を開始",
                    systemImage: learningStore.isPlaying ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .tint(learningStore.isPlaying ? Color.red : Color.accentColor)
            .disabled(!learningStore.isPlaying && learningStore.settings.selectedCardIDs.isEmpty)
            .accessibilityHint(
                learningStore.isPlaying
                    ? "読み上げを停止します"
                    : "選択したカードの読み上げを開始します"
            )

            if let onContinueToSleep {
                Button(action: onContinueToSleep) {
                    centeredActionLabel("睡眠記録へ", systemImage: "moon.zzz.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
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
            addCardsMenu(title: "カードを追加")

            if filteredCards.isEmpty {
                emptyCardsRow
            } else {
                ForEach(filteredCards, id: \.id) { card in
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
                    Label(card.folderName, systemImage: "folder.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                    centeredActionLabel("もう一度テスト", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                if let onOpenHistory {
                    Button(action: onOpenHistory) {
                        centeredActionLabel("記録を見る", systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
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
                        .frame(maxWidth: .infinity, minHeight: 64)
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
                        centeredActionLabel(
                            quizIndex == quizQuestions.count - 1 ? "結果を見る" : "次の問題",
                            systemImage: "arrow.right.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            Section {
                Label("朝の記憶をチェック", systemImage: "sun.horizon.fill")
                    .font(.headline)

                Text("2枚以上のカードから、最大10問を出題します。")
                    .foregroundStyle(.secondary)

                Button(action: startQuiz) {
                    centeredActionLabel("テストを始める", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
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
                        centeredActionLabel(
                            quizDeck.count < 2
                                ? "カードが足りないため記録へ"
                                : "テストをスキップして記録へ",
                            systemImage: "arrow.right"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
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
        .buttonStyle(.bordered)
        .controlSize(.large)
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

    private func centeredActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
    }

    private func addCardsMenu(title: String) -> some View {
        Menu {
            Button {
                isPresentingAddCard = true
            } label: {
                Label("1枚ずつ追加", systemImage: "rectangle.stack.badge.plus")
            }

            Button {
                isImportingCSV = true
            } label: {
                Label("CSVからまとめて追加", systemImage: "tablecells.badge.ellipsis")
            }
        } label: {
            centeredActionLabel(title, systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
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
        guard filteredCards.indices.contains(studyIndex) else { return nil }
        return filteredCards[studyIndex]
    }

    private var filteredCards: [LearningCard] {
        selectedFolder == "__all__"
            ? learningStore.cards
            : learningStore.cards.filter { $0.folderName == selectedFolder }
    }

    private var navigationTitle: String {
        switch phase {
        case .study: "睡眠学習"
        case .audio: "睡眠音声"
        case .test: "朝テスト"
        }
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
        if filteredCards.isEmpty {
            studyIndex = 0
        } else {
            studyIndex = min(max(studyIndex, 0), filteredCards.count - 1)
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
        guard studyIndex < filteredCards.count - 1 else { return }
        withAnimation(.snappy) {
            studyIndex += 1
            isStudyAnswerVisible = false
        }
    }

    private func importCSV(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let fallbackFolder = url.deletingPathExtension().lastPathComponent
            let parsed = try LearningCSVImporter.parse(
                data: data,
                defaultFolderName: fallbackFolder
            )
            let count = learningStore.importCards(parsed.rows)
            csvImportMessage = count > 0
                ? "\(count)枚を追加しました。\(parsed.skippedRows > 0 ? "\(parsed.skippedRows)行は空欄のためスキップしました。" : "")"
                : (learningStore.errorMessage ?? "追加できるカードがありませんでした。")
        } catch {
            csvImportMessage = error.localizedDescription
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
            guard let result = learningStore.saveTestResult(
                correctAnswers: correctQuizAnswers,
                totalQuestions: quizQuestions.count,
                sleepSessionID: targetSleepSessionID
            ) else {
                return
            }
            onTestCompleted?(result)
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
        guard let result = learningStore.saveTestResult(
            correctAnswers: 0,
            totalQuestions: 0,
            sleepSessionID: targetSleepSessionID,
            wasSkipped: true
        ) else {
            return
        }
        onTestCompleted?(result)
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

    let onSave: (String, String, String, String, String) -> Void

    @State private var prompt = ""
    @State private var answer = ""
    @State private var speechText = ""
    @State private var languageCode = "ja-JP"
    @State private var folderName = "自分のカード"

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
                    TextField("例：英単語 Unit 1", text: $folderName)
                } header: {
                    Text("フォルダ")
                } footer: {
                    Text("点字・英単語・授業ごとなど、好きな名前でカードを分けられます。")
                }

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
                    Text("英単語は問題に単語、答えに意味を入れ、読み上げ言語を英語にすると音声学習にも使えます。")
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
            languageCode,
            folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "自分のカード"
                : folderName
        )
        dismiss()
    }
}
