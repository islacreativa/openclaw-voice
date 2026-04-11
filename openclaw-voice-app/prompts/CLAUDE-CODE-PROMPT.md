# Prompt Maestro para Claude Code — OpenClaw Voice

## Contexto del Proyecto

Estamos desarrollando **OpenClaw Voice**, una app nativa iOS (Swift/SwiftUI) que permite interactuar con OpenClaw (ejecutándose en un Mac) mediante voz desde el iPhone, incluyendo soporte para Apple CarPlay.

## Documentación de Referencia

Antes de empezar cualquier tarea, lee estos documentos en orden:

1. `docs/ARCHITECTURE.md` — Arquitectura completa del sistema
2. `docs/IOS-APP.md` — Estructura y especificación de la app iOS
3. `docs/VOICE-ENGINE.md` — Integración de voz (ElevenLabs + Apple Speech)
4. `docs/CARPLAY.md` — Integración con Apple CarPlay
5. `docs/PROTOCOL.md` — Protocolo de comunicación WebSocket
6. `docs/SERVER.md` — Servidor relay para el Mac
7. `docs/REMOTE-CONFIG.md` — Configuración remota de OpenClaw desde la app
8. `docs/SETUP.md` — Guía de configuración
9. `specs/ROADMAP.md` — Plan de desarrollo y sprints

## Instrucciones para Claude Code

### Principios de Desarrollo

1. **Código nativo**: Usar Swift 5.9+ y SwiftUI. NO usar frameworks cross-platform.
2. **iOS 17+**: Aprovechar `@Observable`, structured concurrency (`async/await`), y APIs modernas.
3. **Mínimas dependencias**: Preferir APIs nativas de Apple cuando sea posible. Usar paquetes externos solo cuando aporten valor claro.
4. **Streaming-first**: Todo el pipeline debe funcionar en streaming (respuestas parciales, audio parcial).
5. **Error handling robusto**: Cada operación de red y de audio puede fallar. Manejar todos los errores con feedback al usuario.
6. **CarPlay-ready**: Diseñar desde el inicio para soportar dos interfaces simultáneas (iPhone + CarPlay).

### Stack Técnico

**App iOS:**
- Swift 5.9+, SwiftUI
- Target: iOS 17.0+
- Apple Speech Framework (STT on-device)
- ElevenLabs REST API (TTS streaming)
- URLSessionWebSocketTask (WebSocket nativo)
- AVAudioSession, AVAudioEngine (gestión de audio)
- CarPlay Framework (CPTemplate, CPVoiceControlTemplate)
- Keychain Services (almacenamiento seguro)

**Servidor Relay (Node.js):**
- Node.js 20+
- `ws` para WebSocket server
- `child_process` para gestionar OpenClaw
- `selfsigned` para TLS
- `jsonwebtoken` para auth

### Orden de Desarrollo Recomendado

Seguir los sprints definidos en `specs/ROADMAP.md`:

```
Sprint 1: Relay Server + App iOS básica (texto)
Sprint 2: Voz (STT + TTS + pipeline)
Sprint 3: CarPlay
Sprint 4: Robustez y producción
```

### Convenciones de Código

#### Swift
```swift
// Usar @Observable en vez de ObservableObject cuando sea posible
@Observable
final class MyViewModel { }

// Usar async/await en vez de completion handlers
func fetchData() async throws -> Data { }

// Usar guard para validaciones tempranas
guard let value = optionalValue else { return }

// Naming: camelCase para variables y funciones, PascalCase para tipos
let connectionManager = ConnectionManager()

// Documentar funciones públicas
/// Envía un comando de voz a OpenClaw
/// - Parameter text: El texto transcrito del usuario
/// - Returns: La respuesta de OpenClaw
func sendCommand(_ text: String) async throws -> String { }
```

#### Node.js
```javascript
// Usar ESM imports
import { WebSocketServer } from 'ws';

// Usar async/await
async function processCommand(text) { }

// Manejar errores con try/catch
try {
    await bridge.sendCommand(text);
} catch (error) {
    logger.error(`Command failed: ${error.message}`);
}
```

### Estructura de Archivos a Crear

#### Fase 1 — Servidor Relay
```
openclaw-relay-server/
├── package.json
├── src/
│   ├── index.js
│   ├── config.js
│   ├── server/
│   │   ├── websocket-server.js
│   │   ├── auth.js
│   │   └── message-handler.js
│   ├── openclaw/
│   │   ├── bridge.js
│   │   ├── output-parser.js
│   │   └── process-manager.js
│   ├── session/
│   │   ├── session-manager.js
│   │   └── history.js
│   └── utils/
│       ├── logger.js
│       ├── tls.js
│       └── qr-setup.js
└── certs/
```

#### Fase 2 — App iOS
```
OpenClawVoice/
├── OpenClawVoiceApp.swift
├── Core/ (AppState, AppConfig, Constants)
├── Models/ (Message, ServerMessage, ConnectionStatus, VoiceSettings)
├── Services/
│   ├── WebSocket/ (WebSocketManager, ReconnectionHandler)
│   ├── Voice/ (SpeechRecognizer, ElevenLabsService, AudioSessionManager)
│   ├── Network/ (ConnectionMonitor, ServerDiscovery)
│   └── Security/ (KeychainManager, TokenManager)
├── ViewModels/ (ChatViewModel, SettingsViewModel, ConnectionViewModel)
├── Views/
│   ├── Main/ (ContentView, ChatView, VoiceButton)
│   ├── Connection/ (ConnectionSetupView, QRScannerView)
│   ├── Settings/ (SettingsView, VoiceSettingsView)
│   └── Components/ (MessageBubble, WaveformView, PulsingMicButton)
└── CarPlay/ (CarPlaySceneDelegate, CarPlayTemplateManager, CarPlayVoiceController)
```

### Puntos Críticos a Investigar

1. **Cómo detectar fin de respuesta de OpenClaw**: ¿Usa un prompt? ¿Un marcador? ¿Un JSON mode? Esto es crítico para el `output-parser.js`.
2. **Audio session sharing**: iPhone y CarPlay comparten la misma AVAudioSession. Manejar correctamente las transiciones.
3. **Certificate pinning**: Decidir si implementar pinning del certificado autofirmado del relay o confiar en la conexión TLS.
4. **ElevenLabs WebSocket vs REST**: Para streaming real-time, el WebSocket de ElevenLabs es mejor pero más complejo. Empezar con REST streaming y migrar si la latencia no es suficiente.

### Testing

Para cada componente, crear tests unitarios:
- `WebSocketManagerTests` — Conexión, reconexión, mensajes
- `SpeechRecognizerTests` — Transcripción, estados
- `ElevenLabsServiceTests` — TTS, manejo de errores
- `MessageParsingTests` — Serialización/deserialización JSON

### Comando para Empezar

```
"Lee toda la documentación en docs/ y specs/, luego empieza por el Sprint 1:
1. Crea el proyecto del servidor relay (Node.js) con la estructura definida
2. Implementa el WebSocket server con autenticación
3. Implementa el bridge con OpenClaw
4. Una vez el servidor funcione, crea el proyecto iOS y la conexión WebSocket"
```
