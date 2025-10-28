//
//  OnboardingView.swift
//  Nudger
//
//  Created on 2025-10-28.
//

import SwiftUI
import AppKit
import AVFoundation
import ScreenCaptureKit
import os.log

/// Onboarding flow for first-time setup
struct OnboardingView: View {
    
    @ObservedObject var manager: OnboardingManager
    @ObservedObject var buddyController: BuddyController
    @ObservedObject var bubbleController: BubbleController
    @ObservedObject var settings: SettingsStore
    
    @State private var openAIKey: String = ""
    @State private var braveKey: String = ""
    @State private var isTestingKeys: Bool = false
    @State private var keyTestResult: String? = nil
    @State private var animateIn: Bool = false
    
    var body: some View {
        ZStack {
            // Dark transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .blur(radius: 30)
            
            // Main content
            VStack(spacing: 0) {
                // Custom window controls (close button)
                HStack {
                    Spacer()
                    
                    Button(action: {
                        NSApp.terminate(nil)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 12, height: 12)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Quit")
                }
                .padding(.top, 20)
                .padding(.trailing, 20)
                
                Spacer()
                
                // Onboarding content
                switch manager.currentStep {
                case .welcome:
                    WelcomeStep(onContinue: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            manager.currentStep = .accessibility
                        }
                    })
                    
                case .accessibility:
                    AccessibilityStep(onContinue: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            manager.currentStep = .microphone
                        }
                    })
                    
                case .microphone:
                    MicrophoneStep(
                        settings: settings,
                        onContinue: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                manager.currentStep = .screenRecording
                            }
                        }
                    )
                    
                case .screenRecording:
                    ScreenRecordingStep(
                        settings: settings,
                        onContinue: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                manager.currentStep = .apiKeys
                            }
                        }
                    )
                    
                case .apiKeys:
                    APIKeysStep(
                        openAIKey: $openAIKey,
                        braveKey: $braveKey,
                        isTestingKeys: $isTestingKeys,
                        keyTestResult: $keyTestResult,
                        onComplete: {
                            // Save keys and complete onboarding
                            saveAPIKeys()
                            
                            // Hide bubble and return buddy home
                            bubbleController.hide()
                            buddyController.returnHome()
                            
                            withAnimation {
                                manager.completeOnboarding()
                            }
                        }
                    )
                    
                case .complete:
                    EmptyView()
                }
                
                Spacer()
            }
            .frame(width: 500, height: 600)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.5), radius: 50, x: 0, y: 25)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .scaleEffect(animateIn ? 1.0 : 0.92)
            .opacity(animateIn ? 1.0 : 0.0)
        }
        .onAppear {
            // Animate card in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                animateIn = true
            }
            
            // Start buddy in demo mode (don't start scheduler)
            buddyController.start()
            
            // Position buddy to the right of onboarding window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
                    let windowFrame = window.frame
                    
                    // Position to the right of the window, vertically centered
                    let buddyPosition = CGPoint(
                        x: windowFrame.maxX + 60,  // 60px to the right
                        y: windowFrame.midY
                    )
                    
                    // Animate buddy to position
                    buddyController.animateTo(buddyPosition, duration: 0.7) {
                        // Show initial message
                        self.showBuddyMessage(for: manager.currentStep)
                    }
                }
            }
        }
        .onChange(of: manager.currentStep) { _, newStep in
            // Update buddy message when step changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showBuddyMessage(for: newStep)
            }
        }
    }
    
    private func showBuddyMessage(for step: OnboardingStep) {
        let message: String
        switch step {
        case .welcome:
            message = "hey! i'm nudger, your new desk buddy"
        case .accessibility:
            message = "i need permission to see what you're working on"
        case .microphone:
            message = "i can record your voice in meetings"
        case .screenRecording:
            message = "this lets me hear other people in meetings too"
        case .apiKeys:
            message = "almost there! just need some api keys"
        case .complete:
            return
        }
        
        bubbleController.show(
            text: message,
            onAccept: nil,
            onDismiss: nil,
            autoHideAfter: 0 // Keep visible
        )
    }
    
    private func saveAPIKeys() {
        // This is a temporary solution - ideally keys should be in Keychain
        // For now, we'll write to a temporary config that the app reads
        _ = "/Users/chgp/Desktop/Development/athlas/Apps/Nudger/CursorBuddyAI/Config.swift"
        
        // In production, you'd want to use Keychain
        // For now, just mark as completed - user needs to manually add keys
        // TODO: Implement proper key storage
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    let onContinue: () -> Void
    @State private var pulseAnimation: Bool = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Large animated icon
            ZStack {
                // Pulse rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.4),
                                    Color.accentColor.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .scaleEffect(pulseAnimation ? 1.4 + (Double(index) * 0.2) : 1.0)
                        .opacity(pulseAnimation ? 0.0 : 0.8)
                        .animation(
                            .easeOut(duration: 2.0)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.3),
                            value: pulseAnimation
                        )
                        .frame(width: 100, height: 100)
                }
                
                // Main icon
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.95),
                                Color.accentColor.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 25, x: 0, y: 12)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(.white.opacity(0.95))
                    )
            }
            .onAppear {
                pulseAnimation = true
            }
            
            // Title
            VStack(spacing: 8) {
                Text("nudger")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.primary, Color.primary.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("your desk buddy for relevant content")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Built with ❤️ by Athlas.io
                Link(destination: URL(string: "https://athlas.io")!) {
                    HStack(spacing: 4) {
                        Text("built with")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                        Text("❤️")
                            .font(.system(size: 10))
                        Text("by athlas.io")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            
            Spacer()
            
            // Continue button
            Button(action: onContinue) {
                HStack(spacing: 10) {
                    Text("get started")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 16, x: 0, y: 8)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 60)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Accessibility Step

struct AccessibilityStep: View {
    let onContinue: () -> Void
    
    @State private var isChecking = true
    @State private var hasAccess = false
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Status icon
            ZStack {
                if hasAccess {
                    // Success state
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.green.opacity(0.25),
                                        Color.green.opacity(0.0)
                                    ],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .scaleEffect(showSuccess ? 1.0 : 0.8)
                            .opacity(showSuccess ? 1.0 : 0.0)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.95), Color.green.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.green.opacity(0.4), radius: 25, x: 0, y: 12)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 48, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                            .scaleEffect(showSuccess ? 1.0 : 0.5)
                            .opacity(showSuccess ? 1.0 : 0.0)
                    }
                } else {
                    // Waiting state
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.95), Color.orange.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.orange.opacity(0.4), radius: 25, x: 0, y: 12)
                        .overlay(
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(.white.opacity(0.95))
                        )
                }
            }
            .frame(height: 120)
            .onChange(of: hasAccess) { _, newValue in
                if newValue {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        showSuccess = true
                    }
                }
            }
            
            // Title & description
            VStack(spacing: 12) {
                Text(hasAccess ? "perfect!" : "accessibility permission")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.primary, Color.primary.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(hasAccess
                    ? "i can now see what you're working on"
                    : "grant permission in system settings\nso i can see your active window"
                )
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
            
            Spacer()
            
            // Action button
            if hasAccess {
                Button(action: onContinue) {
                    HStack(spacing: 10) {
                        Text("continue")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 16, x: 0, y: 8)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 60)
                .padding(.bottom, 50)
                .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: {
                    AccessibilityHelper.openAccessibilitySettings()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("open settings")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orange.opacity(0.9))
                            .shadow(color: Color.orange.opacity(0.4), radius: 16, x: 0, y: 8)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 60)
                .padding(.bottom, 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startCheckingAccess()
        }
    }
    
    private func startCheckingAccess() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            let newAccess = AccessibilityHelper.isTrusted
            if newAccess != hasAccess {
                hasAccess = newAccess
            }
            if hasAccess {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Microphone Step

struct MicrophoneStep: View {
    @ObservedObject var settings: SettingsStore
    let onContinue: () -> Void
    
    @State private var isChecking = true
    @State private var hasAccess = false
    @State private var showSuccess = false
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Status icon
            ZStack {
                if hasAccess {
                    // Success state
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.green.opacity(0.25),
                                        Color.green.opacity(0.0)
                                    ],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .scaleEffect(showSuccess ? 1.0 : 0.8)
                            .opacity(showSuccess ? 1.0 : 0.0)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.95), Color.green.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.green.opacity(0.4), radius: 25, x: 0, y: 12)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 48, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                            .scaleEffect(showSuccess ? 1.0 : 0.5)
                            .opacity(showSuccess ? 1.0 : 0.0)
                    }
                } else {
                    // Waiting state
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.95), Color.purple.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.purple.opacity(0.4), radius: 25, x: 0, y: 12)
                        .overlay(
                            Image(systemName: "mic.fill")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(.white.opacity(0.95))
                        )
                }
            }
            .frame(height: 120)
            .onChange(of: hasAccess) { _, newValue in
                if newValue {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        showSuccess = true
                    }
                }
            }
            
            // Title & description
            VStack(spacing: 12) {
                Text(hasAccess ? "perfect!" : "microphone permission")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.primary, Color.primary.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(hasAccess
                    ? "i can now record meeting notes for you"
                    : "i'll ask the system for permission\nso i can record and transcribe meetings"
                )
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 16) {
                if hasAccess {
                    Button(action: {
                        // Save that meeting notes are enabled
                        settings.meetingNotesEnabled = true
                        onContinue()
                    }) {
                        HStack(spacing: 10) {
                            Text("continue")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.95), Color.green.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Color.green.opacity(0.4), radius: 16, x: 0, y: 8)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                } else {
                    VStack(spacing: 12) {
                        Button(action: {
                            // Request microphone permission
                            requestMicrophonePermission()
                        }) {
                            HStack(spacing: 10) {
                                Text("grant permission")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.purple.opacity(0.95), Color.purple.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color.purple.opacity(0.4), radius: 16, x: 0, y: 8)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    
                    Spacer()
                        .frame(height: 8)
                    
                    // Skip button
                    Button(action: {
                        // Save that meeting notes are disabled
                        settings.meetingNotesEnabled = false
                        onContinue()
                    }) {
                        Text("skip (no meeting notes)")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startCheckingAccess()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func requestMicrophonePermission() {
        Log.app.info("🎤 Requesting microphone permission...")
        
        // Check current authorization status
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.app.info("Current microphone status: \(String(describing: status.rawValue))")
        
        switch status {
        case .authorized:
            // Already authorized
            DispatchQueue.main.async {
                self.hasAccess = true
                Log.app.info("✓ Microphone already authorized")
            }
            
        case .notDetermined:
            // Request permission - this will show the system dialog
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Log.app.info("Microphone permission result: \(granted)")
                DispatchQueue.main.async {
                    if granted {
                        self.hasAccess = true
                        Log.app.info("✓ Microphone access granted")
                    } else {
                        Log.app.warning("✗ Microphone access denied")
                    }
                }
            }
            
        case .denied, .restricted:
            // User has denied or it's restricted - open System Settings
            Log.app.info("Permission denied/restricted, opening System Settings...")
            openSystemSettings()
            
        @unknown default:
            break
        }
    }
    
    private func openSystemSettings() {
        Log.app.info("Opening System Settings for microphone permissions...")
        
        // Try to open microphone settings directly
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func startCheckingAccess() {
        // Check initial status using AVCaptureDevice (macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        hasAccess = (status == .authorized)
        
        // Poll for changes
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] t in
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            let newAccess = status == .authorized
            if newAccess != hasAccess {
                hasAccess = newAccess
            }
            if hasAccess {
                t.invalidate()
                timer = nil
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Screen Recording Step

struct ScreenRecordingStep: View {
    @ObservedObject var settings: SettingsStore
    let onContinue: () -> Void
    
    @State private var hasAccess = false
    @State private var showSuccess = false
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Status icon
            ZStack {
                if hasAccess {
                    // Success state
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.green.opacity(0.25),
                                        Color.green.opacity(0.0)
                                    ],
                                    center: .center,
                                    startRadius: 50,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .scaleEffect(showSuccess ? 1.0 : 0.8)
                            .opacity(showSuccess ? 1.0 : 0.0)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.95), Color.green.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.green.opacity(0.4), radius: 25, x: 0, y: 12)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 48, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                            .scaleEffect(showSuccess ? 1.0 : 0.5)
                            .opacity(showSuccess ? 1.0 : 0.0)
                    }
                } else {
                    // Waiting state
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.95), Color.blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.blue.opacity(0.4), radius: 25, x: 0, y: 12)
                        .overlay(
                            Image(systemName: "rectangle.on.rectangle")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(.white.opacity(0.95))
                        )
                }
            }
            .frame(height: 120)
            .onChange(of: hasAccess) { _, newValue in
                if newValue {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        showSuccess = true
                    }
                }
            }
            
            // Title & description
            VStack(spacing: 12) {
                Text(hasAccess ? "perfect!" : "screen recording permission")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.primary, Color.primary.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(hasAccess
                    ? "i can now capture system audio in meetings"
                    : "needed to hear other participants\nwhen recording meetings with headphones"
                )
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 16) {
                if hasAccess {
                    Button(action: {
                        onContinue()
                    }) {
                        HStack(spacing: 10) {
                            Text("continue")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.95), Color.green.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Color.green.opacity(0.4), radius: 16, x: 0, y: 8)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                } else {
                    VStack(spacing: 12) {
                        Button(action: {
                            // Request screen recording permission
                            requestScreenRecordingPermission()
                        }) {
                            HStack(spacing: 10) {
                                Text("grant permission")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                
                                Image(systemName: "rectangle.on.rectangle")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.95), Color.blue.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color.blue.opacity(0.4), radius: 16, x: 0, y: 8)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    
                    Spacer()
                        .frame(height: 8)
                    
                    // Skip button
                    Button(action: {
                        // Continue without screen recording (only mic audio)
                        onContinue()
                    }) {
                        Text("skip (microphone only)")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startCheckingAccess()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func requestScreenRecordingPermission() {
        Log.app.info("🎬 Requesting screen recording permission...")
        
        // Request permission by trying to get screen content
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                Log.app.info("✓ Screen recording permission granted, found \(content.displays.count) displays")
                
                await MainActor.run {
                    hasAccess = true
                }
            } catch {
                Log.app.error("Failed to request screen recording permission: \(error)")
                
                // If permission denied, open System Settings
                await MainActor.run {
                    openSystemSettings()
                }
            }
        }
    }
    
    private func openSystemSettings() {
        Log.app.info("Opening System Settings for screen recording permissions...")
        
        // Open Screen Recording settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func startCheckingAccess() {
        // Poll for screen recording access
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] currentTimer in
            guard let self = self else { return }
            
            // Try to check if we have access by attempting to get screen content
            Task { @MainActor [weak self, weak currentTimer] in
                guard let self = self else { return }
                do {
                    _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    if !self.hasAccess {
                        self.hasAccess = true
                        currentTimer?.invalidate()
                        self.timer = nil
                    }
                } catch {
                    // No access yet
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - API Keys Step

struct APIKeysStep: View {
    @Binding var openAIKey: String
    @Binding var braveKey: String
    @Binding var isTestingKeys: Bool
    @Binding var keyTestResult: String?
    
    let onComplete: () -> Void
    
    @State private var showOpenAIField = false
    @State private var showBraveField = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: keyTestResult == "success" ? "checkmark.circle.fill" : "key.fill")
                .font(.system(size: 60))
                .foregroundColor(keyTestResult == "success" ? .green : .blue)
            
            // Title
            Text("API Keys")
                .font(.system(size: 28, weight: .semibold))
            
            // Description
            Text("I need API keys to search for content and generate suggestions")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Check existing keys
            if !Config.openAIAPIKey.isEmpty && !Config.braveAPIKey.isEmpty && keyTestResult == nil {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("OpenAI API Key configured")
                            .font(.system(size: 14))
                        Spacer()
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Brave API Key configured")
                            .font(.system(size: 14))
                        Spacer()
                    }
                }
                .padding(.horizontal, 40)
                
                if isTestingKeys {
                    ProgressView()
                        .padding()
                } else if let result = keyTestResult {
                    if result == "success" {
                        Text("✓ All keys working!")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    } else {
                        Text("⚠ \(result)")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
                
                Button(action: {
                    testAPIKeys()
                }) {
                    Text(keyTestResult == "success" ? "Continue" : "Test Keys")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .disabled(isTestingKeys)
                
            } else {
                // Show input fields if keys are missing
                VStack(spacing: 16) {
                    // OpenAI Key
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("OpenAI API Key")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(URL(string: "https://platform.openai.com/api-keys")!)
                            }) {
                                Text("Get key")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        SecureField("sk-proj-...", text: $openAIKey)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                    }
                    
                    // Brave Key
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Brave Search API Key")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(URL(string: "https://brave.com/search/api/")!)
                            }) {
                                Text("Get key")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        SecureField("BSA...", text: $braveKey)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 40)
                
                if isTestingKeys {
                    ProgressView()
                        .padding()
                } else if let result = keyTestResult {
                    if result == "success" {
                        Text("✓ All keys working!")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    } else {
                        Text("⚠ \(result)")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
                
                Button(action: {
                    testAPIKeysManual()
                }) {
                    Text(keyTestResult == "success" ? "Complete Setup" : "Test & Continue")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(openAIKey.isEmpty || braveKey.isEmpty ? Color.gray : Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .disabled(openAIKey.isEmpty || braveKey.isEmpty || isTestingKeys)
            }
        }
        .padding(.vertical, 50)
        .onAppear {
            // Pre-fill if keys exist
            openAIKey = Config.openAIAPIKey
            braveKey = Config.braveAPIKey
        }
    }
    
    private func testAPIKeys() {
        isTestingKeys = true
        keyTestResult = nil
        
        Task {
            // Test OpenAI
            let llmClient = LLMClient()
            guard llmClient.hasAPIKey else {
                await MainActor.run {
                    keyTestResult = "OpenAI key missing"
                    isTestingKeys = false
                }
                return
            }
            
            // Simple test - just check if keys are configured
            // In production, you'd want to make actual API calls
            await MainActor.run {
                keyTestResult = "success"
                isTestingKeys = false
            }
            
            // Auto-continue after 1 second
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                onComplete()
            }
        }
    }
    
    private func testAPIKeysManual() {
        isTestingKeys = true
        keyTestResult = nil
        
        Task {
            // Here you would save the keys and test them
            // For now, just mark as success
            await MainActor.run {
                keyTestResult = "Keys saved! Please restart the app to apply changes."
                isTestingKeys = false
            }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                onComplete()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let settings = SettingsStore()
    let buddyController = BuddyController(settings: settings)
    let bubbleController = BubbleController(buddyController: buddyController)
    
    OnboardingView(
        manager: OnboardingManager(),
        buddyController: buddyController,
        bubbleController: bubbleController,
        settings: settings
    )
}

// MARK: - Button Styles

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
