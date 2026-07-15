import Foundation

struct DailyFlowSchedule: Equatable, Hashable, Sendable {
    static let morningStartDefaultsKey = "dailyFlowMorningStartMinutes"
    static let nightStartDefaultsKey = "dailyFlowNightStartMinutes"

    static let defaultMorningStartMinutes = 5 * 60
    static let defaultNightStartMinutes = 19 * 60
    static let `default` = DailyFlowSchedule(
        validatedMorningStartMinutes: defaultMorningStartMinutes,
        nightStartMinutes: defaultNightStartMinutes
    )

    let morningStartMinutes: Int
    let nightStartMinutes: Int

    /// Invalid persisted values (including equal boundaries) deliberately fall
    /// back to the original 05:00 / 19:00 behavior.
    init(morningStartMinutes: Int, nightStartMinutes: Int) {
        guard Self.isValid(
            morningStartMinutes: morningStartMinutes,
            nightStartMinutes: nightStartMinutes
        ) else {
            self = .default
            return
        }
        self.init(
            validatedMorningStartMinutes: morningStartMinutes,
            nightStartMinutes: nightStartMinutes
        )
    }

    private init(
        validatedMorningStartMinutes morningStartMinutes: Int,
        nightStartMinutes: Int
    ) {
        self.morningStartMinutes = morningStartMinutes
        self.nightStartMinutes = nightStartMinutes
    }

    static func isValid(
        morningStartMinutes: Int,
        nightStartMinutes: Int
    ) -> Bool {
        (0..<(24 * 60)).contains(morningStartMinutes)
            && (0..<(24 * 60)).contains(nightStartMinutes)
            && morningStartMinutes != nightStartMinutes
    }

    func period(at date: Date, calendar: Calendar = .current) -> DailyFlowPeriod {
        let minute = Self.minuteOfDay(for: date, calendar: calendar)
        let isNight: Bool

        if nightStartMinutes < morningStartMinutes {
            isNight = minute >= nightStartMinutes && minute < morningStartMinutes
        } else {
            isNight = minute >= nightStartMinutes || minute < morningStartMinutes
        }
        return isNight ? .night : .morning
    }

    func flowDay(
        containing date: Date,
        for flowPeriod: DailyFlowPeriod,
        calendar: Calendar = .current
    ) -> Date {
        let minute = Self.minuteOfDay(for: date, calendar: calendar)
        let startMinute = flowPeriod == .morning
            ? morningStartMinutes
            : nightStartMinutes
        let currentPeriod = period(at: date, calendar: calendar)
        let dayOffset: Int
        if currentPeriod == flowPeriod {
            dayOffset = minute < startMinute ? -1 : 0
        } else {
            // A sample outside the requested period belongs to the next
            // occurrence of that period (for example, a 04:50 wake time to
            // the morning flow that begins at 05:00).
            dayOffset = minute < startMinute ? 0 : 1
        }
        let sourceDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: date
        ) ?? date
        return calendar.startOfDay(for: sourceDay)
    }

    func morningFlowDay(containing date: Date, calendar: Calendar = .current) -> Date {
        flowDay(containing: date, for: .morning, calendar: calendar)
    }

    func nightFlowDay(containing date: Date, calendar: Calendar = .current) -> Date {
        flowDay(containing: date, for: .night, calendar: calendar)
    }

    func nightInterval(
        forFlowDay flowDay: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard let start = calendar.date(
            bySettingHour: nightStartMinutes / 60,
            minute: nightStartMinutes % 60,
            second: 0,
            of: flowDay
        ), let end = calendar.nextDate(
            after: start,
            matching: DateComponents(
                hour: morningStartMinutes / 60,
                minute: morningStartMinutes % 60,
                second: 0
            ),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    var formattedMorningStart: String {
        Self.formatted(minutes: morningStartMinutes)
    }

    var formattedNightStart: String {
        Self.formatted(minutes: nightStartMinutes)
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func formatted(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

enum DailyFlowPeriod: Equatable, Sendable {
    case morning
    case night

    init(
        date: Date,
        calendar: Calendar = .current,
        schedule: DailyFlowSchedule = .default
    ) {
        self = schedule.period(at: date, calendar: calendar)
    }

    /// Keeps the configured night range as one continuous evening journal day.
    static func nightFlowDay(
        containing date: Date,
        calendar: Calendar = .current,
        schedule: DailyFlowSchedule = .default
    ) -> Date {
        schedule.nightFlowDay(containing: date, calendar: calendar)
    }

    /// Keeps a configured morning range that crosses midnight on one flow day.
    static func morningFlowDay(
        containing date: Date,
        calendar: Calendar = .current,
        schedule: DailyFlowSchedule = .default
    ) -> Date {
        schedule.morningFlowDay(containing: date, calendar: calendar)
    }

    var title: String {
        switch self {
        case .morning:
            "朝の流れ"
        case .night:
            "夜の流れ"
        }
    }

    var accessibilityTimeRange: String {
        accessibilityTimeRange(schedule: .default)
    }

    func accessibilityTimeRange(schedule: DailyFlowSchedule) -> String {
        switch self {
        case .morning:
            "\(schedule.formattedMorningStart)から\(schedule.formattedNightStart)前まで"
        case .night:
            "\(schedule.formattedNightStart)から\(schedule.formattedMorningStart)前まで"
        }
    }
}
