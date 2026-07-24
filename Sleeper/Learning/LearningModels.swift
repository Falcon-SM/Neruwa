import Foundation

public enum LearningCardOrigin: String, Codable, Hashable, Sendable {
    case bundled
    case user
    case csv
}

public struct LearningCard: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var prompt: String
    public var answer: String
    public var speechText: String
    public var languageCode: String
    public var folderName: String
    public var origin: LearningCardOrigin

    /// One array per braille cell, containing dot numbers in the range 1...6.
    /// Generic vocabulary cards leave this value as `nil`.
    public var brailleCells: [[Int]]?

    public init(
        id: UUID = UUID(),
        prompt: String,
        answer: String,
        speechText: String,
        languageCode: String,
        brailleCells: [[Int]]? = nil,
        folderName: String? = nil,
        origin: LearningCardOrigin? = nil
    ) {
        let normalizedCells = Self.normalizedBrailleCells(brailleCells)
        self.id = id
        self.prompt = prompt
        self.answer = answer
        self.speechText = speechText
        self.languageCode = languageCode
        self.brailleCells = normalizedCells
        self.folderName = Self.normalizedFolderName(
            folderName,
            fallback: normalizedCells == nil ? "自分のカード" : "点字"
        )
        self.origin = origin ?? (normalizedCells == nil ? .user : .bundled)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case answer
        case speechText
        case languageCode
        case brailleCells
        case folderName
        case origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cells = try container.decodeIfPresent([[Int]].self, forKey: .brailleCells)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            prompt: try container.decode(String.self, forKey: .prompt),
            answer: try container.decode(String.self, forKey: .answer),
            speechText: try container.decode(String.self, forKey: .speechText),
            languageCode: try container.decode(String.self, forKey: .languageCode),
            brailleCells: cells,
            folderName: try container.decodeIfPresent(String.self, forKey: .folderName),
            origin: try container.decodeIfPresent(LearningCardOrigin.self, forKey: .origin)
        )
    }

    private static func normalizedBrailleCells(_ cells: [[Int]]?) -> [[Int]]? {
        guard let cells else { return nil }
        let normalized = cells.compactMap { cell -> [Int]? in
            let dots = Array(Set(cell.filter { (1...6).contains($0) })).sorted()
            return dots.isEmpty ? nil : dots
        }
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedFolderName(
        _ folderName: String?,
        fallback: String
    ) -> String {
        let normalized = folderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? fallback : String(normalized.prefix(40))
    }
}

public struct LearningTestResult: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var completedAt: Date
    public var correctAnswers: Int
    public var totalQuestions: Int
    public var cardIDs: Set<UUID>
    /// The sleep record whose morning flow produced this result.
    /// Results saved before this field was introduced remain unlinked.
    public var sleepSessionID: UUID?
    public var wasSkipped: Bool

    public init(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        correctAnswers: Int,
        totalQuestions: Int,
        cardIDs: Set<UUID> = [],
        sleepSessionID: UUID? = nil,
        wasSkipped: Bool = false
    ) {
        let normalizedTotal = max(0, totalQuestions)
        self.id = id
        self.completedAt = completedAt
        self.correctAnswers = wasSkipped ? 0 : min(max(0, correctAnswers), normalizedTotal)
        self.totalQuestions = wasSkipped ? 0 : normalizedTotal
        self.cardIDs = cardIDs
        self.sleepSessionID = sleepSessionID
        self.wasSkipped = wasSkipped
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case completedAt
        case correctAnswers
        case totalQuestions
        case cardIDs
        case sleepSessionID
        case wasSkipped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            completedAt: try container.decode(Date.self, forKey: .completedAt),
            correctAnswers: try container.decodeIfPresent(Int.self, forKey: .correctAnswers) ?? 0,
            totalQuestions: try container.decodeIfPresent(Int.self, forKey: .totalQuestions) ?? 0,
            cardIDs: try container.decodeIfPresent(Set<UUID>.self, forKey: .cardIDs) ?? [],
            sleepSessionID: try container.decodeIfPresent(UUID.self, forKey: .sleepSessionID),
            wasSkipped: try container.decodeIfPresent(Bool.self, forKey: .wasSkipped) ?? false
        )
    }

    /// Accuracy in the range 0...1.
    public var accuracy: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(correctAnswers) / Double(totalQuestions)
    }

    public var scorePercentage: Int {
        Int((accuracy * 100).rounded())
    }
}

public struct SleepLearningSettings: Codable, Hashable, Sendable {
    public var selectedCardIDs: Set<UUID>
    public var intervalSeconds: Double
    public var durationMinutes: Int
    public var volume: Float
    public var shuffle: Bool
    public var autoStartWithSleepTimer: Bool

    public init(
        selectedCardIDs: Set<UUID> = [],
        intervalSeconds: Double = 5 * 60,
        durationMinutes: Int = 6 * 60 + 30,
        volume: Float = 0.60,
        shuffle: Bool = true,
        autoStartWithSleepTimer: Bool = false
    ) {
        self.selectedCardIDs = selectedCardIDs
        self.intervalSeconds = Self.clampedInterval(intervalSeconds)
        self.durationMinutes = Self.clampedDuration(durationMinutes)
        self.volume = Self.clampedVolume(volume)
        self.shuffle = shuffle
        self.autoStartWithSleepTimer = autoStartWithSleepTimer
    }

    public func normalized(availableCardIDs: Set<UUID>? = nil) -> Self {
        var copy = self
        if let availableCardIDs {
            copy.selectedCardIDs.formIntersection(availableCardIDs)
        }
        copy.intervalSeconds = Self.clampedInterval(copy.intervalSeconds)
        copy.durationMinutes = Self.clampedDuration(copy.durationMinutes)
        copy.volume = Self.clampedVolume(copy.volume)
        return copy
    }

    private static func clampedInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 5 * 60 }
        return min(max(value, 1), 60 * 60)
    }

    private static func clampedDuration(_ value: Int) -> Int {
        min(max(value, 1), 12 * 60)
    }

    private static func clampedVolume(_ value: Float) -> Float {
        guard value.isFinite else { return 0.60 }
        return min(max(value, 0), 1)
    }
}
