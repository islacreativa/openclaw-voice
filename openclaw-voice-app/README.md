# OpenClaw Voice — App iOS Nativa con Voz

## Visión General

OpenClaw Voice es una app nativa iOS (Swift/SwiftUI) que permite interactuar con OpenClaw ejecutándose en tu portátil Mac mediante comandos de voz desde el iPhone, incluyendo soporte completo para Apple CarPlay.

## Arquitectura de Alto Nivel

```
┌─────────────────────┐         WebSocket/TLS         ┌──────────────────────┐
│   iPhone / CarPlay   │ ◄──────────────────────────► │   Mac (Portátil)      │
│                     │                               │                      │
│  ┌───────────────┐  │                               │  ┌────────────────┐  │
│  │ Speech Input  │  │                               │  │ Relay Server   │  │
│  │ (Apple Speech)│  │                               │  │ (Node.js/Py)   │  │
│  └───────┬───────┘  │                               │  └───────┬────────┘  │
│          ▼          │                               │          ▼          │
│  ┌───────────────┐  │      JSON Messages            │  ┌────────────────┐  │
│  │ Voice Engine  │  │ ◄──────────────────────────► │  │   OpenClaw      │  │
│  │ (ElevenLabs)  │  │                               │  │   Instance      │  │
│  └───────────────┘  │                               │  └────────────────┘  │
└─────────────────────┘                               └──────────────────────┘
```

## Stack Tecnológico

- **iOS App**: Swift 5.9+, SwiftUI, iOS 17+
- **Voz STT**: Apple Speech Framework (on-device)
- **Voz TTS**: ElevenLabs API (streaming)
- **Comunicación**: WebSocket (URLSessionWebSocketTask / Starscream)
- **CarPlay**: CarPlay Framework (CPTemplate)
- **Servidor Relay**: Node.js con ws + child_process (o Python con FastAPI + websockets)
- **Seguridad**: TLS, autenticación por token, red local + Tailscale para remoto

## Estructura de Documentación

```
openclaw-voice-app/
├── README.md                          ← Este archivo
├── docs/
│   ├── ARCHITECTURE.md                ← Arquitectura detallada del sistema
│   ├── IOS-APP.md                     ← Especificación de la app iOS
│   ├── VOICE-ENGINE.md                ← Integración ElevenLabs + Speech
│   ├── CARPLAY.md                     ← Integración Apple CarPlay
│   ├── PROTOCOL.md                    ← Protocolo de comunicación WebSocket
│   ├── SERVER.md                      ← Servidor relay en el portátil
│   ├── REMOTE-CONFIG.md               ← Configuración remota de OpenClaw desde la app
│   └── SETUP.md                       ← Guía de configuración y despliegue
├── specs/
│   └── ROADMAP.md                     ← Plan de sprints y roadmap
└── prompts/
    └── CLAUDE-CODE-PROMPT.md          ← Prompt maestro para Claude Code
```

## Inicio Rápido

1. Leer `docs/ARCHITECTURE.md` para entender el sistema completo
2. Seguir `docs/SETUP.md` para configurar el entorno de desarrollo
3. Usar `prompts/CLAUDE-CODE-PROMPT.md` como prompt para Claude Code
4. Seguir `specs/ROADMAP.md` para el orden de desarrollo

## Propietario

- **Proyecto**: DCK Studios
- **Responsable**: Javier Molina (javier.molina@dckstudios.com)
