# Roadmap de Desarrollo — OpenClaw Voice

## Estrategia: MVP Funcional lo Antes Posible

La prioridad es tener una versión funcional (voz → OpenClaw → voz) en el menor tiempo posible. CarPlay y refinamientos vienen después.

## Sprint 1: Fundamentos (3-4 días)

### S1.1 — Relay Server Básico
- [ ] Inicializar proyecto Node.js con dependencias
- [ ] Implementar WebSocket server con TLS autofirmado
- [ ] Implementar autenticación por token
- [ ] Implementar heartbeat (ping/pong)
- [ ] Generar QR code para setup
- [ ] Test: conectar con wscat y enviar/recibir mensajes

### S1.2 — Bridge con OpenClaw
- [ ] Implementar spawn de proceso OpenClaw
- [ ] Implementar envío de comandos por stdin
- [ ] Implementar lectura de stdout con streaming
- [ ] Implementar detección de fin de respuesta
- [ ] Implementar manejo de errores y restart
- [ ] Test: enviar comando por WS → recibir respuesta de OpenClaw

### S1.3 — App iOS: Esqueleto
- [ ] Crear proyecto Xcode con estructura de carpetas
- [ ] Implementar AppState y modelos de datos
- [ ] Implementar WebSocketManager con reconexión
- [ ] Implementar vista de conexión (QR scanner + manual)
- [ ] Implementar ChatView básica (texto)
- [ ] Test: app conecta al relay y muestra mensajes

**Entregable Sprint 1**: Puedes escribir texto en la app → llega a OpenClaw → ves la respuesta en la app.

## Sprint 2: Voz (3-4 días)

### S2.1 — Speech-to-Text
- [ ] Implementar SpeechRecognizer con Apple Speech
- [ ] Implementar modo push-to-talk
- [ ] Implementar VoiceActivityDetector
- [ ] Implementar AudioSessionManager
- [ ] Implementar PulsingMicButton con animaciones
- [ ] Test: hablar al iPhone → ver transcripción correcta

### S2.2 — Text-to-Speech con ElevenLabs
- [ ] Implementar ElevenLabsService (API REST)
- [ ] Implementar streaming TTS
- [ ] Implementar StreamingAudioPlayer
- [ ] Implementar selección de voz
- [ ] Implementar configuración de voice settings
- [ ] Test: texto → audio reproducido correctamente

### S2.3 — Pipeline Completo
- [ ] Conectar STT → WebSocket → OpenClaw → WebSocket → TTS
- [ ] Implementar streaming end-to-end
- [ ] Manejar estados de UI (escuchando, procesando, hablando)
- [ ] Manejar interrupciones de audio
- [ ] Test: hablar → escuchar respuesta de OpenClaw por voz

**Entregable Sprint 2**: Puedes hablar al iPhone → OpenClaw procesa → escuchas la respuesta por voz. **¡MVP funcional!**

## Sprint 3: CarPlay (3-4 días)

### S3.1 — Interfaz CarPlay
- [ ] Implementar CarPlaySceneDelegate
- [ ] Implementar CarPlayTemplateManager
- [ ] Crear templates: voz, historial, estado
- [ ] Implementar estados visuales (idle, listening, processing, speaking)
- [ ] Test: app aparece en simulador CarPlay

### S3.2 — Voz en CarPlay
- [ ] Implementar CarPlayVoiceController
- [ ] Configurar AudioSession para CarPlay
- [ ] Manejar rutas de audio del coche
- [ ] Manejar conexión/desconexión de CarPlay
- [ ] Test: flujo completo de voz en simulador CarPlay

### S3.3 — Solicitar Entitlement
- [ ] Preparar solicitud en Apple Developer Portal
- [ ] Documentar caso de uso
- [ ] Enviar solicitud
- [ ] (Esperar aprobación — puede ser en paralelo con Sprint 4)

**Entregable Sprint 3**: CarPlay funciona en simulador con flujo completo de voz.

## Sprint 4: Pulido y Producción (3-4 días)

### S4.1 — Robustez
- [ ] Reconexión automática con backoff exponencial
- [ ] Manejo completo de errores en toda la cadena
- [ ] Logs y diagnóstico
- [ ] Gestión de memoria y leaks
- [ ] Cancelación de comandos en curso

### S4.2 — Configuración Remota de OpenClaw
- [ ] Implementar Config API Module en el relay server
- [ ] Vista de estado del sistema Mac (CPU, RAM, batería, red)
- [ ] Vista de configuración de OpenClaw (modelo, system prompt, parámetros)
- [ ] Gestión de MCPs (listar, activar/desactivar, configurar)
- [ ] Visor de logs en tiempo real (con filtros por nivel y fuente)
- [ ] Acciones: reiniciar OpenClaw, regenerar token, backup config
- [ ] Seguridad: PIN para acciones sensibles, enmascaramiento de keys
- [ ] Ver `docs/REMOTE-CONFIG.md` para especificación completa

### S4.3 — UX y Polish
- [ ] Animaciones de waveform mientras habla
- [ ] Indicadores claros de estado de conexión
- [ ] Notificaciones de desconexión
- [ ] Settings completo (servidor, voz, idioma)
- [ ] Soporte modo oscuro

### S4.4 — Acceso Remoto
- [ ] Documentar setup con Tailscale
- [ ] Auto-detección de IP Tailscale en servidor
- [ ] Fallback automático red local → Tailscale
- [ ] Test: funciona desde fuera de la red local

### S4.5 — Deploy
- [ ] Configurar relay server como servicio launchd
- [ ] Build para dispositivo real
- [ ] Testing en iPhone real
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
