# Arquitectura del Sistema — OpenClaw Voice

## 1. Visión General

El sistema se compone de dos piezas principales que se comunican en tiempo real:

**App iOS nativa** (iPhone + CarPlay) que captura voz del usuario, la convierte a texto, envía comandos a OpenClaw y reproduce las respuestas con voz sintetizada por ElevenLabs.

**Servidor Relay** en el portátil Mac que actúa como puente entre la app iOS y la instancia local de OpenClaw, gestionando la sesión, el estado y la comunicación bidireccional.

## 2. Diagrama de Componentes

```
┌──────────────────────────────────────────────────────────────────┐
│                        iPhone / CarPlay                          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │   UI Layer   │  │  Voice Layer │  │   Network Layer        │ │
│  │              │  │              │  │                        │ │
│  │ • SwiftUI    │  │ • SpeechRec  │  │ • WebSocketManager     │ │
│  │ • ChatView   │  │ • ElevenLabs │  │ • APIClient            │ │
│  │ • CarPlayUI  │  │ • AudioSess  │  │ • ConnectionMonitor    │ │
│  │ • Settings   │  │ • VAD        │  │ • ReconnectionHandler  │ │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬────────────┘ │
│         │                 │                       │              │
│         └─────────────────┴───────────────────────┘              │
│                           │                                      │
│                    ┌──────┴───────┐                               │
│                    │ AppViewModel │                               │
│                    │ (State Mgmt) │                               │
│                    └──────┬───────┘                               │
└───────────────────────────┼──────────────────────────────────────┘
                            │ WebSocket (wss://)
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│                      Mac (Portátil)                              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    Relay Server                             │  │
│  │                                                            │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │  │
│  │  │ WS Handler   │  │ Session Mgr  │  │ OpenClaw Bridge │  │  │
│  │  │              │  │              │  │                 │  │  │
│  │  │ • Auth       │  │ • State      │  │ • stdin/stdout  │  │  │
│  │  │ • Routing    │  │ • History    │  │ • Process Mgmt  │  │  │
│  │  │ • Heartbeat  │  │ • Context    │  │ • Output Parse  │  │  │
│  │  └──────────────┘  └──────────────┘  └────────┬────────┘  │  │
│  │                                                │          │  │
│  └────────────────────────────────────────────────┼──────────┘  │
│                                                   │              │
│                                          ┌────────▼────────┐     │
│                                          │    OpenClaw     │     │
│                                          │   (Proceso)     │     │
│                                          └─────────────────┘     │
└──────────────────────────────────────────────────────────────────┘
```

## 3. Flujo de Datos Principal

### 3.1 Usuario habla → OpenClaw responde

```
1. Usuario habla al iPhone/CarPlay
2. Apple Speech Framework convierte voz → texto (on-device, baja latencia)
3. App envía texto como mensaje JSON por WebSocket al Relay Server
4. Relay Server reenvía el comando a OpenClaw via stdin del proceso
5. OpenClaw procesa y genera respuesta por stdout
6. Relay Server parsea la salida, la empaqueta como JSON
7. Envía respuesta por WebSocket a la app iOS
8. App recibe texto y lo envía a ElevenLabs API (streaming TTS)
9. Audio se reproduce en el iPhone/CarPlay
10. UI muestra transcripción del diálogo en paralelo
```

### 3.2 Flujo de streaming (respuestas largas)

```
OpenClaw genera tokens → Relay los envía como chunks →
App muestra texto progresivamente + envía chunks a ElevenLabs →
Audio se reproduce en streaming sin esperar respuesta completa
```

## 4. Componentes Clave

### 4.1 App iOS — Capas

| Capa | Responsabilidad | Tecnología |
|------|----------------|------------|
| **UI** | Interfaz visual iPhone + CarPlay | SwiftUI + CarPlay Framework |
| **Voice** | Captura de voz y síntesis | Apple Speech + ElevenLabs SDK |
| **Network** | Comunicación con relay | URLSessionWebSocketTask |
| **State** | Estado de la app y sesión | ObservableObject / @Observable |
| **Audio** | Gestión de sesiones de audio | AVAudioSession |

### 4.2 Servidor Relay — Módulos

| Módulo | Responsabilidad | Tecnología |
|--------|----------------|------------|
| **WebSocket Server** | Acepta conexiones de la app | Node.js `ws` o Python `websockets` |
| **Auth** | Valida token de conexión | JWT o token estático |
| **OpenClaw Bridge** | Gestiona proceso OpenClaw | child_process (Node) o subprocess (Python) |
| **Session Manager** | Mantiene estado y contexto | En memoria |
| **Output Parser** | Parsea stdout de OpenClaw | Regex + JSON |

## 5. Modelo de Datos

### 5.1 Mensaje del Cliente → Servidor

```json
{
  "type": "command",
  "id": "uuid-v4",
  "payload": {
    "text": "busca todas las oportunidades abiertas",
    "context": {
      "source": "voice",
      "carplay": false,
      "language": "es"
    }
  },
  "timestamp": "2026-04-11T10:30:00Z"
}
```

### 5.2 Mensaje del Servidor → Cliente

```json
{
  "type": "response",
  "id": "uuid-v4",
  "request_id": "uuid-del-comando",
  "payload": {
    "text": "He encontrado 15 oportunidades abiertas...",
    "chunk": false,
    "finished": true,
    "metadata": {
      "tokens_used": 250,
      "processing_time_ms": 1200
    }
  },
  "timestamp": "2026-04-11T10:30:01Z"
}
```

### 5.3 Mensajes de Control

```json
{"type": "ping"}
{"type": "pong"}
{"type": "auth", "token": "..."}
{"type": "auth_ok"}
{"type": "error", "code": "AUTH_FAILED", "message": "..."}
{"type": "status", "openclaw_status": "ready|busy|error"}
```

## 6. Seguridad

### 6.1 En Red Local
- WebSocket sobre TLS (wss://) con certificado autofirmado
- Token de autenticación generado al iniciar el relay server
- QR code o entrada manual para vincular app con servidor

### 6.2 Acceso Remoto (fuera de casa/oficina)
- Tailscale VPN para tunnel seguro sin exponer puertos
- Alternativa: Cloudflare Tunnel
- El relay server solo escucha en la interfaz de Tailscale

### 6.3 Almacenamiento
- Token se almacena en iOS Keychain
- No se almacenan conversaciones en disco (solo en memoria de sesión)
- Configuración de ElevenLabs API key en Keychain

## 7. Consideraciones de Rendimiento

### 7.1 Latencia Target
- Voz → Texto (STT): < 300ms (on-device con Apple Speech)
- Texto → OpenClaw → Respuesta: depende de OpenClaw (típico 1-5s)
- Texto → Voz (TTS): < 500ms primer chunk (ElevenLabs streaming)
- **Latencia total percibida**: < 2s hasta primer audio de respuesta

### 7.2 Optimizaciones
- Streaming de respuesta: no esperar a la respuesta completa
- ElevenLabs streaming API: empezar a hablar con el primer chunk
- Prefetch de conexión WebSocket al abrir la app
- Reconexión automática con backoff exponencial
- Cache de voces ElevenLabs seleccionadas

## 8. Requisitos del Sistema

### 8.1 iPhone
- iOS 17.0+
- iPhone con capacidad de Speech Recognition
- Conexión a la misma red que el Mac (o Tailscale)

### 8.2 Mac (Portátil)
- macOS 13+
- OpenClaw instalado y funcional
- Node.js 20+ o Python 3.11+
- Puerto disponible (default: 8765)

### 8.3 CarPlay
- Vehículo o simulador con soporte CarPlay
- Entitlement de CarPlay (requiere Apple Developer Program)
