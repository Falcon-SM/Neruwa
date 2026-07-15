import Foundation

struct EveningEntry: Identifiable, Codable, Hashable, Sendable {
    static let maximumTomorrowItems = 3

    var day: Date
    var todayNote: String
    var letGoNote: String
    var tomorrowItems: [String]
    var completedAt: Date?
    var updatedAt: Date

    var id: Date { day }

    init(
        day: Date,
        todayNote: String = "",
        letGoNote: String = "",
        tomorrowItems: [String] = [],
        completedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.day = day
        self.todayNote = todayNote
        self.letGoNote = letGoNote
        self.tomorrowItems = Array(tomorrowItems.prefix(Self.maximumTomorrowItems))
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case day
        case todayNote
        case letGoNote
        case tomorrowItems
        case completedAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDay = try container.decode(Date.self, forKey: .day)
        let decodedCompletedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)

        self.init(
            day: decodedDay,
            todayNote: try container.decodeIfPresent(String.self, forKey: .todayNote) ?? "",
            letGoNote: try container.decodeIfPresent(String.self, forKey: .letGoNote) ?? "",
            tomorrowItems: try container.decodeIfPresent([String].self, forKey: .tomorrowItems) ?? [],
            completedAt: decodedCompletedAt,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
                ?? decodedCompletedAt
                ?? decodedDay
        )
    }
}
