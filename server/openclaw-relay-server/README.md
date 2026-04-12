# OpenClaw Voice — Relay Server

Node.js WebSocket relay server that bridges the OpenClaw Voice iOS app to your local AI agent (OpenClaw, NemoClaw, etc.).

## Quick Start

```bash
npm install
node src/index.js
```

On first run, the server:
1. Generates self-signed TLS certificates in `~/.openclaw-relay/certs/`
2. Creates a config file at `~/.openclaw-relay/config.json` with:
   - A random 32-byte auth token
   - Default agents (OpenClaw + NemoClaw)
   - Port 8765
3. Displays a QR code for pairing with the iOS app

## Multi-Agent Support

The relay supports multiple AI agents. Switch between them from the iOS app, or edit `~/.openclaw-relay/config.json`:

```json
{
  "agents": [
    {
      "id": "openclaw",
      "name": "OpenClaw",
      "command": "openclaw",
      "args": [],
      "workdir": "/Users/you",
      "env": {},
      "description": "OpenClaw AI assistant"
    },
    {
      "id": "nemoclaw",
      "name": "NemoClaw",
      "command": "nemoclaw",
      "args": [],
      "workdir": "/Users/you",
      "env": {},
      "description": "NemoClaw AI assistant"
    }
  ],
  "currentAgentId": "openclaw"
}
```

Add as many agents as you want — any stdin/stdout-based CLI assistant works.

## Environment Variables

| Variable | Default | Description |
|----------|---------|------------|
| `OPENCLAW_RELAY_PORT` | `8765` | WebSocket port |
| `OPENCLAW_COMMAND` | `openclaw` | Override default agent command on first run |
| `OPENCLAW_WORKDIR` | `$HOME` | Working directory for agents |
| `DEBUG` | `false` | Enable debug logging |

## Architecture

```
src/
├── index.js                  # Entry point
├── config.js                 # Multi-agent config management
├── server/
│   ├── websocket-server.js   # TLS WebSocket server
│   ├── auth.js               # Token authentication
│   └── message-handler.js    # Message router
├── openclaw/
│   └── bridge.js             # AgentBridge (generic, supports any CLI agent)
├── session/
│   └── session-manager.js    # Per-client sessions
└── utils/
    ├── logger.js
    ├── tls.js                # Self-signed cert generation
    └── qr-setup.js           # QR code for pairing
```

## Protocol

Full WebSocket protocol documented in [`docs/PROTOCOL.md`](../../openclaw-voice-app/docs/PROTOCOL.md).

Key message types added for multi-agent support:

- `list_agents` → `agents_list` — List all configured agents
- `switch_agent` → `agent_switched` — Switch the active agent at runtime

## Testing

Manual test with `wscat`:

```bash
# Terminal 1
node src/index.js

# Terminal 2
npm install -g wscat
wscat -c wss://localhost:8765/ws --no-check

> {"type":"auth","token":"YOUR_TOKEN_FROM_CONFIG"}
< {"type":"auth_ok","session_id":"...","server_info":{"current_agent":{...}}}

> {"type":"list_agents","id":"1"}
< {"type":"agents_list","request_id":"1","payload":{"agents":[...]}}

> {"type":"switch_agent","id":"2","payload":{"agent_id":"nemoclaw"}}
< {"type":"agent_switched","request_id":"2","payload":{"success":true,"agent":{...}}}
```
