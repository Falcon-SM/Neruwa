//
//  SettingsView.swift
//  Sleeper
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @EnvironmentObject private var eveningStore: EveningStore
    @Binding var user: AppUser

    @AppStorage("sleepTargetMinutes") private var targetMinutes = 480
    @AppStorage(DailyFlowSchedule.morningStartDefaultsKey)
    private var morningStartMinutes = DailyFlowSchedule.defaultMorningStartMinutes
    @AppStorage(DailyFlowSchedule.nightStartDefaultsKey)
    private var nightStartMinutes = DailyFlowSchedule.defaultNightStartMinutes
    @AppStorage(SleepFeedVisibility.defaultsKey)
    private var defaultShareVisibilityRaw = SleepFeedVisibility.everyone.rawValue

    @State private var isImportingHealthKit = false
    @State private var showsLogoutConfirmation = false
    @State private var showsSleepDeleteConfirmation = false
    @State private var showsEveningDeleteConfirmation = false

    let onLogout: () -> Void
    let onStartDemoFlow: (DailyFlowPeriod) -> Void

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                sleepGoalSection
                dailyFlowTimeSection
                demoSection
                sharingSection
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
            .onAppear {
                normalizePersistedPreferences()
            }
            .onDisappear {
                normalizeDailyFlowTimes()
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

    private var dailyFlowTimeSection: some View {
        Section {
            DatePicker(
                "朝の流れを始める",
                selection: minuteBinding(
                    get: { morningStartMinutes },
                    set: { morningStartMinutes = $0 }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)

            DatePicker(
                "夜の流れを始める",
                selection: minuteBinding(
                    get: { nightStartMinutes },
                    set: { nightStartMinutes = $0 }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)

            if !DailyFlowSchedule.isValid(
                morningStartMinutes: morningStartMinutes,
                nightStartMinutes: nightStartMinutes
            ) {
                Label("朝と夜は異なる時刻にしてください", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if morningStartMinutes != DailyFlowSchedule.defaultMorningStartMinutes
                || nightStartMinutes != DailyFlowSchedule.defaultNightStartMinutes {
                Button("05:00 / 19:00に戻す") {
                    morningStartMinutes = DailyFlowSchedule.defaultMorningStartMinutes
                    nightStartMinutes = DailyFlowSchedule.defaultNightStartMinutes
                }
            }
        } header: {
            Text("朝と夜の切り替え")
        } footer: {
            Text(
                "朝は\(dailyFlowSchedule.formattedMorningStart)から、夜は"
                    + "\(dailyFlowSchedule.formattedNightStart)から始まります。"
                    + "同じ時刻や保存データが不正な場合は05:00 / 19:00を使います。"
            )
        }
    }

    private var sharingSection: some View {
        Section {
            Picker("投稿時の初期設定", selection: defaultShareVisibilityBinding) {
                ForEach(SleepFeedVisibility.allCases) { visibility in
                    Label(visibility.title, systemImage: visibility.systemImage)
                        .tag(visibility)
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
            Text("睡眠の共有")
        } footer: {
            Text(
                "「みんな」はログイン済みのテスト参加者全員への公開です。"
                    + "友達の招待・限定公開はまだ実装していません。投稿画面で毎回変更できます。"
            )
        }
    }

    private var demoSection: some View {
        Section {
            Button {
                onStartDemoFlow(.morning)
            } label: {
                Label("朝を今すぐ始める", systemImage: "sunrise.fill")
            }

            Button {
                onStartDemoFlow(.night)
            } label: {
                Label("夜を今すぐ始める", systemImage: "moon.stars.fill")
            }
        } header: {
            Text("デモ")
        } footer: {
            Text("設定時刻や今日の完了状態に関係なく、選んだ流れを最初から開始します。")
        }
    }

    private var healthSection: some View {
        Section {
            Label {
                Text("Apple Watchや対応アプリが記録した昨晩の睡眠を読み取ります。記録画面では、許可した場合だけ選択日の心の状態も表示します。Neruwaからヘルスケアへ書き込むことはありません。")
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

    private var dataSection: some View {
        Group {
            Section("睡眠記録データ") {
                LabeledContent("保存済み睡眠記録", value: "\(sleepStore.sessions.count)件")

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

    private var dailyFlowSchedule: DailyFlowSchedule {
        DailyFlowSchedule(
            morningStartMinutes: morningStartMinutes,
            nightStartMinutes: nightStartMinutes
        )
    }

    private var defaultShareVisibilityBinding: Binding<SleepFeedVisibility> {
        Binding(
            get: {
                SleepFeedVisibility(rawValue: defaultShareVisibilityRaw) ?? .everyone
            },
            set: { defaultShareVisibilityRaw = $0.rawValue }
        )
    }

    private func minuteBinding(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void
    ) -> Binding<Date> {
        Binding(
            get: { dateForPicker(minutes: get()) },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                set(minutes)
            }
        )
    }

    private func dateForPicker(minutes: Int) -> Date {
        let safeMinutes = (0..<(24 * 60)).contains(minutes) ? minutes : 0
        return Calendar.current.date(
            bySettingHour: safeMinutes / 60,
            minute: safeMinutes % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func normalizePersistedPreferences() {
        normalizeDailyFlowTimes()
        if SleepFeedVisibility(rawValue: defaultShareVisibilityRaw) == nil {
            defaultShareVisibilityRaw = SleepFeedVisibility.everyone.rawValue
        }
    }

    private func normalizeDailyFlowTimes() {
        guard DailyFlowSchedule.isValid(
            morningStartMinutes: morningStartMinutes,
            nightStartMinutes: nightStartMinutes
        ) else {
            morningStartMinutes = DailyFlowSchedule.defaultMorningStartMinutes
            nightStartMinutes = DailyFlowSchedule.defaultNightStartMinutes
            return
        }
    }
}

#Preview {
    SettingsView(
        user: .constant(.guest),
        onLogout: {},
        onStartDemoFlow: { _ in }
    )
        .environmentObject(SleepStore())
        .environmentObject(EveningStore())
}
