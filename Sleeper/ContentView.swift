//
//  ContentView.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/12.
//

import SwiftUI

struct ContentView: View {
    private struct FlowBoundaryTaskID: Hashable {
        let isReady: Bool
        let isActive: Bool
        let profileID: String?
        let morningStartMinutes: Int
        let nightStartMinutes: Int
    }

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DailyFlowSchedule.morningStartDefaultsKey)
    private var morningStartMinutes = DailyFlowSchedule.defaultMorningStartMinutes
    @AppStorage(DailyFlowSchedule.nightStartDefaultsKey)
    private var nightStartMinutes = DailyFlowSchedule.defaultNightStartMinutes
    @State private var user: AppUser?
    @State private var isRestoringSession = true
    @State private var mandatoryFlowContext: MandatoryDailyFlowContext?
    @StateObject private var sleepStore = SleepStore()
    @StateObject private var learningStore = SleepLearningStore()
    @StateObject private var eveningStore = EveningStore()
    @StateObject private var mandatoryFlowStore = MandatoryDailyFlowStore()

    var body: some View {
        Group {
            if isRestoringSession {
                SessionRestoringView()
                    .transition(.opacity)
            } else if user != nil {
                authenticatedRoot
                    .environmentObject(sleepStore)
                    .environmentObject(learningStore)
                    .environmentObject(eveningStore)
                    .environmentObject(mandatoryFlowStore)
                    .transition(.opacity)
            } else {
                LoginScreen(user: loginUser)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isRestoringSession)
        .animation(.easeInOut(duration: 0.35), value: user)
        .task {
            await restoreSession()
        }
        .task(id: user) {
            reconcilePendingMorningFlow(for: user)
            await synchronizeSleepStore(for: user)
            reconcilePendingMorningFlow(for: user)
            guard !isRestoringSession else { return }
            refreshMandatoryFlow(for: self.user)
        }
        .task(id: flowBoundaryTaskID) {
            await keepMandatoryFlowCurrent()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshMandatoryFlow(for: user)
        }
        .onChange(of: morningStartMinutes) { _, _ in
            refreshMandatoryFlow(for: user)
        }
        .onChange(of: nightStartMinutes) { _, _ in
            refreshMandatoryFlow(for: user)
        }
        .onChange(of: sleepStore.sessions.map(\.id)) { _, _ in
            reconcilePendingMorningFlow(for: user)
        }
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
        if let context = mandatoryFlowContext {
            MandatoryDailyFlowGateView(
                context: context,
                onCompleted: { nextContext in
                    handleMandatoryFlowCompletion(nextContext)
                },
                onInterrupted: {
                    learningStore.stopSleepPlayback()
                    mandatoryFlowContext = nil
                }
            )
            .id(context.id)
            .interactiveDismissDisabled()
        } else {
            MainView(user: authenticatedUser)
        }
    }

    /// Keeps the current MainView API compatible while making `user = nil`
    /// perform a complete Firebase + Google sign-out.
    private var authenticatedUser: Binding<AppUser?> {
        Binding(
            get: { user },
            set: { updatedUser in
                if updatedUser == nil, user != nil {
                    mandatoryFlowContext = nil
                    do {
                        try AuthenticationService.signOut()
                    } catch {
                        // The local session still closes so private data is no longer shown.
                        print("Sign-out error: \(error.localizedDescription)")
                    }
                    sleepStore.disconnectFirestore()
                    learningStore.stopSleepPlayback()
                }

                if let updatedUser {
                    sleepStore.activateProfile(updatedUser.id)
                    learningStore.activateProfile(updatedUser.id)
                    eveningStore.activateProfile(updatedUser.id)
                    mandatoryFlowStore.activateProfile(updatedUser.id)
                }
                user = updatedUser
                refreshMandatoryFlow(for: updatedUser)
            }
        )
    }

    /// Activates the account-scoped local cache before MainView becomes visible.
    private var loginUser: Binding<AppUser?> {
        Binding(
            get: { user },
            set: { signedInUser in
                if let signedInUser {
                    sleepStore.activateProfile(signedInUser.id)
                    learningStore.activateProfile(signedInUser.id)
                    eveningStore.activateProfile(signedInUser.id)
                    mandatoryFlowStore.activateProfile(signedInUser.id)
                }
                user = signedInUser
                refreshMandatoryFlow(for: signedInUser)
            }
        )
    }

    private func restoreSession() async {
        let restoredUser: AppUser?

        if AppEnvironment.isRunningForPreviews {
            restoredUser = nil
        } else if AppEnvironment.launchesGuestForUIValidation {
            restoredUser = .guest
        } else {
            restoredUser = await AuthenticationService.restorePreviousUser()
        }

        if let restoredUser {
            sleepStore.activateProfile(restoredUser.id)
            learningStore.activateProfile(restoredUser.id)
            eveningStore.activateProfile(restoredUser.id)
            mandatoryFlowStore.activateProfile(restoredUser.id)
        }
        user = restoredUser
        refreshMandatoryFlow(for: restoredUser)
        isRestoringSession = false
    }

    private func synchronizeSleepStore(for user: AppUser?) async {
        sleepStore.disconnectFirestore()

        guard let user else { return }
        sleepStore.activateProfile(user.id)
        guard !user.isGuest else { return }
        await sleepStore.connectFirestore(userID: user.id)
    }

    private func handleMandatoryFlowCompletion(
        _ nextContext: MandatoryDailyFlowContext?
    ) {
        mandatoryFlowContext = nextContext
        guard nextContext == nil else { return }

        // If a long-running flow crossed a configured time boundary, evaluate
        // the new period only after the finished root has left the hierarchy.
        Task { @MainActor in
            await Task.yield()
            refreshMandatoryFlow(for: user)
        }
    }

    private func refreshMandatoryFlow(
        for user: AppUser?,
        now: Date = Date()
    ) {
        guard let user else {
            mandatoryFlowContext = nil
            return
        }

        mandatoryFlowStore.activateProfile(user.id)

        // A persisted timer always wins over the wall-clock period. This keeps
        // the wake button on screen after relaunching or returning from the
        // background, even after the configured morning boundary has passed.
        if let timerStartedAt = sleepStore.activeTimerStartedAt {
            let nightContext = MandatoryDailyFlowContext(
                profileID: user.id,
                period: .night,
                targetDay: DailyFlowPeriod.nightFlowDay(
                    containing: timerStartedAt,
                    schedule: dailyFlowSchedule
                ),
                schedule: dailyFlowSchedule
            )
            let progress = mandatoryFlowStore.ensureProgress(
                for: nightContext,
                initialStep: .nightSleep,
                targetSleepSessionID: nil
            )
            if progress.step != .nightSleep {
                mandatoryFlowStore.advance(nightContext, to: .nightSleep)
            }
            mandatoryFlowContext = nightContext
            return
        }

        // Once a mandatory flow is visible, keep that exact sequence on
        // screen. A wall-clock boundary must not interrupt journal, study,
        // test, or record input that is already in progress.
        if let visibleContext = mandatoryFlowContext,
           visibleContext.profileID == user.id,
           let progress = mandatoryFlowStore.progress(for: visibleContext),
           progress.step != .completed {
            return
        }

        // A timer-created morning handoff remains mandatory even if the app is
        // reopened after another configured morning/night boundary.
        if let pendingMorningContext = mandatoryFlowStore.latestIncompleteMorningHandoff(
            profileID: user.id,
            schedule: dailyFlowSchedule
        ) {
            mandatoryFlowContext = pendingMorningContext
            return
        }

        let context = MandatoryDailyFlowContext(
            profileID: user.id,
            now: now,
            schedule: dailyFlowSchedule
        )
        mandatoryFlowContext = mandatoryFlowStore.isCompleted(context)
            ? nil
            : context
    }

    private var dailyFlowSchedule: DailyFlowSchedule {
        DailyFlowSchedule(
            morningStartMinutes: morningStartMinutes,
            nightStartMinutes: nightStartMinutes
        )
    }

    private var flowBoundaryTaskID: FlowBoundaryTaskID {
        FlowBoundaryTaskID(
            isReady: !isRestoringSession && user != nil,
            isActive: scenePhase == .active,
            profileID: user?.id,
            morningStartMinutes: morningStartMinutes,
            nightStartMinutes: nightStartMinutes
        )
    }

    /// Re-evaluates the mandatory flow after the authenticated root is mounted
    /// and exactly when either configured morning/night boundary is crossed.
    private func keepMandatoryFlowCurrent() async {
        guard flowBoundaryTaskID.isReady,
              flowBoundaryTaskID.isActive else {
            return
        }

        await Task.yield()
        guard !Task.isCancelled,
              scenePhase == .active,
              !isRestoringSession,
              user != nil else {
            return
        }
        refreshMandatoryFlow(for: user)

        while !Task.isCancelled {
            let now = Date()
            guard let nextBoundary = nextFlowBoundary(after: now) else { return }
            let delay = max(1, nextBoundary.timeIntervalSince(now))

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard scenePhase == .active,
                  !isRestoringSession,
                  user != nil else {
                return
            }
            refreshMandatoryFlow(for: user)
        }
    }

    private func nextFlowBoundary(
        after date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        [
            dailyFlowSchedule.morningStartMinutes,
            dailyFlowSchedule.nightStartMinutes
        ]
        .compactMap { minute in
            calendar.nextDate(
                after: date,
                matching: DateComponents(
                    hour: minute / 60,
                    minute: minute % 60,
                    second: 0
                ),
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }
        .min()
    }

    private func reconcilePendingMorningFlow(for user: AppUser?) {
        guard let user else { return }

        let calendar = Calendar.current
        let sessionsByMorningFlowDay = Dictionary(grouping: sleepStore.resolvedSessions) {
            DailyFlowPeriod.morningFlowDay(
                containing: $0.endDate,
                calendar: calendar,
                schedule: dailyFlowSchedule
            )
        }

        for (flowDay, sessions) in sessionsByMorningFlowDay {
            let context = MandatoryDailyFlowContext(
                profileID: user.id,
                period: .morning,
                targetDay: flowDay,
                calendar: calendar,
                schedule: dailyFlowSchedule
            )
            guard let progress = mandatoryFlowStore.progress(for: context),
                  progress.pendingMood != nil || progress.morningTestResultID != nil else {
                continue
            }

            let existingTarget = progress.targetSleepSessionID.flatMap {
                sleepStore.session(id: $0)
            }
            guard let session = existingTarget ?? sessions.max(by: { $0.endDate < $1.endDate }) else {
                continue
            }

            if progress.targetSleepSessionID != session.id {
                mandatoryFlowStore.setTargetSleepSessionID(context, sessionID: session.id)
            }
            if let mood = progress.pendingMood, session.mood == nil {
                sleepStore.updateReflection(
                    id: session.id,
                    mood: mood,
                    note: progress.pendingNote
                )
            }
            if let resultID = progress.morningTestResultID {
                _ = learningStore.linkTestResult(id: resultID, to: session.id)
            }
        }
    }
}

private struct SessionRestoringView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.indigo)

            Text("夜の準備をしています")
                .font(.headline)

            Text("前回の睡眠記録につないでいます")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}


#Preview {
    ContentView()
}
