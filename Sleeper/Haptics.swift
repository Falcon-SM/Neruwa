//
//  Haptics.swift
//  Sleeper
//
//  Created by Shun Matsumoto on 2026/07/13.
//

import Foundation
import SwiftUI

@MainActor
class HapticsManager{
    static let instance = HapticsManager()
    
    func notification(type : UINotificationFeedbackGenerator.FeedbackType){
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
    
    func impact(style : UIImpactFeedbackGenerator.FeedbackStyle){
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
