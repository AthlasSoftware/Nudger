//
//  MeetingRecorder.swift
//  CursorBuddyAI
//
//  Created on 2025-10-28.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit
import Combine
import os.log

/// Records audio from both microphone and system audio during meetings
@MainActor
class MeetingRecorder: ObservableObject {
    
    @Published var isRecording = false
    @Published var currentMeeting: MeetingSession?
    
    // For microphone recording
    private var micEngine: AVAudioEngine?
    private var micFile: AVAudioFile?
    private var micURL: URL?
    
    // For system audio recording via ScreenCaptureKit
    private var stream: SCStream?
    private var streamOutput: SystemAudioCapture?
    private var systemAudioURL: URL?
    
    // Recording metadata
    private var recordingURL: URL?
    private var startTime: Date?
    
    // MARK: - Recording Control
    
    func startRecording(meetingTitle: String) async throws {
        guard !isRecording else { return }
        
        Log.app.info("Starting meeting recording: \(meetingTitle)")
        
        // Request permissions
        let micPermission = await requestMicrophonePermission()
        guard micPermission else {
            throw RecordingError.permissionDenied
        }
        
        // Create recording directory
        let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecordings")
        
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        
        // Create unique filenames
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeTitle = meetingTitle.replacingOccurrences(of: " ", with: "_")
        
        // Microphone file
        micURL = recordingsDir.appendingPathComponent("\(timestamp)_\(safeTitle)_mic.m4a")
        
        // System audio file
        systemAudioURL = recordingsDir.appendingPathComponent("\(timestamp)_\(safeTitle)_system.m4a")
        
        // Final merged file
        recordingURL = recordingsDir.appendingPathComponent("\(timestamp)_\(safeTitle).m4a")
        
        // Start microphone recording
        try startMicrophoneRecording()
        
        // Try to start system audio recording (optional - falls back to mic only if fails)
        do {
            try await startSystemAudioRecording()
        } catch {
            Log.app.warning("System audio recording failed (will use mic only): \(error)")
            // Continue with mic-only recording
        }
        
        // Update state
        startTime = Date()
        isRecording = true
        currentMeeting = MeetingSession(
            title: meetingTitle,
            startTime: Date(),
            recordingURL: recordingURL!
        )
        
        Log.app.info("✓ Recording started (mic\(self.stream != nil ? " + system audio" : " only"))")
    }
    
    private func startMicrophoneRecording() throws {
        micEngine = AVAudioEngine()
        guard let engine = micEngine else { throw RecordingError.setupFailed }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create audio file for microphone
        guard let url = micURL else { throw RecordingError.setupFailed }
        micFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        
        // Install tap on microphone input
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let audioFile = self.micFile else { return }
            try? audioFile.write(from: buffer)
        }
        
        // Start engine
        try engine.start()
        Log.app.info("Microphone recording started")
    }
    
    private func startSystemAudioRecording() async throws {
        // Request screen recording permission (needed for system audio)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = content.displays.first else {
            throw RecordingError.setupFailed
        }
        
        // Configure to capture system audio only (no video)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.excludesCurrentProcessAudio = true // Don't capture our own app's audio
        streamConfig.sampleRate = 48000
        streamConfig.channelCount = 2
        
        // No video capture
        streamConfig.width = 1
        streamConfig.height = 1
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        
        // Create stream output handler
        streamOutput = SystemAudioCapture(outputURL: systemAudioURL!)
        
        // Create and start stream
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.cursorbuddy.audioCapture"))
        try await stream?.startCapture()
        
        Log.app.info("✓ System audio recording started")
    }
    
    func stopRecording() async throws -> MeetingSession? {
        guard isRecording else { return nil }
        
        Log.app.info("Stopping meeting recording...")
        
        // Stop microphone recording
        if let engine = micEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        micFile = nil
        
        // Stop system audio recording
        if let stream = stream {
            try? await stream.stopCapture()
        }
        streamOutput = nil
        stream = nil
        
        // Wait for file system to sync
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Merge the two audio files if we have both, otherwise use mic only
        var finalAudioURL: URL?
        if let micURL = micURL, let sysURL = systemAudioURL, 
           FileManager.default.fileExists(atPath: sysURL.path),
           let outputURL = recordingURL {
            do {
                finalAudioURL = try await mergeAudioFiles(microphoneURL: micURL, systemURL: sysURL, outputURL: outputURL)
                Log.app.info("✓ Audio files merged successfully")
            } catch {
                Log.app.error("Failed to merge audio files: \(error)")
                // Fall back to just microphone
                finalAudioURL = micURL
            }
        } else if let micURL = micURL {
            // Only microphone recording available
            finalAudioURL = micURL
            Log.app.info("Using microphone-only recording")
        }
        
        // Update session
        if var session = currentMeeting {
            session.endTime = Date()
            session.duration = Date().timeIntervalSince(session.startTime)
            
            // Generate transcript using Whisper API
            if let url = finalAudioURL {
                // Verify file exists and has data
                if FileManager.default.fileExists(atPath: url.path) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        
                        Log.app.info("Audio file size: \(fileSize) bytes")
                        
                        if fileSize < 1000 {
                            Log.app.warning("Audio file too small (\(fileSize) bytes), skipping transcription")
                            session.transcript = nil
                        } else if session.duration < 1.0 {
                            Log.app.warning("Recording too short (\(session.duration)s), skipping transcription")
                            session.transcript = nil
                        } else {
                            session.transcript = try await transcribeAudio(url: url)
                            Log.app.info("✓ Transcription successful: \(session.transcript?.prefix(100) ?? "empty")")
                        }
                    } catch {
                        Log.app.error("Failed to transcribe audio: \(error.localizedDescription)")
                        session.transcript = nil
                    }
                } else {
                    Log.app.error("Audio file does not exist at: \(url.path)")
                    session.transcript = nil
                }
            }
            
            isRecording = false
            currentMeeting = nil
            
            Log.app.info("✓ Meeting recording stopped, duration: \(session.duration)s")
            return session
        }
        
        isRecording = false
        currentMeeting = nil
        return nil
    }
    
    // MARK: - Audio Merging
    
    private func mergeAudioFiles(microphoneURL: URL, systemURL: URL, outputURL: URL) async throws -> URL {
        let composition = AVMutableComposition()
        
        // Load both audio files
        let micAsset = AVURLAsset(url: microphoneURL)
        let sysAsset = AVURLAsset(url: systemURL)
        
        // Get audio tracks
        guard let micTrack = try await micAsset.loadTracks(withMediaType: .audio).first,
              let sysTrack = try await sysAsset.loadTracks(withMediaType: .audio).first else {
            throw RecordingError.setupFailed
        }
        
        // Add tracks to composition
        let compositionMicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let compositionSysTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        let micDuration = try await micAsset.load(.duration)
        let sysDuration = try await sysAsset.load(.duration)
        _ = max(micDuration, sysDuration)  // Not used but kept for potential future use
        
        try compositionMicTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: micDuration), of: micTrack, at: .zero)
        try compositionSysTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: sysDuration), of: sysTrack, at: .zero)
        
        // Export merged audio
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingError.setupFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            return outputURL
        } else {
            throw RecordingError.setupFailed
        }
    }
    
    // MARK: - Transcription
    
    private func transcribeAudio(url: URL) async throws -> String {
        // Use OpenAI Whisper API to transcribe
        let apiKey = Config.openAIAPIKey
        guard apiKey != "YOUR_API_KEY_HERE" else {
            throw RecordingError.missingAPIKey
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create multipart body
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: url))
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct WhisperResponse: Codable {
            let text: String
        }
        
        let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return response.text
    }
    
    // MARK: - Permissions
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - Models

struct MeetingSession: Codable {
    let title: String
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval = 0
    let recordingURL: URL
    var transcript: String?
    var summary: String?
    var notes: String?
}

enum RecordingError: LocalizedError {
    case permissionDenied
    case setupFailed
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .setupFailed:
            return "Failed to setup audio recording"
        case .missingAPIKey:
            return "OpenAI API key not configured"
        }
    }
}
