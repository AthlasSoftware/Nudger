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
    
    @Published var hasCompletedOnboarding: Bool
    
    @Published var currentStep: OnboardingStep = .welcome
    
    init() {
        // Check for completion marker file (persists across builds)
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let nudgerDir = appSupport.appendingPathComponent("Nudger")
        let markerFile = nudgerDir.appendingPathComponent(".onboarding_complete")
        
        if fileManager.fileExists(atPath: markerFile.path) {
            self.hasCompletedOnboarding = true
        } else {
            self.hasCompletedOnboarding = false
        }
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        
        // Create persistent marker file
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let nudgerDir = appSupport.appendingPathComponent("Nudger")
        let markerFile = nudgerDir.appendingPathComponent(".onboarding_complete")
        
        try? fileManager.createDirectory(at: nudgerDir, withIntermediateDirectories: true)
        try? "completed".write(to: markerFile, atomically: true, encoding: .utf8)
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = .welcome
        
        // Remove marker file
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let nudgerDir = appSupport.appendingPathComponent("Nudger")
        let markerFile = nudgerDir.appendingPathComponent(".onboarding_complete")
        
        try? fileManager.removeItem(at: markerFile)
    }
}

enum OnboardingStep {
    case welcome
    case accessibility
    case microphone
    case screenRecording
    case apiKeys
    case complete
}
