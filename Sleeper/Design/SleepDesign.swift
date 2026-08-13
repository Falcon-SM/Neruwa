import Foundation

enum SleepDurationFormatter {
    static func clock(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func summary(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainder = safeMinutes % 60

        switch (hours, remainder) {
        case (0, _):
            return "\(remainder)分"
        case (_, 0):
            return "\(hours)時間"
        default:
            return "\(hours)時間\(remainder)分"
        }
    }

    static func compact(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        return String(format: "%d:%02d", safeMinutes / 60, safeMinutes % 60)
    }
}
