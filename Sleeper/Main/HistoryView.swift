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

        NavigationStack {
            List {
                statusMessages

                Section("直近7日間の概要") {
                    summaryRows(snapshot)
                }

                Section {
                    sevenDayChart(snapshot)
                } header: {
                    Text("睡眠時間")
                } footer: {
                    Text("棒は起きた日ごとの睡眠時間、線は直近7日間の平均目標です。")
                }

                Section {
                    if snapshot.sortedSessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(snapshot.sortedSessions, id: \.id) { session in
                            recordRow(session)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        reflectionTarget = ReflectionTarget(id: session.id)
                                    } label: {
                                        Label(
                                            session.mood == nil ? "振り返る" : "編集",
                                            systemImage: session.mood == nil ? "face.smiling" : "pencil"
                                        )
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingDeletionID = session.id
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        reflectionTarget = ReflectionTarget(id: session.id)
                                    } label: {
                                        Label(
                                            session.mood == nil ? "朝の気分を追加" : "振り返りを編集",
                                            systemImage: session.mood == nil ? "face.smiling" : "pencil"
                                        )
                                    }

                                    Button(role: .destructive) {
                                        pendingDeletionID = session.id
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text("すべての記録")
                        Spacer()
                        Text("\(snapshot.sortedSessions.count)件")
                            .monospacedDigit()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("睡眠の振り返り")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $reflectionTarget) { target in
            MorningReflectionView(sessionID: target.id)
                .environmentObject(sleepStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } else if let statusMessage = sleepStore.statusMessage, !statusMessage.isEmpty {
            Section {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func summaryRows(_ snapshot: HistorySnapshot) -> some View {
        LabeledContent {
            Text(SleepDurationFormatter.compact(minutes: snapshot.averageMinutes))
                .monospacedDigit()
        } label: {
            Label("7日平均", systemImage: "moon.fill")
        }

        LabeledContent {
            Text("\(snapshot.recordedDayCount) / 7")
                .monospacedDigit()
        } label: {
            Label("記録した日", systemImage: "calendar.badge.checkmark")
        }

        LabeledContent {
            Text(SleepDurationFormatter.compact(minutes: snapshot.averageTargetMinutes))
                .monospacedDigit()
        } label: {
            Label("平均目標", systemImage: "scope")
        }

        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("目標への到達度") {
                Text("\(snapshot.achievementPercentage)%")
                    .monospacedDigit()
            }
            ProgressView(value: snapshot.achievementProgress)
                .accessibilityLabel("目標への到達度")
                .accessibilityValue("\(snapshot.achievementPercentage)パーセント")
        }
    }

    private func sevenDayChart(_ snapshot: HistorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(snapshot.sevenDayPoints) { point in
                    BarMark(
                        x: .value("日", point.day, unit: .day),
                        y: .value("睡眠時間", Double(point.minutes) / 60)
                    )
                    .foregroundStyle(
                        point.minutes > 0
                            ? Color.accentColor
                            : Color.secondary.opacity(0.12)
                    )
                    .cornerRadius(4)
                }

                RuleMark(
                    y: .value("目標", Double(snapshot.averageTargetMinutes) / 60)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            }
            .chartYScale(domain: 0...snapshot.chartCeiling)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick().foregroundStyle(.tertiary)
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(hours, specifier: "%.0f")h")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("まだ睡眠記録がありません", systemImage: "moon.zzz")
        } description: {
            Text("夜にタイマーを開始するか、昨夜の時間を手入力すると、ここから振り返れます。")
        }
        .accessibilityElement(children: .combine)
    }

    private func recordRow(_ session: SleepSession) -> some View {
        Button {
            reflectionTarget = ReflectionTarget(id: session.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.wakeDay, format: .dateTime.month().day().weekday(.wide))
                            .font(.headline)
                        Text("\(session.startDate.formatted(date: .omitted, time: .shortened)) 〜 \(session.endDate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(SleepDurationFormatter.summary(minutes: session.durationMinutes))
                        .font(.headline)
                        .monospacedDigit()
                }

                Label(
                    recordTargetMessage(session),
                    systemImage: session.shortageMinutes > 0 ? "scope" : "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(session.shortageMinutes > 0 ? .orange : .green)

                if let mood = session.mood {
                    LabeledContent {
                        Text("\(mood.emoji) \(mood.label)")
                    } label: {
                        Label("今朝の気分", systemImage: "face.smiling")
                    }
                    .font(.subheadline)
                }

                if !session.note.isEmpty {
                    Label {
                        Text(session.note)
                            .lineLimit(3)
                    } icon: {
                        Image(systemName: "quote.opening")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(session.mood == nil ? "朝の気分を追加します" : "振り返りを編集します")
    }

    private func recordTargetMessage(_ session: SleepSession) -> String {
        if session.shortageMinutes > 0 {
            return "目標 \(SleepDurationFormatter.summary(minutes: session.targetMinutes))まで、あと\(SleepDurationFormatter.summary(minutes: session.shortageMinutes))"
        }
        return "目標 \(SleepDurationFormatter.summary(minutes: session.targetMinutes))を達成"
    }

}
