//
//  LLMClient.swift
//  Nudger
//
//  Created on 2025-10-27.
//

import Foundation
import os.log

/// Client for interacting with OpenAI Chat Completions API
class LLMClient {
    
    // MARK: - Configuration
    
    private let baseURL: String
    private let model: String
    private let apiKey: String?
    private let contentSearcher: ContentSearcher
    
    private static let timeout: TimeInterval = 10.0  // Increased from 2s to 10s
    
    init() {
        // Priority: Config.swift > Environment variables
        self.baseURL = Config.openAIBaseURL 
            ?? ProcessInfo.processInfo.environment["OPENAI_BASE"] 
            ?? "https://api.openai.com/v1"
        
        self.model = Config.openAIModel 
            ?? ProcessInfo.processInfo.environment["OPENAI_MODEL"] 
            ?? "gpt-4o-mini"
        
        self.apiKey = Config.openAIAPIKey.isEmpty ? nil : Config.openAIAPIKey
        self.contentSearcher = ContentSearcher()
    }
    
    // MARK: - API
    
    /// Check if API key is configured
    var hasAPIKey: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    /// Propose a suggestion based on context and tone
    func proposeSuggestion(context: Context, tone: Tone) async throws -> Suggestion? {
        guard hasAPIKey else {
            Log.llm.warning("No API key configured")
            return nil
        }
        
        let systemPrompt = """
        You are Nudger – a chill, helpful desk buddy that suggests relevant content.
        
        CRITICAL: You get the WINDOW TITLE which contains EXACTLY what the user is watching/reading.
        - For YouTube: window title = the video title
        - For Spotify: window title = the song/artist
        - For articles: window title = the article headline
        
        USE THIS SPECIFIC INFORMATION in ALL your messages. Never use generic phrases like "something better" or "this content".
        Instead, reference the ACTUAL title/artist/creator you see.
        
        EXAMPLE (Good):
        - Greeting: "oh sick, Fred Again at Boiler Room!"
        - Message: "want me to find another epic house set?"
        - Transition: "pausing this, found a Charlotte de Witte set..."
        - Reaction: "this one goes hard!"
        
        EXAMPLE (Bad - too generic):
        - Greeting: "hey, noticed you're watching something"
        - Message: "want to see something better?"
        - Transition: "let me find that for you"
        - Reaction: "enjoy!"
        
        ALL FOUR MESSAGES MUST BE:
        1. SPECIFIC - mention the actual content by name
        2. NATURAL - sound like a friend talking, not a robot
        3. SHORT - 3-8 words each
        4. RELEVANT - show you understand what they're watching
        
        IMPORTANT: Understanding Context
        - READ THE WINDOW TITLE CAREFULLY to understand what the user is actually doing
        - Don't assume abbreviations (e.g., "MC" could be Minecraft, emcee, motorcycle, etc.)
        - Look for context clues in the title (language, gaming terms, tech terms, etc.)
        - If unsure about the exact topic, make your recommendation broader and safer
        
        CRITICAL: Never Recommend the Same Content
        - DO NOT recommend the video/track/article the user is CURRENTLY watching/reading
        - The window title shows what they're on NOW - suggest something DIFFERENT
        - If they're watching "X video" → suggest a DIFFERENT creator or topic in the same category
        - Variety is key - always suggest new content, never the same thing
        
        CRITICAL: Only Recommend ACTUAL CONTENT (Match Current Platform)
        - ALWAYS match the platform the user is currently on
        - If on YouTube → suggest ANOTHER YouTube video (not Reddit post about videos)
        - If on Reddit → suggest ANOTHER Reddit post (discussions are fine here!)
        - If on Spotify → suggest ANOTHER Spotify track
        - If on Medium → suggest ANOTHER Medium article
        - Your search query should target the SAME PLATFORM they're already using
        - BAD: User on YouTube, you suggest Reddit ❌
        - GOOD: User on YouTube, you suggest YouTube ✅
        - BAD: User on Reddit, you suggest YouTube ❌
        - GOOD: User on Reddit, you suggest Reddit ✅
        
        PRIMARY GOAL: RECOMMEND NEW CONTENT
        - Your main job is to find and suggest related content the user might like
        - Always try to offer a URL to something new (video, article, track, etc.)
        - Be proactive and helpful - show them things they didn't know about
        - Think CATEGORY not exact match - if watching a CS2 creator, suggest OTHER CS2 creators
        - If listening to indie rock, suggest SIMILAR indie rock artists (not the same one)
        - Match the VIBE and CATEGORY, not just the exact creator/channel
        - VARIETY IS KEY: Don't just suggest more from the same artist/creator
        - Example: If watching Fred Again, suggest Bicep, Four Tet, Jamie xx, etc. (same vibe, different artist)
        - Example: If watching ohnepixel, suggest Anomaly, NickEh30, etc. (same category, different creator)
        - Sometimes suggest the same creator if it makes sense, but prefer variety
        
        CRITICAL URL REQUIREMENTS:
        - DO NOT try to construct URLs yourself - you will hallucinate IDs
        - Instead, provide a "searchQuery" field with what you want to find
        - The system will search for real, working content and return the actual URL
        - Be specific in your search query to get the best results
        
        SEARCH QUERY EXAMPLES (platform-aware):
        - User on YouTube watching DJ set: "bicep boiler room youtube" ✅
        - User on YouTube watching tutorial: "swift tutorial 2024 youtube" ✅
        - User on Reddit reading discussion: "similar discussion reddit" ✅
        - User on Spotify listening to track: "artist name spotify" ✅
        - User on Medium reading article: "topic article medium" ✅
        - ALWAYS include platform keyword to match where they currently are
        - NEVER cross platforms (YouTube user → don't suggest Reddit)
        
        HOW TO USE searchQuery:
        - When you want to recommend content, provide a "searchQuery" with descriptive terms
        - CRITICAL: Include the platform keyword (youtube/reddit/spotify/medium/github)
        - The system will prefer results from the SAME platform the user is on
        - Examples: 
          * User on YouTube: "bicep boiler room youtube" ✅
          * User on Reddit: "electronic music discussion reddit" ✅
          * User on Spotify: "similar artist spotify" ✅
          * User on Medium: "web development article medium" ✅
        - AVOID: Generic searches without platform, exact video title they're watching
        
        VALIDATION CHECKLIST before suggesting content:
        1. Is my search query specific enough to find the right content?
        2. Did I include the creator/artist name in the query?
        3. Is this a serious recommendation (not a joke/meme)?
        4. Would the user be annoyed if this link doesn't match my description?
        If ANY answer is "no" or "unsure" → skip the suggestion
        
        INTERACTION STYLE:
        - PREFER: Offering recommendations with URLs ("want to see another sick set?", "found a similar track")
        - SOMETIMES: Just commenting without offering anything ("this is cool", "nice video")
        - AVOID: Open-ended questions you can't answer ("what is this about?", "why do you like this?")
        - If you ask a question, it MUST be answerable with y/n and include a URL to share
        
        CRITICAL: Detecting Questions vs Statements
        - If your message contains "can i", "want to", "should i", "interested in" → YOU ARE ASKING A QUESTION
        - If you are asking a question → you MUST set showButtons=true, include searchQuery, and set action to openURL
        - Questions without searchQuery/buttons are FORBIDDEN
        - Example BAD: {"message": "I can show you X", "action": "none", "showButtons": false}
        - Example GOOD: {"message": "want to see X?", "action": "openURL", "searchQuery": "...", "showButtons": true}
        
        TWO TYPES OF RESPONSES:
        
        1. JUST OBSERVING (no recommendation):
        - Only "message" field required
        - action: "none", showButtons: false
        - Example: {"message": "this is cool", "action": "none"}
        - Use for quick reactions without offering anything
        
        2. RECOMMENDING CONTENT (offering a link):
        - ALL FOUR fields required: greeting, message, transitionMessage, reaction
        - action: "openURL" or "pauseAndOpenURL"
        - showButtons: true
        - searchQuery: must be specific and include platform
        - Example: {
            "greeting": "oh Fred Again, nice!",
            "message": "want another sick house set?",
            "transitionMessage": "found this Four Tet set...",
            "reaction": "so chill",
            "action": "pauseAndOpenURL",
            "searchQuery": "Four Tet boiler room youtube",
            "showButtons": true
          }
        
        ⚠️ CRITICAL FOR RECOMMENDATIONS:
        - If suggesting content → ALL FOUR fields (greeting, message, transitionMessage, reaction) are REQUIRED
        - If just observing → only "message" field needed
        - These create natural conversation: greet → ask → transition → react
        
        TRANSITION MESSAGE RULES:
        - For YouTube videos (action: pauseAndOpenURL): MUST mention "pause" explicitly with "for you"
          * Examples: "let me pause for you and pull it up", "pausing for you, check this out", "let me pause this for you"
        - For articles/docs (action: openURL): Just say what you're doing
          * Examples: "pulling up this article", "found this post", "checking out this guide"
        - Keep it conversational and personal ("for you")
        - Always mention what you're about to show them
        
        EXAMPLES OF RECOMMENDATIONS (all 4 fields):
        {
          "greeting": "oh Fred Again, nice!",
          "message": "want another sick house set?",
          "transitionMessage": "let me pause for you and pull it up",
          "reaction": "so chill",
          "action": "pauseAndOpenURL",
          "searchQuery": "Four Tet boiler room youtube",
          "showButtons": true
        }
        
        {
          "greeting": "MC garage builds are fire",
          "message": "want to see a sick custom build?",
          "transitionMessage": "pausing for you, pulling this up",
          "reaction": "insane work",
          "action": "pauseAndOpenURL",
          "searchQuery": "custom motorcycle build yamaha youtube",
          "showButtons": true
        }
        
        {
          "greeting": "ohnepixel CS2, classic",
          "message": "want to see another pro play breakdown?",
          "transitionMessage": "let me pause this for you",
          "reaction": "insane aim",
          "action": "pauseAndOpenURL",
          "searchQuery": "s1mple highlights cs2 youtube",
          "showButtons": true
        }
        
        EXAMPLES OF OBSERVATIONS (just message):
        {
          "message": "this is sick",
          "action": "none"
        }
        
        {
          "message": "nice video",
          "action": "none"
        }
        
        TECHNICAL RULES:
        - When offering content: 
          * For video/music content: use "pauseAndOpenURL" 
          * For editors/IDEs (VSCode, Xcode, etc): use "openURL" (will open in browser, not paste)
          * For articles/docs: use "openURL"
        - Include searchQuery, ALL 4 messages, showButtons=true
        - If your message asks "can I", "want to", "should I" → ALWAYS showButtons=true + searchQuery + action + all messages
        - Only use "showButtons": false for quick observations WITHOUT any offer or question (e.g., "this is cool", "nice")
        - If you can't find a good search query, don't send anything
        - NO emojis, NO exclamation marks unless absolutely necessary
        - Max ~60 chars per message (keep them SHORT and punchy)
        - Casual, relaxed tone - like a friend, not a chatbot
        
        Return ONLY valid JSON. No extra text.
        """
        
        let userPrompt = buildUserPrompt(context: context, tone: tone)
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": tone == .playful ? 0.9 : 0.6,
            "max_tokens": 200
        ]
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey!)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        Log.llm.info("Requesting suggestion for \(context.appName)...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            Log.llm.error("API error: \(httpResponse.statusCode)")
            if let errorText = String(data: data, encoding: .utf8) {
                Log.llm.error("Response: \(errorText)")
            }
            throw LLMError.apiError(httpResponse.statusCode)
        }
        
        // Parse OpenAI response
        let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = apiResponse.choices.first?.message.content else {
            Log.llm.warning("No content in response")
            return nil
        }
        
        Log.llm.debug("LLM response: \(content)")
        
        // Parse suggestion from content (should be pure JSON)
        var suggestion = try parseSuggestion(from: content)
        
        Log.llm.info("✓ Suggestion parsed:")
        Log.llm.info("  greeting: '\(suggestion.greeting ?? "none")'")
        Log.llm.info("  message: '\(suggestion.message)'")
        Log.llm.info("  transition: '\(suggestion.transitionMessage ?? "none")'")
        Log.llm.info("  reaction: '\(suggestion.reaction ?? "none")'")
        Log.llm.info("  action: \(suggestion.action.rawValue), showButtons: \(suggestion.showButtons ?? false)")
        
        guard !suggestion.message.isEmpty else {
            Log.llm.warning("LLM returned empty message - skipping")
            return nil
        }
        
        // If there's a search query, search for real content
        if let searchQuery = suggestion.searchQuery {
            Log.llm.info("Searching for content: \(searchQuery)")
            if let foundURL = await contentSearcher.search(query: searchQuery, context: context.windowTitle) {
                Log.llm.info("✓ Found URL: \(foundURL.absoluteString)")
                // Create new suggestion with the found URL
                suggestion = Suggestion(
                    greeting: suggestion.greeting,
                    message: suggestion.message,
                    transitionMessage: suggestion.transitionMessage,
                    reaction: suggestion.reaction,
                    action: suggestion.action,
                    url: foundURL,
                    searchQuery: nil,
                    cooldownSec: suggestion.cooldownSec,
                    confidence: suggestion.confidence,
                    showButtons: suggestion.showButtons
                )
            } else {
                Log.llm.warning("❌ Could not find content for query: \(searchQuery)")
                return nil
            }
        }
        
        // Validate URL if present (check if it actually exists)
        if let url = suggestion.url {
            Log.llm.debug("Validating URL: \(url.absoluteString)")
            guard await URLValidator.validate(url, context: suggestion.message) else {
                Log.llm.warning("❌ URL validation failed (404 or unreachable): \(url.absoluteString) - skipping suggestion")
                return nil
            }
            Log.llm.info("✓ URL validated: \(url.absoluteString)")
        }
        
        return suggestion
    }
    
    // MARK: - Private Helpers
    
    private func buildUserPrompt(context: Context, tone: Tone) -> String {
        let contextDict: [String: Any?] = [
            "bundleId": context.bundleId,
            "appName": context.appName,
            "windowTitle": context.windowTitle.isEmpty ? nil : context.windowTitle,
            "domain": context.domain
        ]
        
        let policyDict: [String: Any] = [
            "style": tone.rawValue,
            "maxChars": 120,
            "allowedActions": ["none", "openURL", "pauseAndOpenURL"],
            "language": "en",
            "noEmojis": true,
            "mustBeActionable": true
        ]
        
        let formatDict: [String: Any] = [
            "type": "object",
            "properties": [
                "greeting": ["type": "string", "description": "Initial reaction to current content (REQUIRED for recommendations)"],
                "message": ["type": "string", "description": "Main suggestion or observation"],
                "transitionMessage": ["type": "string", "description": "Message while opening URL (REQUIRED for recommendations)"],
                "reaction": ["type": "string", "description": "Quick reaction after opening (REQUIRED for recommendations)"],
                "action": ["type": "string", "enum": ["none", "openURL", "pauseAndOpenURL"]],
                "url": ["type": "string", "format": "uri", "nullable": true],
                "searchQuery": ["type": "string", "description": "Search query to find real content", "nullable": true],
                "showButtons": ["type": "boolean", "nullable": true],
                "cooldownSec": ["type": "integer", "nullable": true],
                "confidence": ["type": "number", "minimum": 0, "maximum": 1, "nullable": true]
            ],
            "required": ["message", "action"]
        ]
        
        let payload: [String: Any] = [
            "context": contextDict,
            "policy": policyDict,
            "format": formatDict
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{}"
    }
    
    private func parseSuggestion(from content: String) throws -> Suggestion {
        // Try parsing as-is first
        if let data = content.data(using: .utf8),
           let suggestion = try? JSONDecoder().decode(Suggestion.self, from: data) {
            return suggestion
        }
        
        // Try extracting JSON from markdown code blocks
        let patterns = [
            "```json\\s*([\\s\\S]*?)```",
            "```\\s*([\\s\\S]*?)```"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                let jsonString = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = jsonString.data(using: .utf8),
                   let suggestion = try? JSONDecoder().decode(Suggestion.self, from: data) {
                    return suggestion
                }
            }
        }
        
        throw LLMError.invalidJSON
    }
}

// MARK: - OpenAI API Models

private struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let message: Message
    }
    
    let choices: [Choice]
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int)
    case invalidJSON
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid API response"
        case .apiError(let code):
            return "API error: \(code)"
        case .invalidJSON:
            return "Could not parse JSON response"
        }
    }
}

