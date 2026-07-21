//
//  BubbleController.swift
//  Nudger
//
//  Created on 2025-10-27.
//

import Foundation
import AppKit
import SwiftUI
import Combine
import os.log

/// Manages the speech bubble panel
@MainActor
class BubbleController: ObservableObject {
    
    private var panel: NSPanel?
    private var autoHideTask: Task<Void, Never>?
    
    private let buddyController: BuddyController
    
    init(buddyController: BuddyController) {
        self.buddyController = buddyController
    }
    
    // MARK: - Public API
    
    /// Show bubble with optional buttons (for questions)
    func show(
        text: String,
        onAccept: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        autoHideAfter: TimeInterval = 0  // 0 = never auto-hide
    ) {
        let showButtons = (onAccept != nil && onDismiss != nil)
        Log.bubble.info("Showing bubble [\(showButtons ? "with buttons" : "info only")]: '\(text)'")
        
        guard !text.isEmpty else {
            Log.bubble.warning("Attempted to show bubble with empty text - ignoring")
            return
        }
        
        // Cancel any existing auto-hide
        autoHideTask?.cancel()
        
        // Close existing panel
        if let existing = panel {
            existing.close()
        }
        
        // Create bubble view
        let bubbleView = BubbleView(
            message: text,
            onAccept: onAccept != nil ? { [weak self] in
                self?.hide()
                onAccept?()
            } : nil,
            onDismiss: onDismiss != nil ? { [weak self] in
                self?.hide()
                onDismiss?()
            } : nil,
            showButtons: showButtons
        )
        
        // Calculate position relative to buddy
        let position = calculatePosition()
        
        // Create panel
        let panel = NSPanel(
            contentRect: NSRect(origin: position, size: CGSize(width: 280, height: 100)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Host SwiftUI view
        let contentView = NSHostingView(rootView: bubbleView)
        panel.contentView = contentView
        
        // Pre-calculate size with full message to avoid resizing during typewriter
        let sizingView = BubbleView(
            message: text,
            onAccept: nil,
            onDismiss: nil,
            showButtons: showButtons
        )
        let sizingHost = NSHostingView(rootView: sizingView)
        let fittingSize = sizingHost.fittingSize
        panel.setContentSize(fittingSize)
        
        // Re-position after sizing
        let finalPosition = calculatePosition(bubbleSize: fittingSize)
        panel.setFrameOrigin(finalPosition)
        
        panel.orderFrontRegardless()
        
        self.panel = panel
        
        // Schedule auto-hide (only if autoHideAfter > 0)
        if autoHideAfter > 0 {
            autoHideTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(autoHideAfter * 1_000_000_000))
                if !Task.isCancelled {
                    self.hide()
                }
            }
        }
        
        // Start global keyboard monitoring for y/n (only if buttons are shown)
        if showButtons, let onAccept = onAccept, let onDismiss = onDismiss {
            startKeyboardMonitoring(onAccept: onAccept, onDismiss: onDismiss)
        }
    }
    
    // MARK: - Keyboard Monitoring
    
    private var keyMonitor: Any?
    
    private func startKeyboardMonitoring(onAccept: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        stopKeyboardMonitoring()
        
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.panel != nil else { return }
            
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            
            if key == "y" {
                self.hide()
                onAccept()
            } else if key == "n" {
                self.hide()
                onDismiss()
            }
        }
    }
    
    private func stopKeyboardMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    /// Show info-only bubble (no buttons)
    func showInfo(text: String, autoHideAfter: TimeInterval = 3.0) {
        show(text: text, onAccept: nil, onDismiss: nil, autoHideAfter: autoHideAfter)
    }
    
    func hide() {
        Log.bubble.debug("Hiding bubble")
        stopKeyboardMonitoring()
        autoHideTask?.cancel()
        panel?.close()
        panel = nil
    }
    
    // MARK: - Positioning
    
    private func calculatePosition(bubbleSize: CGSize = CGSize(width: 280, height: 80)) -> CGPoint {
        let buddyFrame = buddyController.frame
        guard let screen = NSScreen.main else {
            return CGPoint(x: 100, y: 100)
        }
        
        let screenFrame = screen.visibleFrame
        
        // Show bubble next to the AI buddy (to the right by default)
        var x = buddyFrame.maxX + 16
        var y = buddyFrame.midY - (bubbleSize.height / 2)
        
        let padding: CGFloat = 20
        
        // Flip to left if too close to right edge
        if x + bubbleSize.width > screenFrame.maxX - padding {
            x = buddyFrame.minX - bubbleSize.width - 16
        }
        
        // Adjust Y if too close to edges
        if y + bubbleSize.height > screenFrame.maxY - padding {
            y = buddyFrame.minY - bubbleSize.height - 16
        }
        if y < screenFrame.minY + padding {
            y = buddyFrame.maxY + 16
        }
        
        return CGPoint(x: x, y: y)
    }
}

