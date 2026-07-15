import Charts
import SwiftUI

private struct HistoryDayPoint: Identifiable {
    let day: Date
    let minutes: Int
    let targetMinutes: Int

    var id: Date { day }
}

private enum HealthMoodLoadState {
    case notRequested
    case loading
    case empty
    case loaded([HealthKitStateOfMindData])
    case failed(String)
}

private struct HealthMoodTaskID: Hashable {
    let day: Date
    let isEnabled: Bool
    let reloadToken: Int
}

struct HistoryView: View {
    private struct ReflectionTarget: Identifiable {
        let id: UUID
    }

    @EnvironmentObject private var sleepStore: SleepStore
    @AppStorage("sleepTargetMinutes") private var defaultTargetMinutes = 480

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var reflectionTarget: ReflectionTarget?
    @State private var pendingDeletionID: UUID?
    @State private var healthMoodLoadState: HealthMoodLoadState = .notRequested
    @State private var healthMoodEnabled = false
    @State private var healthMoodReloadToken = 0

    private let calendar = Calendar.current

    private var selectedDay: Date {
        calendar.startOfDay(for: selectedDate)
    }

    private var selectedSessions: [SleepSession] {
        sleepStore.sessions
            .filter { calendar.isDate($0.wakeDay, inSameDayAs: selectedDay) }
            .sorted { $0.endDate > $1.endDate }
    }

    private var selectedTotalMinutes: Int {
        selectedSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    private var selectedTargetMinutes: Int {
        selectedSessions.first?.targetMinutes ?? min(max(defaultTargetMinutes, 360), 600)
    }

    private var sevenDayPoints: [HistoryDayPoint] {
        let days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 6, to: selectedDay)
        }
        let visibleDays = Set(days)
        var totals: [Date: (minutes: Int, targetMinutes: Int, latestEnd: Date)] = [:]

        for session in sleepStore.sessions {
            let day = calendar.startOfDay(for: session.wakeDay)
            guard visibleDays.contains(day) else { continue }

            if let existing = totals[day] {
                totals[day] = (
                    existing.minutes + session.durationMinutes,
                    session.endDate > existing.latestEnd
                        ? session.targetMinutes
                        : existing.targetMinutes,
                    max(existing.latestEnd, session.endDate)
                )
            } else {
                totals[day] = (session.durationMinutes, session.targetMinutes, session.endDate)
            }
        }

        return days.map { day in
            HistoryDayPoint(
                day: day,
                minutes: totals[day]?.minutes ?? 0,
                targetMinutes: totals[day]?.targetMinutes ?? selectedTargetMinutes
            )
        }
    }

    private var chartCeiling: Double {
        let longestHours = Double(sevenDayPoints.map(\.minutes).max() ?? 0) / 60
        return max(10, ceil(longestHours) + 1)
    }

    var body: some View {
        NavigationStack {
            List {
                statusMessages

                calendarSection

                sleepSummarySection

                moodSection

                trendSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("睡眠の記録")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !calendar.isDateInToday(selectedDay) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("今日") {
                            selectedDate = calendar.startOfDay(for: Date())
                        }
                    }
                }
            }
            .refreshable {
                guard healthMoodEnabled else { return }
                healthMoodReloadToken += 1
            }
        }
        .task(
            id: HealthMoodTaskID(
                day: selectedDay,
                isEnabled: healthMoodEnabled,
                reloadToken: healthMoodReloadToken
            )
        ) {
            guard healthMoodEnabled else { return }
            await loadHealthMood(for: selectedDay)
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

    private var calendarSection: some View {
        Section {
            DatePicker(
                "日付",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .accessibilityLabel("記録を表示する日")

            LabeledContent {
                if selectedSessions.isEmpty {
                    Text("記録なし")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(selectedSessions.count)件")
                        .monospacedDigit()
                }
            } label: {
                Label(
                    selectedDay.formatted(.dateTime.month().day().weekday(.wide)),
                    systemImage: selectedSessions.isEmpty
                        ? "calendar"
                        : "calendar.badge.checkmark"
                )
            }
        } header: {
            Text("カレンダー")
        } footer: {
            Text("起きた日を選ぶと、その日の睡眠と気分を一緒に確認できます。")
        }
    }

    private var sleepSummarySection: some View {
        Section {
            if selectedSessions.isEmpty {
                ContentUnavailableView {
                    Label("睡眠記録がありません", systemImage: "bed.double")
                } description: {
                    Text("別の日を選ぶか、夜の流れから睡眠を記録してください。")
                }
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SleepDurationFormatter.compact(minutes: selectedTotalMinutes))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text("この日の合計睡眠時間")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)

                LabeledContent("目標") {
                    Text(SleepDurationFormatter.compact(minutes: selectedTargetMinutes))
                        .monospacedDigit()
                }

                LabeledContent {
                    Text(targetStatus)
                        .foregroundStyle(
                            selectedTotalMinutes >= selectedTargetMinutes ? .green : .orange
                        )
                } label: {
                    Label(
                        "達成状況",
                        systemImage: selectedTotalMinutes >= selectedTargetMinutes
                            ? "checkmark.seal.fill"
                            : "scope"
                    )
                }

                ForEach(selectedSessions) { session in
                    sleepRecordRow(session)
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
                }
            }
        } header: {
            Label("睡眠", systemImage: "bed.double.fill")
        }
    }

    @ViewBuilder
    private var moodSection: some View {
        Section {
            if let session = selectedSessions.first(where: { $0.mood != nil }),
               let mood = session.mood {
                Button {
                    reflectionTarget = ReflectionTarget(id: session.id)
                } label: {
                    LabeledContent {
                        Text("\(mood.emoji)  \(mood.label)")
                    } label: {
                        Label("ねるねで記録", systemImage: "face.smiling")
                    }
                }
                .buttonStyle(.plain)
            } else if let session = selectedSessions.first {
                Button {
                    reflectionTarget = ReflectionTarget(id: session.id)
                } label: {
                    Label("朝の気分を追加", systemImage: "plus.circle")
                }
            }

            healthMoodContent
        } header: {
            Label("心の状態", systemImage: "brain.head.profile")
        } footer: {
            if healthMoodEnabled {
                Text("ヘルスケアの心の状態は表示だけに使い、ねるねの朝の振り返りを上書きしません。")
            }
        }
    }

    @ViewBuilder
    private var healthMoodContent: some View {
        switch healthMoodLoadState {
        case .notRequested:
            Button {
                healthMoodEnabled = true
            } label: {
                Label("ヘルスケアの気分を読み込む", systemImage: "heart.text.square")
            }

        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("ヘルスケアを確認中…")
                    .foregroundStyle(.secondary)
            }

        case .empty:
            VStack(alignment: .leading, spacing: 6) {
                Label("ヘルスケアの記録はありません", systemImage: "heart.text.square")
                    .foregroundStyle(.secondary)
                Text("この日は未記録、または読み取りが許可されていません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("もう一度読み込む") {
                healthMoodReloadToken += 1
            }

        case .loaded(let entries):
            ForEach(entries) { entry in
                healthMoodRow(entry)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("読み込めませんでした", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("再試行") {
                healthMoodReloadToken += 1
            }
        }
    }

    private var trendSection: some View {
        Section {
            Chart {
                ForEach(sevenDayPoints) { point in
                    BarMark(
                        x: .value("日", point.day, unit: .day),
                        y: .value("睡眠時間", Double(point.minutes) / 60)
                    )
                    .foregroundStyle(
                        calendar.isDate(point.day, inSameDayAs: selectedDay)
                            ? Color.accentColor
                            : Color.accentColor.opacity(point.minutes > 0 ? 0.45 : 0.12)
                    )
                    .cornerRadius(4)
                }

                RuleMark(y: .value("目標", Double(selectedTargetMinutes) / 60))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            }
            .chartYScale(domain: 0...chartCeiling)
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
            .frame(height: 190)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(trendAccessibilityLabel)
        } header: {
            Text("選択日までの7日間")
        } footer: {
            Text("選択した日は濃い色、点線はその日の目標睡眠時間です。")
        }
    }

    private func sleepRecordRow(_ session: SleepSession) -> some View {
        Button {
            reflectionTarget = ReflectionTarget(id: session.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        "\(session.startDate.formatted(date: .omitted, time: .shortened)) 〜 \(session.endDate.formatted(date: .omitted, time: .shortened))",
                        systemImage: sourceSymbol(session.source)
                    )
                    .font(.subheadline)

                    Spacer()

                    Text(SleepDurationFormatter.summary(minutes: session.durationMinutes))
                        .font(.headline)
                        .monospacedDigit()
                }

                if let stages = session.stages, stages.recordedMinutes > 0 {
                    Text(stageSummary(stages))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !session.note.isEmpty {
                    Label(session.note, systemImage: "quote.opening")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint(session.mood == nil ? "朝の気分を追加します" : "振り返りを編集します")
    }

    private func healthMoodRow(_ entry: HealthKitStateOfMindData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Gauge(value: (entry.valence + 1) / 2) {
                Image(systemName: "brain.head.profile")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(healthMoodColor(entry.valence))
            .frame(width: 42, height: 42)
            .accessibilityLabel("快・不快の度合い")
            .accessibilityValue(entry.classification)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.classification)
                        .font(.headline)
                    Spacer()
                    Text(entry.date, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(entry.isDailyMood ? "一日の気分" : "その瞬間の感情")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !entry.labels.isEmpty {
                    Text(entry.labels.joined(separator: "・"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @MainActor
    private func loadHealthMood(for day: Date) async {
        healthMoodLoadState = .loading

        do {
            let entries = try await sleepStore.healthKitStateOfMind(
                for: day,
                calendar: calendar
            )
            guard !Task.isCancelled,
                  calendar.isDate(day, inSameDayAs: selectedDay) else { return }
            healthMoodLoadState = entries.isEmpty ? .empty : .loaded(entries)
        } catch {
            guard !Task.isCancelled,
                  calendar.isDate(day, inSameDayAs: selectedDay) else { return }
            healthMoodLoadState = .failed(error.localizedDescription)
        }
    }

    private var targetStatus: String {
        let difference = selectedTotalMinutes - selectedTargetMinutes
        if difference > 0 {
            return "\(SleepDurationFormatter.summary(minutes: difference))上回りました"
        }
        if difference == 0 {
            return "目標を達成しました"
        }
        return "あと\(SleepDurationFormatter.summary(minutes: abs(difference)))"
    }

    private var trendAccessibilityLabel: String {
        let recordedDays = sevenDayPoints.filter { $0.minutes > 0 }.count
        if recordedDays == 0 {
            return "選択日までの7日間に睡眠記録はありません"
        }
        return "選択日までの7日間のうち、\(recordedDays)日に睡眠記録があります"
    }

    private func sourceSymbol(_ source: SleepSource) -> String {
        switch source {
        case .timer: "timer"
        case .manual: "hand.tap"
        case .healthKit: "heart.fill"
        }
    }

    private func stageSummary(_ stages: SleepStageDurations) -> String {
        var parts: [String] = []
        if stages.coreMinutes > 0 {
            parts.append("コア \(SleepDurationFormatter.compact(minutes: stages.coreMinutes))")
        }
        if stages.deepMinutes > 0 {
            parts.append("深い \(SleepDurationFormatter.compact(minutes: stages.deepMinutes))")
        }
        if stages.remMinutes > 0 {
            parts.append("レム \(SleepDurationFormatter.compact(minutes: stages.remMinutes))")
        }
        if stages.awakeMinutes > 0 {
            parts.append("覚醒 \(SleepDurationFormatter.compact(minutes: stages.awakeMinutes))")
        }
        return parts.joined(separator: "  ")
    }

    private func healthMoodColor(_ valence: Double) -> Color {
        switch valence {
        case ..<(-0.6): .indigo
        case -0.6..<(-0.15): .blue
        case -0.15...0.15: .teal
        case 0.15...0.6: .mint
        default: .green
        }
    }
}
