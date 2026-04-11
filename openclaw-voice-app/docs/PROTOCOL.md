# Protocolo de Comunicación WebSocket

## 1. Visión General

La comunicación entre la app iOS y el Relay Server se realiza a través de WebSocket (wss://) con mensajes JSON. El protocolo soporta streaming bidireccional para respuestas en tiempo real.

## 2. Conexión

### 2.1 URL de Conexión

```
Red local:   wss://{ip-mac}:8765/ws
Tailscale:   wss://{tailscale-ip}:8765/ws
```

### 2.2 Handshake

```
Cliente                                    Servidor
  │                                           │
  │──── WS Connect ──────────────────────────►│
  │                                           │
  │──── auth { token: "..." } ───────────────►│
  │                                           │
  │◄─── auth_ok { session_id: "..." } ───────│
  │                                           │
  │◄─── status { openclaw: "ready" } ────────│
  │                                           │
  │──── ping ────────────────────────────────►│
  │◄─── pong ────────────────────────────────│
  │                                           │
```

## 3. Tipos de Mensaje

### 3.1 Cliente → Servidor

#### auth — Autenticación
```json
{
  "type": "auth",
  "token": "jwt-or-static-token",
  "client_info": {
    "device": "iPhone 15 Pro",
    "os_version": "17.4",
    "app_version": "1.0.0",
    "is_carplay": false
  }
}
```

#### command — Enviar comando a OpenClaw
```json
{
  "type": "command",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "payload": {
    "text": "busca las oportunidades de más de 50k",
    "source": "voice",
    "language": "es",
    "context": {
      "carplay": false,
      "previous_command_id": null
    }
  }
}
```

#### cancel — Cancelar comando en curso
```json
{
  "type": "cancel",
  "command_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

#### ping — Heartbeat
```json
{
  "type": "ping",
  "timestamp": "2026-04-11T10:30:00Z"
}
```

### 3.2 Servidor → Cliente

#### auth_ok — Autenticación exitosa
```json
{
  "type": "auth_ok",
  "session_id": "session-uuid",
  "server_info": {
    "version": "1.0.0",
    "openclaw_version": "x.y.z"
  }
}
```

#### auth_error — Error de autenticación
```json
{
  "type": "auth_error",
  "code": "INVALID_TOKEN",
  "message": "Token inválido o expirado"
}
```

#### response_start — Inicio de respuesta
```json
{
  "type": "response_start",
  "command_id": "550e8400-e29b-41d4-a716-446655440000",
  "response_id": "resp-uuid"
}
```

#### response_chunk — Chunk de respuesta (streaming)
```json
{
  "type": "response_chunk",
  "command_id": "550e8400-e29b-41d4-a716-446655440000",
  "response_id": "resp-uuid",
  "payload": {
    "text": "He encontrado 5 oportunidades ",
    "chunk_index": 0
  }
}
```

#### response_end — Fin de respuesta
```json
{
  "type": "response_end",
  "command_id": "550e8400-e29b-41d4-a716-446655440000",
  "response_id": "resp-uuid",
  "payload": {
    "full_text": "He encontrado 5 oportunidades con valor superior a 50k...",
    "metadata": {
      "tokens_input": 45,
      "tokens_output": 230,
      "processing_time_ms": 3200,
      "openclaw_tool_calls": ["crm_search", "crm_filter"]
    }
  }
}
```

#### status — Estado de OpenClaw
```json
{
  "type": "status",
  "openclaw_status": "ready",
  "details": {
    "uptime_seconds": 3600,
    "memory_mb": 256,
    "active_session": true
  }
}
```

#### error — Error
```json
{
  "type": "error",
  "code": "OPENCLAW_ERROR",
  "message": "OpenClaw no pudo procesar el comando",
  "command_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

#### pong — Heartbeat response
```json
{
  "type": "pong",
  "timestamp": "2026-04-11T10:30:00Z"
}
```

## 4. Flujo de Streaming Completo

```
Cliente                                    Servidor
  │                                           │
  │──── command { text: "..." } ─────────────►│
  │                                           │ → OpenClaw procesa
  │◄─── response_start { id } ───────────────│
  │                                           │
  │◄─── response_chunk { text: "He " } ──────│ → App empieza TTS
  │◄─── response_chunk { text: "encontrado "}│
  │◄─── response_chunk { text: "5 " } ───────│
  │◄─── response_chunk { text: "oportun..." }│
  │                                           │
  │◄─── response_end { full_text, meta } ────│
  │                                           │
```

## 5. Códigos de Error

| Código | Descripción |
|--------|------------|
| `AUTH_FAILED` | Token inválido |
| `AUTH_EXPIRED` | Token expirado |
| `OPENCLAW_NOT_RUNNING` | Proceso OpenClaw no está activo |
| `OPENCLAW_BUSY` | OpenClaw está procesando otro comando |
| `OPENCLAW_ERROR` | Error interno de OpenClaw |
| `COMMAND_TIMEOUT` | Comando excedió el timeout (default 60s) |
| `RATE_LIMITED` | Demasiados comandos en poco tiempo |
| `SERVER_ERROR` | Error interno del relay server |

## 6. Reconexión

### 6.1 Estrategia de Backoff Exponencial

```
Intento 1: esperar 1s
Intento 2: esperar 2s
Intento 3: esperar 4s
Intento 4: esperar 8s
Intento 5: esperar 16s
Intento 6+: esperar 30s (máximo)
```

### 6.2 Reconexión Transparente

```
1. WebSocket se desconecta
2. App muestra indicador "Reconectando..."
3. Intentar reconectar con backoff
4. Al reconectar, enviar auth con mismo token
5. Servidor restaura sesión si session_id coincide
6. App continúa normalmente
```

## 7. Heartbeat

- Cliente envía `ping` cada 15 segundos
- Servidor responde con `pong`
- Si no se recibe `pong` en 10 segundos, marcar conexión como perdida
- Iniciar reconexión automática

## 8. Seguridad del Protocolo

### 8.1 TLS
- Todas las conexiones WebSocket usan `wss://` (TLS)
- Para red local, se usa certificado autofirmado generado por el relay server
- La app hace certificate pinning del certificado del relay

### 8.2 Autenticación
- Token generado por el relay server al primer setup
- Mostrado como QR code o texto para copiar
- Almacenado en iOS Keychain
- Opción de regenerar token desde el servidor

### 8.3 Validación
- Todos los mensajes JSON se validan con schema antes de procesar
- Tamaño máximo de mensaje: 1MB
- Rate limiting: máximo 10 comandos por minuto
