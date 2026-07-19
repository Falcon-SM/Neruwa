import SwiftUI

struct MandatoryDailyFlowGateView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @EnvironmentObject private var learningStore: SleepLearningStore
    @EnvironmentObject private var eveningStore: EveningStore
    @EnvironmentObject private var flowStore: MandatoryDailyFlowStore

    let context: MandatoryDailyFlowContext
    let onCompleted: (MandatoryDailyFlowContext?) -> Void
    let onInterrupted: () -> Void

    @State private var currentStep: MandatoryDailyFlowStep?
    @State private var didInitialize = false
    @State private var isCompleting = false

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let currentStep {
                stepContent(currentStep)
                    .id(currentStep.rawValue)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        MandatoryFlowProgressBanner(
                            period: context.period,
                            step: currentStep,
                            canInterrupt: canInterrupt,
                            onInterrupt: interruptFlow
                        )
                    }
            } else {
                ProgressView("今日の流れを準備しています")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ambientScreenBackground()
            }
        }
        .environment(
            \.ambientScene,
            context.period == .night
                ? .night
                : AmbientScene.timeFallback(schedule: context.schedule)
        )
        .preferredColorScheme(context.period == .night ? .dark : nil)
        .interactiveDismissDisabled()
        .task(id: context.id) {
            initializeFlowIfNeeded()
        }
    }

    @ViewBuilder
    private func stepContent(_ step: MandatoryDailyFlowStep) -> some View {
        switch step {
        case .morningMood:
            if let session = targetMorningSession {
                MorningReflectionView(
                    sessionID: session.id,
                    allowsDismissal: false,
                    dismissesOnSave: false
                ) { sessionID in
                    flowStore.setTargetSleepSessionID(context, sessionID: sessionID)
                    advance(to: .morningTest, targetSleepSessionID: sessionID)
                }
                .environmentObject(sleepStore)
            } else {
                MandatoryMorningMoodView(
                    initialMood: flowProgress?.pendingMood,
                    initialNote: flowProgress?.pendingNote ?? ""
                ) { mood, note in
                    flowStore.savePendingMorningReflection(
                        context,
                        mood: mood,
                        note: note
                    )
                    advance(to: .morningTest)
                }
            }

        case .morningTest:
            SleepLearningView(
                phase: .constant(.test),
                targetSleepSessionID: targetMorningSession?.id,
                showsPhaseSelector: false,
                allowsTestSkipping: false,
                onOpenHistory: {
                    attachPendingReflectionIfPossible()
                    advance(to: .morningRecord)
                },
                onTestCompleted: { result in
                    flowStore.markMorningTestCompleted(
                        context,
                        resultID: result.id
                    )
                }
            )
            .environmentObject(learningStore)

        case .morningRecord:
            MandatoryMorningRecordView(
                session: targetMorningSession,
                pendingMood: flowProgress?.pendingMood,
                pendingNote: flowProgress?.pendingNote ?? "",
                onCompleted: completeFlow
            )
            .environmentObject(sleepStore)

        case .nightJournal:
            EveningJournalView(
                day: context.targetDay,
                allowsDismissal: false,
                dismissesOnCompletion: false
            ) {
                advance(to: .nightStudy)
            }
            .environmentObject(eveningStore)

        case .nightStudy:
            SleepLearningView(
                phase: .constant(.study),
                showsPhaseSelector: false,
                showsStudyContinuation: false,
                allowsTestSkipping: false
            )
            .environmentObject(learningStore)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                mandatoryNightAdvanceButton("音声設定へ") {
                    advance(to: .nightAudio)
                }
            }

        case .nightAudio:
            SleepLearningView(
                phase: .constant(.audio),
                showsPhaseSelector: false,
                showsStudyContinuation: false,
                allowsTestSkipping: false
            )
            .environmentObject(learningStore)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                mandatoryNightAdvanceButton("睡眠記録へ") {
                    advance(to: .nightSleep)
                }
            }

        case .nightSleep:
            SleepRecorderView(
                allowedEntryModes: [.timer],
                initialEntryMode: .timer,
                showsHealthImport: false,
                allowsManualFallbackAfterInvalidTimer: true,
                onSleepSessionSaved: completeNightFlow,
                automaticallyPresentsReflection: false
            )
            .environmentObject(sleepStore)
            .environmentObject(learningStore)

        case .completed:
            ProgressView("完了しました")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ambientScreenBackground()
                .onAppear(perform: completeFlow)
        }
    }

    private func mandatoryNightAdvanceButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack {
            Button(action: action) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var flowProgress: MandatoryDailyFlowProgress? {
        flowStore.progress(for: context)
    }

    private var targetMorningSession: SleepSession? {
        if let sessionID = flowProgress?.targetSleepSessionID,
           let session = sleepStore.session(id: sessionID) {
            return session
        }
        return latestMorningSession
    }

    private var latestMorningSession: SleepSession? {
        sleepStore.resolvedSessions
            .filter {
                calendar.isDate(
                    DailyFlowPeriod.morningFlowDay(
                        containing: $0.endDate,
                        calendar: calendar,
                        schedule: context.schedule
                    ),
                    inSameDayAs: context.targetDay
                )
            }
            .max(by: { $0.endDate < $1.endDate })
    }

    private func initializeFlowIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true

        let existing = flowStore.progress(for: context)
        let initial = existing ?? flowStore.ensureProgress(
            for: context,
            initialStep: preferredInitialStep,
            targetSleepSessionID: latestMorningSession?.id
        )

        if initial.targetSleepSessionID == nil,
           let sessionID = latestMorningSession?.id {
            flowStore.setTargetSleepSessionID(context, sessionID: sessionID)
        }

        currentStep = initial.step
        reconcilePersistedData()
    }

    private var preferredInitialStep: MandatoryDailyFlowStep {
        switch context.period {
        case .morning:
            guard let session = latestMorningSession else {
                return .morningMood
            }
            guard session.mood != nil else {
                return .morningMood
            }
            return .morningTest

        case .night:
            if hasActiveTimerForCurrentNight {
                return .nightSleep
            }
            let journalComplete = eveningStore
                .entry(for: context.targetDay, calendar: calendar)?
                .completedAt != nil
            return journalComplete ? .nightStudy : .nightJournal
        }
    }

    private func reconcilePersistedData() {
        guard let step = currentStep else { return }

        switch step {
        case .morningMood:
            if let session = targetMorningSession, session.mood != nil {
                advance(to: .morningTest, targetSleepSessionID: session.id)
                reconcilePersistedData()
            }

        case .morningTest:
            if flowProgress?.morningTestCompletedAt != nil {
                attachPendingReflectionIfPossible()
                advance(to: .morningRecord)
            }

        case .nightJournal:
            if eveningStore.entry(
                for: context.targetDay,
                calendar: calendar
            )?.completedAt != nil {
                advance(to: .nightStudy)
            }

        case .completed:
            completeFlow()

        default:
            break
        }
    }

    private func attachPendingReflectionIfPossible() {
        guard let progress = flowStore.progress(for: context),
              let session = targetMorningSession else {
            return
        }

        flowStore.setTargetSleepSessionID(context, sessionID: session.id)
        if let mood = progress.pendingMood, session.mood == nil {
            sleepStore.updateReflection(
                id: session.id,
                mood: mood,
                note: progress.pendingNote
            )
        }
        if let resultID = progress.morningTestResultID {
            _ = learningStore.linkTestResult(id: resultID, to: session.id)
        }
    }

    private var hasActiveTimerForCurrentNight: Bool {
        guard let startedAt = sleepStore.activeTimerStartedAt,
              let interval = context.schedule.nightInterval(
                forFlowDay: context.targetDay,
                calendar: calendar
              ) else {
            return false
        }
        return startedAt >= interval.start && startedAt < interval.end
    }

    private var canInterrupt: Bool {
        !(currentStep == .nightSleep && sleepStore.activeTimerStartedAt != nil)
    }

    private func interruptFlow() {
        guard canInterrupt, !isCompleting else { return }
        learningStore.stopSleepPlayback()
        onInterrupted()
    }

    private func advance(
        to step: MandatoryDailyFlowStep,
        targetSleepSessionID: UUID? = nil
    ) {
        flowStore.advance(
            context,
            to: step,
            targetSleepSessionID: targetSleepSessionID
        )
        withAnimation(.snappy) {
            currentStep = step
        }
    }

    private func completeFlow() {
        guard !isCompleting else { return }
        isCompleting = true
        flowStore.complete(context)
        onCompleted(nil)
    }

    private func completeNightFlow(_ sessionID: UUID) {
        guard !isCompleting,
              context.period == .night,
              let session = sleepStore.session(id: sessionID) else {
            return
        }

        isCompleting = true
        learningStore.stopSleepPlayback()
        flowStore.complete(context)

        let morningDay = DailyFlowPeriod.morningFlowDay(
            containing: session.endDate,
            calendar: calendar,
            schedule: context.schedule
        )
        let morningContext = MandatoryDailyFlowContext(
            profileID: context.profileID,
            period: .morning,
            targetDay: morningDay,
            calendar: calendar,
            schedule: context.schedule
        )
        flowStore.beginMorningHandoff(
            morningContext,
            targetSleepSessionID: session.id
        )
        onCompleted(morningContext)
    }
}

private struct MandatoryFlowProgressBanner: View {
    let period: DailyFlowPeriod
    let step: MandatoryDailyFlowStep
    let canInterrupt: Bool
    let onInterrupt: () -> Void

    private var totalSteps: Int {
        period == .morning ? 3 : 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    period == .morning ? "朝の流れ" : "夜の流れ",
                    systemImage: period == .morning ? "sunrise.fill" : "moon.stars.fill"
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                if canInterrupt {
                    Button("あとで", action: onInterrupt)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Text("\(step.number) / \(totalSteps)・\(step.title)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)

            ProgressView(
                value: Double(max(0, step.number - 1)),
                total: Double(totalSteps)
            )
            .tint(period == .morning ? .orange : .indigo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(period == .morning ? "朝" : "夜")の流れ、\(totalSteps)ステップ中\(step.number)ステップ目、\(step.title)"
        )
    }
}

private struct MandatoryMorningMoodView: View {
    @State private var selectedMood: SleepMood?
    @State private var note: String
    @FocusState private var noteIsFocused: Bool

    let onSaved: (SleepMood, String) -> Void

    private let noteLimit = 240

    init(
        initialMood: SleepMood?,
        initialNote: String,
        onSaved: @escaping (SleepMood, String) -> Void
    ) {
        _selectedMood = State(initialValue: initialMood)
        _note = State(initialValue: initialNote)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        "睡眠記録はあとで追加できます",
                        systemImage: "clock.badge.questionmark"
                    )
                    .font(.subheadline.weight(.semibold))

                    Text("今の気分を先に保存し、追加された睡眠記録へ自動で結び付けます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("今朝の気分") {
                    MorningMoodPicker(selection: $selectedMood)
                }

                Section {
                    TextField(
                        "夢、体の軽さ、目覚めたときのことなど",
                        text: $note,
                        axis: .vertical
                    )
                    .focused($noteIsFocused)
                    .lineLimit(2...4)
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
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("今日の気分")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack {
                    Button(action: saveMood) {
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        noteIsFocused = false
                    }
                }
            }
        }
        .onChange(of: note) { _, newValue in
            if newValue.count > noteLimit {
                note = String(newValue.prefix(noteLimit))
            }
        }
    }

    private func saveMood() {
        guard let selectedMood else { return }
        onSaved(
            selectedMood,
            note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct MandatoryMorningRecordView: View {
    let session: SleepSession?
    let pendingMood: SleepMood?
    let pendingNote: String
    let onCompleted: () -> Void

    var body: some View {
        HistoryView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    reflectionSummary

                    Button(action: onCompleted) {
                        Label("朝の流れを完了", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
    }

    @ViewBuilder
    private var reflectionSummary: some View {
        if let mood = session?.mood ?? pendingMood {
            HStack(alignment: .top, spacing: 10) {
                Text(mood.emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("今朝の気分：\(mood.label)")
                        .font(.subheadline.weight(.semibold))
                    if session == nil {
                        Text("睡眠記録がないため、今日の流れに保存しています。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !pendingNote.isEmpty {
                        Text(pendingNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
