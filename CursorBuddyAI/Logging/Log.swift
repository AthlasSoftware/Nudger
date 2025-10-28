//
//  Log.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import Foundation
import os.log

/// Centralized logging wrapper around os.Logger
struct Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cursorbuddyai"
    
    static let app = Logger(subsystem: subsystem, category: "App")
    static let buddy = Logger(subsystem: subsystem, category: "Buddy")
    static let bubble = Logger(subsystem: subsystem, category: "Bubble")
    static let llm = Logger(subsystem: subsystem, category: "LLM")
    static let scheduler = Logger(subsystem: subsystem, category: "Scheduler")
    static let context = Logger(subsystem: subsystem, category: "Context")
    static let automation = Logger(subsystem: subsystem, category: "Automation")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
}

