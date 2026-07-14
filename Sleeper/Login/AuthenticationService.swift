//
//  AuthenticationService.swift
//  Sleeper
//

import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

enum AuthenticationError: LocalizedError {
    case firebaseUnavailable
    case missingGoogleIDToken

    var errorDescription: String? {
        switch self {
        case .firebaseUnavailable:
            return "認証の準備ができませんでした。アプリを開き直してお試しください。"
        case .missingGoogleIDToken:
            return "Googleから認証情報を受け取れませんでした。もう一度お試しください。"
        }
    }
}

@MainActor
enum AuthenticationService {
    static func restorePreviousUser() async -> AppUser? {
        guard FirebaseApp.app() != nil else { return nil }

        // Restore Google first so its tokens are refreshed. A valid Firebase
        // session remains usable even if Google restoration is unavailable.
        do {
            let googleUser = try await GIDSignIn.sharedInstance.restorePreviousSignIn()

            if Auth.auth().currentUser == nil {
                let credential = try credential(for: googleUser)
                _ = try await Auth.auth().signIn(with: credential)
            }
        } catch {
            // Firebase persists its own session independently from Google.
            // Falling through restores that session when it is still valid.
        }

        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        return appUser(from: firebaseUser)
    }

    static func signInWithGoogle(presenting viewController: UIViewController) async throws -> AppUser {
        guard FirebaseApp.app() != nil else {
            throw AuthenticationError.firebaseUnavailable
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        let credential = try credential(for: result.user)
        let authResult = try await Auth.auth().signIn(with: credential)
        return appUser(from: authResult.user)
    }

    /// MainView can call this directly from a logout callback. ContentView also
    /// invokes it when MainView sets its existing user binding to `nil`.
    static func signOut() throws {
        var firebaseError: Error?

        if FirebaseApp.app() != nil {
            do {
                try Auth.auth().signOut()
            } catch {
                firebaseError = error
            }
        }

        // Always clear Google even when Firebase sign-out reports an error.
        GIDSignIn.sharedInstance.signOut()

        if let firebaseError {
            throw firebaseError
        }
    }

    private static func credential(for googleUser: GIDGoogleUser) throws -> AuthCredential {
        guard let idToken = googleUser.idToken?.tokenString else {
            throw AuthenticationError.missingGoogleIDToken
        }

        return GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )
    }

    private static func appUser(from firebaseUser: FirebaseAuth.User) -> AppUser {
        AppUser(
            id: firebaseUser.uid,
            name: firebaseUser.displayName
                ?? firebaseUser.email?.components(separatedBy: "@").first
                ?? "おやすみユーザー"
        )
    }
}
