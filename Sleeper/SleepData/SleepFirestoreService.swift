import Foundation
import FirebaseFirestore

struct SleepDeletionTombstone: Codable, Hashable, Sendable {
    let id: UUID
    let updatedAt: Date
}

struct SleepCloudSnapshot: Sendable {
    var sessions: [SleepSession]
    var deletions: [SleepDeletionTombstone]
}

@MainActor
final class SleepFirestoreService {
    static let schemaVersion = 1

    private let database: Firestore
    private let userID: String

    init(userID: String, database: Firestore = Firestore.firestore()) {
        self.userID = userID
        self.database = database
    }

    func synchronize(
        localSessions: [SleepSession],
        localDeletions: [SleepDeletionTombstone]
    ) async throws -> SleepCloudSnapshot {
        let local = SleepCloudSnapshot(
            sessions: localSessions,
            deletions: localDeletions
        )
        let remote = try await fetchSnapshot()
        let merged = Self.merge(local: local, remote: remote)

        // The previous prototype re-read and rewrote every document on every login.
        // Compare against the one query snapshot and only upload actual winners.
        let remoteRecords = Dictionary(
            uniqueKeysWithValues: Self.cloudRecords(from: remote).map { ($0.id, $0) }
        )
        let changedRecords = Self.cloudRecords(from: merged).filter { record in
            Self.requiresRemoteWrite(record, current: remoteRecords[record.id])
        }
        try await writeBatch(records: changedRecords)

        return merged
    }

    func upsert(session: SleepSession) async throws {
        try await write(record: .session(session))
    }

    func markDeleted(_ deletion: SleepDeletionTombstone) async throws {
        try await write(record: .deletion(deletion))
    }

    static func merge(
        local: SleepCloudSnapshot,
        remote: SleepCloudSnapshot
    ) -> SleepCloudSnapshot {
        var records: [UUID: CloudRecord] = [:]

        for record in cloudRecords(from: local) {
            records[record.id] = newer(record, than: records[record.id])
        }
        for record in cloudRecords(from: remote) {
            records[record.id] = newer(record, than: records[record.id])
        }

        var sessions: [SleepSession] = []
        var deletions: [SleepDeletionTombstone] = []
        for record in records.values {
            switch record {
            case .session(let session):
                sessions.append(session)
            case .deletion(let deletion):
                deletions.append(deletion)
            }
        }

        sessions.sort(by: sessionSort)
        deletions.sort { $0.updatedAt > $1.updatedAt }
        return SleepCloudSnapshot(sessions: sessions, deletions: deletions)
    }
}

private extension SleepFirestoreService {
    enum CloudRecord {
        case session(SleepSession)
        case deletion(SleepDeletionTombstone)

        var id: UUID {
            switch self {
            case .session(let session):
                session.id
            case .deletion(let deletion):
                deletion.id
            }
        }

        var updatedAt: Date {
            switch self {
            case .session(let session):
                session.updatedAt
            case .deletion(let deletion):
                deletion.updatedAt
            }
        }

        var isDeletion: Bool {
            if case .deletion = self { return true }
            return false
        }
    }

    var sessionsCollection: CollectionReference {
        database
            .collection("users")
            .document(userID)
            .collection("sleepSessions")
    }

    func fetchSnapshot() async throws -> SleepCloudSnapshot {
        let querySnapshot = try await sessionsCollection.getDocuments()
        var sessions: [SleepSession] = []
        var deletions: [SleepDeletionTombstone] = []

        for document in querySnapshot.documents {
            guard let record = Self.decodeRecord(
                documentID: document.documentID,
                data: document.data()
            ) else {
                continue
            }
            switch record {
            case .session(let session):
                sessions.append(session)
            case .deletion(let deletion):
                deletions.append(deletion)
            }
        }

        return Self.merge(
            local: SleepCloudSnapshot(sessions: sessions, deletions: deletions),
            remote: SleepCloudSnapshot(sessions: [], deletions: [])
        )
    }

    func write(record: CloudRecord) async throws {
        let reference = sessionsCollection.document(record.id.uuidString.lowercased())
        let currentDocument = try await reference.getDocument()

        if let currentData = currentDocument.data(),
           let currentRecord = Self.decodeRecord(
               documentID: currentDocument.documentID,
               data: currentData
           ) {
            if currentRecord.updatedAt > record.updatedAt {
                return
            }
            if currentRecord.updatedAt == record.updatedAt,
               currentRecord.isDeletion,
               !record.isDeletion {
                return
            }
        }

        try await reference.setData(Self.encode(record: record), merge: false)
    }

    func writeBatch(records: [CloudRecord]) async throws {
        guard !records.isEmpty else { return }

        // Firestore allows at most 500 operations per batch. Keep headroom for
        // future metadata writes and avoid a large in-memory batch.
        let batchSize = 400
        for startIndex in stride(from: 0, to: records.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, records.count)
            let batch = database.batch()

            for record in records[startIndex..<endIndex] {
                let reference = sessionsCollection.document(record.id.uuidString.lowercased())
                batch.setData(Self.encode(record: record), forDocument: reference)
            }

            try await batch.commit()
        }
    }

    static func cloudRecords(from snapshot: SleepCloudSnapshot) -> [CloudRecord] {
        snapshot.sessions.map(CloudRecord.session)
            + snapshot.deletions.map(CloudRecord.deletion)
    }

    static func newer(_ candidate: CloudRecord, than current: CloudRecord?) -> CloudRecord {
        guard let current else { return candidate }
        if candidate.updatedAt > current.updatedAt {
            return candidate
        }
        if candidate.updatedAt < current.updatedAt {
            return current
        }
        // If timestamps tie, a deletion wins and prevents a deleted session from
        // being unexpectedly resurrected on another device.
        if candidate.isDeletion != current.isDeletion {
            return candidate.isDeletion ? candidate : current
        }
        return current
    }

    static func requiresRemoteWrite(_ candidate: CloudRecord, current: CloudRecord?) -> Bool {
        guard let current else { return true }
        return candidate.updatedAt != current.updatedAt
            || candidate.isDeletion != current.isDeletion
    }

    static func sessionSort(_ lhs: SleepSession, _ rhs: SleepSession) -> Bool {
        if lhs.endDate == rhs.endDate {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.endDate > rhs.endDate
    }

    static func encode(record: CloudRecord) -> [String: Any] {
        switch record {
        case .session(let session):
            var data: [String: Any] = [
                "schemaVersion": schemaVersion,
                "id": session.id.uuidString.lowercased(),
                "isDeleted": false,
                "startDate": session.startDate,
                "endDate": session.endDate,
                "targetMinutes": session.targetMinutes,
                "source": session.source.rawValue,
                "mood": session.mood.map { $0.rawValue as Any } ?? NSNull(),
                "note": session.note,
                "externalIdentifier": session.externalIdentifier.map { $0 as Any } ?? NSNull(),
                "createdAt": session.createdAt,
                "updatedAt": session.updatedAt
            ]
            if let stages = session.stages {
                data["stages"] = [
                    "awakeMinutes": stages.awakeMinutes,
                    "coreMinutes": stages.coreMinutes,
                    "deepMinutes": stages.deepMinutes,
                    "remMinutes": stages.remMinutes,
                    "unspecifiedMinutes": stages.unspecifiedMinutes
                ]
            } else {
                data["stages"] = NSNull()
            }
            return data

        case .deletion(let deletion):
            return [
                "schemaVersion": schemaVersion,
                "id": deletion.id.uuidString.lowercased(),
                "isDeleted": true,
                "updatedAt": deletion.updatedAt
            ]
        }
    }

    static func decodeRecord(documentID: String, data: [String: Any]) -> CloudRecord? {
        let idString = (data["id"] as? String) ?? documentID
        guard
            let id = UUID(uuidString: idString),
            let updatedAt = date(from: data["updatedAt"])
        else {
            return nil
        }

        if data["isDeleted"] as? Bool == true {
            return .deletion(
                SleepDeletionTombstone(id: id, updatedAt: updatedAt)
            )
        }

        guard
            let startDate = date(from: data["startDate"]),
            let endDate = date(from: data["endDate"]),
            endDate > startDate,
            let targetMinutes = integer(from: data["targetMinutes"])
        else {
            return nil
        }

        let sourceRawValue = data["source"] as? String
        let source = sourceRawValue.flatMap(SleepSource.init(rawValue:)) ?? .manual
        let mood = (data["mood"] as? String).flatMap(SleepMood.init(rawValue:))
        let note = data["note"] as? String ?? ""
        let externalIdentifier = data["externalIdentifier"] as? String
        let createdAt = date(from: data["createdAt"]) ?? updatedAt
        let stages = decodeStages(data["stages"])

        return .session(
            SleepSession(
                id: id,
                startDate: startDate,
                endDate: endDate,
                targetMinutes: targetMinutes,
                source: source,
                mood: mood,
                note: note,
                stages: stages,
                externalIdentifier: externalIdentifier,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        )
    }

    static func decodeStages(_ value: Any?) -> SleepStageDurations? {
        guard let data = value as? [String: Any] else { return nil }
        return SleepStageDurations(
            awakeMinutes: integer(from: data["awakeMinutes"]) ?? 0,
            coreMinutes: integer(from: data["coreMinutes"]) ?? 0,
            deepMinutes: integer(from: data["deepMinutes"]) ?? 0,
            remMinutes: integer(from: data["remMinutes"]) ?? 0,
            unspecifiedMinutes: integer(from: data["unspecifiedMinutes"]) ?? 0
        )
    }

    static func date(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        return value as? Date
    }

    static func integer(from value: Any?) -> Int? {
        if let integer = value as? Int {
            return integer
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }
}
