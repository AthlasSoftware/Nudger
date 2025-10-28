//
//  BuddyMenuView.swift
//  Nudger
//
//  Created on 2025-10-28.
//

import SwiftUI

/// Custom context menu that appears when clicking the buddy
struct BuddyMenuView: View {
    
    let isRecording: Bool
    let isProcessing: Bool
    let isMeetingActive: Bool
    let hasScreenRecordingPermission: Bool
    let recordingDuration: TimeInterval
    
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onViewNotes: () -> Void
    let onSettings: () -> Void
    let onClose: () -> Void
    
    @State private var animateIn = false
    @AppStorage("developerMode") private var developerMode = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    // Status indicator
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.6), radius: 4)
                    
                    Text("nudger")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Developer mode toggle
                    if developerMode {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if isRecording {
                        Text(formattedDuration)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Main menu items
            VStack(spacing: 0) {
                // Recording toggle
                MenuButton(
                    icon: isRecording ? "stop.circle.fill" : "record.circle",
                    title: isRecording ? "Stop Recording" : "Start Recording",
                    subtitle: isRecording ? "saving & transcribing..." : hasScreenRecordingPermission ? "mic + system audio" : "mic only",
                    color: isRecording ? .red : .purple,
                    isEnabled: !isProcessing,
                    action: {
                        if isRecording {
                            onStopRecording()
                        } else {
                            onStartRecording()
                        }
                    }
                )
                
                Divider().padding(.leading, 46)
                
                MenuButton(
                    icon: "doc.text.fill",
                    title: "Meeting Notes",
                    subtitle: "recent transcripts",
                    color: .blue,
                    action: onViewNotes
                )
                
                Divider().padding(.leading, 46)
                
                MenuButton(
                    icon: "gearshape.fill",
                    title: "Settings",
                    subtitle: "permissions & api keys",
                    color: .gray,
                    action: onSettings
                )
            }
            .padding(.vertical, 4)
            
            // Developer section
            if developerMode {
                Divider()
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Developer Info")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    
                    VStack(spacing: 4) {
                        DevInfoRow(label: "Recording", value: isRecording ? "Active" : "Idle", color: isRecording ? .red : .green)
                        DevInfoRow(label: "Processing", value: isProcessing ? "Yes" : "No", color: isProcessing ? .orange : .secondary)
                        DevInfoRow(label: "Meeting", value: isMeetingActive ? "Active" : "None", color: isMeetingActive ? .blue : .secondary)
                        DevInfoRow(label: "Screen Audio", value: hasScreenRecordingPermission ? "Enabled" : "Disabled", color: hasScreenRecordingPermission ? .green : .orange)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
            
            // Footer
            Divider()
            
            HStack(spacing: 4) {
                Button(action: {
                    developerMode.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: developerMode ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("dev mode")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(developerMode ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("v1.0.0")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .scaleEffect(animateIn ? 1.0 : 0.92)
        .opacity(animateIn ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                animateIn = true
            }
        }
    }
    
    private var statusColor: Color {
        if isProcessing { return .yellow }
        if isRecording { return .red }
        if isMeetingActive { return .blue }
        return .green
    }
    
    private var statusText: String {
        if isProcessing { return "processing..." }
        if isRecording { return "recording" }
        if isMeetingActive { return "in meeting" }
        return "ready"
    }
    
    private var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Menu Button

struct MenuButton: View {
    
    let icon: String
    let title: String
    var subtitle: String? = nil
    let color: Color
    var isEnabled: Bool = true
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(isEnabled ? .primary : .secondary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if !isEnabled {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color(nsColor: .controlAccentColor).opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Developer Info Row

struct DevInfoRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                
                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        BuddyMenuView(
            isRecording: false,
            isProcessing: false,
            isMeetingActive: false,
            hasScreenRecordingPermission: true,
            recordingDuration: 0,
            onStartRecording: {},
            onStopRecording: {},
            onViewNotes: {},
            onSettings: {},
            onClose: {}
        )
        
        BuddyMenuView(
            isRecording: true,
            isProcessing: false,
            isMeetingActive: true,
            hasScreenRecordingPermission: true,
            recordingDuration: 125,
            onStartRecording: {},
            onStopRecording: {},
            onViewNotes: {},
            onSettings: {},
            onClose: {}
        )
    }
    .padding()
    .frame(width: 400, height: 700)
}
