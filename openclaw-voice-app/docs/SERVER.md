# Servidor Relay — Especificación Técnica

## 1. Visión General

El Relay Server es un proceso que corre en el Mac (portátil) y actúa como puente entre la app iOS y OpenClaw. Se encarga de:

- Aceptar conexiones WebSocket desde la app iOS
- Autenticar al cliente
- Gestionar el proceso de OpenClaw (spawn, stdin/stdout, lifecycle)
- Parsear la salida de OpenClaw y enviarla en streaming al cliente
- Mantener el estado de sesión

## 2. Stack Tecnológico

### Opción A: Node.js (Recomendada)
```
Node.js 20+
├── ws                    ← WebSocket server
├── child_process         ← Spawn OpenClaw process
├── readline              ← Parsear stdout línea a línea
├── jsonwebtoken          ← Verificar tokens JWT
├── uuid                  ← Generar IDs
├── qrcode-terminal       ← Mostrar QR en terminal
└── selfsigned             ← Generar certificado TLS
```

### Opción B: Python (Alternativa)
```
Python 3.11+
├── websockets            ← WebSocket server
├── asyncio               ← Event loop
├── subprocess/asyncio    ← Spawn OpenClaw process
├── pyjwt                 ← Verificar tokens JWT
├── qrcode                ← Generar QR code
└── ssl                   ← TLS
```

> Se recomienda **Node.js** por mejor soporte de streaming y WebSockets.

## 3. Estructura del Proyecto

```
openclaw-relay-server/
├── package.json
├── src/
│   ├── index.js                    ← Entry point
│   ├── config.js                   ← Configuración
│   ├── server/
│   │   ├── websocket-server.js     ← Servidor WebSocket
│   │   ├── auth.js                 ← Autenticación
│   │   └── message-handler.js      ← Router de mensajes
│   ├── openclaw/
│   │   ├── bridge.js               ← Gestión del proceso OpenClaw
│   │   ├── output-parser.js        ← Parsear stdout
│   │   └── process-manager.js      ← Lifecycle del proceso
│   ├── session/
│   │   ├── session-manager.js      ← Estado de sesión
│   │   └── history.js              ← Historial de conversación
│   └── utils/
│       ├── logger.js               ← Logging
│       ├── tls.js                   ← Certificados TLS
│       └── qr-setup.js             ← Setup con QR code
├── certs/                           ← Certificados autofirmados (generados)
└── README.md
```

## 4. Implementación Principal

### 4.1 Entry Point (index.js)

```javascript
import { WebSocketServer } from './server/websocket-server.js';
import { OpenClawBridge } from './openclaw/bridge.js';
import { SessionManager } from './session/session-manager.js';
import { Config } from './config.js';
import { generateCerts } from './utils/tls.js';
import { showSetupQR } from './utils/qr-setup.js';

async function main() {
    const config = new Config();
    
    // Generar certificados TLS si no existen
    await generateCerts(config.certsPath);
    
    // Iniciar el bridge con OpenClaw
    const openclawBridge = new OpenClawBridge(config);
    await openclawBridge.start();
    
    // Iniciar sesión manager
    const sessionManager = new SessionManager();
    
    // Iniciar servidor WebSocket
    const server = new WebSocketServer({
        port: config.port,
        certsPath: config.certsPath,
        openclawBridge,
        sessionManager,
        authToken: config.authToken
    });
    
    await server.start();
    
    // Mostrar QR para conexión
    showSetupQR(config);
    
    console.log(`🦞 OpenClaw Relay Server running on wss://0.0.0.0:${config.port}`);
    console.log(`📱 Escanea el QR code con la app para conectar`);
}

main().catch(console.error);
```

### 4.2 OpenClaw Bridge

```javascript
import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import readline from 'readline';

export class OpenClawBridge extends EventEmitter {
    constructor(config) {
        super();
        this.config = config;
        this.process = null;
        this.isReady = false;
        this.isProcessing = false;
    }
    
    async start() {
        // Spawn OpenClaw como proceso hijo
        this.process = spawn(this.config.openclawCommand, this.config.openclawArgs, {
            cwd: this.config.openclawWorkdir,
            env: { ...process.env, ...this.config.openclawEnv },
            stdio: ['pipe', 'pipe', 'pipe']
        });
        
        // Parsear stdout línea a línea
        const rl = readline.createInterface({
            input: this.process.stdout,
            crlfDelay: Infinity
        });
        
        rl.on('line', (line) => {
            this.handleOutputLine(line);
        });
        
        // Manejar stderr
        this.process.stderr.on('data', (data) => {
            this.emit('error', data.toString());
        });
        
        // Manejar cierre del proceso
        this.process.on('close', (code) => {
            this.isReady = false;
            this.emit('closed', code);
            // Auto-restart si se cerró inesperadamente
            if (code !== 0) {
                setTimeout(() => this.start(), 2000);
            }
        });
        
        this.isReady = true;
        this.emit('ready');
    }
    
    async sendCommand(text, commandId) {
        if (!this.isReady || this.isProcessing) {
            throw new Error('OpenClaw not ready');
        }
        
        this.isProcessing = true;
        this.currentCommandId = commandId;
        
        // Enviar comando por stdin
        this.process.stdin.write(text + '\n');
        
        this.emit('response_start', { commandId });
    }
    
    handleOutputLine(line) {
        // Detectar si es parte de la respuesta
        const trimmed = line.trim();
        
        if (!trimmed) return;
        
        // Emitir chunk de respuesta
        this.emit('response_chunk', {
            commandId: this.currentCommandId,
            text: trimmed
        });
        
        // Detectar fin de respuesta
        // Esto depende de cómo OpenClaw señaliza fin de respuesta
        // Posibles marcadores: prompt vacío, marcador especial, timeout
        if (this.isEndOfResponse(trimmed)) {
            this.isProcessing = false;
            this.emit('response_end', {
                commandId: this.currentCommandId
            });
        }
    }
    
    isEndOfResponse(line) {
        // Implementar detección de fin de respuesta
        // Puede ser un marcador especial o detección de prompt
        // TODO: Adaptar según el formato de output de OpenClaw
        return false;
    }
    
    async cancel() {
        // Enviar señal de cancelación a OpenClaw
        // Ctrl+C equivalente
        if (this.process) {
            this.process.kill('SIGINT');
        }
        this.isProcessing = false;
    }
    
    getStatus() {
        return {
            running: this.process !== null && !this.process.killed,
            ready: this.isReady,
            processing: this.isProcessing
        };
    }
    
    async stop() {
        if (this.process) {
            this.process.kill();
            this.process = null;
        }
    }
}
```

### 4.3 WebSocket Message Handler

```javascript
export class MessageHandler {
    constructor(openclawBridge, sessionManager) {
        this.bridge = openclawBridge;
        this.sessions = sessionManager;
    }
    
    async handleMessage(ws, message, session) {
        const msg = JSON.parse(message);
        
        switch (msg.type) {
            case 'command':
                return this.handleCommand(ws, msg, session);
            case 'cancel':
                return this.handleCancel(ws, msg, session);
            case 'ping':
                return this.handlePing(ws);
            default:
                return this.sendError(ws, 'UNKNOWN_TYPE', `Tipo desconocido: ${msg.type}`);
        }
    }
    
    async handleCommand(ws, msg, session) {
        const commandId = msg.id;
        const text = msg.payload.text;
        
        // Guardar en historial
        session.addToHistory('user', text, commandId);
        
        // Listeners para streaming de respuesta
        const onChunk = (data) => {
            if (data.commandId === commandId) {
                ws.send(JSON.stringify({
                    type: 'response_chunk',
                    command_id: commandId,
                    response_id: `resp-${commandId}`,
                    payload: { text: data.text }
                }));
            }
        };
        
        const onEnd = (data) => {
            if (data.commandId === commandId) {
                const fullText = session.getResponseText(commandId);
                ws.send(JSON.stringify({
                    type: 'response_end',
                    command_id: commandId,
                    response_id: `resp-${commandId}`,
                    payload: {
                        full_text: fullText,
                        metadata: { processing_time_ms: Date.now() - startTime }
                    }
                }));
                cleanup();
            }
        };
        
        const cleanup = () => {
            this.bridge.removeListener('response_chunk', onChunk);
            this.bridge.removeListener('response_end', onEnd);
        };
        
        this.bridge.on('response_chunk', onChunk);
        this.bridge.on('response_end', onEnd);
        
        const startTime = Date.now();
        
        // Enviar response_start
        ws.send(JSON.stringify({
            type: 'response_start',
            command_id: commandId,
            response_id: `resp-${commandId}`
        }));
        
        // Enviar comando a OpenClaw
        try {
            await this.bridge.sendCommand(text, commandId);
        } catch (error) {
            cleanup();
            this.sendError(ws, 'OPENCLAW_ERROR', error.message, commandId);
        }
    }
    
    handlePing(ws) {
        ws.send(JSON.stringify({
            type: 'pong',
            timestamp: new Date().toISOString()
        }));
    }
    
    sendError(ws, code, message, commandId = null) {
        ws.send(JSON.stringify({
            type: 'error',
            code,
            message,
            command_id: commandId
        }));
    }
}
```

### 4.4 Config

```javascript
import { randomBytes } from 'crypto';
import { existsSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

export class Config {
    constructor() {
        const configPath = join(process.env.HOME, '.openclaw-relay', 'config.json');
        
        if (existsSync(configPath)) {
            const saved = JSON.parse(readFileSync(configPath, 'utf8'));
            Object.assign(this, saved);
        } else {
            this.port = 8765;
            this.authToken = randomBytes(32).toString('hex');
            this.certsPath = join(process.env.HOME, '.openclaw-relay', 'certs');
            this.openclawCommand = 'openclaw';  // Ajustar según instalación
            this.openclawArgs = [];
            this.openclawWorkdir = process.env.HOME;
            this.openclawEnv = {};
            this.maxReconnectAttempts = 10;
            this.heartbeatInterval = 15000;
            this.commandTimeout = 60000;
            
            // Guardar config
            const dir = join(process.env.HOME, '.openclaw-relay');
            if (!existsSync(dir)) {
                mkdirSync(dir, { recursive: true });
            }
            writeFileSync(configPath, JSON.stringify(this, null, 2));
        }
    }
    
    getConnectionURL() {
        const os = require('os');
        const interfaces = os.networkInterfaces();
        // Buscar IP local
        for (const name of Object.keys(interfaces)) {
            for (const iface of interfaces[name]) {
                if (iface.family === 'IPv4' && !iface.internal) {
                    return `wss://${iface.address}:${this.port}/ws`;
                }
            }
        }
        return `wss://localhost:${this.port}/ws`;
    }
}
```

## 5. Setup y Vinculación

### 5.1 Primera Ejecución del Servidor

```bash
# Instalar
cd openclaw-relay-server
npm install

# Ejecutar
node src/index.js

# Output:
# 🦞 OpenClaw Relay Server running on wss://192.168.1.50:8765
# 📱 Escanea el QR code con la app para conectar
# 
# ┌─────────────────────────────────────────┐
# │  ██████████████  QR CODE  ██████████████ │
# │  ██████████████████████████████████████  │
# │  ...                                     │
# └─────────────────────────────────────────┘
# 
# O introduce manualmente:
# URL: wss://192.168.1.50:8765/ws
# Token: a1b2c3d4e5f6...
```

### 5.2 Contenido del QR Code

```json
{
  "url": "wss://192.168.1.50:8765/ws",
  "token": "a1b2c3d4e5f6...",
  "name": "MacBook Pro de Javier"
}
```

## 6. Acceso Remoto con Tailscale

### 6.1 Configuración

```bash
# Instalar Tailscale en Mac
brew install tailscale

# Iniciar Tailscale
tailscale up

# El relay server automáticamente también escucha en la IP de Tailscale
# Ejemplo: wss://100.64.0.1:8765/ws
```

### 6.2 Auto-detección de IP Tailscale

```javascript
// En config.js, detectar interfaz Tailscale
function getTailscaleIP() {
    const interfaces = os.networkInterfaces();
    for (const [name, addrs] of Object.entries(interfaces)) {
        if (name.startsWith('utun') || name === 'tailscale0') {
            const v4 = addrs.find(a => a.family === 'IPv4');
            if (v4) return v4.address;
        }
    }
    return null;
}
```

## 7. Gestión del Proceso OpenClaw

### 7.1 Detección de fin de respuesta

Este es el punto más crítico y depende de cómo OpenClaw funciona. Estrategias:

#### Estrategia A: Marcador de fin
Si OpenClaw tiene un prompt visible (como `> ` o `openclaw> `), detectar cuando aparece el prompt indica fin de respuesta.

#### Estrategia B: Timeout de silencio
Si no hay output durante 2 segundos después del último chunk, considerar fin de respuesta.

#### Estrategia C: API mode
Si OpenClaw soporta un modo API/JSON donde cada respuesta es un JSON completo, usar ese modo.

#### Estrategia D: Wrapper
Crear un wrapper script que envuelve OpenClaw y añade marcadores:
```bash
#!/bin/bash
# openclaw-wrapper.sh
echo "<<RESPONSE_START>>"
openclaw "$@"
echo "<<RESPONSE_END>>"
```

> **IMPORTANTE**: El desarrollador debe investigar cómo OpenClaw señaliza el fin de una respuesta y adaptar `output-parser.js` en consecuencia.

### 7.2 Restart automático

```javascript
// Si OpenClaw se cae, reiniciar automáticamente
process.on('close', (code) => {
    if (code !== 0) {
        console.log(`OpenClaw crashed (code ${code}), restarting in 2s...`);
        setTimeout(() => bridge.start(), 2000);
    }
});
```

## 8. Logging

```javascript
// Niveles: debug, info, warn, error
const logger = {
    info: (msg) => console.log(`[${new Date().toISOString()}] INFO: ${msg}`),
    error: (msg) => console.error(`[${new Date().toISOString()}] ERROR: ${msg}`),
    debug: (msg) => {
        if (process.env.DEBUG) console.log(`[${new Date().toISOString()}] DEBUG: ${msg}`);
    }
};
```

## 9. Ejecutar como Servicio (launchd)

```xml
<!-- ~/Library/LaunchAgents/com.dckstudios.openclaw-relay.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dckstudios.openclaw-relay</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node</string>
        <string>/path/to/openclaw-relay-server/src/index.js</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/openclaw-relay.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/openclaw-relay-error.log</string>
</dict>
</plist>
```

```bash
# Cargar el servicio
launchctl load ~/Library/LaunchAgents/com.dckstudios.openclaw-relay.plist

# Verificar
launchctl list | grep openclaw
```
