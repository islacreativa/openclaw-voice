# Roadmap de Desarrollo — OpenClaw Voice

## Estrategia: MVP Funcional lo Antes Posible

La prioridad es tener una versión funcional (voz → OpenClaw → voz) en el menor tiempo posible. CarPlay y refinamientos vienen después.

## Sprint 1: Fundamentos (3-4 días)

### S1.1 — Relay Server Básico
- [x] Inicializar proyecto Node.js con dependencias
- [x] Implementar WebSocket server con TLS autofirmado
- [x] Implementar autenticación por token
- [x] Implementar heartbeat (ping/pong)
- [x] Generar QR code para setup
- [x] Test: conectar con wscat y enviar/recibir mensajes

### S1.2 — Bridge con OpenClaw
- [x] Implementar spawn de proceso OpenClaw
- [x] Implementar envío de comandos por stdin
- [x] Implementar lectura de stdout con streaming
- [x] Implementar detección de fin de respuesta (prompt regex + silence timeout en `stdio-adapter.js`; JSON framing en `openclaw-adapter.js`)
- [x] Implementar manejo de errores y restart
- [x] Test: enviar comando por WS → recibir respuesta de OpenClaw

### S1.3 — App iOS: Esqueleto
- [x] Crear proyecto Xcode con estructura de carpetas
- [x] Implementar AppState y modelos de datos
- [x] Implementar WebSocketManager con reconexión
- [x] Implementar vista de conexión (QR scanner + manual)
- [x] Implementar ChatView básica (texto)
- [x] Test: app conecta al relay y muestra mensajes

**Entregable Sprint 1**: Puedes escribir texto en la app → llega a OpenClaw → ves la respuesta en la app.

## Sprint 2: Voz (3-4 días)

### S2.1 — Speech-to-Text
- [x] Implementar SpeechRecognizer con Apple Speech
- [x] Implementar modo push-to-talk
- [x] Implementar VoiceActivityDetector (`Services/Voice/VoiceActivityDetector.swift` + hook en SpeechRecognizer tap)
- [x] Implementar AudioSessionManager
- [x] Implementar PulsingMicButton con animaciones
- [x] Test: hablar al iPhone → ver transcripción correcta

### S2.2 — Text-to-Speech con ElevenLabs
- [x] Implementar ElevenLabsService (API REST)
- [x] Implementar streaming TTS
- [x] Implementar StreamingAudioPlayer
- [x] Implementar selección de voz
- [x] Implementar configuración de voice settings
- [x] Test: texto → audio reproducido correctamente

### S2.3 — Pipeline Completo
- [x] Conectar STT → WebSocket → OpenClaw → WebSocket → TTS
- [x] Implementar streaming end-to-end
- [x] Manejar estados de UI (escuchando, procesando, hablando)
- [x] Manejar interrupciones de audio (echo cancellation + mic gating)
- [x] Test: hablar → escuchar respuesta de OpenClaw por voz

### S2.4 — Real-time Conversational AI (extra)
- [x] Integración ElevenLabs Conversational AI (agent)
- [x] RealtimeConversationView con selección de agent editable
- [x] HTTP API OpenAI-compatible en el relay
- [x] Multi-agent (OpenClaw + NemoClaw, switch en caliente)

**Entregable Sprint 2**: Puedes hablar al iPhone → OpenClaw procesa → escuchas la respuesta por voz. **¡MVP funcional!**

## Sprint 3: CarPlay (3-4 días)

### S3.1 — Interfaz CarPlay
- [x] Implementar CarPlaySceneDelegate (`CarPlay/CarPlaySceneDelegate.swift`, conectada a `CarPlayCoordinator`)
- [x] Implementar CarPlayTemplateManager (`CarPlay/CarPlayTemplateManager.swift`)
- [x] Crear templates: voz, historial, estado (CPTabBarTemplate con CPListTemplate + CPVoiceControlTemplate modal)
- [x] Implementar estados visuales (idle, listening, processing, speaking) — driven via `CarPlayVoiceController.state`
- [ ] Test: app aparece en simulador CarPlay (**requiere Xcode del usuario**)

### S3.2 — Voz en CarPlay
- [x] Implementar CarPlayVoiceController con flujo STT → WS → ElevenLabs TTS
- [x] Configurar AudioSession para CarPlay (`.playAndRecord` + `.voiceChat`, BluetoothA2DP/HFP)
- [x] Manejar rutas de audio del coche (BluetoothA2DP/HFP + defaultToSpeaker)
- [x] Manejar conexión/desconexión de CarPlay (`appState.isCarPlayConnected`, NotificationCenter)
- [ ] Test: flujo completo de voz en simulador CarPlay (**requiere Xcode del usuario**)

### S3.3 — Solicitar Entitlement
- [x] Entitlements file creado (`OpenClawVoice/OpenClawVoice.entitlements` con `com.apple.developer.carplay-communication`)
- [ ] Preparar solicitud en Apple Developer Portal (**requiere acceso a la cuenta de desarrollador**)
- [ ] Documentar caso de uso
- [ ] Enviar solicitud
- [ ] (Esperar aprobación — puede ser en paralelo con Sprint 4)

**Entregable Sprint 3**: CarPlay funciona en simulador con flujo completo de voz.

## Sprint 4: Pulido y Producción (3-4 días)

### S4.1 — Robustez
- [x] Reconexión automática con backoff exponencial
- [x] Manejo completo de errores en toda la cadena (errors surfaced via `connectionStatus`, `DisconnectNotifier`, `[WS] Receive error` logs, `service.lastError` en RealtimeView)
- [x] Logs y diagnóstico
- [x] Gestión de memoria y leaks (weak captures en Task closures, cancel de `heartbeatTask`/`receiveTask`/`connectTimeoutTask` en `disconnect()`)
- [x] Cancelación de comandos en curso

### S4.2 — Configuración Remota de OpenClaw
- [x] Implementar Config API Module en el relay server (`server/openclaw-relay-server/src/server/config-handler.js`)
- [x] Vista de estado del sistema Mac (CPU, RAM, batería, red) — `Views/Settings/SystemStatusView.swift` + `utils/system-monitor.js`
- [x] Vista de configuración de OpenClaw (`Views/Settings/OpenClawConfigView.swift`)
- [x] Gestión de MCPs (listar, activar/desactivar) — `Views/Settings/MCPManagementView.swift` (instalación deferred al CLI de OpenClaw)
- [x] Visor de logs en tiempo real con filtros — `Views/Settings/LogViewerView.swift` + `utils/log-bus.js`
- [x] Acciones: reiniciar OpenClaw, regenerar token, backup/restore config
- [x] Seguridad: PIN para acciones sensibles (`Views/Settings/SecurityView.swift` + `Views/Settings/PINGateView.swift`), enmascaramiento de API keys
- [x] Ver `docs/REMOTE-CONFIG.md` para especificación completa

### S4.3 — UX y Polish
- [x] Animaciones de waveform mientras habla (`Views/Components/WaveformView.swift`, integrado en RealtimeConversationView)
- [x] Indicadores claros de estado de conexión
- [x] Notificaciones de desconexión (`Services/Notifications/DisconnectNotifier.swift`, disparado desde `WebSocketManager.handleDisconnection`)
- [x] Settings completo (servidor, voz, idioma)
- [x] Soporte modo oscuro (toda la UI usa colores semánticos `.primary`/`.secondary`/tintados; blancos solo sobre fondos de marca)

### S4.4 — Acceso Remoto
- [x] Documentar setup con Tailscale (`docs/TAILSCALE.md`)
- [x] Auto-detección de IP Tailscale en servidor (config.js `getTailscaleIP`, QR con `tailscale_url`)
- [x] Fallback automático red local → Tailscale (iOS: candidatos en `WebSocketManager` con timeout 6s)
- [ ] Test: funciona desde fuera de la red local (**requiere probar en dispositivo real**)

### S4.5 — Deploy
- [x] Configurar relay server como servicio launchd (`server/openclaw-relay-server/launchd/com.dckstudios.openclaw-relay.plist`)
- [ ] Build para dispositivo real (**requiere Xcode del usuario**)
- [ ] Testing en iPhone real (**requiere dispositivo del usuario**)
- [ ] Testing en CarPlay real (cuando entitlement aprobado)

**Entregable Sprint 4**: App lista para uso diario real.

## Sprint 5: Mejoras (Ongoing)

- [ ] Modo continuo de escucha con wake word
- [ ] Historial de conversaciones persistente
- [ ] Widgets de iOS (estado de conexión)
- [ ] Siri Shortcuts integration
- [ ] Apple Watch companion app (stretch goal)
- [ ] Múltiples instancias de OpenClaw
- [ ] Soporte multiidioma en STT

## Timeline Estimado

```
Semana 1: Sprint 1 + Sprint 2 (MVP funcional)
Semana 2: Sprint 3 + Sprint 4 (versión completa)
Semana 3+: Sprint 5 (mejoras iterativas)
```

## Prioridades Críticas

1. **MVP funcional** (voz → OpenClaw → voz en iPhone) — Sprint 1+2
2. **Detección de fin de respuesta** de OpenClaw — investigar cómo funciona
3. **Latencia aceptable** — streaming end-to-end
4. **CarPlay** — depende del entitlement de Apple
