import Combine
import Foundation

enum MandatoryDailyFlowStep: String, Codable, Equatable, Sendable {
    case morningMood
    case morningPVT
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
        case .morningPVT: 2
        case .morningTest: 3
        case .morningRecord: 4
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
        case .morningPVT: "PVT"
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
    var morningPVTCompletedAt: Date?
    var morningPVTResultID: UUID?
    var morningPVTWasSkipped: Bool?
    var morningTestCompletedAt: Date?
    var morningTestResultID: UUID?
    /// `true` only when waking from the mandatory night timer created this
    /// morning flow. Optional keeps existing persisted v2 records decodable.
    var isNightTimerHandoff: Bool?
    var updatedAt: Date
    var completedAt: Date?

    init(
        step: MandatoryDailyFlowStep,
        targetSleepSessionID: UUID? = nil,
        pendingMood: SleepMood? = nil,
        pendingNote: String = "",
        morningPVTCompletedAt: Date? = nil,
        morningPVTResultID: UUID? = nil,
        morningPVTWasSkipped: Bool = false,
        morningTestCompletedAt: Date? = nil,
        morningTestResultID: UUID? = nil,
        isNightTimerHandoff: Bool = false,
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.step = step
        self.targetSleepSessionID = targetSleepSessionID
        self.pendingMood = pendingMood
        self.pendingNote = pendingNote
        self.morningPVTCompletedAt = morningPVTCompletedAt
        self.morningPVTResultID = morningPVTResultID
        self.morningPVTWasSkipped = morningPVTWasSkipped
        self.morningTestCompletedAt = morningTestCompletedAt
        self.morningTestResultID = morningTestResultID
        self.isNightTimerHandoff = isNightTimerHandoff
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

struct MandatoryDailyFlowContext: Identifiable, Equatable, Sendable {
    let profileID: String
    let period: DailyFlowPeriod
    let targetDay: Date
    let flowID: String
    let schedule: DailyFlowSchedule
    let isDemo: Bool

    init(
        profileID: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        schedule: DailyFlowSchedule = .default
    ) {
        self.profileID = profileID
        self.schedule = schedule
        self.isDemo = false
        self.period = DailyFlowPeriod(
            date: now,
            calendar: calendar,
            schedule: schedule
        )
        let resolvedTargetDay: Date
        switch period {
        case .morning:
            resolvedTargetDay = DailyFlowPeriod.morningFlowDay(
                containing: now,
                calendar: calendar,
                schedule: schedule
            )
        case .night:
            resolvedTargetDay = DailyFlowPeriod.nightFlowDay(
                containing: now,
                calendar: calendar,
                schedule: schedule
            )
        }
        self.targetDay = resolvedTargetDay
        self.flowID = MandatoryDailyFlowStore.flowID(
            period: period,
            targetDay: resolvedTargetDay,
            calendar: calendar
        )
    }

    init(
        profileID: String,
        period: DailyFlowPeriod,
        targetDay: Date,
        calendar: Calendar = .current,
        schedule: DailyFlowSchedule = .default
    ) {
        let normalizedDay = calendar.startOfDay(for: targetDay)
        self.profileID = profileID
        self.period = period
        self.targetDay = normalizedDay
        self.schedule = schedule
        self.isDemo = false
        self.flowID = MandatoryDailyFlowStore.flowID(
            period: period,
            targetDay: normalizedDay,
            calendar: calendar
        )
    }

    init(
        profileID: String,
        demoPeriod: DailyFlowPeriod,
        now: Date = Date(),
        calendar: Calendar = .current,
        schedule: DailyFlowSchedule = .default
    ) {
        self.profileID = profileID
        self.period = demoPeriod
        self.targetDay = calendar.startOfDay(for: now)
        self.schedule = schedule
        self.isDemo = true
        self.flowID = "demo.\(demoPeriod == .morning ? "morning" : "night").\(UUID().uuidString)"
    }

    var id: String {
        "\(profileID)|\(flowID)"
    }

}

@MainActor
final class MandatoryDailyFlowStore: ObservableObject {
    @Published private(set) var progressByFlowID: [String: MandatoryDailyFlowProgress]
    @Published private(set) var errorMessage: String?

    // v2 intentionally starts with a clean daily-flow ledger. The previous
    // behavior marked a night flow complete as soon as its timer started,
    // which can otherwise suppress the corrected wake-up flow indefinitely.
    private static let profileKeyPrefix = "Sleeper.MandatoryDailyFlowStore.profile.v2"
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

    func restart(
        _ context: MandatoryDailyFlowContext,
        at step: MandatoryDailyFlowStep,
        targetSleepSessionID: UUID? = nil
    ) {
        guard Self.normalizedProfileID(context.profileID) == profileID else { return }
        progressByFlowID[context.flowID] = MandatoryDailyFlowProgress(
            step: step,
            targetSleepSessionID: targetSleepSessionID
        )
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

    func markMorningTestCompleted(
        _ context: MandatoryDailyFlowContext,
        resultID: UUID
    ) {
        guard var progress = progress(for: context) else { return }
        let completedAt = Date()
        progress.morningTestCompletedAt = completedAt
        progress.morningTestResultID = resultID
        progress.updatedAt = completedAt
        progressByFlowID[context.flowID] = progress
        persist()
    }

    func markMorningPVTCompleted(
        _ context: MandatoryDailyFlowContext,
        resultID: UUID
    ) {
        guard var progress = progress(for: context) else { return }
        let completedAt = Date()
        progress.morningPVTCompletedAt = completedAt
        progress.morningPVTResultID = resultID
        progress.morningPVTWasSkipped = false
        progress.updatedAt = completedAt
        progressByFlowID[context.flowID] = progress
        persist()
    }

    func markMorningPVTSkipped(_ context: MandatoryDailyFlowContext) {
        guard var progress = progress(for: context) else { return }
        let completedAt = Date()
        progress.morningPVTCompletedAt = completedAt
        progress.morningPVTResultID = nil
        progress.morningPVTWasSkipped = true
        progress.updatedAt = completedAt
        progressByFlowID[context.flowID] = progress
        persist()
    }

    /// Returns the latest morning flow created by a completed night timer.
    /// The handoff must survive later time boundaries so reopening the app can
    /// never route past an unfinished mood/test/record sequence.
    func latestIncompleteMorningHandoff(
        profileID requestedProfileID: String,
        schedule: DailyFlowSchedule,
        calendar: Calendar = .current
    ) -> MandatoryDailyFlowContext? {
        guard Self.normalizedProfileID(requestedProfileID) == profileID else {
            return nil
        }

        var latest: (flowID: String, targetDay: Date, updatedAt: Date)?
        for (flowID, progress) in progressByFlowID {
            guard flowID.hasPrefix("morning."),
                  progress.step != .completed,
                  progress.isNightTimerHandoff == true,
                  let targetDay = Self.targetDay(fromMorningFlowID: flowID, calendar: calendar) else {
                continue
            }

            if let latest, progress.updatedAt <= latest.updatedAt { continue }
            latest = (flowID, targetDay, progress.updatedAt)
        }

        guard let latest else { return nil }
        if supersedeIncompleteMorningHandoffs(except: latest.flowID) {
            persist()
        }
        return MandatoryDailyFlowContext(
            profileID: requestedProfileID,
            period: .morning,
            targetDay: latest.targetDay,
            calendar: calendar,
            schedule: schedule
        )
    }

    /// Starts the morning flow for the exact session that was just saved by
    /// the preceding night flow. A fresh progress value prevents an earlier
    /// completion or test result for the same flow day from skipping steps.
    func beginMorningHandoff(
        _ context: MandatoryDailyFlowContext,
        targetSleepSessionID: UUID
    ) {
        guard context.period == .morning,
              Self.normalizedProfileID(context.profileID) == profileID else {
            return
        }

        _ = supersedeIncompleteMorningHandoffs(except: context.flowID)
        progressByFlowID[context.flowID] = MandatoryDailyFlowProgress(
            step: .morningMood,
            targetSleepSessionID: targetSleepSessionID,
            isNightTimerHandoff: true
        )
        persist()
    }

    func complete(_ context: MandatoryDailyFlowContext) {
        advance(context, to: .completed)
    }

    /// Only the most recently saved sleep should own an unfinished morning
    /// handoff. Older leftovers are completed so they cannot reappear after
    /// the current flow finishes.
    private func supersedeIncompleteMorningHandoffs(
        except retainedFlowID: String,
        at completedAt: Date = Date()
    ) -> Bool {
        let supersededFlowIDs = progressByFlowID.keys.filter { flowID in
            guard flowID != retainedFlowID,
                  flowID.hasPrefix("morning."),
                  let progress = progressByFlowID[flowID] else {
                return false
            }
            return progress.step != .completed
                && progress.isNightTimerHandoff == true
        }

        for flowID in supersededFlowIDs {
            guard var progress = progressByFlowID[flowID] else { continue }
            progress.step = .completed
            progress.updatedAt = completedAt
            progress.completedAt = completedAt
            progressByFlowID[flowID] = progress
        }
        return !supersededFlowIDs.isEmpty
    }
}

fileprivate extension MandatoryDailyFlowStore {
    struct PersistedState: Codable {
        var schemaVersion: Int
        var progressByFlowID: [String: MandatoryDailyFlowProgress]

        init(
            schemaVersion: Int = 2,
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
        let periodKey: String
        switch period {
        case .morning:
            periodKey = "morning"
        case .night:
            periodKey = "night"
        }
        return "\(periodKey).\(dateKey)"
    }

    nonisolated static func targetDay(
        fromMorningFlowID flowID: String,
        calendar: Calendar
    ) -> Date? {
        let prefix = "morning."
        guard flowID.hasPrefix(prefix) else { return nil }

        let components = flowID.dropFirst(prefix.count).split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return nil
        }

        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        return calendar.date(from: dateComponents).map(calendar.startOfDay(for:))
    }
}
