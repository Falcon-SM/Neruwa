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
    case sharing
}

struct MainView: View {
    private struct ReflectionTarget: Identifiable {
        let id: UUID
    }

    private struct AmbientRefreshToken: Equatable {
        let scenePhase: ScenePhase
        let weatherEnabled: Bool
        let lastUpdatedAt: Date?
    }

    @EnvironmentObject private var sleepStore: SleepStore
    @EnvironmentObject private var eveningStore: EveningStore
    @EnvironmentObject private var ambientStore: AmbientEnvironmentStore
    @Environment(\.scenePhase) private var scenePhase
    @Binding var user: AppUser?
    @State private var selectedTab: MainTab = .home
    @State private var learningPhase: SleepLearningPhase = .study
    @State private var isSettingsPresented = false
    @State private var isEveningJournalPresented = false
    @State private var reflectionTarget: ReflectionTarget?
    @State private var morningTestSessionID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("概要", systemImage: "heart.text.square.fill", value: .home) {
                if let userBinding = Binding($user) {
                    HomeView(
                        user: userBinding,
                        selectedTab: $selectedTab,
                        onStartEveningFlow: {
                            isEveningJournalPresented = true
                        },
                        onResumeReflection: { sessionID in
                            reflectionTarget = ReflectionTarget(id: sessionID)
                        },
                        onOpenLearning: openLearning,
                        onOpenSettings: {
                            isSettingsPresented = true
                        }
                    )
                    .environment(\.isAmbientBackgroundActive, selectedTab == .home)
                } else {
                    MissingUserView()
                }
            }

            Tab("夜", systemImage: "moon.stars.fill", value: .sleep) {
                SleepRecorderView(onReflectionSaved: beginMorningTest)
                    .environment(\.isAmbientBackgroundActive, selectedTab == .sleep)
            }

            Tab("学習", systemImage: "book.fill", value: .learning) {
                SleepLearningView(
                    phase: $learningPhase,
                    targetSleepSessionID: activeMorningTestSessionID,
                    onContinueToSleep: {
                        selectedTab = .sleep
                    },
                    onOpenHistory: finishMorningFlow
                )
                .environment(\.isAmbientBackgroundActive, selectedTab == .learning)
            }

            Tab("記録", systemImage: "chart.bar.xaxis", value: .history) {
                HistoryView()
                    .environment(\.isAmbientBackgroundActive, selectedTab == .history)
            }

            Tab("共有", systemImage: "person.2.fill", value: .sharing) {
                if let userBinding = Binding($user) {
                    ShareView(
                        user: userBinding,
                        onOpenSettings: {
                            isSettingsPresented = true
                        }
                    )
                    .environment(\.isAmbientBackgroundActive, selectedTab == .sharing)
                } else {
                    MissingUserView()
                }
            }
        }
        .environment(\.ambientScene, ambientStore.scene)
        .tint(.indigo)
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .preferredColorScheme(ambientStore.scene.isNight ? ColorScheme.dark : nil)
        .onChange(of: learningPhase) { _, newPhase in
            if newPhase == .test, morningTestSessionID == nil {
                morningTestSessionID = latestTodaySessionID
            }
        }
        .task(id: ambientRefreshToken) {
            await refreshAmbientWhileActive()
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            if ambientStore.usesWeatherData {
                WeatherAttributionView(attribution: ambientStore.attribution)
                    .padding(.trailing, 12)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            if let userBinding = Binding($user) {
                SettingsView(
                    user: userBinding,
                    onLogout: {
                        isSettingsPresented = false
                        user = nil
                    }
                )
                .environmentObject(sleepStore)
                .environmentObject(eveningStore)
                .environmentObject(ambientStore)
            }
        }
        .sheet(isPresented: $isEveningJournalPresented) {
            EveningJournalView {
                learningPhase = .study
                morningTestSessionID = nil
                selectedTab = .learning
            }
            .environmentObject(eveningStore)
        }
        .sheet(item: $reflectionTarget) { target in
            MorningReflectionView(
                sessionID: target.id,
                onSaved: beginMorningTest
            )
            .environmentObject(sleepStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func openLearning(
        _ phase: SleepLearningPhase,
        sleepSessionID: UUID?
    ) {
        learningPhase = phase
        morningTestSessionID = phase == .test ? sleepSessionID : nil
        selectedTab = .learning
    }

    private var activeMorningTestSessionID: UUID? {
        guard let morningTestSessionID,
              sleepStore.sessions.contains(where: { $0.id == morningTestSessionID }) else {
            return nil
        }
        return morningTestSessionID
    }

    private var latestTodaySessionID: UUID? {
        let calendar = Calendar.current
        return sleepStore.sessions
            .filter { calendar.isDateInToday($0.wakeDay) }
            .max(by: { $0.endDate < $1.endDate })?
            .id
    }

    private func beginMorningTest(for sessionID: UUID) {
        morningTestSessionID = sessionID
        reflectionTarget = nil
        learningPhase = .test
        selectedTab = .learning
    }

    private func finishMorningFlow() {
        morningTestSessionID = nil
        learningPhase = .study
        selectedTab = .history
    }

    private var ambientRefreshToken: AmbientRefreshToken {
        AmbientRefreshToken(
            scenePhase: scenePhase,
            weatherEnabled: ambientStore.weatherEnabled,
            lastUpdatedAt: ambientStore.lastUpdatedAt
        )
    }

    private func refreshAmbientWhileActive() async {
        guard scenePhase == .active else { return }

        while !Task.isCancelled {
            ambientStore.refreshIfNeeded()

            let now = Date()
            let nextRefresh = ambientStore.nextAutomaticRefreshDate(after: now)
            let delay = max(1, nextRefresh.timeIntervalSince(now))

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }
}

private struct MissingUserView: View {
    var body: some View {
        ContentUnavailableView(
            "ユーザー情報がありません",
            systemImage: "person.crop.circle.badge.exclamationmark"
        )
    }
}

#Preview {
    MainView(user: .constant(.guest))
        .environmentObject(SleepStore())
        .environmentObject(SleepLearningStore())
        .environmentObject(EveningStore())
        .environmentObject(AmbientEnvironmentStore())
}
