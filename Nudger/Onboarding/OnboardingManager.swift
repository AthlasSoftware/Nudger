//
//  OnboardingManager.swift
//  Nudger
//
//  Created on 2025-10-28.
//

import Foundation
import SwiftUI
import Combine

/// Manages onboarding state and completion
@MainActor
class OnboardingManager: ObservableObject {
    
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    @Published var currentStep: OnboardingStep = .welcome
    
    init() {
        // Default to false if key doesn't exist (first launch)
        if UserDefaults.standard.object(forKey: "hasCompletedOnboarding") == nil {
            self.hasCompletedOnboarding = false
        } else {
            self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        }
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = .welcome
    }
}

enum OnboardingStep {
    case welcome
    case accessibility
    case apiKeys
    case complete
}
