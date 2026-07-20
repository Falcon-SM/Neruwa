import Combine
import Foundation

@MainActor
final class PVTStore: ObservableObject {
    @Published private(set) var results: [PVTResult]
    @Published private(set) var errorMessage: String?

    private static let profileKeyPrefix = "Sleeper.PVTStore.profile.v1"
    private static let guestProfileID = "local-demo-user"
    private static let maximumStoredResults = 180

    private let defaults: UserDefaults
    private var profileID: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.profileID = Self.guestProfileID
        let loaded = Self.load(defaults: defaults, profileID: Self.guestProfileID)
        self.results = loaded.results
        self.errorMessage = loaded.errorMessage
    }

    func activateProfile(_ requestedProfileID: String) {
        let normalized = Self.normalizedProfileID(requestedProfileID)
        guard normalized != profileID else { return }
        profileID = normalized
        let loaded = Self.load(defaults: defaults, profileID: normalized)
        results = loaded.results
        errorMessage = loaded.errorMessage
    }

    @discardableResult
    func save(
        reactionTimesMilliseconds: [Int],
        falseStarts: Int,
        sleepSessionID: UUID?
    ) -> PVTResult? {
        guard !reactionTimesMilliseconds.isEmpty else {
            errorMessage = "反応時間を計測できませんでした。"
            return nil
        }
        let result = PVTResult(
            reactionTimesMilliseconds: reactionTimesMilliseconds,
            falseStarts: falseStarts,
            sleepSessionID: sleepSessionID
        )
        results.insert(result, at: 0)
        results = Array(results.prefix(Self.maximumStoredResults))
        persist()
        return result
    }
}

private extension PVTStore {
    struct LoadResult {
        let results: [PVTResult]
        let errorMessage: String?
    }

    static func load(defaults: UserDefaults, profileID: String) -> LoadResult {
        guard let data = defaults.data(forKey: persistenceKey(for: profileID)) else {
            return LoadResult(results: [], errorMessage: nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            let results = try decoder.decode([PVTResult].self, from: data)
            return LoadResult(
                results: Array(results.sorted { $0.completedAt > $1.completedAt }.prefix(maximumStoredResults)),
                errorMessage: nil
            )
        } catch {
            return LoadResult(results: [], errorMessage: "PVTの結果を読み込めませんでした。")
        }
    }

    func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        do {
            defaults.set(try encoder.encode(results), forKey: Self.persistenceKey(for: profileID))
            errorMessage = nil
        } catch {
            errorMessage = "PVTの結果を端末に保存できませんでした。"
        }
    }

    static func persistenceKey(for profileID: String) -> String {
        "\(profileKeyPrefix).\(normalizedProfileID(profileID))"
    }

    static func normalizedProfileID(_ profileID: String) -> String {
        let trimmed = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? guestProfileID : trimmed
    }
}
