# Contributing to Nudger

Thanks for your interest in contributing! Nudger is a small, playful project - contributions of all sizes are welcome.

## Getting Started

1. Fork and clone the repository.
2. Copy the config template and add your own API keys:
   ```bash
   cp Nudger/Config.swift.template Nudger/Config.swift
   ```
   `Config.swift` is gitignored - never commit real API keys.
3. Open `Nudger.xcodeproj` in Xcode 15+ and build (⌘R).

## Guidelines

- **Never commit secrets.** API keys belong in `Config.swift` (gitignored) only. If you accidentally commit a key, rotate it immediately.
- Keep the app privacy-first: no screenshots, no screen content capture, minimal metadata sent to external APIs.
- Match the existing code style (Swift, SwiftUI/AppKit, `os.Logger` for logging).
- For larger changes, open an issue first to discuss the direction.

## Pull Requests

- Keep PRs focused on a single change.
- Describe what the change does and why.
- Make sure the project builds cleanly in Xcode before submitting.

## Reporting Issues

Open a GitHub issue with steps to reproduce, your macOS version, and any relevant output from Console.app (Nudger logs via `os.Logger`).
