import Foundation
import HealthKit

public struct HealthKitSleepData: Hashable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let stages: SleepStageDurations
    public let externalIdentifier: String
    public let sourceName: String

    public init(
        startDate: Date,
        endDate: Date,
        stages: SleepStageDurations,
        externalIdentifier: String,
        sourceName: String
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.stages = stages
        self.externalIdentifier = externalIdentifier
        self.sourceName = sourceName
    }
}

/// A presentation-safe projection of HealthKit's State of Mind sample.
///
/// Keeping HealthKit framework types out of the view makes the selected-day
/// history UI easy to render and keeps iOS 18 availability checks in one place.
public struct HealthKitStateOfMindData: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public let valence: Double
    public let classification: String
    public let labels: [String]
    public let isDailyMood: Bool

    public init(
        id: UUID,
        date: Date,
        valence: Double,
        classification: String,
        labels: [String],
        isDailyMood: Bool
    ) {
        self.id = id
        self.date = date
        self.valence = min(max(valence, -1), 1)
        self.classification = classification
        self.labels = labels
        self.isDailyMood = isDailyMood
    }
}

public enum HealthKitManagerError: LocalizedError {
    case unavailable
    case sleepTypeUnavailable
    case stateOfMindUnavailable
    case authorizationFailed(String?)
    case queryFailed(String)
    case noSleepData

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "この端末ではヘルスケアを利用できません。"
        case .sleepTypeUnavailable:
            "ヘルスケアの睡眠データを読み込めません。"
        case .stateOfMindUnavailable:
            "このiOSではヘルスケアの心の状態を読み込めません。"
        case .authorizationFailed(let message):
            if let message, !message.isEmpty {
                "ヘルスケアへのアクセスを許可できませんでした（\(message)）。"
            } else {
                "ヘルスケアへのアクセスを許可できませんでした。"
            }
        case .queryFailed(let message):
            "ヘルスケアの読み込みに失敗しました（\(message)）。"
        case .noSleepData:
            "過去36時間に取り込める睡眠記録がありません。"
        }
    }
}

@MainActor
public final class HealthKitManager {
    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitManagerError.unavailable
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitManagerError.sleepTypeUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: [sleepType]) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: HealthKitManagerError.authorizationFailed(error?.localizedDescription)
                    )
                }
            }
        }
    }

    /// Requests read-only access to State of Mind separately from sleep data.
    /// HealthKit intentionally does not reveal whether read access was denied;
    /// a denied request therefore has the same empty-result fallback as a day
    /// with no logged state of mind.
    public func requestStateOfMindAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitManagerError.unavailable
        }
        guard #available(iOS 18.0, *) else {
            throw HealthKitManagerError.stateOfMindUnavailable
        }

        let stateOfMindType = HKObjectType.stateOfMindType()
        try await requestAuthorization(reading: [stateOfMindType])
    }

    /// Reads a 36-hour window and returns one coherent sleep episode from one source.
    /// Overlapping stage samples are normalized before their durations are totaled.
    public func fetchLastNightSleepData(referenceDate: Date = Date()) async throws -> HealthKitSleepData {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitManagerError.unavailable
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitManagerError.sleepTypeUnavailable
        }

        let windowEnd = referenceDate
        let windowStart = referenceDate.addingTimeInterval(-36 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart,
            end: windowEnd,
            options: []
        )
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        let samples = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKCategorySample], Error>) in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(
                        throwing: HealthKitManagerError.queryFailed(error.localizedDescription)
                    )
                    return
                }
                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }
            healthStore.execute(query)
        }

        guard let candidate = Self.bestCandidate(
            from: samples,
            windowStart: windowStart,
            windowEnd: windowEnd
        ) else {
            throw HealthKitManagerError.noSleepData
        }

        return HealthKitSleepData(
            startDate: candidate.startDate,
            endDate: candidate.endDate,
            stages: candidate.stages,
            externalIdentifier: candidate.externalIdentifier,
            sourceName: candidate.sourceName
        )
    }

    /// Returns State of Mind samples logged on the selected local calendar day.
    /// An empty result means either no data or read access was not granted.
    public func fetchStateOfMind(
        for day: Date,
        calendar: Calendar = .current
    ) async throws -> [HealthKitStateOfMindData] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitManagerError.unavailable
        }
        guard #available(iOS 18.0, *) else {
            throw HealthKitManagerError.stateOfMindUnavailable
        }
        guard let dayEnd = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: day)
        ) else {
            return []
        }

        let dayStart = calendar.startOfDay(for: day)
        let stateOfMindType = HKObjectType.stateOfMindType()
        let predicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: [.strictStartDate]
        )
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        let samples = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKStateOfMind], Error>) in
            let query = HKSampleQuery(
                sampleType: stateOfMindType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(
                        throwing: HealthKitManagerError.queryFailed(error.localizedDescription)
                    )
                    return
                }
                continuation.resume(returning: results as? [HKStateOfMind] ?? [])
            }
            healthStore.execute(query)
        }

        return samples.map { sample in
            HealthKitStateOfMindData(
                id: sample.uuid,
                date: sample.startDate,
                valence: sample.valence,
                classification: Self.localizedClassification(sample.valenceClassification),
                labels: sample.labels.map(Self.localizedLabel),
                isDailyMood: sample.kind == .dailyMood
            )
        }
    }

    private func requestAuthorization(reading types: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: types) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: HealthKitManagerError.authorizationFailed(error?.localizedDescription)
                    )
                }
            }
        }
    }
}

@available(iOS 18.0, *)
private extension HealthKitManager {
    static func localizedClassification(
        _ classification: HKStateOfMind.ValenceClassification
    ) -> String {
        switch classification {
        case .veryUnpleasant:
            "非常に不快"
        case .unpleasant:
            "不快"
        case .slightlyUnpleasant:
            "やや不快"
        case .neutral:
            "中立"
        case .slightlyPleasant:
            "やや快適"
        case .pleasant:
            "快適"
        case .veryPleasant:
            "非常に快適"
        @unknown default:
            "記録あり"
        }
    }

    static func localizedLabel(_ label: HKStateOfMind.Label) -> String {
        switch label {
        case .amazed: "驚き"
        case .amused: "愉快"
        case .angry: "怒り"
        case .anxious: "不安"
        case .ashamed: "恥ずかしい"
        case .brave: "勇敢"
        case .calm: "穏やか"
        case .content: "満ち足りた"
        case .disappointed: "失望"
        case .discouraged: "落胆"
        case .disgusted: "嫌悪"
        case .embarrassed: "当惑"
        case .excited: "興奮"
        case .frustrated: "いら立ち"
        case .grateful: "感謝"
        case .guilty: "罪悪感"
        case .happy: "幸せ"
        case .hopeless: "絶望"
        case .irritated: "苛立ち"
        case .jealous: "嫉妬"
        case .joyful: "喜び"
        case .lonely: "孤独"
        case .passionate: "情熱的"
        case .peaceful: "安らか"
        case .proud: "誇らしい"
        case .relieved: "安心"
        case .sad: "悲しい"
        case .scared: "怖い"
        case .stressed: "ストレス"
        case .surprised: "びっくり"
        case .worried: "心配"
        case .annoyed: "うんざり"
        case .confident: "自信"
        case .drained: "消耗"
        case .hopeful: "希望"
        case .indifferent: "無関心"
        case .overwhelmed: "圧倒された"
        case .satisfied: "満足"
        @unknown default: "その他"
        }
    }
}

private extension HealthKitManager {
    enum Stage: Int {
        case unspecified
        case core
        case rem
        case deep
        case awake

        var isAsleep: Bool { self != .awake }
    }

    struct StageInterval {
        let startDate: Date
        let endDate: Date
        let stage: Stage
        let sampleID: UUID
        let sourceIdentifier: String
        let sourceName: String
    }

    struct NormalizedSegment {
        let startDate: Date
        let endDate: Date
        let stage: Stage

        var duration: TimeInterval {
            endDate.timeIntervalSince(startDate)
        }
    }

    struct Candidate {
        let startDate: Date
        let endDate: Date
        let stages: SleepStageDurations
        let externalIdentifier: String
        let sourceName: String
        let asleepDuration: TimeInterval
    }

    static func bestCandidate(
        from samples: [HKCategorySample],
        windowStart: Date,
        windowEnd: Date
    ) -> Candidate? {
        let intervals = samples.compactMap { sample -> StageInterval? in
            guard let stage = stage(for: sample.value) else { return nil }

            let clippedStart = max(sample.startDate, windowStart)
            let clippedEnd = min(sample.endDate, windowEnd)
            guard clippedEnd > clippedStart else { return nil }

            let source = sample.sourceRevision.source
            let productType = sample.sourceRevision.productType ?? "unknown-device"
            let sourceIdentifier = "\(source.bundleIdentifier)|\(productType)"
            return StageInterval(
                startDate: clippedStart,
                endDate: clippedEnd,
                stage: stage,
                sampleID: sample.uuid,
                sourceIdentifier: sourceIdentifier,
                sourceName: source.name
            )
        }

        let sourceGroups = Dictionary(grouping: intervals, by: \.sourceIdentifier)
        let candidates = sourceGroups.values.flatMap { intervalsForSource in
            episodeGroups(from: intervalsForSource).compactMap(candidate(from:))
        }

        return candidates.max { lhs, rhs in
            if lhs.asleepDuration == rhs.asleepDuration {
                return lhs.endDate < rhs.endDate
            }
            return lhs.asleepDuration < rhs.asleepDuration
        }
    }

    static func stage(for rawValue: Int) -> Stage? {
        if rawValue == HKCategoryValueSleepAnalysis.awake.rawValue {
            return .awake
        }
        if rawValue == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
            return .deep
        }
        if rawValue == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
            return .rem
        }
        if rawValue == HKCategoryValueSleepAnalysis.asleepCore.rawValue {
            return .core
        }
        if rawValue == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
            return .unspecified
        }
        // Deliberately ignore in-bed samples; they often overlap the stage samples.
        return nil
    }

    static func episodeGroups(from intervals: [StageInterval]) -> [[StageInterval]] {
        let sorted = intervals.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
        guard let first = sorted.first else { return [] }

        let maximumEpisodeGap: TimeInterval = 2 * 60 * 60
        var result: [[StageInterval]] = []
        var current = [first]
        var currentEnd = first.endDate

        for interval in sorted.dropFirst() {
            if interval.startDate.timeIntervalSince(currentEnd) > maximumEpisodeGap {
                result.append(current)
                current = [interval]
                currentEnd = interval.endDate
            } else {
                current.append(interval)
                currentEnd = max(currentEnd, interval.endDate)
            }
        }
        result.append(current)
        return result
    }

    static func candidate(from intervals: [StageInterval]) -> Candidate? {
        let segments = normalizedSegments(from: intervals)
        guard
            let firstAsleep = segments.first(where: { $0.stage.isAsleep }),
            let lastAsleep = segments.last(where: { $0.stage.isAsleep })
        else {
            return nil
        }

        let sleepStart = firstAsleep.startDate
        let sleepEnd = lastAsleep.endDate
        let relevantSegments = segments.filter {
            $0.endDate > sleepStart && $0.startDate < sleepEnd
        }

        var awake: TimeInterval = 0
        var core: TimeInterval = 0
        var deep: TimeInterval = 0
        var rem: TimeInterval = 0
        var unspecified: TimeInterval = 0

        for segment in relevantSegments {
            switch segment.stage {
            case .awake:
                awake += segment.duration
            case .core:
                core += segment.duration
            case .deep:
                deep += segment.duration
            case .rem:
                rem += segment.duration
            case .unspecified:
                unspecified += segment.duration
            }
        }

        let asleepDuration = core + deep + rem + unspecified
        guard asleepDuration > 0 else { return nil }

        let firstSample = intervals
            .filter { $0.stage.isAsleep && $0.endDate > sleepStart && $0.startDate < sleepEnd }
            .min { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.sampleID.uuidString < rhs.sampleID.uuidString
                }
                return lhs.startDate < rhs.startDate
            }
        guard let firstSample else { return nil }

        let stages = SleepStageDurations(
            awakeMinutes: wholeMinutes(awake),
            coreMinutes: wholeMinutes(core),
            deepMinutes: wholeMinutes(deep),
            remMinutes: wholeMinutes(rem),
            unspecifiedMinutes: wholeMinutes(unspecified)
        )
        let identifier = "healthkit:\(firstSample.sourceIdentifier):\(firstSample.sampleID.uuidString)"

        return Candidate(
            startDate: sleepStart,
            endDate: sleepEnd,
            stages: stages,
            externalIdentifier: identifier,
            sourceName: firstSample.sourceName,
            asleepDuration: asleepDuration
        )
    }

    static func normalizedSegments(from intervals: [StageInterval]) -> [NormalizedSegment] {
        let boundaries = Array(
            Set(intervals.flatMap { [$0.startDate, $0.endDate] })
        ).sorted()
        guard boundaries.count > 1 else { return [] }

        return zip(boundaries, boundaries.dropFirst()).compactMap { startDate, endDate in
            guard endDate > startDate else { return nil }
            let activeStage = intervals
                .filter { $0.startDate < endDate && $0.endDate > startDate }
                .map(\.stage)
                .max { $0.rawValue < $1.rawValue }
            guard let activeStage else { return nil }
            return NormalizedSegment(
                startDate: startDate,
                endDate: endDate,
                stage: activeStage
            )
        }
    }

    static func wholeMinutes(_ duration: TimeInterval) -> Int {
        max(0, Int((duration / 60).rounded()))
    }
}
