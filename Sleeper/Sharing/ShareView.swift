import SwiftUI

struct ShareView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @Binding private var user: AppUser
    @StateObject private var feedStore: SleepFeedStore

    let onOpenSettings: () -> Void

    @State private var comment = ""
    @State private var includesMood = false

    init(user: Binding<AppUser>, onOpenSettings: @escaping () -> Void) {
        _user = user
        _feedStore = StateObject(wrappedValue: SleepFeedStore(user: user.wrappedValue))
        self.onOpenSettings = onOpenSettings
    }

    private var latestSummary: SleepShareSummary? {
        guard let latestSession = sleepStore.sessions.max(by: {
            $0.endDate < $1.endDate
        }) else {
            return nil
        }
        return SleepShareSummary(session: latestSession)
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection

                if let notice = feedStore.notice {
                    noticeSection(notice)
                }

                if let summary = latestSummary {
                    composerSection(summary)
                } else {
                    emptyComposerSection
                }

                feedSection
                privacySection

                if let summary = latestSummary {
                    externalShareSection(summary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("共有")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await feedStore.loadFeed()
            }
            .task {
                await feedStore.loadFeed()
            }
            .onChange(of: comment) { _, newValue in
                let limited = String(newValue.prefix(80))
                if limited != newValue {
                    comment = limited
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
        }
    }

    private var profileSection: some View {
        Section {
            LabeledContent {
                Text(feedStore.publicAlias)
                    .fontWeight(.medium)
            } label: {
                Label("公開名", systemImage: "person.crop.circle.fill")
            }

            LabeledContent {
                Text(feedStore.isCloudEnabled ? "認証ユーザー" : "この端末のみ")
                    .foregroundStyle(.secondary)
            } label: {
                Label(
                    "共有範囲",
                    systemImage: feedStore.isCloudEnabled ? "person.2.fill" : "iphone"
                )
            }
        } footer: {
            Text("Googleの名前やメールアドレスは表示せず、ねるね用の匿名名を使います。")
        }
    }

    private func noticeSection(_ notice: String) -> some View {
        Section {
            Label(notice, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func composerSection(_ summary: SleepShareSummary) -> some View {
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

            Button {
                Task { await publish(summary) }
            } label: {
                HStack {
                    if feedStore.isPublishing {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(feedStore.isPublishing ? "投稿しています…" : "フィードに投稿")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(feedStore.isPublishing)
        } header: {
            Text("睡眠を共有")
        } footer: {
            Text("睡眠時間と目標達成率を共有します。気分は自分でオンにしたときだけ含まれます。")
        }
    }

    private var emptyComposerSection: some View {
        Section {
            ContentUnavailableView {
                Label("共有できる記録がありません", systemImage: "moon.zzz")
            } description: {
                Text("睡眠を記録すると、最新の記録を短いひとことと一緒に投稿できます。")
            }
        } header: {
            Text("睡眠を共有")
        }
    }

    private var feedSection: some View {
        Section {
            if feedStore.isLoading, feedStore.posts.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("みんなの記録を読み込んでいます")
                        .foregroundStyle(.secondary)
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
        } header: {
            HStack {
                Text("みんなの睡眠")
                Spacer()
                if feedStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        } footer: {
            Text("フォロワー数やランキングのない、小さな睡眠ログです。下に引いて更新できます。")
        }
    }

    private var privacySection: some View {
        Section("共有されない情報") {
            Label("正確な就寝・起床時刻", systemImage: "clock.badge.xmark")
            Label("睡眠ステージとHealthKitの識別情報", systemImage: "heart.text.square")
            Label("日記と朝の振り返り本文", systemImage: "note.text")
        }
    }

    private func externalShareSection(_ summary: SleepShareSummary) -> some View {
        Section {
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
        } header: {
            Text("その他")
        } footer: {
            Text("必要なときだけiOSの共有シートを開きます。")
        }
    }

    private func publish(_ summary: SleepShareSummary) async {
        let didPublish = await feedStore.publish(
            summary: summary,
            comment: comment,
            includesMood: includesMood
        )
        guard didPublish else { return }
        comment = ""
        includesMood = false
        HapticsManager.instance.notification(type: .success)
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
