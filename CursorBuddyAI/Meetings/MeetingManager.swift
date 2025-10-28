//
//  MeetingManager.swift
//  CursorBuddyAI
//
//  Created on 2025-10-28.
//

import Foundation
import AppKit
import Combine
import os.log

/// Coordinates meeting detection, recording, and notes generation
@MainActor
class MeetingManager: ObservableObject {
    
    private let detector: MeetingDetector
    private let recorder: MeetingRecorder
    private let notesGenerator: MeetingNotesGenerator
    private let buddyController: BuddyController
    private let bubbleController: BubbleController
    private let settings: SettingsStore
    
    @Published var hasAskedToRecord = false
    private var cancellables = Set<AnyCancellable>()
    
    init(
        detector: MeetingDetector,
        recorder: MeetingRecorder,
        notesGenerator: MeetingNotesGenerator,
        buddyController: BuddyController,
        bubbleController: BubbleController,
        settings: SettingsStore
    ) {
        self.detector = detector
        self.recorder = recorder
        self.notesGenerator = notesGenerator
        self.buddyController = buddyController
        self.bubbleController = bubbleController
        self.settings = settings
        
        setupMeetingDetection()
        setupBuddyCallbacks()
    }
    
    // MARK: - Setup
    
    private func setupBuddyCallbacks() {
        // Set up callbacks for buddy menu actions
        buddyController.onStartRecording = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.startManualRecording()
            }
        }
        
        buddyController.onStopRecording = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.stopManualRecording()
            }
        }
    }
    
    private func setupMeetingDetection() {
        // Watch for meeting changes
        detector.$isInMeeting
            .sink { [weak self] isInMeeting in
                guard let self = self else { return }
                
                if isInMeeting {
                    Task { await self.handleMeetingStarted() }
                } else {
                    Task { await self.handleMeetingEnded() }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Meeting Lifecycle
    
    private func handleMeetingStarted() async {
        // Skip if meeting notes are not enabled
        guard settings.meetingNotesEnabled else { return }
        
        guard !hasAskedToRecord else { return }
        guard let meetingTitle = detector.currentMeetingTitle else { return }
        
        Log.app.info("📞 Meeting started: \(meetingTitle)")
        
        // Wait a moment for meeting to stabilize
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Ask if user wants to record
        askToRecord(meetingTitle: meetingTitle)
    }
    
    private func handleMeetingEnded() async {
        guard recorder.isRecording else { return }
        
        Log.app.info("Meeting ended, stopping recording...")
        
        // Set processing state immediately (stops timer, blocks interactions)
        buddyController.setRecording(false)
        buddyController.setProcessing(true)
        
        bubbleController.show(
            text: "meeting ended, transcribing...",
            onAccept: nil,
            onDismiss: nil,
            autoHideAfter: 0  // Don't auto-hide while processing
        )
        
        do {
            // Stop recording and get session
            guard let session = try await recorder.stopRecording() else {
                buddyController.setProcessing(false)
                hasAskedToRecord = false
                return
            }
            
            // Check if we have a transcript
            guard let transcript = session.transcript, !transcript.isEmpty else {
                Log.app.warning("No transcript available (meeting too short or transcription failed)")
                
                buddyController.setProcessing(false)
                
                bubbleController.show(
                    text: "meeting was too short to transcribe",
                    onAccept: nil,
                    onDismiss: nil,
                    autoHideAfter: 3.0
                )
                
                hasAskedToRecord = false
                return
            }
            
            // Show processing message
            bubbleController.show(
                text: "generating notes...",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 0
            )
            
            // Generate notes
            let notes = try await notesGenerator.generateNotes(from: session)
            
            // Export to Pages
            let fileURL = try await notesGenerator.exportToPages(notes: notes)
            
            buddyController.setProcessing(false)
            
            // Show success message
            bubbleController.show(
                text: "notes ready! opened in Pages",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 5.0
            )
            
            Log.app.info("✓ Meeting notes exported: \(fileURL.lastPathComponent)")
            
        } catch {
            Log.app.error("Failed to process meeting: \(error.localizedDescription)")
            
            buddyController.setProcessing(false)
            
            bubbleController.show(
                text: "oops, couldn't process notes",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 3.0
            )
        }
        
        hasAskedToRecord = false
    }
    
    // MARK: - Recording Prompt
    
    private func askToRecord(meetingTitle: String) {
        hasAskedToRecord = true
        
        // Position buddy near Teams window
        positionBuddyNearTeams()
        
        bubbleController.show(
            text: "want me to take notes for this meeting?",
            onAccept: { [weak self] in
                guard let self = self else { return }
                Task { await self.startRecording(meetingTitle: meetingTitle) }
            },
            onDismiss: { [weak self] in
                Log.app.info("User declined meeting recording")
                self?.hasAskedToRecord = false
                // Return buddy home after dismissing
                self?.buddyController.returnHome()
            },
            autoHideAfter: 0  // Wait for user response
        )
    }
    
    private func positionBuddyNearTeams() {
        // Find Teams window and position buddy next to it
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  (bundleId.contains("microsoft.teams") || bundleId.contains("com.microsoft.teams")) else {
                continue
            }
            
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            
            var windowsRef: AnyObject?
            let result = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )
            
            guard result == .success,
                  let windows = windowsRef as? [AXUIElement],
                  let firstWindow = windows.first else {
                continue
            }
            
            // Get window position and size
            var positionRef: AnyObject?
            var sizeRef: AnyObject?
            
            AXUIElementCopyAttributeValue(firstWindow, kAXPositionAttribute as CFString, &positionRef)
            AXUIElementCopyAttributeValue(firstWindow, kAXSizeAttribute as CFString, &sizeRef)
            
            if let positionValue = positionRef,
               let sizeValue = sizeRef {
                var point = CGPoint.zero
                var size = CGSize.zero
                
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                
                // Position buddy to the right of Teams window
                let buddyX = point.x + size.width + 60
                let buddyY = point.y + size.height * 0.5
                
                buddyController.animateTo(CGPoint(x: buddyX, y: buddyY))
                Log.app.info("Positioned buddy near Teams window at (\(buddyX), \(buddyY))")
                return
            }
        }
        
        // Fallback: couldn't find Teams window, use default position
        Log.app.warning("Couldn't find Teams window for positioning")
    }
    
    private func startRecording(meetingTitle: String) async {
        do {
            try await recorder.startRecording(meetingTitle: meetingTitle)
            
            // Update buddy to show recording state (red pulsing)
            buddyController.setRecording(true)
            
            // Show confirmation
            bubbleController.show(
                text: "recording, I'll take notes for you",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 3.0
            )
            
            Log.app.info("✓ Recording started for: \(meetingTitle)")
            
        } catch {
            Log.app.error("Failed to start recording: \(error.localizedDescription)")
            
            bubbleController.show(
                text: "couldn't start recording, check permissions",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 5.0
            )
            
            hasAskedToRecord = false
        }
    }
    
    // MARK: - Public API
    
    func startMonitoring() {
        detector.startMonitoring()
    }
    
    func stopMonitoring() {
        detector.stopMonitoring()
    }
    
    // MARK: - Manual Recording (from buddy menu)
    
    private func startManualRecording() async {
        guard !recorder.isRecording else {
            Log.app.warning("Already recording")
            return
        }
        
        // Get current app name for meeting title
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Manual Recording"
        
        do {
            try await recorder.startRecording(meetingTitle: appName)
            buddyController.setRecording(true)
            
            bubbleController.show(
                text: "recording started, click buddy to stop",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 3.0
            )
            
            Log.app.info("✓ Manual recording started")
            
        } catch {
            Log.app.error("Failed to start manual recording: \(error.localizedDescription)")
            
            bubbleController.show(
                text: "couldn't start recording",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 3.0
            )
        }
    }
    
    private func stopManualRecording() async {
        guard recorder.isRecording else {
            Log.app.warning("Not recording")
            return
        }
        
        Log.app.info("Stopping manual recording...")
        
        // Set processing state immediately (stops timer, blocks interactions)
        buddyController.setRecording(false)
        buddyController.setProcessing(true)
        
        bubbleController.show(
            text: "stopping recording and transcribing...",
            onAccept: nil,
            onDismiss: nil,
            autoHideAfter: 0  // Don't auto-hide while processing
        )
        
        do {
            guard let session = try await recorder.stopRecording() else {
                buddyController.setProcessing(false)
                return
            }
            
            // Check if we have a transcript
            guard let transcript = session.transcript, !transcript.isEmpty else {
                Log.app.warning("No transcript available")
                
                buddyController.setProcessing(false)
                
                bubbleController.show(
                    text: "recording too short to transcribe",
                    onAccept: nil,
                    onDismiss: nil,
                    autoHideAfter: 3.0
                )
                return
            }
            
            bubbleController.show(
                text: "generating notes...",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 0
            )
            
            let notes = try await notesGenerator.generateNotes(from: session)
            let fileURL = try await notesGenerator.exportToPages(notes: notes)
            
            buddyController.setProcessing(false)
            
            bubbleController.show(
                text: "notes ready! opened in Pages",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 5.0
            )
            
            Log.app.info("✓ Manual recording notes exported: \(fileURL.lastPathComponent)")
            
        } catch {
            Log.app.error("Failed to process manual recording: \(error.localizedDescription)")
            
            buddyController.setProcessing(false)
            
            bubbleController.show(
                text: "couldn't process notes",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 3.0
            )
        }
    }
}
