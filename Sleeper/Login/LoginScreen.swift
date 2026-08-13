//
//  LoginScreen.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/12.
//

import SwiftUI

struct AppUser: Identifiable, Equatable {
    var id: String
    var name: String
    var isGuest: Bool = false

    static let guest = AppUser(
        id: "local-demo-user",
        name: "ゲスト",
        isGuest: true
    )
}

@MainActor
struct LoginScreen: View {
    @Binding var user: AppUser?

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 72)

                    brand

                    VStack(spacing: 10) {
                        Text("おやすみの時間を、\nやさしく記録しよう。")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        Text("睡眠のリズムと夜の過ごし方を、\n無理なくひとつに。")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }

                    signInPanel

                    Spacer(minLength: 32)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var brand: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 52, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)

            Text("Neruwa")
                .font(.title2.weight(.semibold))
        }
    }

    private var signInPanel: some View {
        VStack(spacing: 14) {
            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Image(systemName: "g.circle.fill")
                            .font(.title3)
                    }

                    Text(isSigningIn ? "Googleにつないでいます…" : "Googleではじめる")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSigningIn)

            Button {
                enterGuestMode()
            } label: {
                Label("ゲストで試す", systemImage: "person.crop.circle.badge.clock")
                    .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isSigningIn)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text("ゲストの記録はこの端末のみで使用します")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    private func signInWithGoogle() async {
        guard !isSigningIn else { return }

        errorMessage = nil
        isSigningIn = true
        HapticsManager.instance.impact(style: .soft)

        defer { isSigningIn = false }

        guard let rootViewController = getRootViewController() else {
            errorMessage = "ログイン画面を開けませんでした。もう一度お試しください。"
            HapticsManager.instance.notification(type: .error)
            return
        }

        do {
            let signedInUser = try await AuthenticationService.signInWithGoogle(
                presenting: rootViewController
            )
            HapticsManager.instance.notification(type: .success)
            user = signedInUser
        } catch {
            errorMessage = userFacingMessage(for: error)
            HapticsManager.instance.notification(type: .error)
        }
    }

    private func enterGuestMode() {
        errorMessage = nil
        HapticsManager.instance.impact(style: .light)
        user = .guest
    }

    private func userFacingMessage(for error: Error) -> String {
        if let authenticationError = error as? AuthenticationError {
            return authenticationError.errorDescription
                ?? "ログインを完了できませんでした。"
        }

        let nsError = error as NSError
        if nsError.domain == "com.google.GIDSignIn", nsError.code == -5 {
            return "Googleログインをキャンセルしました。"
        }

        return "Googleログインを完了できませんでした。通信環境を確認して、もう一度お試しください。"
    }

    private func getRootViewController() -> UIViewController? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }

        let windows = foregroundScenes.flatMap(\.windows)
        guard let rootVC = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController else {
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

#Preview {
    LoginScreen(user: .constant(nil))
}
