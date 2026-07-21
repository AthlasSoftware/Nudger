//
//  NudgerApp.swift
//  Nudger
//
//  Created on 2025-10-27.
//

import SwiftUI
import os.log

@main
struct NudgerApp: App {
    
    // MARK: - Services (Singletons)
    
    @StateObject private var settings = SettingsStore()
    @StateObject private var contextService = ContextService()
    @StateObject private var onboardingManager = OnboardingManager()
    
    private let llmClient = LLMClient()
    
    @StateObject private var buddyController: BuddyController
    @StateObject private var automationRouter: AutomationRouter
    @StateObject private var bubbleController: BubbleController
    @StateObject private var scheduler: SuggestScheduler
    @StateObject private var meetingDetector: MeetingDetector
    @StateObject private var meetingRecorder: MeetingRecorder
    @StateObject private var meetingManager: MeetingManager
    
    // MARK: - Initialization
    
    init() {
        let settings = SettingsStore()
        let contextService = ContextService()
        let onboardingManager = OnboardingManager()
        let llmClient = LLMClient()
        
        let buddyController = BuddyController(settings: settings)
        let automationRouter = AutomationRouter(buddyController: buddyController)
        let bubbleController = BubbleController(buddyController: buddyController)
        
        let meetingDetector = MeetingDetector()
        let meetingRecorder = MeetingRecorder()
        let notesGenerator = MeetingNotesGenerator(llmClient: llmClient)
        let meetingManager = MeetingManager(
            detector: meetingDetector,
            recorder: meetingRecorder,
            notesGenerator: notesGenerator,
            buddyController: buddyController,
            bubbleController: bubbleController
        )
        
        let scheduler = SuggestScheduler(
            settings: settings,
            contextService: contextService,
            llmClient: llmClient,
            buddyController: buddyController,
            bubbleController: bubbleController,
            automationRouter: automationRouter,
            onboardingManager: onboardingManager,
            meetingDetector: meetingDetector
        )
        
        _settings = StateObject(wrappedValue: settings)
        _contextService = StateObject(wrappedValue: contextService)
        _onboardingManager = StateObject(wrappedValue: onboardingManager)
        _buddyController = StateObject(wrappedValue: buddyController)
        _automationRouter = StateObject(wrappedValue: automationRouter)
        _bubbleController = StateObject(wrappedValue: bubbleController)
        _scheduler = StateObject(wrappedValue: scheduler)
        _meetingDetector = StateObject(wrappedValue: meetingDetector)
        _meetingRecorder = StateObject(wrappedValue: meetingRecorder)
        _meetingManager = StateObject(wrappedValue: meetingManager)
        
        Log.app.info("Nudger initializing...")
    }
    
    // MARK: - App Body
    
    var body: some Scene {
        // Onboarding window (shown on first launch)
        Window("Nudger Setup", id: "onboarding") {
            if !onboardingManager.hasCompletedOnboarding {
                OnboardingView(
                    manager: onboardingManager,
                    buddyController: buddyController,
                    bubbleController: bubbleController
                )
                    .onAppear {
                        // Configure window appearance
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
                                window.isOpaque = false
                                window.backgroundColor = .clear
                                window.hasShadow = true
                                window.level = .floating
                                window.isMovableByWindowBackground = true
                            }
                        }
                    }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        MenuBarExtra("Nudger", systemImage: "cursorarrow.rays") {
            MenuContent(
                settings: settings,
                contextService: contextService,
                buddyController: buddyController,
                scheduler: scheduler,
                onboardingManager: onboardingManager
            )
            .onAppear {
                // DON'T start anything if onboarding is not completed
                // Onboarding will handle buddy positioning
                if onboardingManager.hasCompletedOnboarding && settings.isActive {
                    handleActiveToggle(true)
                }
                
                // Show onboarding if not completed
                if !onboardingManager.hasCompletedOnboarding {
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
            .onChange(of: onboardingManager.hasCompletedOnboarding) { _, completed in
                if completed {
                    // Close onboarding window
                    NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" })?.close()
                    
                    // NOW start the app for real
                    if settings.isActive {
                        handleActiveToggle(true)
                    }
                }
            }
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: settings.isActive) { _, newValue in
            handleActiveToggle(newValue)
        }
    }
    
    // MARK: - Lifecycle Handlers
    
    private func handleActiveToggle(_ isActive: Bool) {
        if isActive {
            buddyController.start()
            scheduler.start()
            meetingManager.startMonitoring()  // Start meeting detection
            Log.app.info("Nudger activated")
        } else {
            scheduler.stop()
            buddyController.stop()
            bubbleController.hide()
            meetingManager.stopMonitoring()  // Stop meeting detection
            Log.app.info("Nudger deactivated")
        }
    }
}

// MARK: - Menu Content

struct MenuContent: View {
    
    @ObservedObject var settings: SettingsStore
    @ObservedObject var contextService: ContextService
    @ObservedObject var buddyController: BuddyController
    @ObservedObject var scheduler: SuggestScheduler
    @ObservedObject var onboardingManager: OnboardingManager
    
    var body: some View {
        // Active toggle
        Toggle("Active", isOn: $settings.isActive)
            .keyboardShortcut("a", modifiers: [.command])
        
        // Frequency slider
        VStack(alignment: .leading, spacing: 4) {
            Text("Frequency")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Rare")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Slider(value: $settings.frequency, in: 0...1)
                
                Text("Often")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        
        Divider()
        
        // Dev mode toggle
        Toggle("Developer Mode", isOn: $settings.devMode)
        
        // Dev mode content
        if settings.devMode {
            Divider()
            
            Group {
                Text("Debug Tools")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Trigger suggestion now") {
                    Task {
                        await scheduler.triggerNow()
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                
                Button("Reset buddy position") {
                    buddyController.resetPosition()
                }
                
                Button("Reset onboarding") {
                    onboardingManager.resetOnboarding()
                    NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" })?.makeKeyAndOrderFront(nil)
                }
                
                Divider()
                
                // Context info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Window")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(contextService.currentContext.appName.isEmpty ? "-" : contextService.currentContext.appName)
                        .font(.caption)
                        .lineLimit(1)
                    
                    if !contextService.currentContext.windowTitle.isEmpty {
                        Text(contextService.currentContext.windowTitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                
                Divider()
                
                // Accessibility status
                if AccessibilityHelper.isTrusted {
                    Label("Accessibility enabled", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button("Request Accessibility") {
                        AccessibilityHelper.requestAccessibility()
                    }
                    Button("Open System Settings") {
                        AccessibilityHelper.openAccessibilitySettings()
                    }
                }
            }
        }
        
        Divider()
        
        // Quit button
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}

// MARK: - Preview

#Preview {
    let settings = SettingsStore()
    let buddyController = BuddyController(settings: settings)
    let onboardingManager = OnboardingManager()
    let meetingDetector = MeetingDetector()
    
    MenuContent(
        settings: settings,
        contextService: ContextService(),
        buddyController: buddyController,
        scheduler: SuggestScheduler(
            settings: settings,
            contextService: ContextService(),
            llmClient: LLMClient(),
            buddyController: buddyController,
            bubbleController: BubbleController(buddyController: buddyController),
            automationRouter: AutomationRouter(buddyController: buddyController),
            onboardingManager: onboardingManager,
            meetingDetector: meetingDetector
        ),
        onboardingManager: onboardingManager
    )
}

