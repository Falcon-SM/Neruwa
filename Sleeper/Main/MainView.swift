//
//  MainView.swift
//  Sleeper
//

import SwiftUI

enum MainTab: Hashable {
    case home
    case sleep
    case learning
    case history
    case settings
}

struct MainView: View {
    @Binding var user: AppUser?
    @State private var selectedTab: MainTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("ホーム", systemImage: "house.fill", value: .home) {
                if let userBinding = Binding($user) {
                    HomeView(user: userBinding, selectedTab: $selectedTab)
                } else {
                    MissingUserView()
                }
            }

            Tab("睡眠", systemImage: "moon.zzz.fill", value: .sleep) {
                SleepRecorderView()
            }

            Tab("学習", systemImage: "book.fill", value: .learning) {
                ZStack {
                    NightSkyBackground()
                    SleepLearningView()
                }
            }

            Tab("記録", systemImage: "chart.bar.xaxis", value: .history) {
                HistoryView()
            }

            Tab("設定", systemImage: "gearshape.fill", value: .settings) {
                if let userBinding = Binding($user) {
                    SettingsView(
                        user: userBinding,
                        onLogout: { user = nil }
                    )
                } else {
                    MissingUserView()
                }
            }
        }
        .tint(SleepPalette.warmGold)
        .tabBarMinimizeBehavior(.onScrollDown)
        .preferredColorScheme(.dark)
    }
}

private struct MissingUserView: View {
    var body: some View {
        ZStack {
            NightSkyBackground()
            ContentUnavailableView(
                "ユーザー情報がありません",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .foregroundStyle(SleepPalette.text)
        }
    }
}

#Preview {
    MainView(user: .constant(.guest))
        .environmentObject(SleepStore())
        .environmentObject(SleepLearningStore())
}
