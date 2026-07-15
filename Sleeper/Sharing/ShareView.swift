import SwiftUI

struct ShareView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @Binding var user: AppUser

    let onOpenSettings: () -> Void

    @State private var options = SleepShareOptions()

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

                if let summary = latestSummary {
                    previewSection(summary)
                    sharingOptionsSection(summary)
                    shareActionSection(summary)
                    privacySection
                } else {
                    emptySection
                    privacySection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ambientScreenBackground()
            .navigationTitle("共有")
            .navigationBarTitleDisplayMode(.large)
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
                Text(user.isGuest ? "この端末から共有" : "システム共有を使用")
                    .foregroundStyle(.secondary)
            } label: {
                Label(
                    user.name,
                    systemImage: user.isGuest
                        ? "person.crop.circle.badge.clock"
                        : "person.crop.circle.fill"
                )
            }
        } footer: {
            Text("ゲストでも、端末に保存した記録を共有できます。")
        }
    }

    private func previewSection(_ summary: SleepShareSummary) -> some View {
        Section("共有プレビュー") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.indigo)
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Neruwaの睡眠記録")
                            .font(.headline)
                        Text(summary.formattedWakeDay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                if options.includesDuration {
                    previewRow(
                        title: "睡眠時間",
                        value: SleepDurationFormatter.summary(minutes: summary.durationMinutes),
                        systemImage: "moon.zzz.fill"
                    )
                }

                if options.includesAchievement,
                   let percentage = summary.achievementPercentage {
                    previewRow(
                        title: "目標達成率",
                        value: "\(percentage)%",
                        systemImage: "target"
                    )
                }

                if options.includesMood, let mood = summary.mood {
                    previewRow(
                        title: "今朝の気分",
                        value: "\(mood.emoji) \(mood.label)",
                        systemImage: "face.smiling"
                    )
                }

                if !options.hasShareableItem(in: summary) {
                    Label("共有する項目を1つ以上選んでください。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func sharingOptionsSection(_ summary: SleepShareSummary) -> some View {
        Section {
            Toggle(isOn: $options.includesDuration) {
                Label("睡眠時間", systemImage: "moon.zzz")
            }

            Toggle(isOn: $options.includesAchievement) {
                Label("目標達成率", systemImage: "target")
            }
            .disabled(summary.achievementPercentage == nil)

            Toggle(isOn: $options.includesMood) {
                Label("今朝の気分", systemImage: "face.smiling")
            }
            .disabled(summary.mood == nil)

            if summary.mood == nil {
                Label("気分は振り返りを保存すると選択できます。", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("共有する項目")
        } footer: {
            Text("気分は初期状態では共有しません。必要なときだけオンにしてください。")
        }
    }

    private func shareActionSection(_ summary: SleepShareSummary) -> some View {
        Section {
            ShareLink(
                item: summary.shareText(options: options),
                subject: Text("Neruwaの睡眠記録"),
                message: Text("共有する内容はNeruwaで選択できます。")
            ) {
                Label("共有シートを開く", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!options.hasShareableItem(in: summary))
        } footer: {
            Text("共有先はiOSの共有シートで選びます。Neruwaが送信先を自動で選ぶことはありません。")
        }
    }

    private var privacySection: some View {
        Section("共有されない情報") {
            Label("正確な就寝・起床時刻", systemImage: "clock.badge.xmark")
            Label("睡眠ステージとHealthKitの識別情報", systemImage: "heart.text.square")
            Label("振り返りに書いたメモ", systemImage: "note.text")
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label("共有できる記録がありません", systemImage: "square.and.arrow.up")
            } description: {
                Text("睡眠を記録すると、最新のサマリーをここから共有できます。")
            }
        }
    }

    private func previewRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        LabeledContent {
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

#Preview("記録なし") {
    ShareView(user: .constant(.guest), onOpenSettings: {})
        .environmentObject(SleepStore())
}
