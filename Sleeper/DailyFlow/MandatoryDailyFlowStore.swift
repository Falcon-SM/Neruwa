import Combine
import Foundation

enum MandatoryDailyFlowStep: String, Codable, Equatable, Sendable {
    case morningMood
    case morningTest
    case morningRecord
    case nightJournal
    case nightStudy
    case nightAudio
    case nightSleep
    case completed

    var number: Int {
        switch self {
        case .morningMood: 1
        case .morningTest: 2
        case .morningRecord: 3
        case .nightJournal: 1
        case .nightStudy: 2
        case .nightAudio: 3
        case .nightSleep: 4
        case .completed: 0
        }
    }

    var title: String {
        switch self {
        case .morningMood: "気分"
        case .morningTest: "点字テスト"
        case .morningRecord: "記録"
        case .nightJournal: "日記"
        case .nightStudy: "点字学習"
        case .nightAudio: "音声設定"
        case .nightSleep: "睡眠記録"
        case .completed: "完了"
        }
    }
}

struct MandatoryDailyFlowProgress: Codable, Equatable, Sendable {
    var step: MandatoryDailyFlowStep
    var targetSleepSessionID: UUID?
    var pendingMood: SleepMood?
    var pendingNote: String
    var morningTestCompletedAt: Date?
    var updatedAt: Date
    var completedAt: Date?

    init(
        step: MandatoryDailyFlowStep,
        targetSleepSessionID: UUID? = nil,
        pendingMood: SleepMood? = nil,
        pendingNote: String = "",
        morningTestCompletedAt: Date? = nil,
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.step = step
        self.targetSleepSessionID = targetSleepSessionID
        self.pendingMood = pendingMood
        self.pendingNote = pendingNote
        self.morningTestCompletedAt = morningTestCompletedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

struct MandatoryDailyFlowContext: Identifiable, Equatable, Sendable {
    let profileID: String
    let period: DailyFlowPeriod
    let targetDay: Date
    let flowID: String

    init(
        profileID: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.profileID = profileID
        self.period = DailyFlowPeriod(date: now, calendar: calendar)
        let resolvedTargetDay: Date
        switch period {
        case .morning:
            resolvedTargetDay = calendar.startOfDay(for: now)
        case .night:
            resolvedTargetDay = DailyFlowPeriod.nightFlowDay(
                containing: now,
                calendar: calendar
            )
        }
        self.targetDay = resolvedTargetDay
        self.flowID = MandatoryDailyFlowStore.flowID(
            period: period,
            targetDay: resolvedTargetDay,
            calendar: calendar
        )
    }

    var id: String {
        "\(profileID)|\(flowID)"
    }

}

@MainActor
final class MandatoryDailyFlowStore: ObservableObject {
    @Published private(set) var progressByFlowID: [String: MandatoryDailyFlowProgress]
    @Published private(set) var errorMessage: String?

    private static let profileKeyPrefix = "Sleeper.MandatoryDailyFlowStore.profile.v1"
    private static let guestProfileID = "local-demo-user"
    private static let maximumStoredFlows = 180

    private let defaults: UserDefaults
    private var profileID: String

    init(defaults: UserDefaults = .standard) {
        let profileID = Self.guestProfileID
        let result = Self.load(
            defaults: defaults,
            key: Self.persistenceKey(for: profileID)
        )
        self.defaults = defaults
        self.profileID = profileID
        self.progressByFlowID = result.progressByFlowID
        self.errorMessage = result.errorMessage
    }

    func activateProfile(_ requestedProfileID: String) {
        let normalized = Self.normalizedProfileID(requestedProfileID)
        guard normalized != profileID else { return }

        profileID = normalized
        let result = Self.load(
            defaults: defaults,
            key: Self.persistenceKey(for: normalized)
        )
        progressByFlowID = result.progressByFlowID
        errorMessage = result.errorMessage
    }

    func progress(for context: MandatoryDailyFlowContext) -> MandatoryDailyFlowProgress? {
        guard Self.normalizedProfileID(context.profileID) == profileID else { return nil }
        return progressByFlowID[context.flowID]
    }

    func isCompleted(_ context: MandatoryDailyFlowContext) -> Bool {
        progress(for: context)?.step == .completed
    }

    @discardableResult
    func ensureProgress(
        for context: MandatoryDailyFlowContext,
        initialStep: MandatoryDailyFlowStep,
        targetSleepSessionID: UUID?
    ) -> MandatoryDailyFlowProgress {
        if let existing = progress(for: context) {
            return existing
        }

        let progress = MandatoryDailyFlowProgress(
            step: initialStep,
            targetSleepSessionID: targetSleepSessionID
        )
        progressByFlowID[context.flowID] = progress
        persist()
        return progress
    }

    func advance(
        _ context: MandatoryDailyFlowContext,
        to step: MandatoryDailyFlowStep,
        targetSleepSessionID: UUID? = nil
    ) {
        guard var progress = progress(for: context) else { return }
        progress.step = step
        if let targetSleepSessionID {
            progress.targetSleepSessionID = targetSleepSessionID
        }
        progress.updatedAt = Date()
        progress.completedAt = step == .completed ? progress.updatedAt : nil
        progressByFlowID[context.flowID] = progress
        persist()
    }

    func savePendingMorningReflection(
        _ context: MandatoryDailyFlowContext,
        mood: SleepMood,
        note: String
    ) {
        guard var progress = progress(for: context) else { return }
        progress.pendingMood = mood
        progress.pendingNote = String(
            note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)
        )
        progress.updatedAt = Date()
        progressByFlowID[context.flowID] = progress
        persist()
    }

    func setTargetSleepSessionID(
        _ context: MandatoryDailyFlowContext,
        sessionID: UUID
    ) {
        guard var progress = progress(for: context) else { return }
        progress.targetSleepSessionID = sessionID
        progress.updatedAt = Date()
        progressByFlowID[context.flowID] = progress
        persist()
    }

    func markMorningTestCompleted(_ context: MandatoryDailyFlowContext) {
        guard var progress = progress(for: context) else { return }
        let completedAt = Date()
        progress.morningTestCompletedAt = completedAt
        progress.updatedAt = completedAt
        progressByFlowID[context.flowID] = progress
        persist()
    }

    func complete(_ context: MandatoryDailyFlowContext) {
        advance(context, to: .completed)
    }
}

fileprivate extension MandatoryDailyFlowStore {
    struct PersistedState: Codable {
        var schemaVersion: Int
        var progressByFlowID: [String: MandatoryDailyFlowProgress]

        init(
            schemaVersion: Int = 1,
            progressByFlowID: [String: MandatoryDailyFlowProgress]
        ) {
            self.schemaVersion = schemaVersion
            self.progressByFlowID = progressByFlowID
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case progressByFlowID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            progressByFlowID = try container.decodeIfPresent(
                [String: MandatoryDailyFlowProgress].self,
                forKey: .progressByFlowID
            ) ?? [:]
        }
    }

    struct LoadResult {
        let progressByFlowID: [String: MandatoryDailyFlowProgress]
        let errorMessage: String?
    }

    static func load(defaults: UserDefaults, key: String) -> LoadResult {
        guard let data = defaults.data(forKey: key) else {
            return LoadResult(progressByFlowID: [:], errorMessage: nil)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            let state = try decoder.decode(PersistedState.self, from: data)
            return LoadResult(
                progressByFlowID: normalized(state.progressByFlowID),
                errorMessage: nil
            )
        } catch {
            return LoadResult(
                progressByFlowID: [:],
                errorMessage: "日次フローの進捗を読み込めませんでした。今回の進捗は引き続き保存できます。"
            )
        }
    }

    func persist() {
        progressByFlowID = Self.normalized(progressByFlowID)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        do {
            let state = PersistedState(progressByFlowID: progressByFlowID)
            defaults.set(try encoder.encode(state), forKey: persistenceKey)
            errorMessage = nil
        } catch {
            errorMessage = "日次フローの進捗を端末に保存できませんでした（\(error.localizedDescription)）。"
        }
    }

    static func normalized(
        _ progressByFlowID: [String: MandatoryDailyFlowProgress]
    ) -> [String: MandatoryDailyFlowProgress] {
        Dictionary(
            uniqueKeysWithValues: progressByFlowID
                .sorted { $0.value.updatedAt > $1.value.updatedAt }
                .prefix(maximumStoredFlows)
                .map { ($0.key, $0.value) }
        )
    }

    var persistenceKey: String {
        Self.persistenceKey(for: profileID)
    }

    static func persistenceKey(for profileID: String) -> String {
        "\(profileKeyPrefix).\(normalizedProfileID(profileID))"
    }

    static func normalizedProfileID(_ profileID: String) -> String {
        let trimmed = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? guestProfileID : trimmed
    }

    nonisolated static func flowID(
        period: DailyFlowPeriod,
        targetDay: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: targetDay)
        let dateKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let periodKey = period == .morning ? "morning" : "night"
        return "\(periodKey).\(dateKey)"
    }
}
