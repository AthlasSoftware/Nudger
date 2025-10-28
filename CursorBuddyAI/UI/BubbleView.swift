//
//  BubbleView.swift
//  CursorBuddyAI
//
//  Created on 2025-10-27.
//

import SwiftUI

/// SwiftUI view for the speech bubble with message and action buttons
struct BubbleView: View {
    
    let message: String
    let onAccept: (() -> Void)?
    let onDismiss: (() -> Void)?
    let showButtons: Bool
    
    @State private var displayedText: String = ""
    @State private var currentIndex: Int = 0
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(message: String, onAccept: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil, showButtons: Bool = true) {
        self.message = message
        self.onAccept = onAccept
        self.onDismiss = onDismiss
        self.showButtons = showButtons
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Message text with typewriter effect
            // Use overlay to reserve space for full message while showing partial text
            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.clear)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280, alignment: .leading)
                .overlay(
                    Text(displayedText.isEmpty ? " " : displayedText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                        .frame(maxWidth: 280, alignment: .leading),
                    alignment: .topLeading
                )
            
            // Action buttons (only if showButtons is true)
            if showButtons, let onAccept = onAccept, let onDismiss = onDismiss {
                HStack(spacing: 6) {
                    Spacer()
                    
                    // Dismiss button - "n"
                    Button(action: onDismiss) {
                        Text("n")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .background(Color.clear)
                    .contentShape(Rectangle())
                    .keyboardShortcut("n", modifiers: [])
                    .opacity(displayedText == message ? 0.6 : 0.3)
                    .disabled(displayedText != message)
                    
                    // Accept button - "y"
                    Button(action: onAccept) {
                        Text("y")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .background(Color.clear)
                    .contentShape(Rectangle())
                    .keyboardShortcut("y", modifiers: [])
                    .opacity(displayedText == message ? 1.0 : 0.3)
                    .disabled(displayedText != message)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear {
            startTypewriterEffect()
        }
        .onChange(of: message) { _, newValue in
            startTypewriterEffect()
        }
    }
    
    private func startTypewriterEffect() {
        displayedText = ""
        currentIndex = 0
        
        guard !message.isEmpty else {
            displayedText = message
            return
        }
        
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            if currentIndex < message.count {
                let index = message.index(message.startIndex, offsetBy: currentIndex)
                displayedText.append(message[index])
                currentIndex += 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        BubbleView(
            message: "i love porter robinson, this set is amazing",
            onAccept: { print("Accept") },
            onDismiss: { print("Dismiss") },
            showButtons: false
        )
        
        BubbleView(
            message: "i want to show you another set i think you'd like, can i show you?",
            onAccept: { print("Accept") },
            onDismiss: { print("Dismiss") },
            showButtons: true
        )
    }
    .padding()
    .frame(width: 300)
    .background(Color.gray.opacity(0.1))
}

