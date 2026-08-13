import Combine
import FirebaseAuth
import FirebaseCore
import Foundation

@MainActor
final class SleepFeedStore: ObservableObject {
    @Published private(set) var posts: [SleepFeedPost]
    @Published private(set) var isLoading = false
    @Published private(set) var isPublishing = false
    @Published private(set) var reactingPostIDs: Set<String> = []
    @Published private(set) var notice: String?

    let publicAlias: String
    let isCloudEnabled: Bool

    private static let persistencePrefix = "Neruwa.SleepFeed.cache.v1"
    private let defaults: UserDefaults
    private let persistenceKey: String
    private let cloud: SleepFeedFirestoreRepository?
    private let localOnlyFeedNotice: String
    private let localOnlyPublishNotice: String
    private var cachedPosts: [SleepFeedPost]
    private var showsSamples: Bool

    init(user: AppUser, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.persistenceKey = "\(Self.persistencePrefix).\(user.id)"
        self.publicAlias = SleepFeedIdentity.publicAlias(for: user)
        self.localOnlyFeedNotice = user.isGuest
            ? "ゲストの投稿とリアクションは、この端末だけに保存されます。"
            : "クラウド共有を利用できないため、投稿とリアクションはこの端末だけに保存されます。"
        self.localOnlyPublishNotice = user.isGuest
            ? "ログインしていないため、この端末だけに投稿を保存しました。"
            : "クラウド共有を利用できないため、この端末だけに投稿を保存しました。"

        if !user.isGuest,
           FirebaseApp.app() != nil,
           Auth.auth().currentUser?.uid == user.id {
            let repository = SleepFeedFirestoreRepository(userID: user.id)
            self.cloud = repository
            self.isCloudEnabled = true
        } else {
            self.cloud = nil
            self.isCloudEnabled = false
        }

        let cached = Self.loadCache(defaults: defaults, key: persistenceKey)
        self.cachedPosts = cached
        self.showsSamples = cached.isEmpty || user.isGuest
        self.posts = []
        updateVisiblePosts()
    }

    func loadFeed() async {
        guard !isLoading else { return }
        guard let cloud else {
            showsSamples = true
            updateVisiblePosts()
            notice = localOnlyFeedNotice
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remotePosts = try await cloud.fetchPosts()
            let localOnlyPosts = cachedPosts.filter { $0.delivery == .local }
            cachedPosts = Self.deduplicated(remotePosts + localOnlyPosts)
            showsSamples = remotePosts.isEmpty
            persistCache()
            updateVisiblePosts()
            notice = remotePosts.isEmpty
                ? "ほかの投稿が届くまで、表示例を確認できます。"
                : nil
        } catch {
            showsSamples = cachedPosts.isEmpty
            updateVisiblePosts()
            notice = "通信できないため、端末に保存したフィードを表示しています。"
        }
    }

    func publish(
        summary: SleepShareSummary,
        comment: String,
        includesMood: Bool,
        visibility: SleepFeedVisibility
    ) async -> Bool {
        guard !isPublishing else { return false }
        isPublishing = true
        defer { isPublishing = false }

        var post = SleepFeedPost(
            summary: summary,
            authorAlias: publicAlias,
            comment: comment,
            includesMood: includesMood,
            delivery: .local
        )
        cachedPosts.insert(post, at: 0)
        showsSamples = cloud == nil || cachedPosts.count == 1
        persistCache()
        updateVisiblePosts()

        guard visibility == .everyone else {
            notice = "この端末だけに投稿を保存しました。"
            return true
        }

        guard let cloud else {
            notice = localOnlyPublishNotice
            return true
        }

        do {
            try await cloud.publish(post)
            post.delivery = .cloud
            replaceCachedPost(post)
            showsSamples = false
            notice = "共有フィードに投稿しました。"
        } catch {
            notice = "送信できなかったため、この端末に投稿を残しました。"
        }
        persistCache()
        updateVisiblePosts()
        return true
    }

    func toggleReaction(for postID: String) async {
        guard !reactingPostIDs.contains(postID),
              let index = posts.firstIndex(where: { $0.id == postID }) else {
            return
        }

        reactingPostIDs.insert(postID)
        defer { reactingPostIDs.remove(postID) }

        let oldPost = posts[index]
        let willReact = !oldPost.isReactedByCurrentUser
        applyReaction(postID: postID, isReacted: willReact)

        guard oldPost.delivery == .cloud, let cloud else {
            notice = oldPost.delivery == .sample
                ? "表示例へのリアクションは、この画面だけで試せます。"
                : "リアクションをこの端末に保存しました。"
            return
        }

        do {
            let cloudState = try await cloud.setReaction(
                postID: postID,
                isReacted: willReact
            )
            synchronizeReaction(postID: postID, state: cloudState)
        } catch {
            notice = "通信できないため、リアクションはこの端末だけに反映しました。"
        }
    }
}

private extension SleepFeedStore {
    struct PersistedState: Codable {
        var posts: [SleepFeedPost]
    }

    func replaceCachedPost(_ post: SleepFeedPost) {
        if let index = cachedPosts.firstIndex(where: { $0.id == post.id }) {
            cachedPosts[index] = post
        } else {
            cachedPosts.insert(post, at: 0)
        }
    }

    func applyReaction(postID: String, isReacted: Bool) {
        guard let visibleIndex = posts.firstIndex(where: { $0.id == postID }) else { return }
        let wasReacted = posts[visibleIndex].isReactedByCurrentUser
        guard wasReacted != isReacted else { return }

        posts[visibleIndex].isReactedByCurrentUser = isReacted
        posts[visibleIndex].reactionCount = max(
            0,
            posts[visibleIndex].reactionCount + (isReacted ? 1 : -1)
        )

        if let cachedIndex = cachedPosts.firstIndex(where: { $0.id == postID }) {
            cachedPosts[cachedIndex].isReactedByCurrentUser = isReacted
            cachedPosts[cachedIndex].reactionCount = posts[visibleIndex].reactionCount
            persistCache()
        }
    }

    func synchronizeReaction(
        postID: String,
        state: SleepFeedFirestoreRepository.ReactionState
    ) {
        guard let visibleIndex = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[visibleIndex].isReactedByCurrentUser = state.isReacted
        posts[visibleIndex].reactionCount = state.reactionCount

        if let cachedIndex = cachedPosts.firstIndex(where: { $0.id == postID }) {
            cachedPosts[cachedIndex].isReactedByCurrentUser = state.isReacted
            cachedPosts[cachedIndex].reactionCount = state.reactionCount
            persistCache()
        }
    }

    func updateVisiblePosts() {
        var visiblePosts = cachedPosts
        if showsSamples {
            visiblePosts.append(contentsOf: Self.samplePosts())
        }
        posts = Self.deduplicated(visiblePosts).sorted {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return $0.createdAt > $1.createdAt
        }
    }

    func persistCache() {
        let state = PersistedState(posts: Array(cachedPosts.prefix(80)))
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    static func loadCache(defaults: UserDefaults, key: String) -> [SleepFeedPost] {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return []
        }
        return state.posts.filter { $0.delivery != .sample }
    }

    static func deduplicated(_ posts: [SleepFeedPost]) -> [SleepFeedPost] {
        var seen = Set<String>()
        return posts.filter { seen.insert($0.id).inserted }
    }

    static func samplePosts(now: Date = Date()) -> [SleepFeedPost] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return [
            SleepFeedPost(
                id: "sample-haru",
                authorAlias: "ねるね4821",
                wakeDay: today,
                durationMinutes: 7 * 60 + 35,
                achievementPercentage: 95,
                mood: .good,
                comment: "目覚ましの前に起きられた 🌱",
                createdAt: now.addingTimeInterval(-38 * 60),
                reactionCount: 3,
                delivery: .sample
            ),
            SleepFeedPost(
                id: "sample-sora",
                authorAlias: "ねるね1964",
                wakeDay: today,
                durationMinutes: 6 * 60 + 50,
                achievementPercentage: 86,
                mood: nil,
                comment: "今日は少し早めに寝てみる",
                createdAt: now.addingTimeInterval(-2 * 60 * 60),
                reactionCount: 2,
                delivery: .sample
            )
        ]
    }
}
