import SwiftUI

private enum SleepEntryMode: String, CaseIterable {
    case timer
    case manual

    var title: String {
        switch self {
        case .timer: "タイマー"
        case .manual: "手入力"
        }
    }
}

struct SleepRecorderView: View {
    private struct ReflectionTarget: Identifiable {
        let id: UUID
    }

    private struct TimerRefreshKey: Equatable {
        let startedAt: Date?
        let shouldRefresh: Bool
    }

    @EnvironmentObject private var sleepStore: SleepStore
    @EnvironmentObject private var learningStore: SleepLearningStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sleepTargetMinutes") private var targetMinutes = 480

    @State private var entryMode: SleepEntryMode = .timer
    @State private var manualDay = Calendar.current.date(
        byAdding: .day,
        value: -1,
        to: Date()
    ) ?? Date()
    @State private var manualStartTime = Calendar.current.date(
        bySettingHour: 23,
        minute: 0,
        second: 0,
        of: Date()
    ) ?? Date()
    @State private var manualEndTime = Calendar.current.date(
        bySettingHour: 7,
        minute: 0,
        second: 0,
        of: Date()
    ) ?? Date()
    @State private var reflectionTarget: ReflectionTarget?
    @State private var timerNow = Date()
    @State private var isScreenVisible = false

    private let minimumTarget = 6 * 60
    private let maximumTarget = 10 * 60
    private let targetStep = 15

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Text("睡眠時間を記録して、朝の調子と一緒に振り返ります。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    statusMessages

                    Picker("記録方法", selection: $entryMode) {
                        ForEach(SleepEntryMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if entryMode == .timer {
                        timerContent
                    } else {
                        manualContent
                    }

                    Divider()

                    targetControl

                    Button(action: importFromHealthKit) {
                        HStack {
                            Spacer()
                            if sleepStore.isSyncing {
                                ProgressView()
                            } else {
                                Image(systemName: "heart.text.square")
                            }
                            Text(sleepStore.isSyncing ? "ヘルスケアを確認中…" : "ヘルスケアから読み込む")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(sleepStore.isSyncing || sleepStore.activeTimerStartedAt != nil)
                    .accessibilityHint("Appleヘルスケアに保存された昨夜の睡眠を取り込みます")
                }
                .padding(.vertical, 16)
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("睡眠")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            isScreenVisible = true
            timerNow = Date()
            targetMinutes = normalizedTarget(targetMinutes)
        }
        .onDisappear {
            isScreenVisible = false
        }
        .onChange(of: targetMinutes) { _, newValue in
            let normalized = normalizedTarget(newValue)
            if normalized != newValue {
                targetMinutes = normalized
            }
        }
        .task(id: timerRefreshKey) {
            await refreshRunningTimer(for: timerRefreshKey)
        }
        .sheet(item: $reflectionTarget) { target in
            MorningReflectionView(sessionID: target.id)
                .environmentObject(sleepStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let errorMessage = sleepStore.errorMessage, !errorMessage.isEmpty {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        } else if let statusMessage = sleepStore.statusMessage, !statusMessage.isEmpty {
            Label(statusMessage, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        }
    }

    private var timerContent: some View {
        let elapsed = elapsedTime(at: timerNow)

        return VStack(spacing: 18) {
            HStack {
                Label(
                    sleepStore.activeTimerStartedAt == nil ? "待機中" : "計測中",
                    systemImage: sleepStore.activeTimerStartedAt == nil ? "moon.zzz" : "record.circle"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    sleepStore.activeTimerStartedAt == nil ? Color.secondary : Color.green
                )

                Spacer()

                if let startedAt = sleepStore.activeTimerStartedAt {
                    Text("開始 \(startedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            SleepTimerDial(elapsed: elapsed)
                .frame(maxWidth: 300)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text(SleepDurationFormatter.clock(elapsed))
                    .font(.system(.largeTitle, design: .rounded, weight: .regular))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(sleepStore.activeTimerStartedAt == nil ? "準備ができたら開始してください" : "計測を続けています")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("経過時間 \(SleepDurationFormatter.clock(elapsed))")

            Button(action: toggleTimer) {
                Label(
                    sleepStore.activeTimerStartedAt == nil ? "睡眠を開始" : "起床して記録",
                    systemImage: sleepStore.activeTimerStartedAt == nil ? "moon.fill" : "sunrise.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(sleepStore.activeTimerStartedAt == nil ? .indigo : .orange)
            .accessibilityHint(
                sleepStore.activeTimerStartedAt == nil
                    ? "睡眠時間の計測を開始します"
                    : "計測を終了して睡眠記録を保存します"
            )
        }
    }

    private var manualContent: some View {
        let dates = resolvedManualDates
        let duration = manualDurationMinutes

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("睡眠時間")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(SleepDurationFormatter.summary(minutes: duration))
                    .font(.largeTitle.weight(.semibold))
                    .contentTransition(.numericText())
            }

            Divider()

            DatePicker("就寝日", selection: $manualDay, displayedComponents: .date)
            DatePicker("就寝時刻", selection: $manualStartTime, displayedComponents: .hourAndMinute)
            DatePicker("起床時刻", selection: $manualEndTime, displayedComponents: .hourAndMinute)

            Text("\(dates.start.formatted(date: .abbreviated, time: .shortened)) 〜 \(dates.end.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("起床時刻が就寝時刻以前の場合は、翌朝として記録します。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: saveManualEntry) {
                Label("この時間で記録", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
        }
    }

    private var targetControl: some View {
        Stepper(
            value: $targetMinutes,
            in: minimumTarget...maximumTarget,
            step: targetStep
        ) {
            LabeledContent {
                Text(SleepDurationFormatter.summary(minutes: targetMinutes))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } label: {
                Label("睡眠目標", systemImage: "target")
            }
        }
        .accessibilityValue(SleepDurationFormatter.summary(minutes: targetMinutes))
        .accessibilityHint("15分単位で調整できます")
    }

    private var resolvedManualDates: (start: Date, end: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: manualDay)
        let startComponents = calendar.dateComponents([.hour, .minute], from: manualStartTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: manualEndTime)

        let start = calendar.date(
            bySettingHour: startComponents.hour ?? 0,
            minute: startComponents.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
        let sameDayEnd = calendar.date(
            bySettingHour: endComponents.hour ?? 0,
            minute: endComponents.minute ?? 0,
            second: 0,
            of: day
        ) ?? day

        if sameDayEnd > start {
            return (start, sameDayEnd)
        }

        let nextDayEnd = calendar.date(byAdding: .day, value: 1, to: sameDayEnd) ?? sameDayEnd
        return (start, nextDayEnd)
    }

    private var manualDurationMinutes: Int {
        let dates = resolvedManualDates
        return max(1, Int(dates.end.timeIntervalSince(dates.start) / 60))
    }

    private func elapsedTime(at date: Date) -> TimeInterval {
        guard let startedAt = sleepStore.activeTimerStartedAt else { return 0 }
        return max(0, date.timeIntervalSince(startedAt))
    }

    private var timerRefreshKey: TimerRefreshKey {
        let startedAt = sleepStore.activeTimerStartedAt
        return TimerRefreshKey(
            startedAt: startedAt,
            shouldRefresh: startedAt != nil
                && isScreenVisible
                && entryMode == .timer
                && scenePhase == .active
        )
    }

    private func refreshRunningTimer(for key: TimerRefreshKey) async {
        timerNow = Date()
        guard key.shouldRefresh else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            timerNow = Date()
        }
    }

    private func normalizedTarget(_ minutes: Int) -> Int {
        let clamped = min(max(minutes, minimumTarget), maximumTarget)
        let steps = Int((Double(clamped - minimumTarget) / Double(targetStep)).rounded())
        return minimumTarget + (steps * targetStep)
    }

    private func toggleTimer() {
        if sleepStore.activeTimerStartedAt == nil {
            sleepStore.startTimer()
            if sleepStore.activeTimerStartedAt != nil,
               learningStore.settings.autoStartWithSleepTimer {
                learningStore.startSleepPlayback()
            }
        } else {
            let session = sleepStore.stopTimer(targetMinutes: targetMinutes)
            if learningStore.settings.autoStartWithSleepTimer {
                learningStore.stopSleepPlayback()
            }
            if let session {
                reflectionTarget = ReflectionTarget(id: session.id)
            }
        }
    }

    private func saveManualEntry() {
        let dates = resolvedManualDates
        if let session = sleepStore.saveManual(
            startDate: dates.start,
            endDate: dates.end,
            targetMinutes: targetMinutes
        ) {
            reflectionTarget = ReflectionTarget(id: session.id)
        }
    }

    private func importFromHealthKit() {
        Task {
            if let session = await sleepStore.importLastNightFromHealthKit(
                targetMinutes: targetMinutes
            ) {
                reflectionTarget = ReflectionTarget(id: session.id)
            }
        }
    }
}

private struct SleepTimerDial: View {
    let elapsed: TimeInterval

    private var hourAngle: Angle {
        .degrees(elapsed.truncatingRemainder(dividingBy: 43_200) / 43_200 * 360)
    }

    private var minuteAngle: Angle {
        .degrees(elapsed.truncatingRemainder(dividingBy: 3_600) / 3_600 * 360)
    }

    private var secondAngle: Angle {
        .degrees(elapsed.truncatingRemainder(dividingBy: 60) / 60 * 360)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2

            ZStack {
                SleepTimerFace(radius: radius)
                    .equatable()

                hand(width: 5, length: radius * 0.43, color: .primary, angle: hourAngle)
                hand(width: 3.5, length: radius * 0.62, color: .orange, angle: minuteAngle)
                hand(width: 1.5, length: radius * 0.70, color: .red, angle: secondAngle)
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    private func hand(
        width: CGFloat,
        length: CGFloat,
        color: Color,
        angle: Angle
    ) -> some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -(length / 2))
            .rotationEffect(angle)
    }
}

/// The face does not depend on elapsed time, so only the hands redraw each second.
private struct SleepTimerFace: View, Equatable {
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                }

            ForEach(0..<60, id: \.self) { tick in
                Capsule(style: .continuous)
                    .fill(tick.isMultiple(of: 5) ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.30))
                    .frame(
                        width: tick.isMultiple(of: 5) ? 2.4 : 1,
                        height: tick.isMultiple(of: 5) ? 10 : 4
                    )
                    .offset(y: -(radius - 18))
                    .rotationEffect(.degrees(Double(tick) * 6))
            }

            VStack {
                Text("12")
                Spacer()
                Text("6")
            }
            .padding(.vertical, 31)

            HStack {
                Text("9")
                Spacer()
                Text("3")
            }
            .padding(.horizontal, 34)

            Circle()
                .fill(.red)
                .frame(width: 13, height: 13)
                .overlay {
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                        .frame(width: 5, height: 5)
                }
        }
        .allowsHitTesting(false)
    }
}
