import Foundation

/// How a sleep session entered the app.
public enum SleepSource: String, Codable, CaseIterable, Hashable, Sendable {
    case timer
    case manual
    case healthKit
}

/// A lightweight reflection recorded after waking up.
public enum SleepMood: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case bad
    case flat
    case good
    case great

    public var id: Self { self }

    public var label: String {
        switch self {
        case .bad:
            "つらい"
        case .flat:
            "ふつう"
        case .good:
            "いい"
        case .great:
            "最高"
        }
    }

    public var emoji: String {
        switch self {
        case .bad:
            "😣"
        case .flat:
            "😐"
        case .good:
            "🙂"
        case .great:
            "😄"
        }
    }
}

/// Stage totals from HealthKit. All values are expressed in whole minutes.
public struct SleepStageDurations: Codable, Hashable, Sendable {
    public var awakeMinutes: Int
    public var coreMinutes: Int
    public var deepMinutes: Int
    public var remMinutes: Int
    public var unspecifiedMinutes: Int

    public init(
        awakeMinutes: Int = 0,
        coreMinutes: Int = 0,
        deepMinutes: Int = 0,
        remMinutes: Int = 0,
        unspecifiedMinutes: Int = 0
    ) {
        self.awakeMinutes = max(0, awakeMinutes)
        self.coreMinutes = max(0, coreMinutes)
        self.deepMinutes = max(0, deepMinutes)
        self.remMinutes = max(0, remMinutes)
        self.unspecifiedMinutes = max(0, unspecifiedMinutes)
    }

    public var asleepMinutes: Int {
        coreMinutes + deepMinutes + remMinutes + unspecifiedMinutes
    }

    public var recordedMinutes: Int {
        awakeMinutes + asleepMinutes
    }
}

public struct SleepSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date
    public var targetMinutes: Int
    public var source: SleepSource
    public var mood: SleepMood?
    public var note: String
    public var stages: SleepStageDurations?
    public var externalIdentifier: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        targetMinutes: Int,
        source: SleepSource,
        mood: SleepMood? = nil,
        note: String = "",
        stages: SleepStageDurations? = nil,
        externalIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.targetMinutes = max(0, targetMinutes)
        self.source = source
        self.mood = mood
        self.note = note
        self.stages = stages
        self.externalIdentifier = externalIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var durationMinutes: Int {
        if source == .healthKit,
           let stages,
           stages.asleepMinutes > 0 {
            return stages.asleepMinutes
        }

        let minutes = endDate.timeIntervalSince(startDate) / 60
        guard minutes > 0 else { return 0 }
        switch source {
        case .timer:
            return max(1, Int(minutes.rounded(.up)))
        case .manual, .healthKit:
            return max(1, Int(minutes.rounded()))
        }
    }

    public var shortageMinutes: Int {
        max(0, targetMinutes - durationMinutes)
    }

    /// The calendar day on which this sleep session ended.
    public var wakeDay: Date {
        Calendar.current.startOfDay(for: endDate)
    }
}
