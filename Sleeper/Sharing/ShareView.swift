import SwiftUI

struct ShareView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @Binding private var user: AppUser
    @StateObject private var feedStore: SleepFeedStore

    let onOpenSettings: () -> Void

    @AppStorage(SleepFeedVisibility.defaultsKey)
    private var defaultVisibilityRaw = SleepFeedVisibility.everyone.rawValue
    @State private var isComposerPresented = false

    init(user: Binding<AppUser>, onOpenSettings: @escaping () -> Void) {
        _user = user
        _feedStore = StateObject(wrappedValue: SleepFeedStore(user: user.wrappedValue))
        self.onOpenSettings = onOpenSettings
    }

    private var latestSummary: SleepShareSummary? {
        guard let latestSession = sleepStore.resolvedSessions.max(by: {
            $0.endDate < $1.endDate
        }) else {
            return nil
        }
        return SleepShareSummary(session: latestSession)
    }

    var body: some View {
        NavigationStack {
            List {
                if feedStore.isLoading, feedStore.posts.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("みんなの睡眠を読み込んでいます")
                            .foregroundStyle(.secondary)
                    }
                } else if feedStore.posts.isEmpty {
                    ContentUnavailableView {
                        Label("投稿はまだありません", systemImage: "moon.zzz")
                    } description: {
                        Text("最初の睡眠ログが届くと、ここに表示されます。")
                    }
                } else {
                    ForEach(feedStore.posts) { post in
                        SleepFeedPostRow(
                            post: post,
                            isReacting: feedStore.reactingPostIDs.contains(post.id),
                            onReact: {
                                Task { await feedStore.toggleReaction(for: post.id) }
                            }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("みんなの睡眠")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await feedStore.loadFeed()
            }
            .task {
                await feedStore.loadFeed()
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isComposerPresented = true
                    } label: {
                        Label("投稿する", systemImage: "square.and.pencil")
                    }

                    Button(action: onOpenSettings) {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isComposerPresented) {
                SleepPostComposerView(
                    summary: latestSummary,
                    feedStore: feedStore,
                    defaultVisibility: defaultVisibility
                )
            }
        }
    }

    private var defaultVisibility: SleepFeedVisibility {
        SleepFeedVisibility(rawValue: defaultVisibilityRaw) ?? .everyone
    }
}

private struct SleepPostComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let summary: SleepShareSummary?
    @ObservedObject var feedStore: SleepFeedStore

    @State private var comment = ""
    @State private var includesMood = false
    @State private var visibility: SleepFeedVisibility

    init(
        summary: SleepShareSummary?,
        feedStore: SleepFeedStore,
        defaultVisibility: SleepFeedVisibility
    ) {
        self.summary = summary
        self.feedStore = feedStore
        _visibility = State(initialValue: defaultVisibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let summary {
                    sleepSection(summary)
                    commentSection(summary)
                    visibilitySection
                    publishSection(summary)
                    externalShareSection(summary)
                    privacySection
                } else {
                    ContentUnavailableView {
                        Label("共有できる記録がありません", systemImage: "moon.zzz")
                    } description: {
                        Text("睡眠を記録すると、最新の記録を投稿できます。")
                    }
                }
            }
            .navigationTitle("睡眠を投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onChange(of: comment) { _, newValue in
                let limited = String(newValue.prefix(80))
                if limited != newValue {
                    comment = limited
                }
            }
        }
    }

    private func sleepSection(_ summary: SleepShareSummary) -> some View {
        Section {
            LabeledContent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(SleepDurationFormatter.summary(minutes: summary.durationMinutes))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(summary.formattedWakeDay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("最新の睡眠", systemImage: "moon.zzz.fill")
            }

            LabeledContent("公開名", value: feedStore.publicAlias)
        } footer: {
            Text("Googleの名前やメールアドレスは表示せず、ねるね用の匿名名を使います。")
        }
    }

    private func commentSection(_ summary: SleepShareSummary) -> some View {
        Section {
            TextField(
                "ひとこと（任意）",
                text: $comment,
                axis: .vertical
            )
            .lineLimit(1...3)
            .textInputAutocapitalization(.never)

            HStack {
                Label("個人情報は書かないでください", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(comment.count)/80")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let mood = summary.mood {
                Toggle(isOn: $includesMood) {
                    Label("気分も共有  \(mood.emoji)", systemImage: "face.smiling")
                }
            }
        } header: {
            Text("投稿内容")
        }
    }

    private var visibilitySection: some View {
        Section {
            Picker("公開範囲", selection: $visibility) {
                ForEach(SleepFeedVisibility.allCases) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }

            LabeledContent {
                Text("準備中")
                    .foregroundStyle(.secondary)
            } label: {
                Label("友達限定", systemImage: "person.2.badge.gearshape")
            }
            .foregroundStyle(.secondary)
        } header: {
            Text("公開範囲")
        } footer: {
            Text(visibility.detail + "。友達の招待・限定公開はまだ実装していません。")
        }
    }

    private func publishSection(_ summary: SleepShareSummary) -> some View {
        Section {
            Button {
                Task { await publish(summary) }
            } label: {
                HStack {
                    if feedStore.isPublishing {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(feedStore.isPublishing ? "投稿しています…" : "投稿する")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(feedStore.isPublishing)

            if let notice = feedStore.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func externalShareSection(_ summary: SleepShareSummary) -> some View {
        Section("その他") {
            ShareLink(
                item: summary.shareText(
                    options: SleepShareOptions(
                        includesDuration: true,
                        includesAchievement: true,
                        includesMood: includesMood
                    )
                ),
                subject: Text("ねるねの睡眠記録")
            ) {
                Label("ほかのアプリで共有", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var privacySection: some View {
        Section("共有されない情報") {
            Label("正確な就寝・起床時刻", systemImage: "clock.badge.xmark")
            Label("睡眠ステージとHealthKitの識別情報", systemImage: "heart.text.square")
            Label("日記と朝の振り返り本文", systemImage: "note.text")
        }
    }

    private func publish(_ summary: SleepShareSummary) async {
        let didPublish = await feedStore.publish(
            summary: summary,
            comment: comment,
            includesMood: includesMood,
            visibility: visibility
        )
        guard didPublish else { return }
        HapticsManager.instance.notification(type: .success)
        dismiss()
    }
}

private struct SleepFeedPostRow: View {
    let post: SleepFeedPost
    let isReacting: Bool
    let onReact: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorAlias)
                        .font(.headline)
                    Text("\(post.formattedWakeDay)の睡眠 ・ \(post.relativeCreatedAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if post.delivery == .sample {
                    Text("表示例")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if post.delivery == .local {
                    Image(systemName: "iphone")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("この端末だけの投稿")
                }
            }

            if !post.comment.isEmpty {
                Text(post.comment)
                    .font(.body)
            }

            HStack(spacing: 18) {
                Label(
                    SleepDurationFormatter.summary(minutes: post.durationMinutes),
                    systemImage: "moon.zzz.fill"
                )

                if let percentage = post.achievementPercentage {
                    Label("\(percentage)%", systemImage: "target")
                }

                if let mood = post.mood {
                    Text(mood.emoji)
                        .accessibilityLabel("気分 \(mood.label)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Button(action: onReact) {
                Label(
                    post.reactionCount == 0 ? "おやすみ" : "おやすみ \(post.reactionCount)",
                    systemImage: post.isReactedByCurrentUser ? "heart.fill" : "heart"
                )
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(post.isReactedByCurrentUser ? Color.pink : Color.secondary)
            .disabled(isReacting)
            .accessibilityLabel(
                post.isReactedByCurrentUser
                    ? "おやすみリアクションを取り消す"
                    : "おやすみリアクションを送る"
            )
        }
        .padding(.vertical, 6)
    }
}

#Preview("共有フィード") {
    ShareView(user: .constant(.guest), onOpenSettings: {})
        .environmentObject(SleepStore())
}
