//
//  BuddyController.swift
//  Nudger
//
//  Created on 2025-10-27.
//

import Foundation
import AppKit
import SwiftUI
import Combine
import os.log

/// Manages the buddy panel (NSPanel) with click-through and drag support
@MainActor
class BuddyController: ObservableObject {
    
    private var panel: NSPanel?
    private let settings: SettingsStore
    
    @Published var isRecording = false  // Bind to meeting recorder
    
    private var eventMonitor: Any?
    private var isCommandDown = false
    private var animationTimer: Timer?
    
    init(settings: SettingsStore) {
        self.settings = settings
    }
    
    // MARK: - Public API
    
    func start() {
        guard panel == nil else { return }
        
        Log.buddy.info("Starting buddy")
        
        let position = settings.buddyPosition
        let size = CGSize(width: 48, height: 48)
        let rect = NSRect(origin: position, size: size)
        
        // Create borderless, floating panel
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.ignoresMouseEvents = true  // Click-through by default
        
        // Host SwiftUI view with recording state binding
        let contentView = NSHostingView(rootView: BuddyView(isRecording: isRecording))
        contentView.frame = panel.contentView!.bounds
        panel.contentView = contentView
        
        panel.orderFrontRegardless()
        
        self.panel = panel
        
        // Monitor Command key for drag mode
        startCommandMonitor()
    }
    
    func stop() {
        Log.buddy.info("Stopping buddy")
        stopCommandMonitor()
        panel?.close()
        panel = nil
    }
    
    func setVisible(_ visible: Bool) {
        panel?.orderOut(nil)
        if visible {
            panel?.orderFrontRegardless()
        }
    }
    
    /// Update recording state and refresh view
    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        
        // Refresh the view with new recording state
        if let panel = panel {
            let contentView = NSHostingView(rootView: BuddyView(isRecording: isRecording))
            contentView.frame = panel.contentView!.bounds
            panel.contentView = contentView
        }
        
        Log.buddy.info("Recording state: \(recording)")
    }
    
    var frame: NSRect {
        return panel?.frame ?? .zero
    }
    
    func resetPosition() {
        settings.resetBuddyPosition()
        let position = settings.buddyPosition
        panel?.setFrameOrigin(position)
    }
    
    /// Animate buddy to a specific screen position
    func animateTo(_ targetPoint: CGPoint, duration: TimeInterval = 0.8, completion: @escaping () -> Void = {}) {
        guard let panel = panel else { 
            completion()
            return 
        }
        
        Log.buddy.info("Animating buddy to (\(targetPoint.x), \(targetPoint.y))")
        
        let startOrigin = panel.frame.origin
        let startTime = Date()
        
        // Cancel any existing animation
        animationTimer?.invalidate()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)
            
            MainActor.assumeIsolated {
                guard let self = self, let panel = self.panel else {
                    self?.animationTimer?.invalidate()
                    completion()
                    return
                }
                
                let eased = self.easeInOutQuad(progress)
                
                let currentX = startOrigin.x + (targetPoint.x - startOrigin.x) * eased
                let currentY = startOrigin.y + (targetPoint.y - startOrigin.y) * eased
                
                panel.setFrameOrigin(CGPoint(x: currentX, y: currentY))
                
                if progress >= 1.0 {
                    self.animationTimer?.invalidate()
                    self.animationTimer = nil
                    completion()
                }
            }
        }
    }
    
    /// Return buddy to its saved home position
    func returnHome(duration: TimeInterval = 0.6) {
        // Get the original home position (not the current animated position)
        guard let homeData = UserDefaults.standard.data(forKey: "buddyPosition"),
              let homePosition = try? JSONDecoder().decode(CGPoint.self, from: homeData) else {
            // Fallback to default
            let defaultPos = settings.buddyPosition
            animateTo(defaultPos, duration: duration)
            return
        }
        
        // Don't update settings.buddyPosition on return - keep the home position
        guard let panel = panel else { return }
        
        Log.buddy.info("Returning buddy home")
        
        let startOrigin = panel.frame.origin
        let startTime = Date()
        
        animationTimer?.invalidate()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)
            
            MainActor.assumeIsolated {
                guard let self = self, let panel = self.panel else {
                    self?.animationTimer?.invalidate()
                    return
                }
                
                let easedProgress = self.easeInOutQuad(progress)
                
                let currentX = startOrigin.x + (homePosition.x - startOrigin.x) * easedProgress
                let currentY = startOrigin.y + (homePosition.y - startOrigin.y) * easedProgress
                
                panel.setFrameOrigin(CGPoint(x: currentX, y: currentY))
                
                if progress >= 1.0 {
                    self.animationTimer?.invalidate()
                    self.animationTimer = nil
                    // Don't save position - we're returning home, not moving home
                }
            }
        }
    }
    
    // Ease-in-out cubic function for smooth animation
    private func easeInOutQuad(_ t: Double) -> Double {
        if t < 0.5 {
            return 2 * t * t
        } else {
            return -1 + (4 - 2 * t) * t
        }
    }
    
    // MARK: - Command Key Monitoring
    
    private func startCommandMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            
            let commandPressed = event.modifierFlags.contains(.command)
            
            if commandPressed != self.isCommandDown {
                self.isCommandDown = commandPressed
                self.updateDragMode(enabled: commandPressed)
            }
            
            return event
        }
    }
    
    private func stopCommandMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func updateDragMode(enabled: Bool) {
        guard let panel = panel else { return }
        
        panel.ignoresMouseEvents = !enabled
        
        if enabled {
            Log.buddy.debug("Drag mode enabled (⌘ held)")
            panel.isMovableByWindowBackground = true
        } else {
            Log.buddy.debug("Drag mode disabled (⌘ released)")
            panel.isMovableByWindowBackground = false
            
            // Save position
            let origin = panel.frame.origin
            settings.buddyPosition = origin
            Log.buddy.info("Saved buddy position: (\(origin.x), \(origin.y))")
        }
    }
}

