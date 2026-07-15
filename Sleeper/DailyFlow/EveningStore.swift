import Combine
import Foundation

@MainActor
final class EveningStore: ObservableObject {
    @Published private(set) var entries: [EveningEntry]
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    static let todayNoteCharacterLimit = 600
    static let letGoNoteCharacterLimit = 600
    static let tomorrowItemCharacterLimit = 120
    static let maximumTomorrowItems = EveningEntry.maximumTomorrowItems
    static let maximumStoredEntries = 180

    private static let profileKeyPrefix = "Sleeper.EveningStore.profile.v1"
    private static let guestProfileID = "local-demo-user"

    private let defaults: UserDefaults
    private var profileID: String

    init(defaults: UserDefaults = .standard) {
        let profileID = Self.guestProfileID
        let loadResult = Self.loadPersistedState(
            from: defaults,
            key: Self.persistenceKey(for: profileID)
        )

        self.defaults = defaults
        self.profileID = profileID
        self.entries = loadResult.entries
        self.statusMessage = nil
        self.errorMessage = loadResult.errorMessage
    }

    func activateProfile(_ requestedProfileID: String) {
        let normalizedProfileID = Self.normalizedProfileID(requestedProfileID)
        guard normalizedProfileID != profileID else { return }

        profileID = normalizedProfileID
        let loadResult = Self.loadPersistedState(
            from: defaults,
            key: Self.persistenceKey(for: normalizedProfileID)
        )
        entries = loadResult.entries
        statusMessage = nil
        errorMessage = loadResult.errorMessage
    }

    func entry(for day: Date, calendar: Calendar = .current) -> EveningEntry? {
        entries.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// Deletes every evening journal entry stored for the active profile only.
    func deleteAllEntriesForCurrentProfile() {
        entries = []
        defaults.removeObject(forKey: persistenceKey)
        errorMessage = nil
        statusMessage = "このプロフィールの夜の日記をすべて削除しました。"
    }

    @discardableResult
    func save(
        day: Date,
        todayNote: String,
        letGoNote: String,
        tomorrowItems: [String],
        completed: Bool = true,
        calendar: Calendar = .current
    ) -> EveningEntry? {
        let now = Date()
        let existingEntry = entry(for: day, calendar: calendar)
        let candidate = EveningEntry(
            day: calendar.startOfDay(for: day),
            todayNote: todayNote,
            letGoNote: letGoNote,
            tomorrowItems: tomorrowItems,
            completedAt: completed ? (existingEntry?.completedAt ?? now) : existingEntry?.completedAt,
            updatedAt: now
        )
        return save(candidate, calendar: calendar)
    }

    @discardableResult
    func save(
        _ entry: EveningEntry,
        calendar: Calendar = .current
    ) -> EveningEntry? {
        errorMessage = nil

        let normalizedDay = calendar.startOfDay(for: entry.day)
        let existingIndex = entries.firstIndex {
            calendar.isDate($0.day, inSameDayAs: normalizedDay)
        }
        let existingEntry = existingIndex.map { entries[$0] }
        let normalizedEntry = Self.normalizedEntry(
            EveningEntry(
                day: normalizedDay,
                todayNote: entry.todayNote,
                letGoNote: entry.letGoNote,
                tomorrowItems: entry.tomorrowItems,
                completedAt: entry.completedAt ?? existingEntry?.completedAt,
                updatedAt: entry.updatedAt
            ),
            calendar: calendar
        )

        if let existingIndex {
            entries[existingIndex] = normalizedEntry
        } else {
            entries.append(normalizedEntry)
        }
        entries = Self.normalizedEntries(entries, calendar: calendar)

        guard persistLocally() else { return nil }
        statusMessage = normalizedEntry.completedAt == nil
            ? "夜の日記を下書き保存しました。"
            : "夜の日記を保存しました。"
        return normalizedEntry
    }
}

private extension EveningStore {
    struct PersistedState: Codable {
        var schemaVersion: Int
        var entries: [EveningEntry]

        init(schemaVersion: Int = 1, entries: [EveningEntry]) {
            self.schemaVersion = schemaVersion
            self.entries = entries
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case entries
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            entries = try container.decodeIfPresent([EveningEntry].self, forKey: .entries) ?? []
        }
    }

    struct LoadResult {
        let entries: [EveningEntry]
        let errorMessage: String?
    }

    static func loadPersistedState(from defaults: UserDefaults, key: String) -> LoadResult {
        guard let data = defaults.data(forKey: key) else {
            return LoadResult(entries: [], errorMessage: nil)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        do {
            let state = try decoder.decode(PersistedState.self, from: data)
            return LoadResult(
                entries: normalizedEntries(state.entries, calendar: .current),
                errorMessage: nil
            )
        } catch {
            return LoadResult(
                entries: [],
                errorMessage: "このプロフィールの夜の日記を読み込めませんでした。新しい記録は引き続き保存できます。"
            )
        }
    }

    static func normalizedEntries(
        _ entries: [EveningEntry],
        calendar: Calendar
    ) -> [EveningEntry] {
        var entriesByDay: [Date: EveningEntry] = [:]

        for entry in entries {
            let normalized = normalizedEntry(entry, calendar: calendar)
            if let current = entriesByDay[normalized.day],
               current.updatedAt >= normalized.updatedAt {
                continue
            }
            entriesByDay[normalized.day] = normalized
        }

        return Array(
            entriesByDay.values
                .sorted { lhs, rhs in
                    if lhs.day == rhs.day {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhs.day > rhs.day
                }
                .prefix(maximumStoredEntries)
        )
    }

    static func normalizedEntry(
        _ entry: EveningEntry,
        calendar: Calendar
    ) -> EveningEntry {
        EveningEntry(
            day: calendar.startOfDay(for: entry.day),
            todayNote: limitedText(
                entry.todayNote,
                maximumCharacters: todayNoteCharacterLimit
            ),
            letGoNote: limitedText(
                entry.letGoNote,
                maximumCharacters: letGoNoteCharacterLimit
            ),
            tomorrowItems: entry.tomorrowItems
                .prefix(maximumTomorrowItems)
                .map {
                    limitedText(
                        $0,
                        maximumCharacters: tomorrowItemCharacterLimit
                    )
                },
            completedAt: entry.completedAt,
            updatedAt: entry.updatedAt
        )
    }

    static func limitedText(_ text: String, maximumCharacters: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumCharacters))
    }

    func persistLocally() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]

        do {
            let state = PersistedState(entries: entries)
            defaults.set(try encoder.encode(state), forKey: persistenceKey)
            return true
        } catch {
            errorMessage = "夜の日記を端末内に保存できませんでした（\(error.localizedDescription)）。"
            return false
        }
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
