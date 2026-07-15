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
    @Binding var user: AppUser
    @Binding var selectedTab: MainTab

    @AppStorage("sleepTargetMinutes") private var targetMinutes = 480

    private var latestSession: SleepSession? {
        sleepStore.sessions.max(by: { $0.endDate < $1.endDate })
    }

    private var weeklySummary: WeeklySummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let sessions = sleepStore.sessions.filter { $0.wakeDay >= start }

        let totalsByDay = Dictionary(grouping: sessions, by: \.wakeDay)
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
                welcomeSection
                tonightSection
                recentSleepSection
                weeklySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("概要")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var welcomeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date.now.formatted(date: .long, time: .omitted))
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
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 11 { return "おはよう、\(user.name)さん" }
        if hour < 17 { return "こんにちは、\(user.name)さん" }
        return "こんばんは、\(user.name)さん"
    }

    private var streak: Int {
        let calendar = Calendar.current
        let recordedDays = Set(sleepStore.sessions.map(\.wakeDay))
        var cursor = calendar.startOfDay(for: .now)

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
}

#Preview {
    HomeView(
        user: .constant(.guest),
        selectedTab: .constant(.home)
    )
    .environmentObject(SleepStore())
}
