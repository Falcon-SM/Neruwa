//
//  SleeperApp.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/12.
//

import SwiftUI
import GoogleSignIn
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // プレビュー時はFirebase初期化をパス
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        
        FirebaseApp.configure()
        return true
    }
}

@main
struct SleeperApp: App {
    init() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil {
            FirebaseApp.configure()
        }
    }
    
    @State var user: AppUser?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil else { return }
                    
                    do {
                        _ = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                        
                        if let firebaseUser = Auth.auth().currentUser {
                            self.user = AppUser(
                                id: firebaseUser.uid,
                                name: firebaseUser.displayName ?? firebaseUser.email ?? "User"
                            )
                        }
                    } catch {
                        print("Failed to restore previous sign-in: \(error.localizedDescription)")
                    }
                }
        }
    }
}
