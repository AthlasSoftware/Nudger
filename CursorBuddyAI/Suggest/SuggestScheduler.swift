//
//  SuggestScheduler.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import Foundation
import AppKit
import Combine
import os.log

/// Schedules and manages suggestion prompts with jittered timing and cooldowns
@MainActor
class SuggestScheduler: ObservableObject {
    
    private let settings: SettingsStore
    private let contextService: ContextService
    private let llmClient: LLMClient
    private let buddyController: BuddyController
    private let bubbleController: BubbleController
    private let automationRouter: AutomationRouter
    private let onboardingManager: OnboardingManager
    private let meetingDetector: MeetingDetector
    
    private var timer: Timer?
    private var hasShownAPIKeyWarning = false
    
    init(
        settings: SettingsStore,
        contextService: ContextService,
        llmClient: LLMClient,
        buddyController: BuddyController,
        bubbleController: BubbleController,
        automationRouter: AutomationRouter,
        onboardingManager: OnboardingManager,
        meetingDetector: MeetingDetector
    ) {
        self.settings = settings
        self.contextService = contextService
        self.llmClient = llmClient
        self.buddyController = buddyController
        self.bubbleController = bubbleController
        self.automationRouter = automationRouter
        self.onboardingManager = onboardingManager
        self.meetingDetector = meetingDetector
        
        // Wire up bubble controller to automation router for follow-up messages
        automationRouter.setBubbleController(bubbleController)
    }
    
    // MARK: - Lifecycle
    
    func start() {
        guard timer == nil else { return }
        
        Log.scheduler.info("Starting suggestion scheduler")
        
        // Check API key first
        if !llmClient.hasAPIKey && !hasShownAPIKeyWarning {
            showAPIKeyWarning()
            hasShownAPIKeyWarning = true
            return
        }
        
        scheduleNextTick()
    }
    
    func stop() {
        Log.scheduler.info("Stopping suggestion scheduler")
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Scheduling
    
    private func scheduleNextTick() {
        // Jittered interval: 3-5 seconds
        let interval = Double.random(in: 3.0...5.0)
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
                self?.scheduleNextTick()
            }
        }
    }
    
    private func tick() async {
        // CRITICAL: Block completely during onboarding
        guard onboardingManager.hasCompletedOnboarding else {
            Log.scheduler.debug("Skipping tick (onboarding in progress)")
            return
        }
        
        // CRITICAL: Block during meetings
        guard !meetingDetector.isInMeeting else {
            Log.scheduler.debug("Skipping tick (in meeting)")
            return
        }
        
        // Check if active
        guard settings.isActive else {
            return
        }
        
        // Random gate based on frequency
        let roll = Double.random(in: 0...1)
        guard roll < settings.frequency else {
            Log.scheduler.debug("Skipping tick (gate: \(roll) >= \(self.settings.frequency))")
            return
        }
        
        // Get current context
        let context = contextService.current()
        
        // Skip if no meaningful context
        guard !context.bundleId.isEmpty else {
            Log.scheduler.debug("Skipping tick (empty context)")
            return
        }
        
        // Cooldown key: domain or bundleId
        let cooldownKey = context.domain ?? context.bundleId
        
        // Check cooldown
        if settings.isOnCooldown(key: cooldownKey) {
            Log.scheduler.debug("Skipping tick (cooldown active for \(cooldownKey))")
            return
        }
        
        // Prune old cooldowns periodically
        settings.pruneCooldowns()
        
        // Request suggestion from LLM
        await requestSuggestion(context: context, cooldownKey: cooldownKey)
    }
    
    // MARK: - Suggestion Request
    
    private func requestSuggestion(context: Context, cooldownKey: String) async {
        let tone: Tone = settings.playfulTone ? .playful : .plain
        
        Log.scheduler.info("Requesting suggestion for \(context.appName)...")
        
        do {
            guard let suggestion = try await llmClient.proposeSuggestion(context: context, tone: tone) else {
                Log.scheduler.debug("No suggestion returned")
                return
            }
            
            // Apply cooldown if specified
            if let cooldownSec = suggestion.cooldownSec {
                settings.setCooldown(key: cooldownKey, seconds: cooldownSec)
            } else {
                // Default cooldown: 120 seconds (2 minutes) - more relaxed
                settings.setCooldown(key: cooldownKey, seconds: 120)
            }
            
            // Show bubble
            showSuggestion(suggestion)
            
        } catch {
            Log.scheduler.error("Failed to get suggestion: \(error.localizedDescription)")
        }
    }
    
    private func showSuggestion(_ suggestion: Suggestion) {
        // Get the frontmost window frame (where user is actually looking)
        guard let windowInfo = getActiveWindowInfo() else {
            Log.scheduler.warning("Could not get active window info")
            return
        }
        
        Log.scheduler.info("Starting animated suggestion flow...")
        
        // STEP 1: Animate buddy toward top-right area of window for greeting
        // Position at ~75% width (right side), ~35% height (upper area)
        let greetingOffset = CGPoint(
            x: windowInfo.x + windowInfo.width * 0.75,
            y: windowInfo.y + windowInfo.height * 0.35
        )
        
        buddyController.animateTo(greetingOffset, duration: 0.8) {
            // STEP 2: Show greeting (from LLM, or skip if just observing)
            if let greeting = suggestion.greeting {
                Log.scheduler.info("Showing greeting: '\(greeting)'")
                
                self.bubbleController.show(
                    text: greeting,
                    onAccept: nil,
                    onDismiss: nil,
                    autoHideAfter: 1.2
                )
            }
            
            // STEP 3: Move to right-middle area for main message
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000) // 1.4 seconds
                
                await MainActor.run {
                    // Position at ~70% width (right side), ~50% height (middle)
                    let messageOffset = CGPoint(
                        x: windowInfo.x + windowInfo.width * 0.70,
                        y: windowInfo.y + windowInfo.height * 0.50
                    )
                    
                    self.buddyController.animateTo(messageOffset, duration: 0.4) {
                        let showButtons = suggestion.showButtons ?? (suggestion.action != .none)
                        
                        if showButtons {
                            // Question/offer with y/n buttons - NO timeout
                            self.bubbleController.show(
                                text: suggestion.message,
                                onAccept: { [weak self] in
                                    guard let self = self else { return }
                                    Log.scheduler.info("User accepted suggestion")
                                    self.handleAcceptWithReaction(suggestion, windowInfo: windowInfo)
                                },
                                onDismiss: { [weak self] in
                                    Log.scheduler.debug("User dismissed suggestion")
                                    self?.buddyController.returnHome()
                                },
                                autoHideAfter: 0  // Never timeout for questions
                            )
                        } else {
                            // Statement/observation without buttons - auto-hide and return
                            self.bubbleController.show(
                                text: suggestion.message,
                                onAccept: nil,
                                onDismiss: nil,
                                autoHideAfter: 5.0
                            )
                            // Return buddy home after showing
                            Task {
                                try? await Task.sleep(nanoseconds: 5_500_000_000)
                                self.buddyController.returnHome()
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Window info for positioning buddy relative to active window
    private struct WindowInfo {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }
    
    /// Get the center of the frontmost app's main window
    private func getActiveWindowInfo() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let pid = app.processIdentifier as pid_t? else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        
        // Try focused window
        var focusedWindow: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        
        var windowElement: AXUIElement?
        if focusedResult == .success, let fwObj = focusedWindow {
            windowElement = (fwObj as! AXUIElement)
        } else {
            // Fallback: use first window
            var windowsObj: AnyObject?
            let windowsResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsObj
            )
            if windowsResult == .success, let windows = windowsObj as? [AXUIElement], let first = windows.first {
                windowElement = first
            }
        }
        
        guard let window = windowElement else { return nil }
        
        // Get window position and size
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        
        guard let positionValue = positionValue,
              let sizeValue = sizeValue else {
            return nil
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        // Return window info
        return WindowInfo(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }
    
    private func handleAccept(_ suggestion: Suggestion) {
        Task { @MainActor in
            // Perform the action
            self.automationRouter.handle(suggestion.action, url: suggestion.url)
            
            // Return buddy home after action completes
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self.buddyController.returnHome()
        }
    }
    
    /// Handle accept with a final reaction before going home
    private func handleAcceptWithReaction(_ suggestion: Suggestion, windowInfo: WindowInfo) {
        Task { @MainActor in
            // STEP 1: Show transition message (what we're about to do)
            if let transitionMessage = suggestion.transitionMessage {
                // Move to right-upper area for transition (~75% width, ~30% height)
                let transitionOffset = CGPoint(
                    x: windowInfo.x + windowInfo.width * 0.75,
                    y: windowInfo.y + windowInfo.height * 0.30
                )
                
                self.buddyController.animateTo(transitionOffset, duration: 0.3) {
                    self.bubbleController.show(
                        text: transitionMessage,
                        onAccept: nil,
                        onDismiss: nil,
                        autoHideAfter: 1.8
                    )
                }
                
                // Wait for transition message to show
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
            
            // STEP 2: Perform the action (this will pause, open, and play)
            self.automationRouter.handle(suggestion.action, url: suggestion.url)
            
            // Wait for action to complete (pause + open tab + paste + go + play)
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds for all automation steps
            
            // STEP 3: Move to right-lower area for reaction (~72% width, ~65% height)
            if let reaction = suggestion.reaction {
                let reactionOffset = CGPoint(
                    x: windowInfo.x + windowInfo.width * 0.72,
                    y: windowInfo.y + windowInfo.height * 0.65
                )
                
                self.buddyController.animateTo(reactionOffset, duration: 0.4) {
                    self.bubbleController.show(
                        text: reaction,
                        onAccept: nil,
                        onDismiss: nil,
                        autoHideAfter: 2.0
                    )
                    
                    // Return home after reaction
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        self.buddyController.returnHome()
                    }
                }
            } else {
                // No reaction, just return home
                self.buddyController.returnHome()
            }
        }
    }
    
    private func showAPIKeyWarning() {
        bubbleController.show(
            text: "Set your OPENAI_API_KEY in Config.swift to activate suggestions.",
            onAccept: nil,
            onDismiss: nil,
            autoHideAfter: 15.0
        )
    }
    
    // MARK: - Manual Trigger (for Debug)
    
    func triggerNow() async {
        let context = contextService.current()
        guard !context.bundleId.isEmpty else {
            Log.scheduler.warning("Cannot trigger: empty context")
            return
        }
        
        let cooldownKey = context.domain ?? context.bundleId
        await requestSuggestion(context: context, cooldownKey: cooldownKey)
    }
}

