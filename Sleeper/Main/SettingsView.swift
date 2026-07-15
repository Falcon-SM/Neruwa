//
//  SettingsView.swift
//  Sleeper
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @EnvironmentObject private var eveningStore: EveningStore
    @EnvironmentObject private var ambientStore: AmbientEnvironmentStore
    @Binding var user: AppUser

    @AppStorage("sleepTargetMinutes") private var targetMinutes = 480

    @State private var isImportingHealthKit = false
    @State private var showsLogoutConfirmation = false
    @State private var showsSleepDeleteConfirmation = false
    @State private var showsEveningDeleteConfirmation = false

    let onLogout: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                sleepGoalSection
                backgroundSection
                healthSection
                dataSection
                accountSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
            .alert("ログアウトしますか？", isPresented: $showsLogoutConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("ログアウト", role: .destructive, action: onLogout)
            } message: {
                Text(user.isGuest
                     ? "ゲストモードを終了します。端末内の睡眠記録は削除されません。"
                     : "端末内の記録は残り、再ログインすると同期できます。")
            }
            .alert("すべての睡眠記録を削除しますか？", isPresented: $showsSleepDeleteConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("すべて削除", role: .destructive) {
                    sleepStore.deleteAll()
                    HapticsManager.instance.notification(type: .warning)
                }
            } message: {
                Text("この端末の睡眠記録を削除します。ログイン中はクラウド側にも削除を反映します。夜の日記は削除されません。元に戻せません。")
            }
            .alert("夜の日記をすべて削除しますか？", isPresented: $showsEveningDeleteConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("日記をすべて削除", role: .destructive) {
                    eveningStore.deleteAllEntriesForCurrentProfile()
                    HapticsManager.instance.notification(type: .warning)
                }
            } message: {
                Text("このプロフィールの夜の日記\(eveningStore.entries.count)件を端末から削除します。睡眠記録は削除されません。元に戻せません。")
            }
        }
    }

    private var profileSection: some View {
        Section("プロフィール") {
            HStack(spacing: 14) {
                Image(systemName: user.isGuest ? "person.crop.circle.badge.clock" : "person.crop.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.headline)
                    Text(user.isGuest ? "ゲスト・この端末のみ" : "Firebase アカウント")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if sleepStore.isSyncing {
                    ProgressView()
                        .accessibilityLabel("同期中")
                } else {
                    Image(systemName: user.isGuest ? "iphone" : "checkmark.icloud.fill")
                        .foregroundStyle(user.isGuest ? Color.secondary : Color.green)
                        .accessibilityLabel(user.isGuest ? "端末内に保存" : "同期済み")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var sleepGoalSection: some View {
        Section {
            LabeledContent("目標睡眠時間") {
                Text(SleepDurationFormatter.summary(minutes: targetMinutes))
                    .fontWeight(.semibold)
            }

            Slider(
                value: Binding(
                    get: { Double(targetMinutes) },
                    set: { targetMinutes = Int($0 / 15) * 15 }
                ),
                in: 360...600,
                step: 15
            )
            .tint(.orange)
            .accessibilityLabel("目標睡眠時間")
            .accessibilityValue(SleepDurationFormatter.summary(minutes: targetMinutes))

            HStack {
                Text("6時間")
                Spacer()
                Text("10時間")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("睡眠目標")
        } footer: {
            Text("目標は睡眠を記録した時点で各セッションに保存されます。変更しても過去の比較には影響しません。")
        }
    }

    private var healthSection: some View {
        Section {
            Label {
                Text("Apple Watchや対応アプリが記録した昨晩の睡眠を読み取ります。Neruwaからヘルスケアへ書き込むことはありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.pink)
            }

            Button {
                Task { await importHealthKit() }
            } label: {
                HStack(spacing: 8) {
                    if isImportingHealthKit {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(isImportingHealthKit ? "読み込み中…" : "昨晩の睡眠を読み込む")
                }
            }
            .disabled(isImportingHealthKit)
        } header: {
            Text("ヘルスケア連携")
        }
    }

    private var backgroundSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { ambientStore.weatherEnabled },
                    set: { ambientStore.setWeatherEnabledFromUserAction($0) }
                )
            ) {
                Label("現在地の天気に合わせる", systemImage: "cloud.sun.fill")
            }

            LabeledContent {
                if ambientStore.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            } label: {
                Label(
                    ambientStore.weatherStatus.message,
                    systemImage: ambientStore.weatherStatus.systemImage
                )
                .foregroundStyle(.secondary)
            }

            if ambientStore.weatherEnabled {
                Button {
                    ambientStore.refreshIfNeeded(force: true)
                } label: {
                    Label("天気を更新", systemImage: "arrow.clockwise")
                }
                .disabled(ambientStore.isRefreshing)
            }

            if let lastUpdatedAt = ambientStore.lastUpdatedAt {
                LabeledContent("最終更新") {
                    Text(lastUpdatedAt, style: .relative)
                }
            }

            WeatherAttributionView(
                attribution: ambientStore.usesWeatherData
                    ? ambientStore.attribution
                    : nil
            )
        } header: {
            Text("背景")
        } footer: {
            Text("夜は星空、朝から昼は時刻に合わせた空を表示します。天気連動は継続追跡せず、更新時に現在地を一度だけ取得します。位置は保存・共有しません。")
        }
    }

    private var dataSection: some View {
        Group {
            Section("睡眠記録データ") {
                LabeledContent("保存済み睡眠記録", value: "\(sleepStore.sessions.count)件")

                if let statusMessage = sleepStore.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let errorMessage = sleepStore.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    showsSleepDeleteConfirmation = true
                } label: {
                    Label("すべての睡眠記録を削除", systemImage: "trash")
                }
                .disabled(sleepStore.sessions.isEmpty)
            }

            Section("夜の日記データ") {
                LabeledContent("保存済み夜の日記", value: "\(eveningStore.entries.count)件")

                if let statusMessage = eveningStore.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let errorMessage = eveningStore.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    showsEveningDeleteConfirmation = true
                } label: {
                    Label("すべての夜の日記を削除", systemImage: "trash")
                }
                .disabled(eveningStore.entries.isEmpty)
            }
        }
    }

    private var accountSection: some View {
        Section("アカウント") {
            Button(role: .destructive) {
                showsLogoutConfirmation = true
                HapticsManager.instance.notification(type: .warning)
            } label: {
                Label(
                    user.isGuest ? "ゲストモードを終了" : "ログアウト",
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
        }
    }

    private func importHealthKit() async {
        guard !isImportingHealthKit else { return }
        isImportingHealthKit = true
        defer { isImportingHealthKit = false }

        _ = await sleepStore.importLastNightFromHealthKit(targetMinutes: targetMinutes)
    }
}

#Preview {
    SettingsView(user: .constant(.guest), onLogout: {})
        .environmentObject(SleepStore())
        .environmentObject(EveningStore())
        .environmentObject(AmbientEnvironmentStore())
}
