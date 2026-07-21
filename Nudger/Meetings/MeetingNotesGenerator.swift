//
//  MeetingNotesGenerator.swift
//  Nudger
//
//  Created on 2025-10-28.
//

import Foundation
import AppKit
import os.log

/// Generates formatted meeting notes from transcripts using AI
@MainActor
class MeetingNotesGenerator {
    
    private let llmClient: LLMClient
    
    init(llmClient: LLMClient) {
        self.llmClient = llmClient
    }
    
    // MARK: - Generate Notes
    
    func generateNotes(from session: MeetingSession) async throws -> MeetingNotes {
        guard let transcript = session.transcript else {
            throw NotesError.noTranscript
        }
        
        Log.app.info("Generating meeting notes for: \(session.title)")
        
        // Use LLM to extract structured notes
        let prompt = buildNotesPrompt(transcript: transcript, meetingTitle: session.title)
        let notes = try await requestNotesFromLLM(prompt: prompt)
        
        return MeetingNotes(
            session: session,
            summary: notes.summary,
            keyPoints: notes.keyPoints,
            actionItems: notes.actionItems,
            decisions: notes.decisions,
            participants: notes.participants
        )
    }
    
    // MARK: - Export to Pages
    
    func exportToPages(notes: MeetingNotes) async throws -> URL {
        // Create RTF document (Pages can open RTF files)
        let rtfContent = generateRTF(from: notes)
        
        // Save to Documents
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingNotes")
        
        try? FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
        
        let timestamp = ISO8601DateFormatter().string(from: notes.session.startTime)
        let filename = "\(timestamp)_\(notes.session.title.replacingOccurrences(of: " ", with: "_")).rtf"
        let fileURL = documentsDir.appendingPathComponent(filename)
        
        try rtfContent.write(to: fileURL, atomically: true, encoding: .utf8)
        
        Log.app.info("✓ Exported meeting notes to: \(fileURL.path)")
        
        // Open in Pages
        NSWorkspace.shared.open(fileURL)
        
        return fileURL
    }
    
    // MARK: - Private Helpers
    
    private func buildNotesPrompt(transcript: String, meetingTitle: String) -> String {
        """
        You are an expert meeting note-taker. Analyze this meeting transcript and extract structured notes.
        
        Meeting Title: \(meetingTitle)
        
        Transcript:
        \(transcript)
        
        Generate a comprehensive meeting summary in JSON format with the following structure:
        {
          "summary": "2-3 sentence overview of the meeting",
          "keyPoints": ["key point 1", "key point 2", ...],
          "actionItems": ["action item 1", "action item 2", ...],
          "decisions": ["decision 1", "decision 2", ...],
          "participants": ["person 1", "person 2", ...]
        }
        
        Rules:
        - Summary should be concise but informative
        - Key points should capture main discussion topics
        - Action items should be specific and actionable (include who if mentioned)
        - Decisions should be clear outcomes or agreements
        - Participants should list people mentioned or speaking in the transcript
        - Keep everything professional and well-formatted
        - Focus on important information, skip small talk
        
        Return ONLY valid JSON, no extra text.
        """
    }
    
    private func requestNotesFromLLM(prompt: String) async throws -> LLMNotesResponse {
        guard let apiKey = Config.openAIKey else {
            throw NotesError.missingAPIKey
        }
        
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are an expert meeting note-taker that outputs structured JSON."],
            ["role": "user", "content": prompt]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "temperature": 0.3,
            "max_tokens": 2000
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw NotesError.invalidResponse
        }
        
        // Parse JSON response
        guard let jsonData = content.data(using: .utf8) else {
            throw NotesError.invalidResponse
        }
        
        return try JSONDecoder().decode(LLMNotesResponse.self, from: jsonData)
    }
    
    private func generateRTF(from notes: MeetingNotes) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        
        let startTime = dateFormatter.string(from: notes.session.startTime)
        let duration = formatDuration(notes.session.duration)
        
        var rtf = """
        {\\rtf1\\ansi\\deff0
        {\\fonttbl{\\f0 Helvetica;}{\\f1 Helvetica-Bold;}}
        {\\colortbl;\\red0\\green0\\blue0;\\red100\\green100\\blue100;}
        
        {\\f1\\fs36 \(notes.session.title)\\par}
        \\par
        {\\f0\\fs24 \\b Date:\\b0  \(startTime)\\par}
        {\\f0\\fs24 \\b Duration:\\b0  \(duration)\\par}
        \\par
        
        {\\f1\\fs28 Summary\\par}
        {\\f0\\fs24 \(notes.summary)\\par}
        \\par
        
        """
        
        if !notes.participants.isEmpty {
            rtf += """
            {\\f1\\fs28 Participants\\par}
            {\\f0\\fs24
            """
            for participant in notes.participants {
                rtf += "• \(participant)\\par\n"
            }
            rtf += "}\\par\n"
        }
        
        if !notes.keyPoints.isEmpty {
            rtf += """
            {\\f1\\fs28 Key Discussion Points\\par}
            {\\f0\\fs24
            """
            for (index, point) in notes.keyPoints.enumerated() {
                rtf += "\(index + 1). \(point)\\par\n"
            }
            rtf += "}\\par\n"
        }
        
        if !notes.decisions.isEmpty {
            rtf += """
            {\\f1\\fs28 Decisions Made\\par}
            {\\f0\\fs24
            """
            for decision in notes.decisions {
                rtf += "✓ \(decision)\\par\n"
            }
            rtf += "}\\par\n"
        }
        
        if !notes.actionItems.isEmpty {
            rtf += """
            {\\f1\\fs28 Action Items\\par}
            {\\f0\\fs24
            """
            for item in notes.actionItems {
                rtf += "☐ \(item)\\par\n"
            }
            rtf += "}\\par\n"
        }
        
        rtf += "}"
        
        return rtf
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Models

struct MeetingNotes {
    let session: MeetingSession
    let summary: String
    let keyPoints: [String]
    let actionItems: [String]
    let decisions: [String]
    let participants: [String]
}

struct LLMNotesResponse: Codable {
    let summary: String
    let keyPoints: [String]
    let actionItems: [String]
    let decisions: [String]
    let participants: [String]
}

enum NotesError: LocalizedError {
    case noTranscript
    case missingAPIKey
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .noTranscript:
            return "No transcript available"
        case .missingAPIKey:
            return "OpenAI API key not configured"
        case .invalidResponse:
            return "Invalid response from AI"
        }
    }
}
