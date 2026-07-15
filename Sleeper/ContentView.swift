//
//  ContentView.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/12.
//

import SwiftUI

struct ContentView: View {
    @State private var user: AppUser?
    @State private var isRestoringSession = true
    @StateObject private var sleepStore = SleepStore()
    @StateObject private var learningStore = SleepLearningStore()
    @StateObject private var eveningStore = EveningStore()

    var body: some View {
        Group {
            if isRestoringSession {
                SessionRestoringView()
                    .transition(.opacity)
            } else if user != nil {
                MainView(user: authenticatedUser)
                    .environmentObject(sleepStore)
                    .environmentObject(learningStore)
                    .environmentObject(eveningStore)
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
            await synchronizeSleepStore(for: user)
        }
    }

    /// Keeps the current MainView API compatible while making `user = nil`
    /// perform a complete Firebase + Google sign-out.
    private var authenticatedUser: Binding<AppUser?> {
        Binding(
            get: { user },
            set: { updatedUser in
                if updatedUser == nil, user != nil {
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
                }
                user = updatedUser
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
                }
                user = signedInUser
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
        }
        user = restoredUser
        isRestoringSession = false
    }

    private func synchronizeSleepStore(for user: AppUser?) async {
        sleepStore.disconnectFirestore()

        guard let user else { return }
        sleepStore.activateProfile(user.id)
        guard !user.isGuest else { return }
        await sleepStore.connectFirestore(userID: user.id)

        // A connection attempt may finish after logout or an account switch.
        if self.user != user {
            sleepStore.disconnectFirestore()
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
