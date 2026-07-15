import Foundation

/// A deliberately reduced representation of a sleep session for external sharing.
///
/// Exact bed and wake times, HealthKit stages, external identifiers, and the
/// private reflection note never enter this type, so they cannot accidentally be
/// added to a ShareLink payload by the presentation layer.
struct SleepShareSummary: Equatable, Sendable {
    let wakeDay: Date
    let durationMinutes: Int
    let targetMinutes: Int
    let mood: SleepMood?

    init(session: SleepSession) {
        wakeDay = session.wakeDay
        durationMinutes = max(0, session.durationMinutes)
        targetMinutes = max(0, session.targetMinutes)
        mood = session.mood
    }

    var achievementPercentage: Int? {
        guard targetMinutes > 0 else { return nil }
        let percentage = Double(durationMinutes) / Double(targetMinutes) * 100
        return max(0, Int(percentage.rounded()))
    }

    var formattedWakeDay: String {
        wakeDay.formatted(
            .dateTime
                .year()
                .month(.wide)
                .day()
                .weekday(.wide)
        )
    }

    func shareText(options: SleepShareOptions) -> String {
        var lines = [
            "Neruwaで睡眠を記録しました",
            formattedWakeDay
        ]

        if options.includesDuration {
            lines.append("睡眠時間: \(SleepDurationFormatter.summary(minutes: durationMinutes))")
        }

        if options.includesAchievement, let achievementPercentage {
            lines.append("目標達成率: \(achievementPercentage)%")
        }

        if options.includesMood, let mood {
            lines.append("今朝の気分: \(mood.emoji) \(mood.label)")
        }

        lines.append("#Neruwa")
        return lines.joined(separator: "\n")
    }
}

struct SleepShareOptions: Equatable, Sendable {
    var includesDuration = true
    var includesAchievement = true
    var includesMood = false

    func hasShareableItem(in summary: SleepShareSummary) -> Bool {
        includesDuration
            || (includesAchievement && summary.achievementPercentage != nil)
            || (includesMood && summary.mood != nil)
    }
}
