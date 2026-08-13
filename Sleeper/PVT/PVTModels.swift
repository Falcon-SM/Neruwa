import Foundation

struct PVTResult: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let completedAt: Date
    let reactionTimesMilliseconds: [Int]
    let falseStarts: Int
    let sleepSessionID: UUID?

    init(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        reactionTimesMilliseconds: [Int],
        falseStarts: Int,
        sleepSessionID: UUID? = nil
    ) {
        self.id = id
        self.completedAt = completedAt
        self.reactionTimesMilliseconds = reactionTimesMilliseconds.map { max(0, $0) }
        self.falseStarts = max(0, falseStarts)
        self.sleepSessionID = sleepSessionID
    }

    var averageMilliseconds: Int {
        guard !reactionTimesMilliseconds.isEmpty else { return 0 }
        return reactionTimesMilliseconds.reduce(0, +) / reactionTimesMilliseconds.count
    }

    var fastestMilliseconds: Int {
        reactionTimesMilliseconds.min() ?? 0
    }

    var lapseCount: Int {
        reactionTimesMilliseconds.filter { $0 >= 500 }.count
    }
}
