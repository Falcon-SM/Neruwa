//
//  SleeperApp.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/12.
//

import SwiftUI
import GoogleSignIn
import FirebaseCore

enum AppEnvironment {
    static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    static var launchesGuestForUIValidation: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-NeruwaGuestMode")
#else
        false
#endif
    }
}

enum FirebaseBootstrap {
    private static let configureOnce: Void = {
        guard !AppEnvironment.isRunningForPreviews else { return }
        FirebaseApp.configure()
    }()

    static func configureIfNeeded() {
        _ = configureOnce
    }
}

@main
struct SleeperApp: App {
    init() {
        FirebaseBootstrap.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
