import Charts
import SwiftUI

private struct SleepDayPoint: Identifiable {
    let day: Date
    let minutes: Int
    let targetMinutes: Int

    var id: Date { day }
}

private struct SleepDayAccumulator {
    var minutes: Int
    var latestEndDate: Date
    var targetMinutes: Int
}

private struct HistorySnapshot {
    let sortedSessions: [SleepSession]
    let sevenDayPoints: [SleepDayPoint]
    let recordedDayCount: Int
    let averageMinutes: Int
    let averageTargetMinutes: Int
    let achievementProgress: Double
    let achievementPercentage: Int
    let chartCeiling: Double
    let chartAccessibilityLabel: String

    init(
        sessions: [SleepSession],
        defaultTargetMinutes: Int,
        calendar: Calendar
    ) {
        let normalizedTarget = min(max(defaultTargetMinutes, 360), 600)
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 6, to: today)
        }
        let visibleDays = Set(days)
        var dailyTotals: [Date: SleepDayAccumulator] = [:]

        for session in sessions {
            let day = calendar.startOfDay(for: session.endDate)
            guard visibleDays.contains(day) else { continue }

            if var total = dailyTotals[day] {
                total.minutes += session.durationMinutes
                if session.endDate > total.latestEndDate {
                    total.latestEndDate = session.endDate
                    total.targetMinutes = session.targetMinutes
                }
                dailyTotals[day] = total
            } else {
                dailyTotals[day] = SleepDayAccumulator(
                    minutes: session.durationMinutes,
                    latestEndDate: session.endDate,
                    targetMinutes: session.targetMinutes
                )
            }
        }

        let points = days.map { day in
            let total = dailyTotals[day]
            return SleepDayPoint(
                day: day,
                minutes: total?.minutes ?? 0,
                targetMinutes: total?.targetMinutes ?? normalizedTarget
            )
        }

        let recordedPoints = points.filter { $0.minutes > 0 }
        let recordedCount = recordedPoints.count
        let average: Int
        let targetAverage: Int

        if recordedPoints.isEmpty {
            average = 0
            targetAverage = normalizedTarget
        } else {
            average = recordedPoints.reduce(0) { $0 + $1.minutes }
                / recordedPoints.count
            targetAverage = recordedPoints.reduce(0) { $0 + $1.targetMinutes }
                / recordedPoints.count
        }

        let progress: Double
        if targetAverage > 0 {
            progress = min(
                max(Double(average) / Double(targetAverage), 0),
                1
            )
        } else {
            progress = 0
        }

        let longestHours = Double(points.map(\.minutes).max() ?? 0) / 60
        let accessibilityLabel: String

        if recordedCount == 0 {
            accessibilityLabel = "直近7日間の睡眠記録はまだありません"
        } else {
            accessibilityLabel = "直近7日間のうち\(recordedCount)日を記録。平均睡眠時間は\(SleepDurationFormatter.summary(minutes: average))です"
        }

        sortedSessions = sessions.sorted { $0.endDate > $1.endDate }
        sevenDayPoints = points
        recordedDayCount = recordedCount
        averageMinutes = average
        averageTargetMinutes = targetAverage
        achievementProgress = progress
        achievementPercentage = Int((progress * 100).rounded())
        chartCeiling = max(10, ceil(longestHours) + 1)
        chartAccessibilityLabel = accessibilityLabel
    }
}

struct HistoryView: View {
    private struct ReflectionTarget: Identifiable {
        let id: UUID
    }

    @EnvironmentObject private var sleepStore: SleepStore
    @AppStorage("sleepTargetMinutes") private var defaultTargetMinutes = 480

    @State private var reflectionTarget: ReflectionTarget?
    @State private var pendingDeletionID: UUID?

    private let calendar = Calendar.current

    var body: some View {
        let snapshot = HistorySnapshot(
            sessions: sleepStore.sessions,
            defaultTargetMinutes: defaultTargetMinutes,
            calendar: calendar
        )

        ZStack {
            NightSkyBackground()

            ScrollView {
                LazyVStack(spacing: 18) {
                    FlowHeader(
                        eyebrow: "Morning · History",
                        title: "睡眠の振り返り",
                        subtitle: "長さだけでなく、朝の感覚も一緒に眺めます。",
                        symbol: "chart.bar.xaxis"
                    )

                    statusMessages
                    summaryCard(snapshot)
                    sevenDayChart(snapshot)
                    recordsHeader(count: snapshot.sortedSessions.count)

                    if snapshot.sortedSessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(snapshot.sortedSessions, id: \.id) { session in
                            recordCard(session)
                        }
                    }
                }
            }
            .sleepScreenScroll()
        }
        .foregroundStyle(SleepPalette.text)
        .preferredColorScheme(.dark)
        .sheet(item: $reflectionTarget) { target in
            MorningReflectionView(sessionID: target.id)
                .environmentObject(sleepStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(SleepPalette.night)
        }
        .confirmationDialog(
            "睡眠記録を削除",
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
            if let sessionID = pendingDeletionID {
                Button("削除", role: .destructive) {
                    sleepStore.delete(id: sessionID)
                    pendingDeletionID = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                pendingDeletionID = nil
            }
        } message: {
            Text("この操作は取り消せません。")
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

    private func summaryCard(_ snapshot: HistorySnapshot) -> some View {
        GlassCard(tint: SleepPalette.warmGold.opacity(0.09), padding: 16) {
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    summaryMetric(
                        title: "7日平均",
                        value: SleepDurationFormatter.compact(minutes: snapshot.averageMinutes),
                        symbol: "moon.fill",
                        color: SleepPalette.warmGold
                    )

                    summaryDivider

                    summaryMetric(
                        title: "記録した日",
                        value: "\(snapshot.recordedDayCount) / 7",
                        symbol: "calendar.badge.checkmark",
                        color: SleepPalette.chartBlue
                    )

                    summaryDivider

                    summaryMetric(
                        title: "目標",
                        value: SleepDurationFormatter.compact(minutes: snapshot.averageTargetMinutes),
                        symbol: "scope",
                        color: SleepPalette.mint
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("目標への到達度")
                            .font(.caption)
                            .foregroundStyle(SleepPalette.secondaryText)
                        Spacer()
                        Text("\(snapshot.achievementPercentage)%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(SleepPalette.warmGold)
                    }

                    ProgressView(value: snapshot.achievementProgress)
                        .tint(SleepPalette.warmGold)
                        .accessibilityLabel("目標への到達度")
                        .accessibilityValue("\(snapshot.achievementPercentage)パーセント")
                }
            }
        }
    }

    private func summaryMetric(
        title: String,
        value: String,
        symbol: String,
        color: Color
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(SleepPalette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 46)
            .accessibilityHidden(true)
    }

    private func sevenDayChart(_ snapshot: HistorySnapshot) -> some View {
        SurfaceCard(tint: SleepPalette.chartBlue.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("直近7日間")
                            .font(.headline)
                        Text("棒は起きた日ごとの睡眠時間")
                            .font(.caption)
                            .foregroundStyle(SleepPalette.secondaryText)
                    }

                    Spacer()

                    Label("目標", systemImage: "line.diagonal")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SleepPalette.warmGold)
                }

                Chart {
                    ForEach(snapshot.sevenDayPoints) { point in
                        BarMark(
                            x: .value("日", point.day, unit: .day),
                            y: .value("睡眠時間", Double(point.minutes) / 60)
                        )
                        .foregroundStyle(
                            point.minutes > 0
                                ? SleepPalette.chartBlue
                                : Color.white.opacity(0.07)
                        )
                        .cornerRadius(6)
                    }

                    RuleMark(
                        y: .value("目標", Double(snapshot.averageTargetMinutes) / 60)
                    )
                    .foregroundStyle(SleepPalette.warmGold.opacity(0.86))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
                .chartYScale(domain: 0...snapshot.chartCeiling)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisGridLine()
                            .foregroundStyle(Color.clear)
                        AxisTick()
                            .foregroundStyle(Color.white.opacity(0.14))
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .foregroundStyle(SleepPalette.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(hours, specifier: "%.0f")h")
                                    .font(.caption2)
                                    .foregroundStyle(SleepPalette.secondaryText)
                            }
                        }
                    }
                }
                .frame(height: 208)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.chartAccessibilityLabel)

                if snapshot.recordedDayCount == 0 {
                    Label("最初の睡眠を記録すると、ここにリズムが現れます。", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(SleepPalette.secondaryText)
                }
            }
        }
    }

    private func recordsHeader(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("すべての記録")
                .font(.title3.bold())
            Spacer()
            Text("\(count)件")
                .font(.caption.monospacedDigit())
                .foregroundStyle(SleepPalette.secondaryText)
        }
        .padding(.top, 2)
    }

    private var emptyState: some View {
        SurfaceCard(tint: SleepPalette.chartBlue.opacity(0.08)) {
            ContentUnavailableView {
                Label("まだ睡眠記録がありません", systemImage: "moon.zzz")
            } description: {
                Text("夜にタイマーを開始するか、昨夜の時間を手入力すると、ここから振り返れます。")
            }
            .foregroundStyle(SleepPalette.text)
        }
        .accessibilityElement(children: .combine)
    }

    private func recordCard(_ session: SleepSession) -> some View {
        SurfaceCard(tint: moodTint(session.mood).opacity(0.08), padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.wakeDay, format: .dateTime.month().day().weekday(.wide))
                            .font(.headline)
                        Text("\(session.startDate.formatted(date: .omitted, time: .shortened)) 〜 \(session.endDate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SleepPalette.secondaryText)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        pendingDeletionID = session.id
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .tint(SleepPalette.danger.opacity(0.13))
                    .accessibilityLabel("この睡眠記録を削除")
                }

                HStack(alignment: .lastTextBaseline) {
                    Text(SleepDurationFormatter.summary(minutes: session.durationMinutes))
                        .font(.title2.bold())
                        .foregroundStyle(SleepPalette.text)
                        .contentTransition(.numericText())

                    Spacer()

                    if let mood = session.mood {
                        HStack(spacing: 5) {
                            Text(mood.emoji)
                            Text(mood.label)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(
                            .regular.tint(moodTint(mood).opacity(0.18)),
                            in: Capsule(style: .continuous)
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("今朝の気分、\(mood.label)")
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: session.shortageMinutes > 0 ? "scope" : "checkmark.seal.fill")
                        .foregroundStyle(session.shortageMinutes > 0 ? SleepPalette.sunrise : SleepPalette.mint)
                    Text(recordTargetMessage(session))
                        .font(.caption)
                        .foregroundStyle(SleepPalette.secondaryText)
                }

                if !session.note.isEmpty {
                    Divider()
                        .overlay(Color.white.opacity(0.10))
                    Label {
                        Text(session.note)
                            .lineLimit(3)
                    } icon: {
                        Image(systemName: "quote.opening")
                            .foregroundStyle(SleepPalette.warmGold)
                    }
                    .font(.footnote)
                    .foregroundStyle(SleepPalette.secondaryText)
                }

                Button {
                    reflectionTarget = ReflectionTarget(id: session.id)
                } label: {
                    Label(
                        session.mood == nil ? "朝の気分を追加" : "振り返りを編集",
                        systemImage: session.mood == nil ? "face.smiling" : "pencil"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 15))
                .tint(moodTint(session.mood).opacity(0.12))
            }
        }
    }

    private func recordTargetMessage(_ session: SleepSession) -> String {
        if session.shortageMinutes > 0 {
            return "目標 \(SleepDurationFormatter.summary(minutes: session.targetMinutes))まで、あと\(SleepDurationFormatter.summary(minutes: session.shortageMinutes))"
        }
        return "目標 \(SleepDurationFormatter.summary(minutes: session.targetMinutes))を達成"
    }

    private func moodTint(_ mood: SleepMood?) -> Color {
        guard let mood else { return SleepPalette.chartBlue }
        return switch mood {
        case .bad: SleepPalette.danger
        case .flat: SleepPalette.secondaryText
        case .good: SleepPalette.mint
        case .great: SleepPalette.warmGold
        }
    }
}
