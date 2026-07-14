//
//  HomeView.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/12.
//

import Foundation
import SwiftUI

struct MainView: View {
    @AppStorage("isFirstLaunch") private var isFirstLaunch: Bool = true
    @State private var showOnboarding: Bool = false
    @Binding var user: AppUser?
    
    var body: some View {
        TabView{
            Tab("Home", systemImage: "house"){
                if let bindingUser = Binding($user) {
                    HomeView(user: bindingUser)
                } else {
                    Text("ユーザー情報がありません")
                }
            }
            
            Tab("Settings", systemImage:"gear"){
                if let BindingUser = Binding($user) {
                    SettingsView(user: BindingUser, onLogout: {
                        self.user = nil
                    })
                } else {
                    Text("エラー: ユーザー情報がありません")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
    
    private func closeOnBoarding() {
        withAnimation {
            showOnboarding = false
            isFirstLaunch = false
            
        }
    }
}

#Preview {
    MainView(user: .constant(AppUser(id: "123", name: "表現2B")))
}
