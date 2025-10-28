//
//  AutomationRouter.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import Foundation
import AppKit
import Combine
import os.log

/// Routes automation actions from suggestions
@MainActor
class AutomationRouter: ObservableObject {
    
    private let buddyController: BuddyController
    private var bubbleController: BubbleController?
    
    init(buddyController: BuddyController) {
        self.buddyController = buddyController
    }
    
    /// Set bubble controller (needed for follow-up messages)
    func setBubbleController(_ controller: BubbleController) {
        self.bubbleController = controller
    }
    
    /// Handle a suggestion action
    func handle(_ action: Suggestion.Action, url: URL?) {
        Log.automation.info("Handling action: \(action.rawValue)")
        
        switch action {
        case .none:
            Log.automation.debug("No action to perform")
            
        case .openURL:
            if let url = url {
                // Check if we're in an editor/IDE - just open in browser, don't paste
                if isInEditor() {
                    _ = NSWorkspace.shared.open(url)
                    Log.automation.info("In editor - opened URL in browser: \(url)")
                } else {
                    _ = NSWorkspace.shared.open(url)
                    Log.automation.info("Opened URL: \(url)")
                }
            }
            
        case .pauseAndOpenURL:
            if let url = url {
                // Check if we're in an editor - don't try to pause/paste, just open
                if isInEditor() {
                    _ = NSWorkspace.shared.open(url)
                    Log.automation.info("In editor - opened URL in browser instead of paste: \(url)")
                } else {
                    Log.automation.info("pauseAndOpenURL -> will pause and open")
                    animateBuddyAndOpenURL(url)
                }
            } else {
                Log.automation.warning("pauseAndOpenURL action but no URL provided")
            }
        }
    }
    
    /// Check if current app is a text editor or IDE
    private func isInEditor() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let editorBundleIds = [
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "com.sublimetext.4",
            "com.sublimetext.3",
            "com.jetbrains.intellij",
            "com.jetbrains.pycharm",
            "com.jetbrains.webstorm",
            "com.github.atom",
            "com.coteditor.CotEditor",
            "com.panic.Nova",
            "com.torusknot.SourceFinderPro",
            "com.barebones.bbedit"
        ]
        
        return editorBundleIds.contains(frontApp.bundleIdentifier ?? "")
    }
    
    // MARK: - Animated Actions
    
    private func animateBuddyAndOpenURL(_ url: URL) {
        Log.automation.info("Opening URL with pause-and-open flow: \(url)")
        
        Task { @MainActor in
            // Get current mouse/content location
            let mouseLocation = NSEvent.mouseLocation
            
            // Step 1: Click to pause current video
            _ = await self.clickAtLocation(mouseLocation)
            Log.automation.info("Clicked to pause current content")
            
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            
            // Step 2: Open new tab with Cmd+T
            await self.openNewTab()
            Log.automation.info("Opened new tab")
            
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            
            // Step 3: Paste URL and press Enter
            await self.pasteAndGo(url.absoluteString)
            Log.automation.info("Pasted URL and navigated")
            
            // Step 4: Wait for page to load, then click to play
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s for page load
            
            // Click center of screen to start video
            if let screen = NSScreen.main {
                let screenCenter = CGPoint(
                    x: screen.frame.midX,
                    y: screen.frame.midY
                )
                _ = await self.clickAtLocation(screenCenter)
                Log.automation.info("Clicked to play new content")
            }
            
            Log.automation.info("Complete pause-open-play flow finished")
        }
    }
    
    // MARK: - Automation Helpers
    
    private func clickAtLocation(_ location: CGPoint) async {
        let source = CGEventSource(stateID: .hidSystemState)
        
        if let clickDown = CGEvent(mouseEventSource: source,
                                   mouseType: .leftMouseDown,
                                   mouseCursorPosition: location,
                                   mouseButton: .left),
           let clickUp = CGEvent(mouseEventSource: source,
                                mouseType: .leftMouseUp,
                                mouseCursorPosition: location,
                                mouseButton: .left) {
            clickDown.post(tap: .cghidEventTap)
            clickUp.post(tap: .cghidEventTap)
        }
    }
    
    private func openNewTab() async {
        // Cmd+T to open new tab
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        
        let tDown = CGEvent(keyboardEventSource: source, virtualKey: 0x11, keyDown: true) // T key
        tDown?.flags = .maskCommand
        
        let tUp = CGEvent(keyboardEventSource: source, virtualKey: 0x11, keyDown: false)
        tUp?.flags = .maskCommand
        
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.post(tap: .cghidEventTap)
        tDown?.post(tap: .cghidEventTap)
        tUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        Log.automation.info("Opened new tab with Cmd+T")
    }
    
    private func pasteAndGo(_ text: String) async {
        // Put URL on clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Cmd+V to paste
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        // Wait a bit then press Enter
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        
        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
        
        Log.automation.info("Pasted URL and pressed Enter")
    }
}

