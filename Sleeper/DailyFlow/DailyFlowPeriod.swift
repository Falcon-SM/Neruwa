import Foundation

enum DailyFlowPeriod: Equatable, Sendable {
    case morning
    case night

    init(date: Date, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: date)
        self = hour >= 19 || hour < 5 ? .night : .morning
    }

    /// Keeps 19:00–04:59 as one continuous evening journal day.
    static func nightFlowDay(
        containing date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let hour = calendar.component(.hour, from: date)
        let journalDate = hour < 5
            ? (calendar.date(byAdding: .day, value: -1, to: date) ?? date)
            : date
        return calendar.startOfDay(for: journalDate)
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
        switch self {
        case .morning:
            "朝5時から夜7時前まで"
        case .night:
            "夜7時から朝5時前まで"
        }
    }
}
