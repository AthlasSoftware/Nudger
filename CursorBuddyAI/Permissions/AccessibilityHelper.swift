//
//  AccessibilityHelper.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import Foundation
import AppKit
import ApplicationServices

/// Helper for managing Accessibility permissions
class AccessibilityHelper {
    
    /// Check if the app is trusted for Accessibility
    static var isTrusted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request Accessibility permissions (shows system prompt or opens settings)
    static func requestAccessibility() {
        // Trigger the system prompt by attempting an AX operation
        let trustedWithPrompt = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary)
        
        // If already trusted, we're done
        if trustedWithPrompt {
            return
        }
        
        // If not trusted and on newer macOS where prompt may not appear,
        // open settings after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !AXIsProcessTrusted() {
                openAccessibilitySettings()
            }
        }
    }

    /// Open System Settings at Privacy → Accessibility
    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                break
            }
        }
    }
}

