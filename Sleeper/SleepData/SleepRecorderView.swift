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

    var symbol: String {
        switch self {
        case .timer: "timer"
        case .manual: "square.and.pencil"
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
        ZStack {
            NightSkyBackground()

            ScrollView {
                LazyVStack(spacing: 18) {
                    FlowHeader(
                        eyebrow: "Night · Sleep",
                        title: "睡眠記録",
                        subtitle: "一日を閉じて、明日の朝へつなげます。",
                        symbol: "moon.stars.fill"
                    )

                    statusMessages
                    modeSelector

                    if entryMode.rawValue == SleepEntryMode.timer.rawValue {
                        timerContent
                    } else {
                        manualContent
                    }

                    targetControl
                    primaryAction
                    healthKitAction
                }
            }
            .sleepScreenScroll()
        }
        .foregroundStyle(SleepPalette.text)
        .preferredColorScheme(.dark)
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
                .presentationBackground(SleepPalette.night)
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let errorMessage = sleepStore.errorMessage, !errorMessage.isEmpty {
            SleepStatusBanner(message: errorMessage, kind: .error)
        } else if let statusMessage = sleepStore.statusMessage, !statusMessage.isEmpty {
            SleepStatusBanner(message: statusMessage, kind: .success)
        }
    }

    private var modeSelector: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(SleepEntryMode.allCases, id: \.rawValue) { mode in
                    modeButton(mode)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("記録方法")
    }

    @ViewBuilder
    private func modeButton(_ mode: SleepEntryMode) -> some View {
        let selected = entryMode.rawValue == mode.rawValue

        if selected {
            Button {
                withAnimation(.snappy) {
                    entryMode = mode
                }
            } label: {
                Label(mode.title, systemImage: mode.symbol)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .tint(SleepPalette.warmGold)
            .foregroundStyle(SleepPalette.night)
            .accessibilityAddTraits(.isSelected)
        } else {
            Button {
                withAnimation(.snappy) {
                    entryMode = mode
                }
            } label: {
                Label(mode.title, systemImage: mode.symbol)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .tint(Color.white.opacity(0.08))
            .foregroundStyle(SleepPalette.text)
        }
    }

    private var timerContent: some View {
        let elapsed = elapsedTime(at: timerNow)

        return GlassCard(tint: SleepPalette.chartBlue.opacity(0.10), padding: 20) {
            VStack(spacing: 18) {
                HStack {
                    Label(
                        sleepStore.activeTimerStartedAt == nil ? "就寝前" : "計測中",
                        systemImage: sleepStore.activeTimerStartedAt == nil
                            ? "moon.zzz.fill"
                            : "waveform.path.ecg"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        sleepStore.activeTimerStartedAt == nil
                            ? SleepPalette.secondaryText
                            : SleepPalette.mint
                    )

                    Spacer()

                    if let startedAt = sleepStore.activeTimerStartedAt {
                        Text(startedAt, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SleepPalette.secondaryText)
                            .accessibilityLabel("開始時刻")
                    }
                }

                SleepTimerDial(elapsed: elapsed)
                    .frame(maxWidth: 276)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text(SleepDurationFormatter.clock(elapsed))
                        .font(.system(size: 35, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(sleepStore.activeTimerStartedAt == nil ? "準備ができたら始めましょう" : "ゆっくり、おやすみなさい")
                        .font(.footnote)
                        .foregroundStyle(SleepPalette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("経過時間 \(SleepDurationFormatter.clock(elapsed))")
            }
        }
    }

    private var manualContent: some View {
        let dates = resolvedManualDates
        let duration = manualDurationMinutes

        return SurfaceCard(tint: SleepPalette.sunrise.opacity(0.09)) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("日時を入力", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    Spacer()
                    Text(SleepDurationFormatter.summary(minutes: duration))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SleepPalette.warmGold)
                        .contentTransition(.numericText())
                }

                DatePicker(
                    "就寝日",
                    selection: $manualDay,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(SleepPalette.warmGold)

                Divider()
                    .overlay(Color.white.opacity(0.12))

                HStack(alignment: .center, spacing: 10) {
                    manualTimePicker(
                        title: "寝た時間",
                        symbol: "moon.fill",
                        selection: $manualStartTime
                    )

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SleepPalette.warmGold)
                        .accessibilityHidden(true)

                    manualTimePicker(
                        title: "起きた時間",
                        symbol: "sun.horizon.fill",
                        selection: $manualEndTime
                    )
                }

                Label {
                    Text("\(dates.start.formatted(date: .abbreviated, time: .shortened)) 〜 \(dates.end.formatted(date: .abbreviated, time: .shortened))")
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SleepPalette.sunrise)
                }
                .font(.caption)
                .foregroundStyle(SleepPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                Text("起きた時間が寝た時間以前の場合は、翌朝として安全に記録します。")
                    .font(.caption2)
                    .foregroundStyle(SleepPalette.secondaryText)
            }
        }
    }

    private func manualTimePicker(
        title: String,
        symbol: String,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(SleepPalette.secondaryText)

            DatePicker(
                title,
                selection: selection,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(SleepPalette.warmGold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targetControl: some View {
        SurfaceCard(tint: SleepPalette.warmGold.opacity(0.08), padding: 16) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("目標睡眠時間", systemImage: "scope")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SleepPalette.secondaryText)
                    Text(SleepDurationFormatter.summary(minutes: targetMinutes))
                        .font(.title3.bold())
                        .foregroundStyle(SleepPalette.text)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 8)

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        targetAdjustmentButton(
                            symbol: "minus",
                            accessibilityLabel: "目標を15分短くする",
                            disabled: targetMinutes <= minimumTarget
                        ) {
                            adjustTarget(by: -targetStep)
                        }

                        targetAdjustmentButton(
                            symbol: "plus",
                            accessibilityLabel: "目標を15分長くする",
                            disabled: targetMinutes >= maximumTarget
                        ) {
                            adjustTarget(by: targetStep)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(SleepDurationFormatter.summary(minutes: targetMinutes))
    }

    private func targetAdjustmentButton(
        symbol: String,
        accessibilityLabel: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(Color.white.opacity(0.08))
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if entryMode.rawValue == SleepEntryMode.timer.rawValue {
            Button(action: toggleTimer) {
                Label(
                    sleepStore.activeTimerStartedAt == nil
                        ? "睡眠をはじめる"
                        : "起きた・記録する",
                    systemImage: sleepStore.activeTimerStartedAt == nil
                        ? "moon.fill"
                        : "sunrise.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .tint(
                sleepStore.activeTimerStartedAt == nil
                    ? SleepPalette.warmGold
                    : SleepPalette.sunrise
            )
            .foregroundStyle(SleepPalette.night)
            .accessibilityHint(
                sleepStore.activeTimerStartedAt == nil
                    ? "睡眠時間の計測を開始します"
                    : "計測を終了して睡眠記録を保存します"
            )
        } else {
            Button(action: saveManualEntry) {
                Label("この時間で記録する", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .tint(SleepPalette.warmGold)
            .foregroundStyle(SleepPalette.night)
        }
    }

    private var healthKitAction: some View {
        Button(action: importFromHealthKit) {
            HStack(spacing: 10) {
                if sleepStore.isSyncing {
                    ProgressView()
                        .tint(SleepPalette.text)
                } else {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(SleepPalette.mint)
                }
                Text(sleepStore.isSyncing ? "ヘルスケアを確認中…" : "昨夜をヘルスケアから読み込む")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .tint(SleepPalette.mint.opacity(0.12))
        .disabled(sleepStore.isSyncing || sleepStore.activeTimerStartedAt != nil)
        .accessibilityHint("Appleヘルスケアに保存された昨夜の睡眠を取り込みます")
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

    private func adjustTarget(by minutes: Int) {
        withAnimation(.snappy) {
            targetMinutes = normalizedTarget(targetMinutes + minutes)
        }
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

                hand(
                    width: 5,
                    length: radius * 0.44,
                    color: SleepPalette.text,
                    angle: hourAngle
                )
                hand(
                    width: 3.5,
                    length: radius * 0.62,
                    color: SleepPalette.warmGold,
                    angle: minuteAngle
                )
                hand(
                    width: 1.5,
                    length: radius * 0.68,
                    color: SleepPalette.sunrise,
                    angle: secondAngle
                )

            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(SleepPalette.text)
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
            .shadow(color: color.opacity(0.22), radius: 4)
    }
}

/// The face does not depend on elapsed time. EquatableView lets SwiftUI keep
/// its 60 tick marks intact while only the three clock hands update.
private struct SleepTimerFace: View, Equatable {
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            SleepPalette.panel.opacity(0.86),
                            SleepPalette.night.opacity(0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    SleepPalette.warmGold.opacity(0.40),
                                    Color.white.opacity(0.08),
                                    SleepPalette.chartBlue.opacity(0.34)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                        .allowsHitTesting(false)
                }

            ForEach(0..<60, id: \.self) { tick in
                Capsule(style: .continuous)
                    .fill(
                        tick.isMultiple(of: 5)
                            ? SleepPalette.text.opacity(0.76)
                            : SleepPalette.secondaryText.opacity(0.30)
                    )
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
                .fill(SleepPalette.warmGold)
                .frame(width: 13, height: 13)
                .overlay {
                    Circle()
                        .fill(SleepPalette.night)
                        .frame(width: 5, height: 5)
                }
        }
        .allowsHitTesting(false)
    }
}
