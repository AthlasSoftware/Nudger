//
//  ContextService.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import Foundation
import AppKit
import ApplicationServices
import Combine
import os.log

/// Service that provides lightweight context about the user's current activity
@MainActor
class ContextService: ObservableObject {
    
    @Published private(set) var currentContext: Context = .empty
    
    private var timer: Timer?
    
    init() {
        startMonitoring()
    }
    
    nonisolated deinit {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            NSWorkspace.shared.notificationCenter.removeObserver(self)
        }
    }
    
    // MARK: - Public API
    
    /// Get the current context snapshot
    func current() -> Context {
        return currentContext
    }
    
    // MARK: - Private Monitoring
    
    private func startMonitoring() {
        Task {
            await updateContext()
        }
        
        // Update context every 2 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.updateContext()
            }
        }
        
        // Also listen to workspace notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.updateContext()
            }
        }
    }
    
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    private func updateContext() async {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            currentContext = .empty
            return
        }
        
        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? ""
        
        // Read window title via AX (required). No fallbacks.
        let windowTitle = getWindowTitle(for: app)
        
        currentContext = Context(
            bundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            domain: nil  // v2: extract domain from browser
        )
        
        Log.context.debug("Context updated: \(appName) (\(bundleId))")
    }
    
    /// Attempt to get window title (requires Accessibility permissions)
    /// Returns empty string if not available
    private func getWindowTitle(for app: NSRunningApplication) -> String {
        guard let pid = app.processIdentifier as pid_t? else { return "" }
        
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
            // CFTypeRef -> AXUIElement (bridged CF type)
            windowElement = (fwObj as! AXUIElement)
        } else {
            // Fallback: use the first window in kAXWindows
            var windowsObj: AnyObject?
            let windowsResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsObj
            )
            if windowsResult == .success, let windows = windowsObj as? [AXUIElement], let first = windows.first {
                windowElement = first
                Log.context.debug("Focused window missing; used first window from kAXWindows")
            } else {
                Log.context.debug("No windows available via AX for app \(app.localizedName ?? "")")
                return ""
            }
        }
        
        // Read title
        var title: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            windowElement!,
            kAXTitleAttribute as CFString,
            &title
        )
        
        guard titleResult == .success, let titleString = title as? String else {
            Log.context.debug("AXTitle missing for app \(app.localizedName ?? "")")
            return ""
        }
        
        let trimmed = String(titleString.prefix(200))
        Log.context.debug("Got window title: \(trimmed)")
        return trimmed
    }

    // No non-AX fallbacks by design
}

