//
//  SettingsView.swift
//  Sleeper
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sleepStore: SleepStore
    @Binding var user: AppUser

    @AppStorage("sleepTargetMinutes") private var targetMinutes = 480

    @State private var isImportingHealthKit = false
    @State private var showsLogoutConfirmation = false
    @State private var showsDeleteConfirmation = false

    let onLogout: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                NightSkyBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        FlowHeader(
                            eyebrow: "Settings",
                            title: "設定",
                            subtitle: "眠る目標とデータの扱いを調整できます。",
                            symbol: "gearshape.fill",
                            completedSteps: 0,
                            totalSteps: 1
                        )

                        profileCard
                        sleepGoalCard
                        healthCard
                        dataCard
                        accountCard
                    }
                }
                .sleepScreenScroll()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("ログアウトしますか？", isPresented: $showsLogoutConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("ログアウト", role: .destructive, action: onLogout)
            } message: {
                Text(user.isGuest
                     ? "ゲストモードを終了します。端末内の睡眠記録は削除されません。"
                     : "端末内の記録は残り、再ログインすると同期できます。")
            }
            .alert("すべての睡眠記録を削除しますか？", isPresented: $showsDeleteConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("すべて削除", role: .destructive) {
                    sleepStore.sessions.map(\.id).forEach(sleepStore.delete(id:))
                    HapticsManager.instance.notification(type: .warning)
                }
            } message: {
                Text("この端末の記録を削除します。ログイン中はクラウド側にも削除を反映します。元に戻せません。")
            }
        }
    }

    private var profileCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: user.isGuest ? "person.crop.circle.badge.clock" : "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(SleepPalette.warmGold)
                    .frame(width: 58, height: 58)
                    .glassEffect(
                        .regular.tint(SleepPalette.warmGold.opacity(0.14)),
                        in: .circle
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.title3.bold())
                        .foregroundStyle(SleepPalette.text)
                    Text(user.isGuest ? "ゲスト・この端末のみ" : "Firebase アカウント")
                        .font(.caption)
                        .foregroundStyle(SleepPalette.secondaryText)
                }

                Spacer()

                if sleepStore.isSyncing {
                    ProgressView()
                        .tint(SleepPalette.warmGold)
                        .accessibilityLabel("同期中")
                } else {
                    Image(systemName: user.isGuest ? "iphone" : "checkmark.icloud.fill")
                        .foregroundStyle(user.isGuest ? SleepPalette.secondaryText : SleepPalette.mint)
                }
            }
        }
    }

    private var sleepGoalCard: some View {
        SurfaceCard(tint: SleepPalette.warmGold.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 16) {
                Label("目標睡眠時間", systemImage: "target")
                    .font(.headline)
                    .foregroundStyle(SleepPalette.text)

                HStack(alignment: .lastTextBaseline) {
                    Text(SleepDurationFormatter.summary(minutes: targetMinutes))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(SleepPalette.warmGold)
                    Spacer()
                    Text("6〜10時間")
                        .font(.caption)
                        .foregroundStyle(SleepPalette.secondaryText)
                }

                Slider(
                    value: Binding(
                        get: { Double(targetMinutes) },
                        set: { targetMinutes = Int($0 / 15) * 15 }
                    ),
                    in: 360...600,
                    step: 15
                )
                .tint(SleepPalette.warmGold)
                .accessibilityValue(SleepDurationFormatter.summary(minutes: targetMinutes))

                Text("睡眠を記録した時点の目標を各セッションへ保存するため、後から目標を変えても過去の比較は変わりません。")
                    .font(.footnote)
                    .foregroundStyle(SleepPalette.secondaryText)
            }
        }
    }

    private var healthCard: some View {
        SurfaceCard(tint: SleepPalette.mint.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 14) {
                Label("ヘルスケア連携", systemImage: "heart.text.square.fill")
                    .font(.headline)
                    .foregroundStyle(SleepPalette.text)

                Text("Apple Watch や対応アプリが記録した昨晩の睡眠を読み取ります。ねるわから HealthKit へ書き込むことはありません。")
                    .font(.footnote)
                    .foregroundStyle(SleepPalette.secondaryText)

                Button {
                    Task { await importHealthKit() }
                } label: {
                    HStack {
                        if isImportingHealthKit {
                            ProgressView().tint(SleepPalette.text)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isImportingHealthKit ? "読み込み中…" : "昨晩の睡眠を読み込む")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                }
                .buttonStyle(.glass)
                .disabled(isImportingHealthKit)
            }
        }
    }

    private var dataCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("データ", systemImage: "externaldrive.fill")
                    .font(.headline)
                    .foregroundStyle(SleepPalette.text)

                LabeledContent("保存済みセッション") {
                    Text("\(sleepStore.sessions.count)件")
                        .foregroundStyle(SleepPalette.text)
                }
                .foregroundStyle(SleepPalette.secondaryText)

                if let statusMessage = sleepStore.statusMessage {
                    SleepStatusBanner(message: statusMessage, kind: .success)
                }

                if let errorMessage = sleepStore.errorMessage {
                    SleepStatusBanner(message: errorMessage, kind: .error)
                }

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("すべての睡眠記録を削除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.glass)
                .tint(SleepPalette.danger)
                .disabled(sleepStore.sessions.isEmpty)
            }
        }
    }

    private var accountCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("アカウント", systemImage: "person.crop.circle")
                    .font(.headline)
                    .foregroundStyle(SleepPalette.text)

                Button {
                    showsLogoutConfirmation = true
                    HapticsManager.instance.notification(type: .warning)
                } label: {
                    Label(user.isGuest ? "ゲストモードを終了" : "ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(.glass)
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
}
