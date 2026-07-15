//
//  HomeView.swift
//  Sleeper
//

import SwiftUI

struct HomeView: View {
    private struct WeeklySummary {
        let sessionCount: Int
        let averageMinutes: Int?
    }

    @EnvironmentObject private var sleepStore: SleepStore
    @EnvironmentObject private var learningStore: SleepLearningStore
    @EnvironmentObject private var eveningStore: EveningStore
    @Binding var user: AppUser
    @Binding var selectedTab: MainTab

    private let now: Date
    private let calendar: Calendar
    private let onStartEveningFlow: () -> Void
    private let onResumeReflection: (UUID) -> Void
    private let onOpenLearning: (SleepLearningPhase, UUID?) -> Void
    private let onOpenSettings: () -> Void

    @AppStorage("sleepTargetMinutes") private var targetMinutes = 480

    init(
        user: Binding<AppUser>,
        selectedTab: Binding<MainTab>,
        now: Date = .now,
        calendar: Calendar = .current,
        onStartEveningFlow: @escaping () -> Void = {},
        onResumeReflection: @escaping (UUID) -> Void = { _ in },
        onOpenLearning: @escaping (SleepLearningPhase, UUID?) -> Void = { _, _ in },
        onOpenSettings: @escaping () -> Void = {}
    ) {
        _user = user
        _selectedTab = selectedTab
        self.now = now
        self.calendar = calendar
        self.onStartEveningFlow = onStartEveningFlow
        self.onResumeReflection = onResumeReflection
        self.onOpenLearning = onOpenLearning
        self.onOpenSettings = onOpenSettings
    }

    private var latestSession: SleepSession? {
        sleepStore.sessions.max(by: { $0.endDate < $1.endDate })
    }

    private var latestTodaySession: SleepSession? {
        sleepStore.sessions
            .filter { calendar.isDate($0.endDate, inSameDayAs: now) }
            .max(by: { $0.endDate < $1.endDate })
    }

    private var morningFlowSession: SleepSession? {
        guard dailyFlowPeriod == .morning else { return nil }
        guard let session = latestTodaySession else { return nil }
        return session
    }

    private var dailyFlowPeriod: DailyFlowPeriod {
        DailyFlowPeriod(date: now, calendar: calendar)
    }

    private func morningTestResult(for sessionID: UUID) -> LearningTestResult? {
        learningStore.results
            .filter { $0.sleepSessionID == sessionID }
            .max(by: { $0.completedAt < $1.completedAt })
    }

    private var weeklySummary: WeeklySummary {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let sessions = sleepStore.sessions.filter {
            $0.endDate >= start && $0.endDate <= now
        }

        let totalsByDay = Dictionary(grouping: sessions) {
            calendar.startOfDay(for: $0.endDate)
        }
            .mapValues { sessions in
                sessions.map(\.durationMinutes).reduce(0, +)
            }
        let average = totalsByDay.isEmpty
            ? nil
            : totalsByDay.values.reduce(0, +) / totalsByDay.count

        return WeeklySummary(
            sessionCount: sessions.count,
            averageMinutes: average
        )
    }

    var body: some View {
        NavigationStack {
            List {
                dailyFlowSection
                welcomeSection
                tonightSection
                recentSleepSection
                weeklySection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("ねるね")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
        }
    }

    private var dailyFlowSection: some View {
        Section {
            if dailyFlowPeriod == .night {
                nightFlowContent
            } else if let session = morningFlowSession {
                let testResult = morningTestResult(for: session.id)
                flowStepRow(
                    title: "今朝の気分",
                    detail: session.mood.map { "\($0.emoji) \($0.label)" } ?? "未入力",
                    systemImage: "face.smiling",
                    isComplete: session.mood != nil
                )
                flowStepRow(
                    title: "朝の点字テスト",
                    detail: testResult.map { $0.wasSkipped ? "スキップ済み" : "完了" } ?? "これから",
                    systemImage: "checkmark.circle",
                    isComplete: testResult != nil
                )
                flowStepRow(
                    title: "記録を確認",
                    detail: session.mood != nil && testResult != nil ? "準備できました" : "最後のステップ",
                    systemImage: "chart.bar.xaxis",
                    isComplete: session.mood != nil && testResult != nil
                )

                Button(action: continueMorningFlow) {
                    Label(morningActionTitle(for: session), systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                flowStepRow(
                    title: "昨夜の睡眠を記録",
                    detail: sleepStore.activeTimerStartedAt == nil
                        ? "タイマーまたは手入力で追加してください"
                        : "睡眠タイマーを停止して記録を完成させてください",
                    systemImage: "moon.zzz.fill",
                    isComplete: false
                )
                flowStepRow(
                    title: "朝の振り返り",
                    detail: "睡眠記録のあとに、気分 → 点字テスト → 記録へ進みます",
                    systemImage: "sunrise.fill",
                    isComplete: false
                )

                Button {
                    selectedTab = .sleep
                } label: {
                    Label(
                        sleepStore.activeTimerStartedAt != nil
                            ? "睡眠タイマーを確認"
                            : "睡眠を記録",
                        systemImage: "arrow.right.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } header: {
            Text(dailyFlowPeriod.title)
                .accessibilityLabel("\(dailyFlowPeriod.title)、\(dailyFlowPeriod.accessibilityTimeRange)")
        } footer: {
            Text(dailyFlowFooterText)
        }
    }

    private var dailyFlowFooterText: String {
        if dailyFlowPeriod == .night {
            return "日記 → 学ぶ → 睡眠音声 → 睡眠記録の順で進めます。"
        }
        if morningFlowSession == nil {
            return "睡眠記録を追加すると、気分 → 朝テスト → 記録へ進めます。"
        }
        return "気分 → 朝テスト → 記録の順で進めます。"
    }

    @ViewBuilder
    private var nightFlowContent: some View {
        let journalDay = DailyFlowPeriod.nightFlowDay(containing: now, calendar: calendar)
        let journalComplete = eveningStore.entry(for: journalDay, calendar: calendar)?.completedAt != nil

        flowStepRow(
            title: "今日を閉じる",
            detail: journalComplete ? "日記を保存済み" : "今日・手放す・明日の3つ",
            systemImage: "square.and.pencil",
            isComplete: journalComplete
        )
        flowStepRow(
            title: "点字を学ぶ",
            detail: "カードと睡眠音声",
            systemImage: "book.fill",
            isComplete: false
        )
        flowStepRow(
            title: "睡眠を記録",
            detail: sleepStore.activeTimerStartedAt == nil ? "タイマーまたは手入力" : "タイマー計測中",
            systemImage: "moon.zzz.fill",
            isComplete: sleepStore.activeTimerStartedAt != nil
        )

        Button {
            if sleepStore.activeTimerStartedAt != nil {
                selectedTab = .sleep
            } else if journalComplete {
                onOpenLearning(.study, nil)
            } else {
                onStartEveningFlow()
            }
        } label: {
            Label(
                sleepStore.activeTimerStartedAt != nil
                    ? "睡眠タイマーを確認"
                    : (journalComplete ? "点字学習へ" : "今日を閉じる"),
                systemImage: "arrow.right.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var welcomeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(now.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(greeting)
                    .font(.title2.bold())

                Text("睡眠を評価するのではなく、少しずつ自分のリズムを見つけましょう。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            LabeledContent {
                Label("\(streak)日", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
            } label: {
                Text("連続記録")
            }
            .accessibilityLabel("連続記録 \(streak)日")
        }
    }

    private var tonightSection: some View {
        Section {
            LabeledContent {
                Text(SleepDurationFormatter.summary(minutes: targetMinutes))
                    .fontWeight(.semibold)
            } label: {
                Label("目標睡眠時間", systemImage: "target")
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: sleepStore.activeTimerStartedAt == nil ? "moon.zzz.fill" : "timer")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(sleepStore.activeTimerStartedAt == nil ? "睡眠を記録しましょう" : "睡眠タイマーは記録中です")
                        .font(.headline)

                    Text(sleepStore.activeTimerStartedAt == nil
                         ? "就寝時にタイマーを開始するか、あとから手入力できます。"
                         : "開始時刻から経過時間を自動で計算しています。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)

            Button {
                selectedTab = .sleep
                HapticsManager.instance.impact(style: .soft)
            } label: {
                Label(
                    sleepStore.activeTimerStartedAt == nil ? "睡眠を記録" : "タイマーを確認",
                    systemImage: "arrow.right.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } header: {
            Text("今夜")
        }
    }

    @ViewBuilder
    private var recentSleepSection: some View {
        Section {
            if let latestSession {
                LabeledContent("睡眠時間") {
                    Text(SleepDurationFormatter.summary(minutes: latestSession.durationMinutes))
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                }

                LabeledContent("起床日") {
                    Text(latestSession.endDate, format: .dateTime.month().day().weekday(.abbreviated))
                }

                LabeledContent("目標との差") {
                    Text(goalDifference(for: latestSession))
                        .foregroundStyle(latestSession.shortageMinutes > 0 ? .orange : .green)
                }

                LabeledContent("今朝の気分", value: latestSession.mood?.emoji ?? "未記録")
                LabeledContent("記録方法", value: sourceLabel(latestSession.source))
            } else {
                ContentUnavailableView(
                    "まだ記録がありません",
                    systemImage: "moon.zzz",
                    description: Text("最初の睡眠を記録すると、ここに表示されます。")
                )
            }

            Button {
                selectedTab = .history
            } label: {
                Label("すべての記録を見る", systemImage: "chart.bar.xaxis")
            }
        } header: {
            Text("最近の睡眠")
        }
    }

    private var weeklySection: some View {
        let summary = weeklySummary

        return Section {
            LabeledContent("1日平均") {
                Text(summary.averageMinutes.map { SleepDurationFormatter.summary(minutes: $0) } ?? "記録待ち")
                    .fontWeight(.semibold)
            }

            LabeledContent("記録数", value: "\(summary.sessionCount)セッション")

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(
                    value: Double(summary.averageMinutes ?? 0),
                    total: Double(max(targetMinutes, 1))
                )
                .tint(.orange)

                Text(weeklyInsight(for: summary.averageMinutes))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        } header: {
            Text("過去7日間")
        }
    }

    private var greeting: String {
        let hour = calendar.component(.hour, from: now)
        if hour < 11 { return "おはよう、\(user.name)さん" }
        if hour < 17 { return "こんにちは、\(user.name)さん" }
        return "こんばんは、\(user.name)さん"
    }

    private var streak: Int {
        let recordedDays = Set(
            sleepStore.sessions
                .filter { $0.endDate <= now }
                .map { calendar.startOfDay(for: $0.endDate) }
        )
        var cursor = calendar.startOfDay(for: now)

        if !recordedDays.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        var count = 0
        while recordedDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private func goalDifference(for session: SleepSession) -> String {
        session.shortageMinutes > 0
            ? "−\(SleepDurationFormatter.summary(minutes: session.shortageMinutes))"
            : "達成"
    }

    private func weeklyInsight(for averageMinutes: Int?) -> String {
        guard let averageMinutes else {
            return "記録が増えると、目標時間との差をここで確認できます。"
        }
        let difference = averageMinutes - targetMinutes
        if abs(difference) < 15 { return "目標に近い睡眠時間を保てています。" }
        if difference > 0 {
            return "平均は目標より \(SleepDurationFormatter.summary(minutes: difference)) 長めです。"
        }
        return "平均は目標より \(SleepDurationFormatter.summary(minutes: abs(difference))) 短めです。"
    }

    private func sourceLabel(_ source: SleepSource) -> String {
        switch source {
        case .timer: "タイマー"
        case .manual: "手入力"
        case .healthKit: "ヘルスケア"
        }
    }

    private func continueMorningFlow() {
        guard let session = morningFlowSession else { return }
        if session.mood == nil {
            onResumeReflection(session.id)
        } else if morningTestResult(for: session.id) == nil {
            onOpenLearning(.test, session.id)
        } else {
            selectedTab = .history
        }
    }

    private func morningActionTitle(for session: SleepSession) -> String {
        if session.mood == nil { return "今朝の気分を記録" }
        if morningTestResult(for: session.id) == nil { return "朝テストへ" }
        return "記録を見る"
    }

    private func flowStepRow(
        title: String,
        detail: String,
        systemImage: String,
        isComplete: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)、\(detail)、\(isComplete ? "完了" : "未完了")")
    }
}

#Preview {
    HomeView(
        user: .constant(.guest),
        selectedTab: .constant(.home)
    )
    .environmentObject(SleepStore())
    .environmentObject(SleepLearningStore())
    .environmentObject(EveningStore())
}
