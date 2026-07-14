import SwiftUI

private enum LearningPhase: String, CaseIterable, Hashable {
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

    var symbol: String {
        switch self {
        case .study: "rectangle.stack.fill"
        case .audio: "speaker.wave.2.fill"
        case .test: "checkmark.circle.fill"
        }
    }

    var step: Int {
        switch self {
        case .study: 1
        case .audio: 2
        case .test: 3
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

    @State private var phase: LearningPhase = .study
    @State private var studyIndex = 0
    @State private var isStudyAnswerVisible = false
    @State private var isPresentingAddCard = false
    @State private var pendingDeletionID: UUID?

    @State private var quizQuestions: [LearningQuizQuestion] = []
    @State private var quizIndex = 0
    @State private var selectedQuizOptionID: UUID?
    @State private var correctQuizAnswers = 0
    @State private var isQuizComplete = false

    private let intervalOptions: [Double] = [30, 60, 120, 300]
    private let durationOptions = [15, 30, 60, 90, 390]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 18) {
                FlowHeader(
                    eyebrow: "Sleep Learning",
                    title: "睡眠学習",
                    subtitle: "昼に覚えて、眠る前に整え、朝にたしかめます。",
                    symbol: "book.pages.fill",
                    completedSteps: phase.step,
                    totalSteps: 3
                )

                statusMessages
                phaseSelector

                switch phase {
                case .study:
                    studySection
                case .audio:
                    audioSection
                case .test:
                    testSection
                }
            }
        }
        .sleepScreenScroll()
        .foregroundStyle(SleepPalette.text)
        .onChange(of: learningStore.cards.map(\.id)) { _, _ in
            normalizeStudyIndex()
            if quizQuestions.contains(where: { question in
                !learningStore.cards.contains(where: { $0.id == question.cardID })
            }) {
                resetQuiz()
            }
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
            .presentationBackground(SleepPalette.night)
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
            SleepStatusBanner(message: errorMessage, kind: .error)
        } else if let statusMessage = learningStore.statusMessage, !statusMessage.isEmpty {
            SleepStatusBanner(message: statusMessage, kind: .success)
        }
    }

    private var phaseSelector: some View {
        Picker("学習フェーズ", selection: $phase) {
            ForEach(LearningPhase.allCases, id: \.rawValue) { phase in
                Label(phase.title, systemImage: phase.symbol)
                    .tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .padding(5)
        .background(SleepPalette.panel.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("睡眠学習のフェーズ")
    }

    @ViewBuilder
    private var studySection: some View {
        sectionHeading(
            title: "学習カード",
            subtitle: "カードをタップして答えを確認",
            trailing: "\(learningStore.cards.count)枚"
        )

        if let card = currentStudyCard {
            GlassCard(tint: SleepPalette.warmGold.opacity(0.09), padding: 18) {
                VStack(spacing: 18) {
                    HStack {
                        Text("\(studyIndex + 1) / \(learningStore.cards.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(SleepPalette.warmGold)
                        Spacer()
                        Text(card.languageCode)
                            .font(.caption2.monospaced())
                            .foregroundStyle(SleepPalette.secondaryText)
                    }

                    Button {
                        withAnimation(.snappy) {
                            isStudyAnswerVisible.toggle()
                        }
                    } label: {
                        VStack(spacing: 18) {
                            studyPrompt(card)

                            Divider()
                                .overlay(Color.white.opacity(0.10))

                            if isStudyAnswerVisible {
                                studyAnswer(card)
                                    .transition(.blurReplace.combined(with: .opacity))
                            } else {
                                Label("答えを見る", systemImage: "hand.tap.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SleepPalette.secondaryText)
                                    .frame(minHeight: 72)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isStudyAnswerVisible ? "答えを隠します" : "答えを表示します")

                    HStack(spacing: 10) {
                        Button(action: previousStudyCard) {
                            Label("前へ", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                        .disabled(studyIndex == 0)

                        Button(action: nextStudyCard) {
                            Label("次へ", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                        .tint(SleepPalette.warmGold)
                        .foregroundStyle(SleepPalette.night)
                        .disabled(studyIndex >= learningStore.cards.count - 1)
                    }
                }
            }
        } else {
            emptyCardsPanel
        }

        Button {
            isPresentingAddCard = true
        } label: {
            Label("自分のカードを追加", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 17))
        .tint(SleepPalette.chartBlue.opacity(0.12))
    }

    @ViewBuilder
    private func studyPrompt(_ card: LearningCard) -> some View {
        if let cells = card.brailleCells, !cells.isEmpty {
            VStack(spacing: 13) {
                Text("この点字は？")
                    .font(.subheadline)
                    .foregroundStyle(SleepPalette.secondaryText)
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
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(SleepPalette.warmGold)
                Text(card.answer)
                    .font(.footnote)
                    .foregroundStyle(SleepPalette.secondaryText)
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
                        .foregroundStyle(SleepPalette.secondaryText)
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
        sectionHeading(
            title: "睡眠中の音声",
            subtitle: "選んだカードを静かに読み上げます",
            trailing: learningStore.isPlaying ? "再生中" : "待機中"
        )

        GlassCard(tint: playbackTint.opacity(0.10), padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Image(systemName: learningStore.isPlaying ? "waveform.circle.fill" : "moon.zzz.fill")
                        .font(.title2)
                        .foregroundStyle(playbackTint)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(learningStore.isPlaying ? "読み上げています" : "再生の準備")
                            .font(.headline)
                        Text(playbackDetail)
                            .font(.caption)
                            .foregroundStyle(SleepPalette.secondaryText)
                            .lineLimit(2)
                    }
                }

                if let currentCard = learningStore.currentSpokenCard {
                    LearningInlineCard(card: currentCard)
                }

                Button(action: togglePlayback) {
                    Label(
                        learningStore.isPlaying ? "睡眠音声を停止" : "睡眠音声を開始",
                        systemImage: learningStore.isPlaying ? "stop.fill" : "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .tint(learningStore.isPlaying ? SleepPalette.sunrise : SleepPalette.warmGold)
                .foregroundStyle(SleepPalette.night)
                .disabled(!learningStore.isPlaying && learningStore.settings.selectedCardIDs.isEmpty)
                .accessibilityHint(
                    learningStore.isPlaying
                        ? "読み上げを停止します"
                        : "選択したカードの読み上げを開始します"
                )
            }
        }

        LearningOpaquePanel {
            VStack(spacing: 0) {
                settingPickerRow(
                    title: "再生間隔",
                    symbol: "timer",
                    selection: settingsBinding(\.intervalSeconds),
                    options: intervalOptions,
                    label: intervalLabel
                )

                learningDivider

                settingPickerRow(
                    title: "再生時間",
                    symbol: "clock.fill",
                    selection: settingsBinding(\.durationMinutes),
                    options: durationOptions,
                    label: durationLabel
                )

                learningDivider

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("音量", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int((learningStore.settings.volume * 100).rounded()))%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(SleepPalette.secondaryText)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                        Slider(
                            value: settingsBinding(\.volume),
                            in: Float(0)...Float(1),
                            step: Float(0.05)
                        )
                        .tint(SleepPalette.warmGold)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(SleepPalette.secondaryText)
                }
                .padding(.vertical, 14)

                learningDivider

                Toggle(isOn: settingsBinding(\.shuffle)) {
                    Label("順番をシャッフル", systemImage: "shuffle")
                        .font(.subheadline.weight(.medium))
                }
                .tint(SleepPalette.warmGold)
                .padding(.vertical, 14)

                learningDivider

                Toggle(isOn: settingsBinding(\.autoStartWithSleepTimer)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("睡眠タイマーと一緒に開始", systemImage: "moon.fill")
                            .font(.subheadline.weight(.medium))
                        Text("睡眠計測を始めると自動再生")
                            .font(.caption)
                            .foregroundStyle(SleepPalette.secondaryText)
                    }
                }
                .tint(SleepPalette.warmGold)
                .padding(.vertical, 14)

                learningDivider

                Label(
                    "眠りを妨げない小さな音量から試してください。学習効果を保証する機能ではなく、端末負荷を抑えるため再生は最大120回です。",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(SleepPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
            }
        }

        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("再生するカード")
                    .font(.headline)
                Text("\(learningStore.settings.selectedCardIDs.count)枚を選択中")
                    .font(.caption)
                    .foregroundStyle(SleepPalette.secondaryText)
            }
            Spacer()
            Button {
                isPresentingAddCard = true
            } label: {
                Label("追加", systemImage: "plus")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(SleepPalette.chartBlue.opacity(0.12))
        }

        if learningStore.cards.isEmpty {
            emptyCardsPanel
        } else {
            ForEach(learningStore.cards, id: \.id) { card in
                audioSelectionRow(card)
            }
        }
    }

    private func audioSelectionRow(_ card: LearningCard) -> some View {
        let selected = learningStore.settings.selectedCardIDs.contains(card.id)

        return HStack(spacing: 10) {
            Button {
                learningStore.toggleSelection(cardID: card.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? SleepPalette.warmGold : SleepPalette.secondaryText)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.prompt)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(card.speechText)
                            .font(.caption)
                            .foregroundStyle(SleepPalette.secondaryText)
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

            Button(role: .destructive) {
                pendingDeletionID = card.id
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SleepPalette.danger)
            .accessibilityLabel("\(card.prompt)を削除")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            selected ? SleepPalette.panel.opacity(0.90) : SleepPalette.panel.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(
                    selected ? SleepPalette.warmGold.opacity(0.34) : Color.white.opacity(0.07),
                    lineWidth: selected ? 1 : 0.75
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var testSection: some View {
        sectionHeading(
            title: "朝の確認テスト",
            subtitle: "昨日覚えたカードを思い出します",
            trailing: quizQuestions.isEmpty ? "未開始" : "\(min(quizIndex + 1, quizQuestions.count)) / \(quizQuestions.count)"
        )

        if isQuizComplete {
            quizResultPanel
        } else if let question = currentQuizQuestion {
            quizQuestionPanel(question)
        } else {
            quizStartPanel
        }
    }

    private var quizStartPanel: some View {
        GlassCard(tint: SleepPalette.mint.opacity(0.08), padding: 20) {
            VStack(spacing: 16) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(SleepPalette.warmGold)

                VStack(spacing: 5) {
                    Text("朝の記憶をチェック")
                        .font(.title3.bold())
                    Text("2枚以上のカードから、最大10問を出題します。")
                        .font(.subheadline)
                        .foregroundStyle(SleepPalette.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Button(action: startQuiz) {
                    Label("テストを始める", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .tint(SleepPalette.warmGold)
                .foregroundStyle(SleepPalette.night)
                .disabled(quizDeck.count < 2)

                if quizDeck.count < 2 {
                    Text("テストにはカードが2枚以上必要です。")
                        .font(.caption)
                        .foregroundStyle(SleepPalette.sunrise)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func quizQuestionPanel(_ question: LearningQuizQuestion) -> some View {
        GlassCard(tint: SleepPalette.chartBlue.opacity(0.09), padding: 18) {
            VStack(spacing: 17) {
                ProgressView(value: Double(quizIndex + 1), total: Double(quizQuestions.count))
                    .tint(SleepPalette.warmGold)
                    .accessibilityLabel("テストの進み具合")
                    .accessibilityValue("\(quizIndex + 1)問目、全\(quizQuestions.count)問")

                if let cells = question.brailleCells, !cells.isEmpty {
                    VStack(spacing: 10) {
                        Text("この点字はどのかな？")
                            .font(.subheadline)
                            .foregroundStyle(SleepPalette.secondaryText)
                        BrailleCellsView(cells: cells)
                    }
                } else {
                    Text(question.prompt)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 90)
                }

                VStack(spacing: 9) {
                    ForEach(question.options) { option in
                        quizOptionButton(option, for: question)
                    }
                }

                if selectedQuizOptionID != nil {
                    Button(action: advanceQuiz) {
                        Label(
                            quizIndex == quizQuestions.count - 1 ? "結果を見る" : "次の問題",
                            systemImage: "arrow.right.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 17))
                    .tint(SleepPalette.warmGold)
                    .foregroundStyle(SleepPalette.night)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        let color: Color = {
            if hasAnswered && isCorrect { return SleepPalette.mint }
            if hasAnswered && isSelected { return SleepPalette.danger }
            return Color.white.opacity(0.08)
        }()

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
                        .foregroundStyle(isCorrect ? SleepPalette.mint : SleepPalette.danger)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(color.opacity(hasAnswered ? 0.20 : 1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(color.opacity(hasAnswered ? 0.78 : 0.30), lineWidth: isSelected || (hasAnswered && isCorrect) ? 1.5 : 0.75)
                .allowsHitTesting(false)
        }
        .disabled(hasAnswered)
        .accessibilityLabel(option.text)
        .accessibilityValue(quizOptionAccessibilityValue(isSelected: isSelected, isCorrect: isCorrect, hasAnswered: hasAnswered))
    }

    private var quizResultPanel: some View {
        GlassCard(tint: resultTint.opacity(0.12), padding: 22) {
            VStack(spacing: 16) {
                Image(systemName: resultSymbol)
                    .font(.system(size: 46))
                    .foregroundStyle(resultTint)

                VStack(spacing: 4) {
                    Text("テスト完了")
                        .font(.subheadline)
                        .foregroundStyle(SleepPalette.secondaryText)
                    Text("\(quizScorePercent)%")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(resultTint)
                    Text("\(correctQuizAnswers) / \(quizQuestions.count)問 正解")
                        .font(.headline)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("テスト完了、\(quizQuestions.count)問中\(correctQuizAnswers)問正解、\(quizScorePercent)パーセント")

                Button(action: startQuiz) {
                    Label("もう一度テスト", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 17))
                .tint(SleepPalette.warmGold)
                .foregroundStyle(SleepPalette.night)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyCardsPanel: some View {
        LearningOpaquePanel {
            ContentUnavailableView {
                Label("カードがありません", systemImage: "rectangle.stack.badge.plus")
            } description: {
                Text("自分の言葉や覚えたい内容を追加できます。")
            }
            .foregroundStyle(SleepPalette.text)
        }
    }

    private func sectionHeading(title: String, subtitle: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SleepPalette.secondaryText)
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(SleepPalette.warmGold)
        }
        .accessibilityElement(children: .combine)
    }

    private var learningDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }

    private func settingPickerRow<Value: Hashable>(
        title: String,
        symbol: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(SleepPalette.warmGold)
        }
        .padding(.vertical, 13)
    }

    private var currentStudyCard: LearningCard? {
        guard learningStore.cards.indices.contains(studyIndex) else { return nil }
        return learningStore.cards[studyIndex]
    }

    private var playbackTint: Color {
        learningStore.isPlaying ? SleepPalette.mint : SleepPalette.chartBlue
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
        case 80...: SleepPalette.mint
        case 50...: SleepPalette.warmGold
        default: SleepPalette.sunrise
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
            learningStore.saveTestResult(
                correctAnswers: correctQuizAnswers,
                totalQuestions: quizQuestions.count
            )
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

private struct LearningOpaquePanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                SleepPalette.panel.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

private struct LearningInlineCard: View {
    let card: LearningCard

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(SleepPalette.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.prompt)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(card.speechText)
                    .font(.caption)
                    .foregroundStyle(SleepPalette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SleepPalette.night.opacity(0.52), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .foregroundStyle(SleepPalette.secondaryText)
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
                                    ? SleepPalette.warmGold
                                    : SleepPalette.night.opacity(0.72)
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        activeDots.contains(dot)
                                            ? SleepPalette.warmGold.opacity(0.92)
                                            : SleepPalette.secondaryText.opacity(0.42),
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("覚えたいカードを追加")
                            .font(.title2.bold())
                        Text("一般カードとして、問題と答えを自由に登録できます。")
                            .font(.subheadline)
                            .foregroundStyle(SleepPalette.secondaryText)
                    }

                    learningField(title: "問題", placeholder: "例：TLSとは？", text: $prompt)
                    learningField(title: "答え", placeholder: "例：通信を暗号化する仕組み", text: $answer)
                    learningField(
                        title: "読み上げる文（省略可）",
                        placeholder: "空欄なら答えを読み上げます",
                        text: $speechText
                    )

                    HStack {
                        Label("読み上げ言語", systemImage: "globe")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Picker("読み上げ言語", selection: $languageCode) {
                            Text("日本語").tag("ja-JP")
                            Text("英語").tag("en-US")
                        }
                        .pickerStyle(.menu)
                        .tint(SleepPalette.warmGold)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(SleepPalette.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    Text("点字カードは初期デッキに含まれます。追加したカードは通常の問題カードとして使えます。")
                        .font(.caption)
                        .foregroundStyle(SleepPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
            .foregroundStyle(SleepPalette.text)
            .background(SleepPalette.night.ignoresSafeArea())
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
        .preferredColorScheme(.dark)
    }

    private func learningField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SleepPalette.secondaryText)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(SleepPalette.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                        .allowsHitTesting(false)
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
