//
//  SettingsView.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/13.
//

import Foundation
import SwiftUI
import GoogleSignIn

struct SettingsView: View {
    // 変数など
    @Binding var user: AppUser
    @State private var isShowLogOutAlert = false
    @State private var isShowDeleteAccountAlert = false
    
    @AppStorage("enableAppLimits") private var enableAppLimits = false
    @AppStorage("notificationFrequency") private var notificationFrequency = "ふつう"
    let options = ["なし", "少なめ", "ふつう", "多め"]
    @AppStorage("adjustExample") private var adjustExample: Double = 5
    
    
    var onLogout: () -> Void
    
    var body: some View {
        ZStack {
            NavigationStack {
                VStack {
                    List {
                        Toggle("アプリ制限を有効にする", isOn: $enableAppLimits)
                        Picker("通知の頻度", selection: $notificationFrequency) {
                            ForEach(options, id:\.self) { option in
                                Text(option)
                            }
                        }
                        VStack(alignment: .leading) {
                            Text("調整する:")
                            Slider(value: $adjustExample, in:0...10, minimumValueLabel: Text("少ない"), maximumValueLabel: Text("多い")) {
                                Text("値")
                            }
                        }
                    
                    Section {
                            Button("ログアウト") {
                                HapticsManager.instance.notification(type: .warning)
                                isShowLogOutAlert.toggle()
                            }
                            .alert("本当にログアウトしますか?", isPresented: $isShowLogOutAlert) {
                                Button("やめる", role:.cancel) {}
                                Button("ログアウトする", role: .destructive) {
                                    GIDSignIn.sharedInstance.signOut()
                                    onLogout()
                                }
                            } message: {
                                Text("後からいつでも再ログインできます")
                            }
                            
                            Button("アカウントを削除") {
                                HapticsManager.instance.notification(type: .warning)
                                isShowLogOutAlert.toggle()
                            }
                            .alert("本当にアカウントを削除しますか?", isPresented: $isShowDeleteAccountAlert) {
                                Button("やめる", role:.cancel) {}
                                Button("アカウントを削除する", role: .destructive) {
                                    // 処理を実装
                                }
                            } message: {
                                Text("この操作は取り消せません")
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView(user: .constant(AppUser(id: "123", name: "表現2B")), onLogout: {})
}
