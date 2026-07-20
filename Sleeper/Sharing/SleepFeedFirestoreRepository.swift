import FirebaseFirestore
import Foundation

///
@MainActor
final class SleepFeedFirestoreRepository {
    struct ReactionState: Sendable {
        let isReacted: Bool
        let reactionCount: Int
    }

    private static let schemaVersion = 1
    private static let maximumPostCount = 40

    private let database: Firestore
    private let userID: String

    init(userID: String, database: Firestore = Firestore.firestore()) {
        self.userID = userID
        self.database = database
    }
    
    func fetchPosts() async throws -> [SleepFeedPost] {
        let snapshot = try await userPostsCollection
            .order(by: "createdAt", descending: true)
            .limit(to: Self.maximumPostCount)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            decode(
                documentID: document.documentID,
                data: document.data()
            )
        }
    }
    func publish(_ post: SleepFeedPost) async throws {
        let postReference = userPostsCollection.document(post.id)
        
        try await postReference.setData([
            "schemaVersion": Self.schemaVersion,
            "authorAlias": post.authorAlias,
            "wakeDay": post.wakeDay,
            "durationMinutes": post.durationMinutes,
            "achievementPercentage": post.achievementPercentage.map { $0 as Any } ?? NSNull(),
            "mood": post.mood.map { $0.rawValue as Any } ?? NSNull(),
            "comment": post.comment,
            "createdAt": FieldValue.serverTimestamp(),
            "reactionCount": 0
        ])
    }

    func setReaction(
        postID: String,
        isReacted desiredState: Bool
    ) async throws -> ReactionState {
        let postReference = userPostsCollection.document(postID)
        let reactionReference = postReference
            .collection("sleepFeedReactions")
            .document(userID)

        let existingReaction = try await reactionReference.getDocument()
        let currentState = existingReaction.exists

        if currentState != desiredState {
            let batch = database.batch()
            if desiredState {
                batch.setData([
                    "userID": userID,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: reactionReference)
            } else {
                batch.deleteDocument(reactionReference)
            }
            batch.updateData(
                ["reactionCount": FieldValue.increment(Int64(desiredState ? 1 : -1))],
                forDocument: postReference
            )
            try await batch.commit()
        }

        let updatedPost = try await postReference.getDocument()
        guard let data = updatedPost.data() else {
            throw NSError(
                domain: "SleepFeedFirestoreRepository",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "投稿が見つかりません。"]
            )
        }
        return ReactionState(
            isReacted: desiredState,
            reactionCount: max(0, Self.integer(data["reactionCount"]) ?? 0)
        )
    }
}

private extension SleepFeedFirestoreRepository {
    var userPostsCollection: CollectionReference {
        database.collection("users").document(userID).collection("sleepPosts")
    }

    func decode(
        documentID: String,
        data: [String: Any]
    ) -> SleepFeedPost? {
        guard Self.integer(data["schemaVersion"]) == Self.schemaVersion,
              let alias = data["authorAlias"] as? String,
              let wakeTimestamp = data["wakeDay"] as? Timestamp,
              let durationMinutes = Self.integer(data["durationMinutes"]),
              let createdTimestamp = data["createdAt"] as? Timestamp else {
            return nil
        }

        let achievementPercentage = Self.integer(data["achievementPercentage"])
        let mood = (data["mood"] as? String).flatMap(SleepMood.init(rawValue:))
        let comment = data["comment"] as? String ?? ""
        let reactionCount = Self.integer(data["reactionCount"]) ?? 0

        return SleepFeedPost(
            id: documentID,
            authorAlias: alias,
            wakeDay: wakeTimestamp.dateValue(),
            durationMinutes: durationMinutes,
            achievementPercentage: achievementPercentage,
            mood: mood,
            comment: comment,
            createdAt: createdTimestamp.dateValue(),
            reactionCount: reactionCount,
            isReactedByCurrentUser: false,
            delivery: .cloud
        )
    }

    static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
