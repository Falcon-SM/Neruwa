import AVFoundation
import Combine
import Foundation

@MainActor
public final class SleepLearningStore: NSObject, ObservableObject {
    @Published public private(set) var cards: [LearningCard]
    @Published public private(set) var results: [LearningTestResult]
    @Published public private(set) var settings: SleepLearningSettings
    @Published public private(set) var isPlaying: Bool
    @Published public private(set) var currentSpokenCard: LearningCard?
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var errorMessage: String?

    public static let defaultCards: [LearningCard] = [
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000001")!,
            prompt: "あ",
            answer: "1の点",
            speechText: "あ",
            languageCode: "ja-JP",
            brailleCells: [[1]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000002")!,
            prompt: "い",
            answer: "1・2の点",
            speechText: "い",
            languageCode: "ja-JP",
            brailleCells: [[1, 2]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000003")!,
            prompt: "う",
            answer: "1・4の点",
            speechText: "う",
            languageCode: "ja-JP",
            brailleCells: [[1, 4]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000004")!,
            prompt: "え",
            answer: "1・2・4の点",
            speechText: "え",
            languageCode: "ja-JP",
            brailleCells: [[1, 2, 4]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000005")!,
            prompt: "お",
            answer: "2・4の点",
            speechText: "お",
            languageCode: "ja-JP",
            brailleCells: [[2, 4]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000006")!,
            prompt: "か",
            answer: "1・6の点",
            speechText: "か",
            languageCode: "ja-JP",
            brailleCells: [[1, 6]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000007")!,
            prompt: "き",
            answer: "1・2・6の点",
            speechText: "き",
            languageCode: "ja-JP",
            brailleCells: [[1, 2, 6]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000008")!,
            prompt: "く",
            answer: "1・4・6の点",
            speechText: "く",
            languageCode: "ja-JP",
            brailleCells: [[1, 4, 6]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000009")!,
            prompt: "け",
            answer: "1・2・4・6の点",
            speechText: "け",
            languageCode: "ja-JP",
            brailleCells: [[1, 2, 4, 6]]
        ),
        LearningCard(
            id: UUID(uuidString: "B4A111E0-0000-4000-8000-000000000010")!,
            prompt: "こ",
            answer: "2・4・6の点",
            speechText: "こ",
            languageCode: "ja-JP",
            brailleCells: [[2, 4, 6]]
        )
    ]

    private static let profileKeyPrefix = "Sleeper.SleepLearningStore.profile.v1"
    private static let guestProfileID = "local-demo-user"
    private static let maximumQueuedUtterances = 120
    private static let maximumStoredResults = 100

    private let defaults: UserDefaults
    private let speechSynthesizer: AVSpeechSynthesizer
    private var profileID: String
    private var cardsByUtteranceID: [ObjectIdentifier: LearningCard] = [:]
    private var pendingUtteranceIDs: Set<ObjectIdentifier> = []
    private var audioSessionIsActive = false

    public override init() {
        let defaults = UserDefaults.standard
        let profileID = Self.guestProfileID
        let loadResult = Self.loadPersistedState(
            from: defaults,
            key: Self.persistenceKey(for: profileID)
        )

        self.defaults = defaults
        self.speechSynthesizer = AVSpeechSynthesizer()
        self.profileID = profileID
        self.cards = loadResult.state.cards
        self.results = loadResult.state.results
        self.settings = loadResult.state.settings
        self.isPlaying = false
        self.currentSpokenCard = nil
        self.statusMessage = nil
        self.errorMessage = loadResult.errorMessage

        super.init()
        speechSynthesizer.delegate = self
    }

    public var selectedCards: [LearningCard] {
        cards.filter { settings.selectedCardIDs.contains($0.id) }
    }

    public func activateProfile(_ requestedProfileID: String) {
        let normalizedProfileID = Self.normalizedProfileID(requestedProfileID)
        guard normalizedProfileID != profileID else { return }

        stopPlayback(showStatus: false)
        persistLocally()
        profileID = normalizedProfileID

        let loadResult = Self.loadPersistedState(
            from: defaults,
            key: Self.persistenceKey(for: normalizedProfileID)
        )
        cards = loadResult.state.cards
        results = loadResult.state.results
        settings = loadResult.state.settings
        currentSpokenCard = nil
        statusMessage = nil
        errorMessage = loadResult.errorMessage
    }

    public func card(id: UUID) -> LearningCard? {
        cards.first { $0.id == id }
    }

    @discardableResult
    public func addCard(
        prompt: String,
        answer: String,
        speechText: String,
        languageCode: String,
        brailleCells: [[Int]]? = nil
    ) -> LearningCard? {
        errorMessage = nil
        guard let card = validatedCard(
            id: UUID(),
            prompt: prompt,
            answer: answer,
            speechText: speechText,
            languageCode: languageCode,
            brailleCells: brailleCells
        ) else {
            return nil
        }

        if isPlaying {
            stopPlayback(showStatus: false)
        }
        cards.append(card)
        settings.selectedCardIDs.insert(card.id)
        settings = settings.normalized(availableCardIDs: Set(cards.map(\.id)))
        statusMessage = "学習カードを追加しました。"
        persistLocally()
        return card
    }

    public func updateCard(
        id: UUID,
        prompt: String,
        answer: String,
        speechText: String,
        languageCode: String,
        brailleCells: [[Int]]? = nil
    ) {
        errorMessage = nil
        guard let index = cards.firstIndex(where: { $0.id == id }) else {
            errorMessage = "更新する学習カードが見つかりません。"
            return
        }
        guard let updatedCard = validatedCard(
            id: id,
            prompt: prompt,
            answer: answer,
            speechText: speechText,
            languageCode: languageCode,
            brailleCells: brailleCells
        ) else {
            return
        }

        if isPlaying {
            stopPlayback(showStatus: false)
        }
        cards[index] = updatedCard
        statusMessage = "学習カードを更新しました。"
        persistLocally()
    }

    public func deleteCard(id: UUID) {
        errorMessage = nil
        guard cards.contains(where: { $0.id == id }) else {
            errorMessage = "削除する学習カードが見つかりません。"
            return
        }

        if isPlaying {
            stopPlayback(showStatus: false)
        }
        cards.removeAll { $0.id == id }
        settings.selectedCardIDs.remove(id)
        statusMessage = "学習カードを削除しました。"
        persistLocally()
    }

    public func toggleSelection(cardID: UUID) {
        errorMessage = nil
        guard cards.contains(where: { $0.id == cardID }) else {
            errorMessage = "選択する学習カードが見つかりません。"
            return
        }

        if isPlaying {
            stopPlayback(showStatus: false)
        }
        if settings.selectedCardIDs.contains(cardID) {
            settings.selectedCardIDs.remove(cardID)
        } else {
            settings.selectedCardIDs.insert(cardID)
        }
        statusMessage = "再生するカードを更新しました。"
        persistLocally()
    }

    public func updateSettings(_ newSettings: SleepLearningSettings) {
        errorMessage = nil
        if isPlaying {
            stopPlayback(showStatus: false)
        }
        settings = newSettings.normalized(availableCardIDs: Set(cards.map(\.id)))
        statusMessage = "睡眠学習の設定を保存しました。"
        persistLocally()
    }

    @discardableResult
    public func saveTestResult(
        correctAnswers: Int,
        totalQuestions: Int,
        sleepSessionID: UUID? = nil,
        wasSkipped: Bool = false
    ) -> LearningTestResult? {
        errorMessage = nil
        guard wasSkipped || totalQuestions > 0 else {
            errorMessage = "テストの問題数を確認できませんでした。"
            return nil
        }

        let result = LearningTestResult(
            correctAnswers: correctAnswers,
            totalQuestions: totalQuestions,
            cardIDs: settings.selectedCardIDs,
            sleepSessionID: sleepSessionID,
            wasSkipped: wasSkipped
        )
        results.insert(result, at: 0)
        if results.count > Self.maximumStoredResults {
            results.removeLast(results.count - Self.maximumStoredResults)
        }
        statusMessage = wasSkipped
            ? "朝のテストをスキップしました。"
            : "学習テストの結果を保存しました。"
        persistLocally()
        return result
    }

    public func deleteTestResult(id: UUID) {
        errorMessage = nil
        guard results.contains(where: { $0.id == id }) else {
            errorMessage = "削除するテスト結果が見つかりません。"
            return
        }
        results.removeAll { $0.id == id }
        statusMessage = "テスト結果を削除しました。"
        persistLocally()
    }

    public func startSleepPlayback() {
        errorMessage = nil
        guard !isPlaying else {
            statusMessage = "睡眠学習はすでに再生中です。"
            return
        }

        let playableCards = selectedCards.filter {
            !$0.speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !playableCards.isEmpty else {
            errorMessage = "再生する学習カードを1枚以上選んでください。"
            statusMessage = nil
            return
        }

        let normalizedSettings = settings.normalized(
            availableCardIDs: Set(cards.map(\.id))
        )
        settings = normalizedSettings
        let playbackCards = Self.makePlaybackQueue(
            from: playableCards,
            settings: normalizedSettings
        )
        guard !playbackCards.isEmpty else {
            errorMessage = "睡眠学習の再生キューを作成できませんでした。"
            statusMessage = nil
            return
        }

        do {
            try activateAudioSession()
        } catch {
            errorMessage = "音声再生を開始できませんでした（\(error.localizedDescription)）。"
            statusMessage = nil
            deactivateAudioSession(reportError: false)
            return
        }

        cardsByUtteranceID.removeAll(keepingCapacity: true)
        pendingUtteranceIDs.removeAll(keepingCapacity: true)
        currentSpokenCard = nil
        isPlaying = true
        statusMessage = "睡眠学習を開始しました。\(playbackCards.count)回の音声を再生します。"

        for (index, card) in playbackCards.enumerated() {
            let utterance = AVSpeechUtterance(string: card.speechText)
            utterance.voice = AVSpeechSynthesisVoice(language: card.languageCode)
            utterance.volume = normalizedSettings.volume
            utterance.postUtteranceDelay = index == playbackCards.index(before: playbackCards.endIndex)
                ? 0
                : normalizedSettings.intervalSeconds

            let utteranceID = ObjectIdentifier(utterance)
            cardsByUtteranceID[utteranceID] = card
            pendingUtteranceIDs.insert(utteranceID)
            speechSynthesizer.speak(utterance)
        }
    }

    public func stopSleepPlayback() {
        stopPlayback(showStatus: true)
    }
}

private extension SleepLearningStore {
    struct PersistedState: Codable {
        var schemaVersion: Int
        var cards: [LearningCard]
        var results: [LearningTestResult]
        var settings: SleepLearningSettings

        init(
            schemaVersion: Int = 1,
            cards: [LearningCard],
            results: [LearningTestResult],
            settings: SleepLearningSettings
        ) {
            self.schemaVersion = schemaVersion
            self.cards = cards
            self.results = results
            self.settings = settings
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case cards
            case results
            case settings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            cards = try container.decodeIfPresent([LearningCard].self, forKey: .cards) ?? []
            results = try container.decodeIfPresent(
                [LearningTestResult].self,
                forKey: .results
            ) ?? []
            settings = try container.decodeIfPresent(
                SleepLearningSettings.self,
                forKey: .settings
            ) ?? SleepLearningSettings()
        }
    }

    struct LoadResult {
        let state: PersistedState
        let errorMessage: String?
    }

    static func freshState() -> PersistedState {
        let cards = defaultCards
        return PersistedState(
            cards: cards,
            results: [],
            settings: SleepLearningSettings(
                selectedCardIDs: Set(cards.map(\.id))
            )
        )
    }

    static func loadPersistedState(from defaults: UserDefaults, key: String) -> LoadResult {
        guard let data = defaults.data(forKey: key) else {
            return LoadResult(state: freshState(), errorMessage: nil)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            let decoded = try decoder.decode(PersistedState.self, from: data)
            return LoadResult(state: normalizedState(decoded), errorMessage: nil)
        } catch {
            return LoadResult(
                state: freshState(),
                errorMessage: "このプロフィールの学習データを読み込めなかったため、初期デッキを表示しています。"
            )
        }
    }

    static func normalizedState(_ state: PersistedState) -> PersistedState {
        var seenCardIDs: Set<UUID> = []
        let cards = state.cards.compactMap { card -> LearningCard? in
            guard seenCardIDs.insert(card.id).inserted else { return nil }
            let prompt = card.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = card.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let speechText = card.speechText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, !answer.isEmpty, !speechText.isEmpty else { return nil }
            let languageCode = card.languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
            return LearningCard(
                id: card.id,
                prompt: prompt,
                answer: answer,
                speechText: speechText,
                languageCode: languageCode.isEmpty ? "ja-JP" : languageCode,
                brailleCells: card.brailleCells
            )
        }
        let availableIDs = Set(cards.map(\.id))
        let results = state.results
            .map {
                LearningTestResult(
                    id: $0.id,
                    completedAt: $0.completedAt,
                    correctAnswers: $0.correctAnswers,
                    totalQuestions: $0.totalQuestions,
                    cardIDs: $0.cardIDs.intersection(availableIDs),
                    sleepSessionID: $0.sleepSessionID,
                    wasSkipped: $0.wasSkipped
                )
            }
            .sorted { $0.completedAt > $1.completedAt }
        return PersistedState(
            schemaVersion: state.schemaVersion,
            cards: cards,
            results: Array(results.prefix(maximumStoredResults)),
            settings: state.settings.normalized(availableCardIDs: availableIDs)
        )
    }

    func persistLocally() {
        let state = PersistedState(
            cards: cards,
            results: results,
            settings: settings
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]

        do {
            defaults.set(try encoder.encode(state), forKey: persistenceKey)
        } catch {
            errorMessage = "学習データを端末内に保存できませんでした（\(error.localizedDescription)）。"
        }
    }

    func validatedCard(
        id: UUID,
        prompt: String,
        answer: String,
        speechText: String,
        languageCode: String,
        brailleCells: [[Int]]?
    ) -> LearningCard? {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSpeechText = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLanguageCode = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedPrompt.isEmpty else {
            errorMessage = "カードの問題を入力してください。"
            return nil
        }
        guard !normalizedAnswer.isEmpty else {
            errorMessage = "カードの答えを入力してください。"
            return nil
        }
        guard !normalizedSpeechText.isEmpty else {
            errorMessage = "読み上げる内容を入力してください。"
            return nil
        }

        return LearningCard(
            id: id,
            prompt: normalizedPrompt,
            answer: normalizedAnswer,
            speechText: normalizedSpeechText,
            languageCode: normalizedLanguageCode.isEmpty ? "ja-JP" : normalizedLanguageCode,
            brailleCells: brailleCells
        )
    }

    static func makePlaybackQueue(
        from selectedCards: [LearningCard],
        settings: SleepLearningSettings
    ) -> [LearningCard] {
        guard !selectedCards.isEmpty else { return [] }
        let durationSeconds = Double(settings.durationMinutes) * 60
        let requestedCount = max(
            1,
            Int(ceil(durationSeconds / settings.intervalSeconds))
        )
        let utteranceCount = min(maximumQueuedUtterances, requestedCount)

        var queue: [LearningCard] = []
        queue.reserveCapacity(utteranceCount)
        while queue.count < utteranceCount {
            var cycle = selectedCards
            if settings.shuffle {
                cycle.shuffle()
            }
            queue.append(contentsOf: cycle.prefix(utteranceCount - queue.count))
        }
        return queue
    }

    func activateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try audioSession.setActive(true)
        audioSessionIsActive = true
    }

    func deactivateAudioSession(reportError: Bool) {
        guard audioSessionIsActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
            audioSessionIsActive = false
        } catch {
            audioSessionIsActive = false
            if reportError {
                errorMessage = "音声セッションを終了できませんでした（\(error.localizedDescription)）。"
            }
        }
    }

    func stopPlayback(showStatus: Bool) {
        let hadPlayback = isPlaying
            || speechSynthesizer.isSpeaking
            || speechSynthesizer.isPaused
            || !pendingUtteranceIDs.isEmpty

        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        cardsByUtteranceID.removeAll(keepingCapacity: true)
        pendingUtteranceIDs.removeAll(keepingCapacity: true)
        currentSpokenCard = nil
        isPlaying = false
        deactivateAudioSession(reportError: showStatus)

        if showStatus {
            statusMessage = hadPlayback
                ? "睡眠学習の再生を停止しました。"
                : "睡眠学習は停止中です。"
        }
    }

    func handleUtteranceStarted(id: ObjectIdentifier) {
        guard isPlaying, let card = cardsByUtteranceID[id] else { return }
        currentSpokenCard = card
    }

    func handleUtteranceFinished(id: ObjectIdentifier, wasCancelled: Bool) {
        guard pendingUtteranceIDs.remove(id) != nil else { return }
        if currentSpokenCard == cardsByUtteranceID[id] {
            currentSpokenCard = nil
        }
        cardsByUtteranceID.removeValue(forKey: id)

        guard pendingUtteranceIDs.isEmpty else { return }
        isPlaying = false
        currentSpokenCard = nil
        deactivateAudioSession(reportError: true)
        statusMessage = wasCancelled
            ? "睡眠学習の再生が中断されました。"
            : "睡眠学習の再生が完了しました。"
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
}

extension SleepLearningStore: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.handleUtteranceStarted(id: utteranceID)
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.handleUtteranceFinished(id: utteranceID, wasCancelled: false)
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.handleUtteranceFinished(id: utteranceID, wasCancelled: true)
        }
    }
}
