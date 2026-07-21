//
//  MeetingRecorder.swift
//  Nudger
//
//  Created on 2025-10-28.
//

import Foundation
import AVFoundation
import AppKit
import os.log

/// Records audio from both microphone and system audio during meetings
@MainActor
class MeetingRecorder: ObservableObject {
    
    @Published var isRecording = false
    @Published var currentMeeting: MeetingSession?
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startTime: Date?
    
    // MARK: - Recording Control
    
    func startRecording(meetingTitle: String) async throws {
        guard !isRecording else { return }
        
        Log.app.info("Starting meeting recording: \(meetingTitle)")
        
        // Request microphone permission
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            throw RecordingError.permissionDenied
        }
        
        // Create recording directory
        let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingRecordings")
        
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        
        // Create unique filename
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "\(timestamp)_\(meetingTitle.replacingOccurrences(of: " ", with: "_")).m4a"
        recordingURL = recordingsDir.appendingPathComponent(filename)
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { throw RecordingError.setupFailed }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create audio file
        guard let url = recordingURL else { throw RecordingError.setupFailed }
        audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        
        // Install tap on microphone input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let audioFile = self.audioFile else { return }
            try? audioFile.write(from: buffer)
        }
        
        // Start engine
        try engine.start()
        
        // Update state
        startTime = Date()
        isRecording = true
        currentMeeting = MeetingSession(
            title: meetingTitle,
            startTime: Date(),
            recordingURL: url
        )
        
        Log.app.info("✓ Meeting recording started")
    }
    
    func stopRecording() async throws -> MeetingSession? {
        guard isRecording, let engine = audioEngine else { return nil }
        
        Log.app.info("Stopping meeting recording...")
        
        // Stop recording
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        // Update session
        if var session = currentMeeting {
            session.endTime = Date()
            session.duration = Date().timeIntervalSince(session.startTime)
            
            // Generate transcript using Whisper API
            if let url = recordingURL {
                session.transcript = try? await transcribeAudio(url: url)
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
    
    // MARK: - Transcription
    
    private func transcribeAudio(url: URL) async throws -> String {
        // Use OpenAI Whisper API to transcribe
        guard let apiKey = Config.openAIKey else {
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
