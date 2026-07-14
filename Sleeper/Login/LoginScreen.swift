//
//  LoginScreen.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/12.
//

import Foundation
import SwiftUI
import GoogleSignIn
import FirebaseAuth

struct AppUser {
    var id: String
    var name: String
}

@MainActor
struct LoginScreen: View {
    @Binding var user: AppUser?
    var body: some View {
        VStack{
            Text("ログイン画面")
            Button {
                Task {
                    await handleSignupButton()
                }
            } label: {
                Text("Googleでログイン")
            }
            .padding(.vertical, 80)
        }
    }
    
    // MARK: - async/await で実装
    func handleSignupButton() async {
        print("Sign in with google clicked")
        
        guard let rootViewController = getRootViewController() else {
            print("Root view controller not found.")
            return
        }
        
        do {
            // 1. Googleでサインインを実行し、結果を受け取る
            let gidSignInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            
            // 2. Googleユーザー情報からIDトークンとアクセストークンを取得
            guard let idToken = gidSignInResult.user.idToken?.tokenString else {
                print("ID Token not found")
                return
            }
            let accessToken = gidSignInResult.user.accessToken.tokenString
            
            // 3. トークンを使ってFirebaseの認証情報を生成
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            // 4. Firebaseにサインイン
            let authResult = try await Auth.auth().signIn(with: credential)
            let firebaseUser = authResult.user
            
            // 5. ユーザー情報を更新
            self.user = AppUser(
                id: firebaseUser.uid,
                name: firebaseUser.displayName ?? ""
            )
            print("Successfully signed in with Firebase. User: \(firebaseUser.uid)")
            
        } catch {
            let nsError = error as NSError
            print("--- Google Sign-In Error Details ---")
            print("Domain: \(nsError.domain)")
            print("Code: \(nsError.code)")
            print("Description: \(nsError.localizedDescription)")
            print("UserInfo: \(nsError.userInfo)")
            print("------------------------------------")
        }
    }
    
    func getRootViewController() -> UIViewController? {
        // 現在アクティブなウィンドウシーンを探す
        let foregroundScenes = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
        
        // 通常のシミュレータ実行、およびプレビュー環境の両方に対応して最前面のウィンドウを取得
        guard let window = foregroundScenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else {
            return nil
        }
        
        guard let rootVC = window.rootViewController else {
            return nil
        }
        
        return getVisibleViewController(from: rootVC)
    }
    
    private func getVisibleViewController(from vc: UIViewController) -> UIViewController {
        if let nav = vc as? UINavigationController {
            return getVisibleViewController(from: nav.visibleViewController ?? nav)
        }
        if let tab = vc as? UITabBarController {
            return getVisibleViewController(from: tab.selectedViewController ?? tab)
        }
        if let presented = vc.presentedViewController {
            return getVisibleViewController(from: presented)
        }
        return vc
    }
}

#Preview{
    LoginScreen(user: .constant(nil))
}
