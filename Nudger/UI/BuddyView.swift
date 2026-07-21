//
//  BuddyView.swift
//  Nudger
//
//  Created on 2025-10-27.
//

import SwiftUI

/// SwiftUI view of the buddy cursor with subtle animations
struct BuddyView: View {
    
    @State private var isBlinking = false
    @State private var scale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0
    
    var isRecording: Bool = false  // Pass from controller
    
    private let size: CGFloat = 24
    
    var body: some View {
        ZStack {
            // Recording pulse effect (red glow)
            if isRecording {
                Circle()
                    .fill(Color.red.opacity(0.4))
                    .frame(width: size * 1.5, height: size * 1.5)
                    .opacity(pulseOpacity)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseOpacity)
            }
            
            // Main buddy circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: isRecording ? [
                            Color.red.opacity(0.9),
                            Color.red.opacity(0.7)
                        ] : [
                            Color.primary.opacity(0.9),
                            Color.primary.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: isRecording ? .red.opacity(0.3) : .black.opacity(0.15), radius: 3, x: 0, y: 2)
            
            // Inner highlight
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 8, height: 8)
                .offset(x: -3, y: -3)
                .opacity(isBlinking ? 0.1 : 0.3)
        }
        .scaleEffect(scale)
        .onAppear {
            if isRecording {
                startRecordingPulse()
            } else {
                startIdleAnimation()
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                startRecordingPulse()
            } else {
                pulseOpacity = 1.0
                startIdleAnimation()
            }
        }
    }
    
    // MARK: - Recording Pulse
    
    private func startRecordingPulse() {
        pulseOpacity = 0.2
    }
    
    // MARK: - Idle Animation
    
    private func startIdleAnimation() {
        // Subtle pulse every 8-12 seconds
        let delay = Double.random(in: 8...12)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.4)) {
                isBlinking = true
                scale = 1.1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isBlinking = false
                    scale = 1.0
                }
                
                // Schedule next pulse
                startIdleAnimation()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BuddyView()
        .frame(width: 100, height: 100)
        .background(Color.gray.opacity(0.2))
}

