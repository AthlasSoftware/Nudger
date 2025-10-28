//
//  SettingsStore.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import Foundation
import SwiftUI
import Combine

/// Observable settings store backed by UserDefaults and AppStorage
@MainActor
class SettingsStore: ObservableObject {
    
    // MARK: - Published Settings
    
    @AppStorage("isActive") var isActive: Bool = true
    @AppStorage("frequency") var frequency: Double = 0.2
    @AppStorage("playfulTone") var playfulTone: Bool = true
    @AppStorage("devMode") var devMode: Bool = false
    @AppStorage("meetingNotesEnabled") var meetingNotesEnabled: Bool = false
    
    // MARK: - Buddy Position
    
    private static let buddyPositionKey = "buddyPosition"
    
    var buddyPosition: CGPoint {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.buddyPositionKey),
                  let point = try? JSONDecoder().decode(CGPoint.self, from: data) else {
                return defaultBuddyPosition()
            }
            return point
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.buddyPositionKey)
            }
        }
    }
    
    /// Default buddy position: bottom-right with 24pt inset
    private func defaultBuddyPosition() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 100, y: 100)
        }
        let frame = screen.visibleFrame
        return CGPoint(
            x: frame.maxX - 64,
            y: frame.minY + 64
        )
    }
    
    func resetBuddyPosition() {
        buddyPosition = defaultBuddyPosition()
    }
    
    // MARK: - Cooldowns
    
    private static let cooldownsKey = "cooldowns"
    
    /// Dictionary of key -> next allowed time
    private(set) var cooldowns: [String: Date] = [:]
    
    init() {
        loadCooldowns()
    }
    
    private func loadCooldowns() {
        guard let data = UserDefaults.standard.data(forKey: Self.cooldownsKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return
        }
        cooldowns = decoded
    }
    
    private func saveCooldowns() {
        if let data = try? JSONEncoder().encode(cooldowns) {
            UserDefaults.standard.set(data, forKey: Self.cooldownsKey)
        }
    }
    
    /// Check if the given key is on cooldown
    func isOnCooldown(key: String) -> Bool {
        guard let nextAllowed = cooldowns[key] else {
            return false
        }
        return Date() < nextAllowed
    }
    
    /// Set cooldown for the given key
    func setCooldown(key: String, seconds: Int) {
        cooldowns[key] = Date().addingTimeInterval(TimeInterval(seconds))
        saveCooldowns()
    }
    
    /// Prune expired cooldowns
    func pruneCooldowns() {
        let now = Date()
        cooldowns = cooldowns.filter { $0.value > now }
        saveCooldowns()
    }
}

