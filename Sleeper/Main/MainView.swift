//
//  MainView.swift
//  Sleeper
//

import SwiftUI

enum MainTab: Hashable {
    case sleep
    case learning
    case pvt
    case history
    case sharing
}

struct MainView: View {
    private struct FlowClockTaskID: Hashable {
        let isActive: Bool
        let morningStartMinutes: Int
        let nightStartMinutes: Int
    }

    @EnvironmentObject private var sleepStore: SleepStore
    @EnvironmentObject private var eveningStore: EveningStore
    @Environment(\.scenePhase) private var scenePhase
    @Binding var user: AppUser?
    @AppStorage(DailyFlowSchedule.morningStartDefaultsKey)
    private var morningStartMinutes = DailyFlowSchedule.defaultMorningStartMinutes
    @AppStorage(DailyFlowSchedule.nightStartDefaultsKey)
    private var nightStartMinutes = DailyFlowSchedule.defaultNightStartMinutes
    @State private var selectedTab: MainTab = .history
    @State private var flowNow = Date()
    @State private var isSettingsPresented = false

    let onStartDemoFlow: (DailyFlowPeriod) -> Void

    init(
        user: Binding<AppUser?>,
        onStartDemoFlow: @escaping (DailyFlowPeriod) -> Void = { _ in }
    ) {
        _user = user
        self.onStartDemoFlow = onStartDemoFlow
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("睡眠記録", systemImage: "bed.double.fill", value: .sleep) {
                SleepRecorderView(
                    allowedEntryModes: [.manual],
                    initialEntryMode: .manual,
                    showsHealthImport: false
                )
                    .environment(\.isAmbientBackgroundActive, selectedTab == .sleep)
            }

            Tab("学習", systemImage: "book.fill", value: .learning) {
                SleepLearningView()
                    .environment(\.isAmbientBackgroundActive, selectedTab == .learning)
            }

            Tab("PVT", systemImage: "bolt.fill", value: .pvt) {
                PVTView()
                    .environment(\.isAmbientBackgroundActive, selectedTab == .pvt)
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
        .environment(\.ambientScene, ambientScene)
        .tint(.indigo)
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .preferredColorScheme(ambientScene.isNight ? ColorScheme.dark : nil)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .task(id: flowClockTaskID) {
            await keepClockCurrentWhileActive()
        }
        .sheet(isPresented: $isSettingsPresented) {
            if let userBinding = Binding($user) {
                SettingsView(
                    user: userBinding,
                    onLogout: {
                        isSettingsPresented = false
                        user = nil
                    },
                    onStartDemoFlow: { period in
                        isSettingsPresented = false
                        onStartDemoFlow(period)
                    }
                )
                .environmentObject(sleepStore)
                .environmentObject(eveningStore)
            }
        }
    }

    private var ambientScene: AmbientScene {
        AmbientScene.timeFallback(
            at: flowNow,
            schedule: dailyFlowSchedule
        )
    }

    private var dailyFlowSchedule: DailyFlowSchedule {
        DailyFlowSchedule(
            morningStartMinutes: morningStartMinutes,
            nightStartMinutes: nightStartMinutes
        )
    }

    private var flowClockTaskID: FlowClockTaskID {
        FlowClockTaskID(
            isActive: scenePhase == .active,
            morningStartMinutes: morningStartMinutes,
            nightStartMinutes: nightStartMinutes
        )
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            flowNow = Date()
        }
    }

    private func keepClockCurrentWhileActive() async {
        guard scenePhase == .active else { return }

        while !Task.isCancelled {
            let currentDate = Date()
            let calendar = Calendar.current

            flowNow = currentDate

            let nextUpdate = nextClockUpdate(after: currentDate, calendar: calendar)
            let delay = max(1, nextUpdate.timeIntervalSince(currentDate))

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    private func nextClockUpdate(after date: Date, calendar: Calendar) -> Date {
        let morningSceneEnd = (
            dailyFlowSchedule.morningStartMinutes + 4 * 60
        ) % (24 * 60)
        let transitionMinutes = Set([
            0,
            9 * 60,
            11 * 60,
            17 * 60,
            dailyFlowSchedule.morningStartMinutes,
            dailyFlowSchedule.nightStartMinutes,
            morningSceneEnd
        ])

        return transitionMinutes
            .compactMap { minute in
                calendar.nextDate(
                    after: date,
                    matching: DateComponents(
                        hour: minute / 60,
                        minute: minute % 60,
                        second: 0
                    ),
                    matchingPolicy: .nextTime
                )
            }
            .min()
            ?? date.addingTimeInterval(60 * 60)
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
        .environmentObject(PVTStore())
        .environmentObject(EveningStore())
}
