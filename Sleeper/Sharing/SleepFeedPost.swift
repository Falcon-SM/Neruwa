import Foundation

/// The deliberately small, public representation used by the in-app feed.
///
/// A feed post cannot contain exact bed/wake times, sleep stages, HealthKit
/// identifiers, the evening journal, or the private morning reflection note.
/// Keeping those fields out of this type makes accidental sharing harder than
/// relying on the view to hide them.
struct SleepFeedPost: Identifiable, Codable, Hashable, Sendable {
    enum Delivery: String, Codable, Hashable, Sendable {
        case cloud
        case local
        case sample
    }

    let id: String
    let authorAlias: String
    let wakeDay: Date
    let durationMinutes: Int
    let achievementPercentage: Int?
    let mood: SleepMood?
    let comment: String
    let createdAt: Date
    var reactionCount: Int
    var isReactedByCurrentUser: Bool
    var delivery: Delivery

    init(
        id: String = UUID().uuidString.lowercased(),
        authorAlias: String,
        wakeDay: Date,
        durationMinutes: Int,
        achievementPercentage: Int?,
        mood: SleepMood?,
        comment: String,
        createdAt: Date = Date(),
        reactionCount: Int = 0,
        isReactedByCurrentUser: Bool = false,
        delivery: Delivery
    ) {
        self.id = id
        self.authorAlias = Self.sanitizedAlias(authorAlias)
        self.wakeDay = Calendar.current.startOfDay(for: wakeDay)
        self.durationMinutes = min(max(0, durationMinutes), 20 * 60)
        self.achievementPercentage = achievementPercentage.map { min(max(0, $0), 300) }
        self.mood = mood
        self.comment = Self.sanitizedComment(comment)
        self.createdAt = createdAt
        self.reactionCount = max(0, reactionCount)
        self.isReactedByCurrentUser = isReactedByCurrentUser
        self.delivery = delivery
    }

    init(
        summary: SleepShareSummary,
        authorAlias: String,
        comment: String,
        includesMood: Bool,
        delivery: Delivery
    ) {
        self.init(
            authorAlias: authorAlias,
            wakeDay: summary.wakeDay,
            durationMinutes: summary.durationMinutes,
            achievementPercentage: summary.achievementPercentage,
            mood: includesMood ? summary.mood : nil,
            comment: comment,
            delivery: delivery
        )
    }

    var formattedWakeDay: String {
        wakeDay.formatted(.dateTime.month(.abbreviated).day())
    }

    var relativeCreatedAt: String {
        createdAt.formatted(.relative(presentation: .named))
    }

    static func sanitizedComment(_ value: String) -> String {
        let singleLine: String = value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        let withoutControls = singleLine.unicodeScalars.reduce(into: "") { result, scalar in
            guard !CharacterSet.controlCharacters.contains(scalar) else { return }
            result.unicodeScalars.append(scalar)
        }
        let trimmed = withoutControls.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(80))
    }

    static func sanitizedAlias(_ value: String) -> String {
        let sanitized = value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((sanitized.isEmpty ? "ねるねユーザー" : sanitized).prefix(20))
    }
}

enum SleepFeedIdentity {
    /// Builds a stable public nickname without exposing a Google display name,
    /// email address, or Firebase UID in the interface or post payload.
    static func publicAlias(for user: AppUser) -> String {
        if user.isGuest {
            return "この端末のねるね"
        }

        var hash: UInt32 = 2_166_136_261
        for byte in user.id.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return "ねるね\((hash % 9_000) + 1_000)"
    }
}
