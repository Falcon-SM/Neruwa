//
//  ContentView.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/12.
//

import SwiftUI
import GoogleSignIn

struct ContentView: View {
    @State private var user: AppUser?
    var body: some View {
        if let _ = user {
            MainView(user: $user)
        } else {
            LoginScreen(user: self.$user)
        }
    }
}


#Preview {
    ContentView()
}
