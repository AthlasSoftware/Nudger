//
//  BuddyController.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import Foundation
import AppKit
import SwiftUI
import Combine
import ScreenCaptureKit
import os.log

/// Manages the buddy panel (NSPanel) with click-through and drag support
@MainActor
class BuddyController: ObservableObject {
    
    private var panel: NSPanel?
    private var menuPanel: NSPanel?
    private var timerPanel: NSPanel?  // Separate panel for timer overlay
    private let settings: SettingsStore
    
    @Published var isRecording = false  // Bind to meeting recorder
    @Published var recordingDuration: TimeInterval = 0
    @Published var isProcessing = false  // Processing transcription/notes after recording
    
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    
    /// Check if the menu is currently open
    var isMenuOpen: Bool {
        return menuPanel != nil
    }
    
    private var eventMonitor: Any?
    private var isCommandDown = false
    private var animationTimer: Timer?
    private var recordingTimer: Timer?
    
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
        panel.ignoresMouseEvents = false  // Enable clicks
        
        // Host SwiftUI view with recording state binding
        let contentView = NSHostingView(rootView: BuddyView(isRecording: isRecording, recordingDuration: recordingDuration, isProcessing: isProcessing))
        contentView.frame = panel.contentView!.bounds
        panel.contentView = contentView
        
        // Add click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleBuddyClick))
        contentView.addGestureRecognizer(clickGesture)
        
        panel.orderFrontRegardless()
        
        self.panel = panel
        
        // Monitor Command key for drag mode
        startCommandMonitor()
    }
    
    func stop() {
        Log.buddy.info("Stopping buddy")
        stopCommandMonitor()
        stopRecordingTimer()
        hideTimer()
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
        
        if recording {
            startRecordingTimer()
            showTimer()
        } else {
            stopRecordingTimer()
            hideTimer()
        }
        
        updateView()
        updateInteractivity()
        
        Log.buddy.info("Recording state: \(recording)")
    }
    
    /// Set processing state (transcribing/generating notes)
    func setProcessing(_ processing: Bool) {
        guard isProcessing != processing else { return }
        isProcessing = processing
        
        updateView()
        updateInteractivity()
        
        Log.buddy.info("Processing state: \(processing)")
    }
    
    /// Update the view with current recording state and duration
    private func updateView() {
        guard let panel = panel else { return }
        
        // Panel always stays 48x48 - NEVER resizes
        let contentView = NSHostingView(rootView: BuddyView(isRecording: isRecording, recordingDuration: 0, isProcessing: isProcessing))
        contentView.frame = panel.contentView!.bounds
        panel.contentView = contentView
        
        // Always re-add click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleBuddyClick))
        contentView.addGestureRecognizer(clickGesture)
    }
    
    /// Update just the timer display in separate panel
    private func updateTimerOnly() {
        guard isRecording, let timerPanel = timerPanel else { return }
        
        // Create timer view
        let timerView = TimerView(duration: recordingDuration)
        let contentView = NSHostingView(rootView: timerView)
        contentView.frame = timerPanel.contentView!.bounds
        timerPanel.contentView = contentView
    }
    
    /// Show timer in separate floating panel to the left of buddy
    private func showTimer() {
        guard let buddyPanel = panel else { return }
        hideTimer()  // Clean up any existing
        
        let buddyFrame = buddyPanel.frame
        let timerWidth: CGFloat = 60
        let timerHeight: CGFloat = 24
        let timerX = buddyFrame.minX - timerWidth - 8
        let timerY = buddyFrame.midY - timerHeight / 2
        
        let timerRect = NSRect(x: timerX, y: timerY, width: timerWidth, height: timerHeight)
        
        let panel = NSPanel(
            contentRect: timerRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.ignoresMouseEvents = true
        
        let timerView = TimerView(duration: recordingDuration)
        let contentView = NSHostingView(rootView: timerView)
        contentView.frame = panel.contentView!.bounds
        panel.contentView = contentView
        
        panel.orderFrontRegardless()
        self.timerPanel = panel
        
        Log.buddy.info("Timer panel shown")
    }
    
    /// Hide timer panel
    private func hideTimer() {
        timerPanel?.close()
        timerPanel = nil
    }
    
    /// Update buddy interactivity based on recording state
    private func updateInteractivity() {
        guard let panel = panel else { return }
        
        // Disable all interactions when recording OR processing
        if isRecording || isProcessing {
            panel.ignoresMouseEvents = true
            panel.isMovableByWindowBackground = false
        } else {
            // When idle: enable clicks (drag mode controlled by Command key)
            panel.ignoresMouseEvents = false
        }
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
    
    // MARK: - Menu
    
    @objc private func handleBuddyClick() {
        // Block clicks when processing
        guard !isProcessing else {
            Log.buddy.info("Buddy clicked while processing - ignoring")
            return
        }
        
        // Ignore clicks when menu is already open
        guard menuPanel == nil else { return }
        
        // Always allow opening menu (it has Stop Recording when recording)
        showMenu()
    }
    
    private func showMenu() {
        guard let buddyPanel = panel else { return }
        guard let screen = NSScreen.main else { return }
        
        let buddyFrame = buddyPanel.frame
        let screenFrame = screen.visibleFrame
        
        // Position menu to the LEFT of buddy (since buddy is in right corner)
        let menuWidth: CGFloat = 220
        let menuHeight: CGFloat = 240
        var menuX = buddyFrame.minX - menuWidth - 10
        var menuY = buddyFrame.midY - menuHeight / 2
        
        // Keep menu on screen - adjust X if goes off left edge
        if menuX < screenFrame.minX {
            // Menu doesn't fit on left, try right side
            menuX = buddyFrame.maxX + 10
            // If still off screen (right edge), clamp it
            if menuX + menuWidth > screenFrame.maxX {
                menuX = screenFrame.maxX - menuWidth - 10
            }
        }
        
        // Keep menu on screen - adjust Y if goes off top/bottom
        if menuY < screenFrame.minY {
            menuY = screenFrame.minY + 10
        } else if menuY + menuHeight > screenFrame.maxY {
            menuY = screenFrame.maxY - menuHeight - 10
        }
        
        let menuRect = NSRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
        
        let menuPanel = NSPanel(
            contentRect: menuRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        menuPanel.backgroundColor = .clear
        menuPanel.isOpaque = false
        menuPanel.hasShadow = false
        menuPanel.level = .floating
        menuPanel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Check screen recording permission
        let hasScreenRecording = checkScreenRecordingPermission()
        
        let menuView = BuddyMenuView(
            isRecording: isRecording,
            isProcessing: isProcessing,
            isMeetingActive: false, // TODO: Get from MeetingManager
            hasScreenRecordingPermission: hasScreenRecording,
            recordingDuration: recordingDuration,
            onStartRecording: { [weak self] in
                self?.hideMenu()
                self?.onStartRecording?()
            },
            onStopRecording: { [weak self] in
                self?.hideMenu()
                self?.onStopRecording?()
            },
            onViewNotes: { [weak self] in
                self?.hideMenu()
                self?.openNotesFolder()
            },
            onSettings: { [weak self] in
                self?.hideMenu()
                self?.openSettings()
            },
            onClose: { [weak self] in
                self?.hideMenu()
            }
        )
        
        let contentView = NSHostingView(rootView: menuView)
        contentView.frame = menuPanel.contentView!.bounds
        menuPanel.contentView = contentView
        
        menuPanel.orderFrontRegardless()
        self.menuPanel = menuPanel
        
        // Disable buddy interactions while menu is open
        buddyPanel.ignoresMouseEvents = true
        
        // Close menu when clicking outside
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.hideMenu()
            }
        }
        
        Log.buddy.info("Showing buddy menu at (\(menuX), \(menuY))")
    }
    
    private func hideMenu() {
        menuPanel?.close()
        menuPanel = nil
        
        // Re-enable buddy interactions when menu closes
        if let buddyPanel = panel, !isCommandDown {
            buddyPanel.ignoresMouseEvents = false
        }
        
        Log.buddy.info("Hiding buddy menu")
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
        
        // Never allow drag mode when recording
        guard !isRecording else { return }
        
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
    
    // MARK: - Recording Timer
    
    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer?.invalidate()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.recordingDuration += 1
                // Update timer display only (no panel resize/move)
                self.updateTimerOnly()
            }
        }
        
        Log.buddy.info("Started recording timer")
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        Log.buddy.info("Stopped recording timer")
    }
    
    // MARK: - Helper Functions
    
    private func checkScreenRecordingPermission() -> Bool {
        // Try to access screen content to check permission
        let task = Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return true
            } catch {
                return false
            }
        }
        
        // This is a synchronous check, so we can't use async here
        // For now, return false if permission not granted yet
        return false
    }
    
    private func openNotesFolder() {
        let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecordings")
        
        if !FileManager.default.fileExists(atPath: recordingsDir.path) {
            try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }
        
        NSWorkspace.shared.open(recordingsDir)
        Log.buddy.info("Opened notes folder")
    }
    
    private func openSettings() {
        // TODO: Implement settings window
        Log.buddy.info("Settings not yet implemented")
    }
}

// MARK: - Timer View

struct TimerView: View {
    let duration: TimeInterval
    
    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        Text(formattedDuration)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.25))
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

