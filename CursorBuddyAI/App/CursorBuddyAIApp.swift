//
//  CursorBuddyAIApp.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import SwiftUI
import os.log

@main
struct CursorBuddyAIApp: App {
    
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
            bubbleController: bubbleController,
            settings: settings
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
        // Onboarding window (conditionally shown)
        Window("Nudger Setup", id: "onboarding") {
            if !onboardingManager.hasCompletedOnboarding {
                OnboardingView(
                    manager: onboardingManager,
                    buddyController: buddyController,
                    bubbleController: bubbleController,
                    settings: settings
                )
                    .frame(width: 500, height: 600)
                    .background(Color.clear)
                    .onAppear {
                        // Configure window appearance
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
                                window.isOpaque = false
                                window.backgroundColor = .clear
                                window.hasShadow = false
                                window.level = .floating
                                window.isMovableByWindowBackground = true
                                window.titlebarAppearsTransparent = true
                                window.titleVisibility = .hidden
                                window.styleMask.insert(.borderless)
                                window.styleMask.remove(.titled)
                                window.standardWindowButton(.closeButton)?.isHidden = true
                                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                                window.standardWindowButton(.zoomButton)?.isHidden = true
                            }
                        }
                    }
            } else {
                // Empty view when onboarding is complete
                EmptyView()
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
    
    @AppStorage("developerMode") private var developerMode = false
    
    var body: some View {
        // Status section
        Section {
            HStack {
                Circle()
                    .fill(settings.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .shadow(color: settings.isActive ? .green.opacity(0.6) : .clear, radius: 4)
                
                Text(settings.isActive ? "Active" : "Inactive")
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
                
                Toggle("", isOn: $settings.isActive)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        
        Divider()
        
        // Quick actions
        Section("Actions") {
            Button(action: { openNotesFolder() }) {
                Label("Meeting Notes", systemImage: "doc.text.fill")
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Button(action: { /* TODO */ }) {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
        
        Divider()
        
        // Suggestion settings
        Section("Suggestions") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Frequency")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(frequencyLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                
                Slider(value: $settings.frequency, in: 0...1)
                    .controlSize(.small)
                
                HStack {
                    Text("Rare")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Often")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        
        // Developer mode toggle
        Divider()
        
        Toggle("Developer Mode", isOn: $developerMode)
            .font(.system(size: 12, weight: .medium))
        
        // Developer section
        if developerMode {
            Divider()
            
            Section("Developer") {
                // Quick actions
                Button(action: { 
                    Task { await scheduler.triggerNow() }
                }) {
                    Label("Trigger Suggestion", systemImage: "sparkles")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                
                Button(action: { buddyController.resetPosition() }) {
                    Label("Reset Buddy Position", systemImage: "arrow.counterclockwise")
                }
                
                Button(action: { 
                    onboardingManager.resetOnboarding()
                    NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" })?.makeKeyAndOrderFront(nil)
                }) {
                    Label("Reset Onboarding", systemImage: "arrow.uturn.backward")
                }
            }
            
            Divider()
            
            Section("System Status") {
                // Context info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Active Window")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    if !contextService.currentContext.appName.isEmpty {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                            
                            Text(contextService.currentContext.appName)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }
                        
                        if !contextService.currentContext.windowTitle.isEmpty {
                            Text(contextService.currentContext.windowTitle)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .padding(.leading, 8)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
                
                Divider()
                
                // Permissions status
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Permissions")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    PermissionRow(
                        name: "Accessibility",
                        granted: AccessibilityHelper.isTrusted,
                        action: {
                            if !AccessibilityHelper.isTrusted {
                                AccessibilityHelper.openAccessibilitySettings()
                            }
                        }
                    )
                    
                    PermissionRow(
                        name: "Microphone",
                        granted: settings.meetingNotesEnabled,
                        action: nil
                    )
                    
                    PermissionRow(
                        name: "Screen Recording",
                        granted: checkScreenRecordingPermission(),
                        action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )
                }
                .padding(.vertical, 2)
                
                Divider()
                
                // Scheduler info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Scheduler")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    HStack {
                        Text("Interval")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1fs", scheduler.currentInterval))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                    
                    HStack {
                        Text("Next tick")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(scheduler.isRunning ? "running" : "stopped")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(scheduler.isRunning ? .green : .gray)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        
        Divider()
        
        // Quit button
        Button("Quit Nudger") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
    
    private var frequencyLabel: String {
        switch settings.frequency {
        case 0..<0.25: return "RARE"
        case 0.25..<0.5: return "LOW"
        case 0.5..<0.75: return "MEDIUM"
        default: return "HIGH"
        }
    }
    
    private func openNotesFolder() {
        let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecordings")
        
        if !FileManager.default.fileExists(atPath: recordingsDir.path) {
            try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }
        
        NSWorkspace.shared.open(recordingsDir)
    }
    
    private func checkScreenRecordingPermission() -> Bool {
        // Simple heuristic - if we can't check async, assume false
        return false
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let name: String
    let granted: Bool
    let action: (() -> Void)?
    
    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(granted ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                
                Text(name)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.green)
                } else if action != nil {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
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

