import Foundation

enum SleepSessionResolver {
    static func areEquivalent(
        _ lhs: SleepSession,
        _ rhs: SleepSession,
        calendar: Calendar = .current
    ) -> Bool {
        guard lhs.endDate > lhs.startDate, rhs.endDate > rhs.startDate else { return false }
        guard calendar.isDate(lhs.endDate, inSameDayAs: rhs.endDate) else { return false }

        let lhsDuration = lhs.endDate.timeIntervalSince(lhs.startDate)
        let rhsDuration = rhs.endDate.timeIntervalSince(rhs.startDate)
        let shorterDuration = min(lhsDuration, rhsDuration)
        guard shorterDuration >= 30 * 60 else { return false }

        let overlapStart = max(lhs.startDate, rhs.startDate)
        let overlapEnd = min(lhs.endDate, rhs.endDate)
        let overlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
        let startsClose = abs(lhs.startDate.timeIntervalSince(rhs.startDate)) <= 45 * 60
        let endsClose = abs(lhs.endDate.timeIntervalSince(rhs.endDate)) <= 90 * 60
        return overlap / shorterDuration >= 0.65 || (startsClose && endsClose)
    }

    static func merged(
        preservingIDOf existing: SleepSession,
        with incoming: SleepSession
    ) -> SleepSession {
        let timing = preferredTimingRecord(existing, incoming)
        let reflection = preferredReflectionRecord(existing, incoming)
        return SleepSession(
            id: existing.id,
            startDate: timing.startDate,
            endDate: timing.endDate,
            targetMinutes: existing.targetMinutes > 0 ? existing.targetMinutes : incoming.targetMinutes,
            source: timing.source,
            mood: reflection.mood,
            note: reflection.note,
            stages: timing.stages ?? existing.stages ?? incoming.stages,
            externalIdentifier: timing.externalIdentifier
                ?? existing.externalIdentifier
                ?? incoming.externalIdentifier,
            createdAt: min(existing.createdAt, incoming.createdAt),
            updatedAt: max(existing.updatedAt, incoming.updatedAt)
        )
    }

    static func resolved(_ sessions: [SleepSession]) -> [SleepSession] {
        var result: [SleepSession] = []
        for session in sessions.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            if let index = result.firstIndex(where: { areEquivalent($0, session) }) {
                result[index] = merged(preservingIDOf: result[index], with: session)
            } else {
                result.append(session)
            }
        }
        return result.sorted { $0.endDate > $1.endDate }
    }

    private static func preferredTimingRecord(
        _ lhs: SleepSession,
        _ rhs: SleepSession
    ) -> SleepSession {
        let lhsRank = timingRank(lhs)
        let rhsRank = timingRank(rhs)
        if lhsRank != rhsRank { return lhsRank > rhsRank ? lhs : rhs }
        return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }

    private static func timingRank(_ session: SleepSession) -> Int {
        switch session.source {
        case .healthKit: 3
        case .timer: 2
        case .manual: 1
        }
    }

    private static func preferredReflectionRecord(
        _ lhs: SleepSession,
        _ rhs: SleepSession
    ) -> SleepSession {
        let lhsHasReflection = lhs.mood != nil || !lhs.note.isEmpty
        let rhsHasReflection = rhs.mood != nil || !rhs.note.isEmpty
        if lhsHasReflection != rhsHasReflection { return lhsHasReflection ? lhs : rhs }
        return lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
    }
}
