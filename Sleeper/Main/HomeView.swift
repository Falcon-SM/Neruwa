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
            ZStack {
                NightSkyBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        header
                        nextActionCard
                        latestRecordCard
                        weeklyCard
                    }
                }
                .sleepScreenScroll()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("ねるわ", systemImage: "moon.stars.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(SleepPalette.warmGold)

                Spacer()

                Label("\(streak)日", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SleepPalette.warmGold)
                    .accessibilityLabel("連続記録 \(streak)日")
            }

            Text(Date.now.formatted(date: .long, time: .omitted))
                .font(.caption)
                .foregroundStyle(SleepPalette.secondaryText)

            Text(greeting)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(SleepPalette.text)

            Text("睡眠を評価するのではなく、少しずつ自分のリズムを見つけよう。")
                .font(.subheadline)
                .foregroundStyle(SleepPalette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var nextActionCard: some View {
        GlassCard(tint: SleepPalette.warmGold.opacity(0.12), padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: sleepStore.activeTimerStartedAt == nil ? "moon.zzz.fill" : "timer")
                        .font(.title2)
                        .foregroundStyle(SleepPalette.warmGold)
                        .frame(width: 44, height: 44)
                        .glassEffect(
                            .regular.tint(SleepPalette.warmGold.opacity(0.16)),
                            in: .circle
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(sleepStore.activeTimerStartedAt == nil ? "そろそろ眠ろう" : "睡眠タイマーは記録中")
                            .font(.title3.bold())
                            .foregroundStyle(SleepPalette.text)

                        Text(sleepStore.activeTimerStartedAt == nil
                             ? "目標は \(SleepDurationFormatter.summary(minutes: targetMinutes))"
                             : "開始時刻から自動で経過時間を計算しています")
                            .font(.subheadline)
                            .foregroundStyle(SleepPalette.secondaryText)
                    }
                }

                Button {
                    selectedTab = .sleep
                    HapticsManager.instance.impact(style: .soft)
                } label: {
                    Label(
                        sleepStore.activeTimerStartedAt == nil ? "睡眠を記録する" : "タイマーを確認する",
                        systemImage: "arrow.right"
                    )
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(SleepPalette.warmGold)
            }
        }
    }

    @ViewBuilder
    private var latestRecordCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("最近の睡眠", systemImage: "clock.fill")
                        .font(.headline)
                        .foregroundStyle(SleepPalette.text)
                    Spacer()
                    Button("記録を見る") {
                        selectedTab = .history
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SleepPalette.warmGold)
                }

                if let latestSession {
                    HStack(alignment: .lastTextBaseline) {
                        Text(SleepDurationFormatter.summary(minutes: latestSession.durationMinutes))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(SleepPalette.warmGold)
                            .minimumScaleFactor(0.75)

                        Spacer()

                        Text(latestSession.endDate, format: .dateTime.month().day().weekday(.abbreviated))
                            .font(.caption)
                            .foregroundStyle(SleepPalette.secondaryText)
                    }

                    Divider().overlay(Color.white.opacity(0.10))

                    HStack(spacing: 0) {
                        metric(
                            title: "目標との差",
                            value: latestSession.shortageMinutes > 0
                                ? "−\(SleepDurationFormatter.summary(minutes: latestSession.shortageMinutes))"
                                : "達成",
                            color: latestSession.shortageMinutes > 0 ? SleepPalette.sunrise : SleepPalette.mint
                        )
                        metric(
                            title: "今朝の気分",
                            value: latestSession.mood?.emoji ?? "未記録",
                            color: SleepPalette.text
                        )
                        metric(
                            title: "記録方法",
                            value: sourceLabel(latestSession.source),
                            color: SleepPalette.text
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "まだ記録がありません",
                        systemImage: "moon.zzz",
                        description: Text("最初の睡眠を記録すると、ここに振り返りが表示されます。")
                    )
                    .foregroundStyle(SleepPalette.text)
                }
            }
        }
    }

    private var weeklyCard: some View {
        let summary = weeklySummary

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("7日間のリズム", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(SleepPalette.text)

                HStack(alignment: .lastTextBaseline) {
                    Text(summary.averageMinutes.map { SleepDurationFormatter.summary(minutes: $0) } ?? "記録待ち")
                        .font(.title2.bold())
                        .foregroundStyle(SleepPalette.text)
                    Spacer()
                    Text("\(summary.sessionCount) セッション")
                        .font(.caption)
                        .foregroundStyle(SleepPalette.secondaryText)
                }

                ProgressView(
                    value: Double(summary.averageMinutes ?? 0),
                    total: Double(max(targetMinutes, 1))
                )
                .tint(SleepPalette.warmGold)

                Text(weeklyInsight(for: summary.averageMinutes))
                    .font(.footnote)
                    .foregroundStyle(SleepPalette.secondaryText)
            }
        }
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(SleepPalette.secondaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
