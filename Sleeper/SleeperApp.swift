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

    static var showcaseScreen: String? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let optionIndex = arguments.firstIndex(of: "-NeruwaShowcase"),
              arguments.indices.contains(optionIndex + 1) else {
            return nil
        }
        return arguments[optionIndex + 1]
#else
        return nil
#endif
    }
}

enum FirebaseBootstrap {
    private static let configureOnce: Void = {
        guard !AppEnvironment.isRunningForPreviews,
              AppEnvironment.showcaseScreen == nil else {
            return
        }
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
            Group {
#if DEBUG
                if let screen = AppEnvironment.showcaseScreen {
                    AppShowcaseView(screen: screen)
                } else {
                    ContentView()
                }
#else
                ContentView()
#endif
            }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
