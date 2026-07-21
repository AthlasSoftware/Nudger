//
//  MeetingManager.swift
//  Nudger
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
    
    @Published var hasAskedToRecord = false
    private var cancellables = Set<AnyCancellable>()
    
    init(
        detector: MeetingDetector,
        recorder: MeetingRecorder,
        notesGenerator: MeetingNotesGenerator,
        buddyController: BuddyController,
        bubbleController: BubbleController
    ) {
        self.detector = detector
        self.recorder = recorder
        self.notesGenerator = notesGenerator
        self.buddyController = buddyController
        self.bubbleController = bubbleController
        
        setupMeetingDetection()
    }
    
    // MARK: - Setup
    
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
        
        do {
            // Stop recording and get session
            guard let session = try await recorder.stopRecording() else { return }
            
            // Update buddy state
            buddyController.setRecording(false)
            
            // Show processing message
            bubbleController.show(
                text: "meeting done, processing notes...",
                onAccept: nil,
                onDismiss: nil,
                autoHideAfter: 3.0
            )
            
            // Generate notes
            let notes = try await notesGenerator.generateNotes(from: session)
            
            // Export to Pages
            let fileURL = try await notesGenerator.exportToPages(notes: notes)
            
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
        
        bubbleController.show(
            text: "want me to take notes for this meeting?",
            onAccept: { [weak self] in
                guard let self = self else { return }
                Task { await self.startRecording(meetingTitle: meetingTitle) }
            },
            onDismiss: { [weak self] in
                Log.app.info("User declined meeting recording")
                self?.hasAskedToRecord = false
            },
            autoHideAfter: 0  // Wait for user response
        )
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
}
