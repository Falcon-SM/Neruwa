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
        ZStack {
            background

            ScrollView {
                VStack(spacing: 34) {
                    Spacer(minLength: 64)

                    brand

                    VStack(spacing: 18) {
                        Text("おやすみの時間を、\nやさしく記録しよう。")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)

                        Text("睡眠のリズムと夜の過ごし方を、\n無理なくひとつに。")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineSpacing(4)
                    }

                    signInPanel

                    Spacer(minLength: 28)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.035, blue: 0.09),
                    Color(red: 0.075, green: 0.065, blue: 0.17),
                    Color(red: 0.035, green: 0.07, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.indigo.opacity(0.25), .clear],
                center: UnitPoint(x: 0.88, y: 0.08),
                startRadius: 12,
                endRadius: 250
            )

            RadialGradient(
                colors: [Color.cyan.opacity(0.09), .clear],
                center: UnitPoint(x: 0.08, y: 0.90),
                startRadius: 10,
                endRadius: 230
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var brand: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.cyan.opacity(0.78))
                .frame(width: 88, height: 88)
                .glassEffect(
                    .regular.tint(Color.indigo.opacity(0.25)),
                    in: .circle
                )

            Text("Neruwa")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.92))
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
                            .tint(.white)
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
            .buttonStyle(.glassProminent)
            .tint(Color(red: 0.25, green: 0.32, blue: 0.72))
            .disabled(isSigningIn)

            Button {
                enterGuestMode()
            } label: {
                Label("ゲストで試す", systemImage: "person.crop.circle.badge.clock")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.glass)
            .tint(.white.opacity(0.82))
            .disabled(isSigningIn)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.72))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text("ゲストの記録はこの端末のみで使用します")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.46))
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .glassEffect(
            .regular.tint(Color.white.opacity(0.035)),
            in: .rect(cornerRadius: 30)
        )
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
