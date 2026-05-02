# OpenClaw Voice

**Voice interface for [OpenClaw](https://github.com/openclaw), [NemoClaw](https://github.com/nemoclaw), and other AI agents — from your iPhone and Apple CarPlay.**

Talk to any stdin/stdout AI assistant running on your Mac using natural voice commands from your iPhone — at your desk, on the couch, or in the car via CarPlay. Switch between multiple agents on the fly. OpenClaw Voice handles the full pipeline: speech recognition, real-time communication, and high-quality voice responses.

```
 iPhone / CarPlay                          Mac (laptop)
┌─────────────────┐    WebSocket/TLS    ┌──────────────────┐
│                 │ ◄────────────────► │                  │
│  Speech Input   │                     │  Relay Server    │
│  (Apple Speech) │    JSON Messages    │  (Node.js)       │
│                 │ ◄────────────────► │                  │
│  Voice Output   │                     │  OpenClaw        │
│  (ElevenLabs)   │                     │  (local process) │
└─────────────────┘                     └──────────────────┘
```

## How It Works

1. **You speak** to your iPhone or CarPlay
2. **Apple Speech Framework** converts your voice to text on-device (low latency, private)
3. The app sends the text over **WebSocket (TLS)** to a relay server on your Mac
4. The relay server pipes the command to your **local OpenClaw instance**
5. OpenClaw's response streams back in real-time
6. **ElevenLabs** synthesizes the response into natural-sounding speech
7. You hear the answer — the whole loop takes **under 2 seconds** to first audio

## Features

- **Multi-agent support** — run OpenClaw, NemoClaw, or any other stdin/stdout AI agent. Switch between agents from the app.
- **Voice-first interaction** — push-to-talk with on-device speech recognition + voice activity detection
- **Real-time conversational AI** — optional ElevenLabs Agent mode with full-duplex streaming and OpenAI-compatible HTTP backend
- **Streaming responses** — hear the agent's answer as it's being generated, not after
- **Apple CarPlay** — minimalist, voice-driven interface with `CPVoiceControlTemplate` for safe driving
- **ElevenLabs TTS** — multilingual, high-quality voice synthesis with configurable voices
- **Secure by default** — TLS encryption, token auth, iOS Keychain storage, optional 4-6 digit PIN gating sensitive remote actions
- **Remote access** — works outside your local network via Tailscale VPN with auto-detection and automatic LAN→Tailscale fallback
- **Remote config dashboard** — from the iPhone you can:
  - Monitor Mac status (CPU, RAM, battery, disk, uptime)
  - View live relay + OpenClaw logs with level/source filters
  - Manage MCPs (enable/disable, status)
  - Edit OpenClaw command/workdir/env vars (API keys masked)
  - Restart OpenClaw or the relay, regenerate the auth token, backup/restore config
- **QR code pairing** — scan to connect the app to your Mac
- **Auto-reconnection** — exponential backoff, transparent session recovery, on-screen disconnect notifications
- **Echo cancellation + mic gating** — prevents the model hearing its own TTS output
- **Waveform UI** — visual feedback while the agent listens or speaks
- **launchd autostart** — relay can run as a background service on the Mac

## Architecture

The system has two components:

### iOS App (Swift/SwiftUI)
- **UI Layer** — SwiftUI chat interface + CarPlay templates
- **Voice Layer** — Apple Speech (STT) + ElevenLabs (TTS) + AVAudioSession management
- **Network Layer** — WebSocket client with reconnection, heartbeat, and connection monitoring

### Relay Server (Node.js)
- **WebSocket Server** — accepts TLS connections from the app, handles auth
- **OpenClaw Bridge** — spawns and manages the OpenClaw process via stdin/stdout
- **Session Manager** — maintains conversation state and history
- **Config API** — exposes system status, OpenClaw config, and MCP management

Full architecture details: [`docs/ARCHITECTURE.md`](openclaw-voice-app/docs/ARCHITECTURE.md)

## Tech Stack

| Component | Technology |
|-----------|-----------|
| iOS App | Swift 5.9+, SwiftUI, iOS 17+ |
| Speech-to-Text | Apple Speech Framework (on-device) |
| Text-to-Speech | ElevenLabs API (streaming) |
| Communication | WebSocket over TLS (`wss://`) |
| CarPlay | CarPlay Framework (`CPVoiceControlTemplate`) |
| Relay Server | Node.js 20+ with `ws`, `child_process` |
| Security | TLS, JWT/token auth, iOS Keychain |
| Remote Access | Tailscale VPN (optional) |

## Prerequisites

### Mac (server)
- macOS 13+
- At least one AI agent installed (OpenClaw, NemoClaw, or any CLI-based assistant)
- Node.js 20+ (`brew install node`)
- Xcode 15+ (for iOS development)
- `xcodegen` to generate the Xcode project (`brew install xcodegen`)

### iPhone
- iOS 17.0+
- Same WiFi network as your Mac (or Tailscale)

### Accounts
- [Apple Developer Program](https://developer.apple.com/) ($99/year) — required for CarPlay entitlement and device deployment
- [ElevenLabs API key](https://elevenlabs.io) — for voice synthesis
- [Tailscale](https://tailscale.com) (optional) — free for personal use, enables remote access

## Quick Start

### 1. Start the Relay Server

```bash
cd server/openclaw-relay-server
npm install
node src/index.js
```

The server will:
- Generate TLS certificates automatically
- Create an auth token
- Display a QR code for pairing with the app
- Start listening on `wss://0.0.0.0:8765`

Test the connection:
```bash
npm install -g wscat
wscat -c wss://localhost:8765/ws --no-check
```

### 2. Build the iOS App

```bash
cd ios/OpenClawVoice
xcodegen generate
open OpenClawVoice.xcodeproj
```

In Xcode:
1. Select your Apple Developer Team in Signing & Capabilities
2. Connect your iPhone and press `Cmd + R`
3. In the app, scan the QR code from the relay server — or enter the URL and token manually

### 3. Talk to Your Agent

Press and hold the microphone button, speak your command, and release. The agent's response will play back as natural speech. To switch between agents, go to **Settings → AI Agent**.

## Configuring Agents

By default, the relay server is configured for two agents: **OpenClaw** and **NemoClaw**. You can edit `~/.openclaw-relay/config.json` to add more:

```json
{
  "agents": [
    { "id": "openclaw",  "name": "OpenClaw",  "command": "openclaw",  "description": "..." },
    { "id": "nemoclaw",  "name": "NemoClaw",  "command": "nemoclaw",  "description": "..." },
    { "id": "my-agent",  "name": "My Agent",  "command": "/path/to/cli", "args": ["--chat"] }
  ],
  "currentAgentId": "openclaw"
}
```

Any CLI assistant that reads from stdin and writes to stdout will work.

## Documentation

| Document | Description |
|----------|------------|
| [`docs/ARCHITECTURE.md`](openclaw-voice-app/docs/ARCHITECTURE.md) | System architecture and component diagrams |
| [`docs/IOS-APP.md`](openclaw-voice-app/docs/IOS-APP.md) | iOS app structure and specification |
| [`docs/VOICE-ENGINE.md`](openclaw-voice-app/docs/VOICE-ENGINE.md) | Voice pipeline — ElevenLabs + Apple Speech |
| [`docs/CARPLAY.md`](openclaw-voice-app/docs/CARPLAY.md) | Apple CarPlay integration |
| [`docs/PROTOCOL.md`](openclaw-voice-app/docs/PROTOCOL.md) | WebSocket protocol specification |
| [`docs/SERVER.md`](openclaw-voice-app/docs/SERVER.md) | Relay server specification |
| [`docs/REMOTE-CONFIG.md`](openclaw-voice-app/docs/REMOTE-CONFIG.md) | Remote OpenClaw configuration |
| [`docs/SETUP.md`](openclaw-voice-app/docs/SETUP.md) | Setup and deployment guide |
| [`docs/TAILSCALE.md`](openclaw-voice-app/docs/TAILSCALE.md) | Remote access over Tailscale (LAN + VPN fallback) |
| [`docs/CUSTOM-LLM.md`](openclaw-voice-app/docs/CUSTOM-LLM.md) | Wire ElevenLabs Realtime agent to your OpenClaw via Tailscale Funnel |
| [`specs/ROADMAP.md`](openclaw-voice-app/specs/ROADMAP.md) | Development roadmap and sprints |

## Development Roadmap

| Sprint | Focus | Status |
|--------|-------|--------|
| **Sprint 1** | Relay Server + basic iOS app | ✅ Done |
| **Sprint 2** | Voice pipeline (STT + TTS + real-time agent) | ✅ Done — MVP shipped |
| **Sprint 3** | Apple CarPlay | ✅ Code complete (templates + voice flow); device test + entitlement pending |
| **Sprint 4** | Polish, remote config, deploy | ✅ Code complete; physical device testing pending |
| **Sprint 5** | Enhancements (wake word, history, Watch, widgets) | 🟡 Backlog |

See the full roadmap with task breakdowns: [`specs/ROADMAP.md`](openclaw-voice-app/specs/ROADMAP.md)

## Contributing

We welcome contributions! This project is in active development and there are many ways to help:

- **Pick an issue** — check [open issues](../../issues) labeled `good first issue` or `help wanted`
- **Report bugs** — open an issue with the Bug Report template
- **Suggest features** — open an issue with the Feature Request template
- **Improve docs** — documentation PRs are always welcome
- **Code contributions** — see our [Contributing Guide](CONTRIBUTING.md)

### Areas Where We Need Help

- **Swift/SwiftUI developers** — iOS app, CarPlay integration, audio session management
- **Node.js developers** — relay server, OpenClaw bridge, output parsing
- **Audio engineers** — streaming audio pipeline, low-latency TTS playback
- **CarPlay testers** — testing on real CarPlay hardware
- **Translators** — app localization (currently Spanish + English)
- **Designers** — UI/UX for the iPhone and CarPlay interfaces

## Project Structure

```
openclaw-voice/
├── ios/                          # Xcode project
│   └── OpenClawVoice/
├── server/                       # Relay server (Node.js)
│   └── openclaw-relay-server/
├── openclaw-voice-app/
│   ├── docs/                     # Technical documentation
│   ├── specs/                    # Roadmap and planning
│   └── prompts/                  # AI assistant prompts
├── CLAUDE.md                     # Claude Code guidance
├── CONTRIBUTING.md               # Contribution guide
├── LICENSE                       # MIT License
└── README.md                     # This file
```

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenClaw](https://github.com/openclaw) — the AI assistant that powers the brain
- [ElevenLabs](https://elevenlabs.io) — for incredible multilingual voice synthesis
- [Apple Speech Framework](https://developer.apple.com/documentation/speech) — for on-device speech recognition

---

**OpenClaw Voice** is a [DCK Studios](https://dckstudios.com) project.

Built with love by the community.
