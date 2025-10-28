//
//  Schemas.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import Foundation

// MARK: - Suggestion

/// A suggestion from the LLM, including message, action, and metadata
struct Suggestion: Codable {
    enum Action: String, Codable {
        case none
        case openURL
        case pauseAndOpenURL
    }
    
    let greeting: String?            // Initial reaction to current content (required for recommendations)
    let message: String              // Main suggestion or observation
    let transitionMessage: String?   // Message to show while performing action (required for recommendations)
    let reaction: String?            // Short reaction to show after opening URL (required for recommendations)
    let action: Action
    let url: URL?
    let searchQuery: String?         // Search query to find real content (alternative to url)
    let cooldownSec: Int?            // Optional cooldown in seconds
    let confidence: Double?          // 0..1 confidence score
    let showButtons: Bool?           // Whether to show y/n buttons (defaults to true for questions)
}

// MARK: - Tone

/// The tone/style for LLM responses
enum Tone: String, Codable {
    case playful
    case plain
}

// MARK: - Context

/// Lightweight context about the current user activity
struct Context {
    let bundleId: String
    let appName: String
    let windowTitle: String      // Max 200 chars - includes full video title!
    let domain: String?          // Optional domain (v2)
    
    /// Empty context for when frontmost app is unavailable
    static var empty: Context {
        Context(bundleId: "", appName: "", windowTitle: "", domain: nil)
    }
}

