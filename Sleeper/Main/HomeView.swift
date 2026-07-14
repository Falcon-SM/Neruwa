//
//  HomeView.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/13.
//

import Foundation
import SwiftUI
import GoogleSignIn

struct HomeView: View {
    @AppStorage("isFirstLaunch") private var isFirstLaunch: Bool = true
    @State private var showOnboarding: Bool = false
    @Binding var user: AppUser
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("ホーム画面")
                    .font(.largeTitle)
                    .padding()
                
                Text("\(user.name)さん、こんにちは！")
                
                ForEach(0..<50) { index in
                    Text("Item \(index)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}

#Preview {
    HomeView(user: .constant(AppUser(id: "123", name: "表現2B")))
}
