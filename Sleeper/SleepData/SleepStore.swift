import Combine
import Foundation

@MainActor
public final class SleepStore: ObservableObject {
    @Published public private(set) var sessions: [SleepSession]
    @Published public private(set) var activeTimerStartedAt: Date?
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isSyncing: Bool

    private static let legacyPersistenceKey = "Sleeper.SleepStore.state.v1"
    private static let profileKeyPrefix = "Sleeper.SleepStore.profile.v1"
    private static let guestProfileID = "local-demo-user"

    private let defaults: UserDefaults
    private let healthKitManager: HealthKitManager
    private var profileID: String
    private var deletions: [SleepDeletionTombstone]
    private var firestoreService: SleepFirestoreService?
    private var cloudWriteTail: Task<Void, Never>?
    private var syncOperationCount = 0

    public init() {
        let defaults = UserDefaults.standard
        let profileID = Self.guestProfileID
        let profileKey = Self.persistenceKey(for: profileID)
        let hasProfileState = defaults.data(forKey: profileKey) != nil
        let loadResult = Self.loadPersistedState(
            from: defaults,
            key: hasProfileState ? profileKey : Self.legacyPersistenceKey
        )
        let normalizedTimer = Self.normalizedTimerStart(loadResult.state.activeTimerStartedAt)

        self.defaults = defaults
        self.healthKitManager = HealthKitManager()
        self.profileID = profileID
        self.sessions = loadResult.state.sessions.sorted(by: Self.sessionSort)
        self.activeTimerStartedAt = normalizedTimer
        self.statusMessage = normalizedTimer == nil
            ? nil
            : "前回開始した睡眠計測を継続しています。"
        self.errorMessage = loadResult.errorMessage
            ?? (loadResult.state.activeTimerStartedAt != nil && normalizedTimer == nil
                ? "24時間以上前、または未来の睡眠タイマーをリセットしました。"
                : nil)
        self.isSyncing = false
        self.deletions = loadResult.state.deletions

        if !hasProfileState,
           defaults.data(forKey: Self.legacyPersistenceKey) != nil {
            persistLocally()
            defaults.removeObject(forKey: Self.legacyPersistenceKey)
        } else if loadResult.state.activeTimerStartedAt != normalizedTimer {
            persistLocally()
        }
    }

    /// Switches the local cache before a user can see or synchronize records.
    /// Guest data and each Firebase UID intentionally use separate storage.
    public func activateProfile(_ requestedProfileID: String) {
        let normalizedProfileID = Self.normalizedProfileID(requestedProfileID)
        guard normalizedProfileID != profileID else { return }

        disconnectFirestore(showStatus: false)
        persistLocally()
        profileID = normalizedProfileID

        let loadResult = Self.loadPersistedState(
            from: defaults,
            key: Self.persistenceKey(for: normalizedProfileID)
        )
        let normalizedTimer = Self.normalizedTimerStart(loadResult.state.activeTimerStartedAt)
        sessions = loadResult.state.sessions.sorted(by: Self.sessionSort)
        activeTimerStartedAt = normalizedTimer
        deletions = loadResult.state.deletions
        statusMessage = normalizedTimer == nil
            ? nil
            : "前回開始した睡眠計測を継続しています。"
        errorMessage = loadResult.errorMessage
            ?? (loadResult.state.activeTimerStartedAt != nil && normalizedTimer == nil
                ? "24時間以上前、または未来の睡眠タイマーをリセットしました。"
                : nil)

        if loadResult.state.activeTimerStartedAt != normalizedTimer {
            persistLocally()
        }
    }

    public func startTimer() {
        errorMessage = nil
        guard activeTimerStartedAt == nil else {
            statusMessage = "睡眠計測はすでに開始されています。"
            return
        }

        activeTimerStartedAt = Date()
        statusMessage = "睡眠計測を開始しました。おやすみなさい。"
        persistLocally()
    }

    @discardableResult
    public func stopTimer(targetMinutes: Int) -> SleepSession? {
        errorMessage = nil
        guard targetMinutes > 0 else {
            errorMessage = "目標睡眠時間を1分以上に設定してください。"
            return nil
        }
        guard let startDate = activeTimerStartedAt else {
            errorMessage = "開始中の睡眠計測がありません。"
            return nil
        }

        let endDate = Date()
        guard endDate > startDate else {
            errorMessage = "計測時間を確認できませんでした。もう一度お試しください。"
            return nil
        }
        guard endDate.timeIntervalSince(startDate) <= 24 * 60 * 60 else {
            activeTimerStartedAt = nil
            errorMessage = "24時間を超えた睡眠タイマーをリセットしました。必要な時間を手入力してください。"
            statusMessage = nil
            persistLocally()
            return nil
        }

        let session = SleepSession(
            startDate: startDate,
            endDate: endDate,
            targetMinutes: targetMinutes,
            source: .timer,
            createdAt: endDate,
            updatedAt: endDate
        )
        activeTimerStartedAt = nil
        save(session, message: "睡眠記録を保存しました。おはようございます。")
        return session
    }

    @discardableResult
    public func saveManual(
        startDate: Date,
        endDate: Date,
        targetMinutes: Int
    ) -> SleepSession? {
        errorMessage = nil
        guard targetMinutes > 0 else {
            errorMessage = "目標睡眠時間を1分以上に設定してください。"
            return nil
        }
        guard endDate > startDate else {
            errorMessage = "起床時刻は就寝時刻より後にしてください。"
            return nil
        }
        guard endDate <= Date().addingTimeInterval(5 * 60) else {
            errorMessage = "未来の起床時刻は記録できません。"
            return nil
        }
        guard endDate.timeIntervalSince(startDate) < 20 * 60 * 60 else {
            errorMessage = "20時間以上の記録は入力ミスの可能性があります。就寝・起床時刻を確認してください。"
            return nil
        }

        let now = Date()
        let session = SleepSession(
            startDate: startDate,
            endDate: endDate,
            targetMinutes: targetMinutes,
            source: .manual,
            createdAt: now,
            updatedAt: now
        )
        save(session, message: "睡眠記録を追加しました。")
        return session
    }

    public func session(id: UUID) -> SleepSession? {
        sessions.first { $0.id == id }
    }

    public func updateReflection(id: UUID, mood: SleepMood?, note: String) {
        errorMessage = nil
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            errorMessage = "更新する睡眠記録が見つかりません。"
            return
        }

        var updatedSession = sessions[index]
        updatedSession.mood = mood
        updatedSession.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSession.updatedAt = timestamp(after: updatedSession.updatedAt)
        sessions[index] = updatedSession
        sessions.sort(by: Self.sessionSort)
        deletions.removeAll { $0.id == id }
        statusMessage = "ふりかえりを保存しました。"
        persistLocally()
        enqueueCloudMutation(.upsert(updatedSession))
    }

    public func delete(id: UUID) {
        errorMessage = nil
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            errorMessage = "削除する睡眠記録が見つかりません。"
            return
        }

        let removed = sessions.remove(at: index)
        let deletion = SleepDeletionTombstone(
            id: id,
            updatedAt: timestamp(after: removed.updatedAt)
        )
        deletions.removeAll { $0.id == id }
        deletions.append(deletion)
        statusMessage = "睡眠記録を削除しました。"
        persistLocally()
        enqueueCloudMutation(.delete(deletion))
    }

    /// Removes all local sessions in one state update and queues tombstones in
    /// one cloud operation. This keeps large histories from repeatedly encoding
    /// the complete store on the main actor.
    public func deleteAll() {
        errorMessage = nil
        guard !sessions.isEmpty else { return }

        let removedSessions = sessions
        sessions = []

        let removedIDs = Set(removedSessions.map(\.id))
        deletions.removeAll { removedIDs.contains($0.id) }
        let newDeletions = removedSessions.map { session in
            SleepDeletionTombstone(
                id: session.id,
                updatedAt: timestamp(after: session.updatedAt)
            )
        }
        deletions.append(contentsOf: newDeletions)
        deletions.sort { $0.updatedAt > $1.updatedAt }

        statusMessage = "すべての睡眠記録を削除しました。"
        persistLocally()
        enqueueCloudMutation(.deleteMany(newDeletions))
    }

    @discardableResult
    public func importLastNightFromHealthKit(targetMinutes: Int) async -> SleepSession? {
        errorMessage = nil
        guard targetMinutes > 0 else {
            errorMessage = "目標睡眠時間を1分以上に設定してください。"
            return nil
        }

        beginSyncOperation()
        defer { endSyncOperation() }

        do {
            try await healthKitManager.requestAuthorization()
            let healthData = try await healthKitManager.fetchLastNightSleepData()
            let now = Date()

            let importedSession: SleepSession
            if let index = matchingHealthSessionIndex(for: healthData) {
                let existing = sessions[index]
                importedSession = SleepSession(
                    id: existing.id,
                    startDate: healthData.startDate,
                    endDate: healthData.endDate,
                    targetMinutes: targetMinutes,
                    source: .healthKit,
                    mood: existing.mood,
                    note: existing.note,
                    stages: healthData.stages,
                    externalIdentifier: healthData.externalIdentifier,
                    createdAt: existing.createdAt,
                    updatedAt: timestamp(after: existing.updatedAt)
                )
            } else {
                importedSession = SleepSession(
                    startDate: healthData.startDate,
                    endDate: healthData.endDate,
                    targetMinutes: targetMinutes,
                    source: .healthKit,
                    stages: healthData.stages,
                    externalIdentifier: healthData.externalIdentifier,
                    createdAt: now,
                    updatedAt: now
                )
            }

            save(
                importedSession,
                message: "\(healthData.sourceName) の睡眠記録を取り込みました。"
            )
            return importedSession
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            return nil
        }
    }

    /// Reads HealthKit's State of Mind for a selected day without mutating the
    /// app's own reflection. The HealthKit value is richer than `SleepMood`, so
    /// History presents both sources instead of silently reducing or overwriting it.
    public func healthKitStateOfMind(
        for day: Date,
        calendar: Calendar = .current
    ) async throws -> [HealthKitStateOfMindData] {
        try await healthKitManager.requestStateOfMindAuthorization()
        return try await healthKitManager.fetchStateOfMind(for: day, calendar: calendar)
    }

    public func connectFirestore(userID: String) async {
        errorMessage = nil
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty, !normalizedUserID.contains("/") else {
            firestoreService = nil
            cloudWriteTail?.cancel()
            cloudWriteTail = nil
            errorMessage = "クラウド同期のユーザー情報が正しくありません。"
            return
        }

        cloudWriteTail?.cancel()
        cloudWriteTail = nil
        let service = SleepFirestoreService(userID: normalizedUserID)
        firestoreService = service
        beginSyncOperation()
        defer { endSyncOperation() }

        do {
            let synchronized = try await service.synchronize(
                localSessions: sessions,
                localDeletions: deletions
            )
            guard firestoreService === service else { return }

            // A local edit can happen while Firestore is awaiting the network.
            // Merge once more before publishing so such an edit is never lost.
            let currentLocal = SleepCloudSnapshot(
                sessions: sessions,
                deletions: deletions
            )
            let finalSnapshot = SleepFirestoreService.merge(
                local: currentLocal,
                remote: synchronized
            )
            sessions = finalSnapshot.sessions.sorted(by: Self.sessionSort)
            deletions = finalSnapshot.deletions
            persistLocally()
            statusMessage = "クラウド同期が完了しました。"
        } catch {
            guard firestoreService === service else { return }
            // The service is kept so a later local edit can retry its own write.
            errorMessage = "クラウドに接続できませんでした。端末内の記録はそのまま使えます（\(error.localizedDescription)）。"
            statusMessage = nil
        }
    }

    public func disconnectFirestore() {
        disconnectFirestore(showStatus: true)
    }

    private func disconnectFirestore(showStatus: Bool) {
        let wasConnected = firestoreService != nil
        firestoreService = nil
        cloudWriteTail?.cancel()
        cloudWriteTail = nil
        if wasConnected {
            errorMessage = nil
            statusMessage = showStatus
                ? "クラウド同期を解除しました。端末内の記録は保持されています。"
                : nil
        }
    }
}

private extension SleepStore {
    enum CloudMutation {
        case upsert(SleepSession)
        case delete(SleepDeletionTombstone)
        case deleteMany([SleepDeletionTombstone])
    }

    struct PersistedState: Codable {
        var schemaVersion: Int
        var sessions: [SleepSession]
        var activeTimerStartedAt: Date?
        var deletions: [SleepDeletionTombstone]

        init(
            schemaVersion: Int = 1,
            sessions: [SleepSession] = [],
            activeTimerStartedAt: Date? = nil,
            deletions: [SleepDeletionTombstone] = []
        ) {
            self.schemaVersion = schemaVersion
            self.sessions = sessions
            self.activeTimerStartedAt = activeTimerStartedAt
            self.deletions = deletions
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case sessions
            case activeTimerStartedAt
            case deletions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            sessions = try container.decodeIfPresent([SleepSession].self, forKey: .sessions) ?? []
            activeTimerStartedAt = try container.decodeIfPresent(Date.self, forKey: .activeTimerStartedAt)
            deletions = try container.decodeIfPresent(
                [SleepDeletionTombstone].self,
                forKey: .deletions
            ) ?? []
        }
    }

    struct LoadResult {
        let state: PersistedState
        let errorMessage: String?
    }

    static func loadPersistedState(from defaults: UserDefaults, key: String) -> LoadResult {
        guard let data = defaults.data(forKey: key) else {
            return LoadResult(state: PersistedState(), errorMessage: nil)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            let state = try decoder.decode(PersistedState.self, from: data)
            return LoadResult(state: state, errorMessage: nil)
        } catch {
            // Early prototypes may have persisted just an array of sessions.
            if let legacySessions = try? decoder.decode([SleepSession].self, from: data) {
                return LoadResult(
                    state: PersistedState(sessions: legacySessions),
                    errorMessage: nil
                )
            }
            return LoadResult(
                state: PersistedState(),
                errorMessage: "端末内の睡眠記録を読み込めなかったため、新しい保存領域を開始しました。"
            )
        }
    }

    func persistLocally() {
        let state = PersistedState(
            sessions: sessions,
            activeTimerStartedAt: activeTimerStartedAt,
            deletions: deletions
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]

        do {
            defaults.set(try encoder.encode(state), forKey: persistenceKey)
        } catch {
            errorMessage = "端末内への保存に失敗しました（\(error.localizedDescription)）。"
        }
    }

    func save(_ session: SleepSession, message: String) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort(by: Self.sessionSort)
        deletions.removeAll { $0.id == session.id }
        statusMessage = message
        persistLocally()
        enqueueCloudMutation(.upsert(session))
    }

    func matchingHealthSessionIndex(for healthData: HealthKitSleepData) -> Int? {
        if let exactMatch = sessions.firstIndex(where: {
            $0.source == .healthKit
                && $0.externalIdentifier == healthData.externalIdentifier
        }) {
            return exactMatch
        }

        let calendar = Calendar.current
        return sessions.indices
            .filter { index in
                let session = sessions[index]
                guard session.source == .healthKit else { return false }
                guard calendar.isDate(session.endDate, inSameDayAs: healthData.endDate) else {
                    return false
                }
                let overlapStart = max(session.startDate, healthData.startDate)
                let overlapEnd = min(session.endDate, healthData.endDate)
                let overlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
                let shorterDuration = min(
                    session.endDate.timeIntervalSince(session.startDate),
                    healthData.endDate.timeIntervalSince(healthData.startDate)
                )
                return overlap >= min(60 * 60, shorterDuration * 0.5)
            }
            .max { lhs, rhs in
                let lhsDifference = abs(
                    sessions[lhs].startDate.timeIntervalSince(healthData.startDate)
                )
                let rhsDifference = abs(
                    sessions[rhs].startDate.timeIntervalSince(healthData.startDate)
                )
                return lhsDifference > rhsDifference
            }
    }

    func enqueueCloudMutation(_ mutation: CloudMutation) {
        guard let service = firestoreService else { return }
        let previousTask = cloudWriteTail

        let task = Task { @MainActor [weak self, weak service] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            guard let self, let service, self.firestoreService === service else { return }

            do {
                switch mutation {
                case .upsert(let session):
                    try await service.upsert(session: session)
                case .delete(let deletion):
                    try await service.markDeleted(deletion)
                case .deleteMany(let deletions):
                    try await service.markDeleted(deletions)
                }
            } catch {
                guard self.firestoreService === service else { return }
                self.errorMessage = "クラウドへの反映に失敗しました。端末内には保存されています（\(error.localizedDescription)）。"
            }
        }
        cloudWriteTail = task
    }

    func beginSyncOperation() {
        syncOperationCount += 1
        isSyncing = true
    }

    func endSyncOperation() {
        syncOperationCount = max(0, syncOperationCount - 1)
        isSyncing = syncOperationCount > 0
    }

    func timestamp(after previous: Date) -> Date {
        let now = Date()
        return now > previous ? now : previous.addingTimeInterval(0.001)
    }

    static func sessionSort(_ lhs: SleepSession, _ rhs: SleepSession) -> Bool {
        if lhs.endDate == rhs.endDate {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.endDate > rhs.endDate
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

    static func normalizedTimerStart(_ startDate: Date?) -> Date? {
        guard let startDate else { return nil }
        let elapsed = Date().timeIntervalSince(startDate)
        guard elapsed >= 0, elapsed <= 24 * 60 * 60 else { return nil }
        return startDate
    }
}
