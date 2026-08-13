import SwiftUI

#if DEBUG
/// Deterministic, signed-out screens used for visual QA and release imagery.
/// Pass `-NeruwaShowcase <screen>` to a debug build.
struct AppShowcaseView: View {
    let screen: String

    @State private var user = AppUser.guest
    @StateObject private var sleepStore = SleepStore()
    @StateObject private var learningStore = SleepLearningStore()
    @StateObject private var pvtStore = PVTStore()
    @StateObject private var eveningStore = EveningStore()
    @StateObject private var flowStore = MandatoryDailyFlowStore()

    private let morningContext = MandatoryDailyFlowContext(
        profileID: "showcase-morning",
        demoPeriod: .morning
    )
    private let nightContext = MandatoryDailyFlowContext(
        profileID: "showcase-night",
        demoPeriod: .night
    )

    var body: some View {
        screenContent
            .environmentObject(sleepStore)
            .environmentObject(learningStore)
            .environmentObject(pvtStore)
            .environmentObject(eveningStore)
            .environmentObject(flowStore)
            .environment(\.ambientScene, ambientScene)
            .preferredColorScheme(ambientScene.isNight ? .dark : nil)
            .task {
                let profileID = "showcase-\(screen)"
                sleepStore.activateProfile(profileID)
                learningStore.activateProfile(profileID)
                pvtStore.activateProfile(profileID)
                eveningStore.activateProfile(profileID)
                flowStore.activateProfile(profileID)
            }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch screen {
        case "sleep":
            SleepRecorderView(
                allowedEntryModes: [.manual],
                initialEntryMode: .manual,
                showsHealthImport: false
            )
        case "learning":
            SleepLearningView()
        case "pvt":
            PVTView()
        case "history":
            HistoryView()
        case "sharing":
            ShareView(user: $user, onOpenSettings: {})
        case "settings":
            SettingsView(
                user: $user,
                onLogout: {},
                onStartDemoFlow: { _ in }
            )
        case "morning":
            MandatoryDailyFlowGateView(
                context: morningContext,
                onCompleted: { _ in },
                onInterrupted: {}
            )
        case "night":
            MandatoryDailyFlowGateView(
                context: nightContext,
                onCompleted: { _ in },
                onInterrupted: {}
            )
        default:
            HistoryView()
        }
    }

    private var ambientScene: AmbientScene {
        switch screen {
        case "sleep", "learning", "night":
            .night
        default:
            .day
        }
    }
}
#endif
