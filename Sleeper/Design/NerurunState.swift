import Foundation

enum NerurunCondition: String, CaseIterable, Sendable {
    case normal
    case discouraged
    case exhausted
    case thriving

    var title: String {
        switch self {
        case .normal:
            "いつものねるるん"
        case .discouraged:
            "ちょっとしょんぼり"
        case .exhausted:
            "疲れが限界かも"
        case .thriving:
            "とてもいいペース"
        }
    }

    var message: String {
        switch self {
        case .normal:
            "今日の眠りも一緒に記録しよう"
        case .discouraged:
            "クローバーも少し元気がないみたい。今夜は早めに休もう"
        case .exhausted:
            "目の下にクマができているよ。今日は睡眠を最優先にしよう"
        case .thriving:
            "記録も睡眠も安定しているよ。小さな仲間が増えました"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: "sparkles"
        case .discouraged: "leaf.fill"
        case .exhausted: "moon.zzz.fill"
        case .thriving: "bird.fill"
        }
    }
}

struct NerurunStatus: Equatable, Sendable {
    let condition: NerurunCondition
    let companionCount: Int
}

enum NerurunStatusEvaluator {
    static func evaluate(
        sessions: [SleepSession],
        fallbackTargetMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> NerurunStatus {
        let recent = sessions
            .filter { $0.endDate <= now }
            .sorted { $0.endDate > $1.endDate }

        guard let latest = recent.first else {
            return NerurunStatus(condition: .normal, companionCount: 0)
        }

        let latestRatio = achievementRatio(
            for: latest,
            fallbackTargetMinutes: fallbackTargetMinutes
        )
        let latestThree = Array(recent.prefix(3))
        let recentAverage = latestThree
            .map { achievementRatio(for: $0, fallbackTargetMinutes: fallbackTargetMinutes) }
            .reduce(0, +) / Double(max(latestThree.count, 1))
        let consecutiveBadMoods = recent.prefix(2).allSatisfy { $0.mood == .bad }

        if latestRatio < 0.62
            || (latestThree.count >= 2 && recentAverage < 0.68)
            || (recent.count >= 2 && consecutiveBadMoods) {
            return NerurunStatus(condition: .exhausted, companionCount: 0)
        }

        let lastSevenDays = recent.filter {
            guard let boundary = calendar.date(byAdding: .day, value: -7, to: now) else {
                return false
            }
            return $0.wakeDay >= calendar.startOfDay(for: boundary)
        }
        let recordedDays = Set(lastSevenDays.map { calendar.startOfDay(for: $0.wakeDay) })
        let stableAverage = lastSevenDays.isEmpty
            ? 0
            : lastSevenDays
                .map { achievementRatio(for: $0, fallbackTargetMinutes: fallbackTargetMinutes) }
                .reduce(0, +) / Double(lastSevenDays.count)
        let positiveMoods = lastSevenDays.filter {
            $0.mood == .good || $0.mood == .great
        }.count
        let hasBadMood = lastSevenDays.contains { $0.mood == .bad }

        if recordedDays.count >= 5,
           stableAverage >= 0.90,
           positiveMoods >= 3,
           !hasBadMood {
            let streak = consecutiveRecordedDays(
                in: recent,
                now: now,
                calendar: calendar
            )
            return NerurunStatus(
                condition: .thriving,
                companionCount: min(3, max(1, streak / 3))
            )
        }

        let daysSinceLatest = calendar.dateComponents(
            [.day],
            from: latest.wakeDay,
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if latestRatio < 0.85
            || latest.mood == .bad
            || latest.mood == .flat
            || daysSinceLatest >= 2 {
            return NerurunStatus(condition: .discouraged, companionCount: 0)
        }

        return NerurunStatus(condition: .normal, companionCount: 0)
    }

    private static func achievementRatio(
        for session: SleepSession,
        fallbackTargetMinutes: Int
    ) -> Double {
        let target = session.targetMinutes > 0
            ? session.targetMinutes
            : max(fallbackTargetMinutes, 1)
        return Double(session.durationMinutes) / Double(max(target, 1))
    }

    private static func consecutiveRecordedDays(
        in sessions: [SleepSession],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let recordedDays = Set(sessions.map { calendar.startOfDay(for: $0.wakeDay) })
        var day = calendar.startOfDay(for: now)
        if !recordedDays.contains(day),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
           recordedDays.contains(yesterday) {
            day = yesterday
        }

        var streak = 0
        while recordedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previous
        }
        return streak
    }
}
