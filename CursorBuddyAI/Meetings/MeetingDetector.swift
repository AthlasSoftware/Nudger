//
//  MeetingDetector.swift
//  CursorBuddyAI
//
//  Created on 2025-10-28.
//

import Foundation
import AppKit
import Combine
import os.log

/// Detects when user is in a Teams meeting
@MainActor
class MeetingDetector: ObservableObject {
    
    @Published var isInMeeting = false
    @Published var currentMeetingTitle: String?
    
    private var timer: Timer?
    
    // MARK: - Detection
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForMeeting()
            }
        }
        
        Log.app.info("Meeting detector started")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        Log.app.info("Meeting detector stopped")
    }
    
    private func checkForMeeting() {
        // Check all running apps for Teams meetings, not just frontmost
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  isTeamsApp(bundleId) else { continue }
            
            // Get Teams window titles
            if let meetingTitle = getTeamsMeetingWindow(pid: app.processIdentifier) {
                // Found an active meeting
                if !isInMeeting {
                    isInMeeting = true
                    currentMeetingTitle = meetingTitle
                    Log.app.info("📞 Teams meeting detected: \(meetingTitle)")
                }
                return
            }
        }
        
        // No meeting found
        if isInMeeting {
            isInMeeting = false
            currentMeetingTitle = nil
            Log.app.info("Meeting ended")
        }
    }
    
    private func getTeamsMeetingWindow(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowsRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        
        // Check all windows for meeting indicators
        for window in windows {
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(
                window,
                kAXTitleAttribute as CFString,
                &titleValue
            )
            
            if let title = titleValue as? String,
               isMeetingWindow(title) {
                return extractMeetingTitle(from: title)
            }
        }
        
        return nil
    }
    
    private func isTeamsApp(_ bundleId: String) -> Bool {
        bundleId.contains("microsoft.teams") || 
        bundleId.contains("com.microsoft.teams")
    }
    
    private func isMeetingWindow(_ title: String) -> Bool {
        let lowerTitle = title.lowercased()
        
        // Exclude non-meeting windows
        let excludeKeywords = [
            "chat |",
            "calendar |",
            "activity |",
            "teams |",
            "files |"
        ]
        
        for keyword in excludeKeywords {
            if lowerTitle.hasPrefix(keyword.lowercased()) {
                return false
            }
        }
        
        // Look for actual meeting indicators
        let meetingKeywords = [
            "meeting |",
            "meeting -",
            "call with",
            "| meeting",
            "video call"
        ]
        
        for keyword in meetingKeywords {
            if lowerTitle.contains(keyword.lowercased()) {
                return true
            }
        }
        
        // Also check if window title is very short and ends with "| Microsoft Teams"
        // (this often indicates an active meeting window)
        if lowerTitle.hasSuffix("| microsoft teams") {
            let prefix = lowerTitle.replacingOccurrences(of: "| microsoft teams", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            // If prefix is just a name or short title (< 30 chars), likely a meeting
            if prefix.count > 0 && prefix.count < 30 && !prefix.contains("|") {
                return true
            }
        }
        
        return false
    }
    
    private func extractMeetingTitle(from windowTitle: String) -> String {
        // Extract meeting name from window title
        // Usually format: "Meeting Name | Microsoft Teams"
        if let range = windowTitle.range(of: "|") {
            return String(windowTitle[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func getWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let pid = app.processIdentifier as pid_t? else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        
        guard result == .success, let window = focusedWindow else {
            return nil
        }
        
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        
        return titleValue as? String
    }
}
