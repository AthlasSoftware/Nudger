//
//  MeetingDetector.swift
//  Nudger
//
//  Created on 2025-10-28.
//

import Foundation
import AppKit
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
            Task { @MainActor in
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
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        let bundleId = app.bundleIdentifier ?? ""
        let windowTitle = getWindowTitle() ?? ""
        
        // Detect Teams meeting
        let isTeamsMeeting = isTeamsApp(bundleId) && isMeetingWindow(windowTitle)
        
        if isTeamsMeeting && !isInMeeting {
            // Meeting started
            isInMeeting = true
            currentMeetingTitle = extractMeetingTitle(from: windowTitle)
            Log.app.info("📞 Teams meeting detected: \(self.currentMeetingTitle ?? "Untitled")")
        } else if !isTeamsMeeting && isInMeeting {
            // Meeting ended
            isInMeeting = false
            currentMeetingTitle = nil
            Log.app.info("Meeting ended")
        }
    }
    
    private func isTeamsApp(_ bundleId: String) -> Bool {
        bundleId.contains("microsoft.teams") || 
        bundleId.contains("com.microsoft.teams")
    }
    
    private func isMeetingWindow(_ title: String) -> Bool {
        let meetingKeywords = [
            "meeting",
            "call",
            "| Microsoft Teams",
            "video call"
        ]
        
        return meetingKeywords.contains { keyword in
            title.lowercased().contains(keyword.lowercased())
        }
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
