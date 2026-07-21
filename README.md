# Nudger

A playful macOS menu bar app that puts an AI-powered desk buddy on your screen. It watches what you're doing (without screenshots!) and occasionally nudges you with helpful tips and content recommendations powered by OpenAI.

## Features

- **Buddy cursor** — a tiny cursor-shaped companion that sits on your desktop; ⌘-drag it anywhere and it remembers its position
- **Smart suggestions** — periodic speech bubbles with tips and recommendations generated from your current app context
- **Real, working links** — content recommendations are backed by Brave Search and validated before they're shown
- **Meeting assistant** — detects when you're in a meeting, can record system audio, transcribe it with Whisper, and generate structured meeting notes
- **Privacy-first** — only lightweight metadata (app name, bundle ID, window title) is sent to the API; never screenshots or screen content
- **Minimal & playful** — clean UI, low CPU usage, adjustable suggestion frequency

## Requirements

- macOS 14.0+ (Sonoma or later)
- Xcode 15+ / Swift 5.9+ (to build)
- An [OpenAI API key](https://platform.openai.com/api-keys) (required)
- A [Brave Search API key](https://brave.com/search/api/) (free tier available; used for content recommendations)

## Setup

### 1. Clone and configure

```bash
git clone <this-repo>
cd Nudger
cp Nudger/Config.swift.template Nudger/Config.swift
```

Open `Nudger/Config.swift` and add your API keys:

```swift
static let openAIAPIKey = "sk-..."       // required
static let braveAPIKey  = "BSA..."       // for content recommendations
```

> `Config.swift` is gitignored so your keys stay out of version control. **Never commit real API keys.**

Optional overrides in the same file:

```swift
static let openAIModel: String? = "gpt-4o"                  // default: gpt-4o-mini
static let openAIBaseURL: String? = "https://.../v1"        // default: api.openai.com/v1
```

### 2. Build and run

```bash
open Nudger.xcodeproj
```

Build and run with ⌘R. On first launch, Nudger walks you through onboarding (permissions and API keys). For everyday use, build a Release version and add it to your Login Items.

## Usage

### Menu bar controls

Click the Nudger icon in the menu bar:

- **Active** — toggle the buddy on/off (⌘A)
- **Frequency** — how often suggestions appear, from rare to often
- **Developer Mode** — debug tools:
  - **Trigger suggestion now** (⌘⇧T)
  - **Reset buddy position**
  - **Reset onboarding**
  - Accessibility status and current window context

### The buddy

- Hold **⌘** and drag the buddy to reposition it — the position persists across launches
- When a speech bubble appears: **✓** accepts the suggestion (e.g. opens a recommended link), **✕** dismisses it; bubbles auto-hide after a few seconds

### Permissions

- **Accessibility (optional)** — improves window title detection for better context. The app works without it.
- **Screen/audio recording (optional)** — only needed if you use the meeting recording feature.

## Privacy & Data

Nudger is designed with privacy in mind:

- **No screen capture** for suggestions — the app never takes screenshots or reads screen content
- **Minimal context** — only the app name, bundle ID, and window title (truncated) are sent to OpenAI
- **Meeting recording is explicit** — audio is only captured for the meeting notes feature, transcribed via OpenAI's Whisper API, and processed on your behalf with your own API key
- **No persistent activity logs** — your activity is not stored or analyzed
- **Your keys, your data** — all API calls go directly from your machine to OpenAI/Brave using your own keys

## Architecture

Swift, SwiftUI, and AppKit. Main source lives in `Nudger/`:

- `App/` — app entry point with `MenuBarExtra` and dependency wiring
- `Buddy/` — buddy cursor panel and controllers
- `UI/` — SwiftUI views for the buddy and speech bubbles
- `Suggest/` — suggestion scheduling with jittered timers and cooldowns
- `Services/` — context service (monitors active app/window)
- `LLM/` — OpenAI client, Brave content search, URL validation, schemas
- `Meetings/` — meeting detection, audio capture, Whisper transcription, notes generation
- `Automation/` — routes accepted suggestions to actions (URL opening, etc.)
- `Onboarding/` — first-launch setup flow
- `Settings/` — UserDefaults-backed settings store
- `Permissions/` — Accessibility permission helpers
- `Logging/` — centralized logging via `os.Logger`

## Troubleshooting

**"Set your OPENAI_API_KEY in Config.swift to activate suggestions"**
The app couldn't find an API key. Make sure you copied `Config.swift.template` to `Config.swift` and added your key, then rebuild.

**Suggestions aren't appearing**
Check that **Active** is enabled, raise the **Frequency** slider, verify your OpenAI key is valid and has credits, and check Console.app for Nudger log output.

**Window titles are empty**
Grant Accessibility permission (enable Developer Mode in the menu → Request Accessibility) for better window title detection.

## Project Status — Up for Grabs! 🎁

This project is no longer actively maintained by its original author — and that's by design. **Feel free to take it over and do whatever you want with it**: fork it, rename it, ship it, sell it, turn it into something completely different. No permission needed (the MIT license already covers you), no attribution expected.

If you build something cool with it, the original author would love to hear about it — say hi on X: [@CarlAtAthlas](https://x.com/CarlAtAthlas) or [@athlasio](https://x.com/athlasio).

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get started.

## Roadmap Ideas

- Store API keys in the macOS Keychain instead of `Config.swift`
- Richer context (active browser tab URLs via AppleScript)
- Custom buddy personalities and prompts
- Multi-language support

## License

[MIT](LICENSE)
