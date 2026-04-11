# Guía de Configuración y Despliegue

## 1. Requisitos Previos

### 1.1 Mac (Portátil — Servidor)
- macOS 13 Ventura o superior
- OpenClaw instalado y funcionando
- Node.js 20+ (`brew install node`)
- Xcode 15+ (para desarrollo iOS)
- Apple Developer Account (para CarPlay entitlement y deploy en dispositivo)

### 1.2 iPhone
- iOS 17.0 o superior
- En la misma red WiFi que el Mac (o Tailscale configurado)

### 1.3 Cuentas y API Keys
- **Apple Developer Program** ($99/año) — necesario para CarPlay y deploy
- **ElevenLabs API Key** — crear cuenta en https://elevenlabs.io
- **Tailscale** (opcional) — para acceso remoto, gratis para uso personal

## 2. Configuración del Servidor Relay

### 2.1 Instalación

```bash
# Clonar o crear el proyecto
mkdir openclaw-relay-server
cd openclaw-relay-server

# Inicializar
npm init -y

# Instalar dependencias
npm install ws uuid jsonwebtoken qrcode-terminal selfsigned

# Crear estructura
mkdir -p src/server src/openclaw src/session src/utils certs
```

### 2.2 Configurar OpenClaw

Antes de iniciar el servidor, verificar que OpenClaw funciona:

```bash
# Verificar que openclaw está instalado
which openclaw
# o
openclaw --version

# Ejecutar una prueba
echo "hola" | openclaw
```

> **Nota**: El comando exacto para invocar OpenClaw puede variar. Ajustar en `config.js` → `openclawCommand` y `openclawArgs`.

### 2.3 Primer inicio

```bash
# Desde el directorio del servidor
node src/index.js

# Se generarán automáticamente:
# - Certificados TLS en ./certs/
# - Config en ~/.openclaw-relay/config.json
# - Token de autenticación
# - QR code en terminal
```

### 2.4 Variables de entorno opcionales

```bash
export OPENCLAW_RELAY_PORT=8765          # Puerto del servidor
export OPENCLAW_COMMAND=openclaw         # Comando para ejecutar OpenClaw
export OPENCLAW_WORKDIR=$HOME            # Directorio de trabajo
export DEBUG=true                        # Habilitar logs de debug
```

## 3. Configuración del Proyecto iOS

### 3.1 Crear proyecto en Xcode

```
1. File → New → Project → iOS → App
2. Product Name: OpenClawVoice
3. Team: Tu Apple Developer Team
4. Organization Identifier: com.dckstudios
5. Interface: SwiftUI
6. Language: Swift
7. Minimum Deployment: iOS 17.0
```

### 3.2 Añadir Capabilities

```
1. Seleccionar target OpenClawVoice
2. Signing & Capabilities → + Capability:
   - Background Modes:
     ✓ Audio, AirPlay, and Picture in Picture
     ✓ Voice over IP
   - CarPlay (Communication) — requiere entitlement aprobado
3. Info.plist → añadir permisos (ver IOS-APP.md sección 4)
```

### 3.3 Añadir dependencias (SPM)

```
1. File → Add Package Dependencies
2. Añadir:
   - https://github.com/kishikawakatsumi/KeychainAccess (para Keychain)
   - https://github.com/twostraws/CodeScanner (para QR)
3. Seleccionar target OpenClawVoice para ambos
```

### 3.4 Configurar ElevenLabs API Key

La API key se introduce en la app al configurar por primera vez:
```
Settings → Voice → ElevenLabs API Key → Pegar key
```
Se almacena de forma segura en iOS Keychain.

## 4. Desarrollo Paso a Paso

### Paso 1: Relay Server básico
```bash
# Objetivo: servidor WS que recibe y envía mensajes
# Test: conectar con websocat o wscat
npm install -g wscat
wscat -c wss://localhost:8765/ws --no-check
```

### Paso 2: Bridge con OpenClaw
```bash
# Objetivo: enviar comando por WS → ejecutar en OpenClaw → devolver resultado
# Test: enviar JSON command y recibir respuesta
```

### Paso 3: App iOS — Conexión
```
# Objetivo: app que conecta al relay server y envía/recibe mensajes
# Test: enviar texto → ver respuesta en pantalla
```

### Paso 4: App iOS — Voz (STT)
```
# Objetivo: grabar voz → convertir a texto → enviar como comando
# Test: hablar al teléfono → ver transcripción → ver respuesta
```

### Paso 5: App iOS — Voz (TTS)
```
# Objetivo: respuesta de OpenClaw → ElevenLabs TTS → reproducir
# Test: hablar → escuchar respuesta por voz
```

### Paso 6: Streaming
```
# Objetivo: respuestas largas llegan en streaming → TTS en streaming
# Test: comando complejo → empezar a escuchar antes de que termine
```

### Paso 7: CarPlay
```
# Objetivo: interfaz CarPlay funcional con voz
# Test: usar simulador de CarPlay en Xcode
```

### Paso 8: Polish
```
# Objetivo: reconexión, manejo de errores, UI pulida
# Test: desconectar WiFi → reconecta automáticamente
```

## 5. Deploy en iPhone

### 5.1 Desarrollo (cable USB)
```
1. Conectar iPhone por USB
2. En Xcode, seleccionar tu iPhone como destino
3. Cmd + R para compilar y ejecutar
4. Confiar en el certificado de desarrollo en:
   iPhone → Settings → General → VPN & Device Management
```

### 5.2 TestFlight (distribución beta)
```
1. Product → Archive en Xcode
2. Distribute App → TestFlight
3. Subir a App Store Connect
4. Invitar testers internos/externos
```

## 6. Resolución de Problemas

### No conecta por WebSocket
```bash
# Verificar que el servidor está corriendo
lsof -i :8765

# Verificar conectividad
ping <ip-del-mac>

# Probar WebSocket
wscat -c wss://<ip-del-mac>:8765/ws --no-check
```

### Speech Recognition no funciona
```
- Verificar permisos en Settings → Privacy → Speech Recognition
- Verificar permisos de micrófono
- Probar con locale "en-US" si "es-ES" no funciona on-device
```

### ElevenLabs no genera audio
```
- Verificar API key válida
- Verificar cuota disponible en elevenlabs.io/dashboard
- Verificar conexión a internet
- Probar con curl:
  curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/pNInz6obpgDQGcFmaJgB" \
    -H "xi-api-key: YOUR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"text":"Hola mundo","model_id":"eleven_multilingual_v2"}' \
    --output test.mp3
```

### CarPlay no aparece
```
- Verificar entitlement de CarPlay está configurado
- Usar simulador: Xcode → Window → Devices → CarPlay
- Verificar que el SceneDelegate de CarPlay está registrado en Info.plist
```

## 7. Estructura Final del Repositorio

```
openclaw-voice/
├── ios/                                ← Proyecto Xcode
│   └── OpenClawVoice/
│       └── (estructura de IOS-APP.md)
├── server/                             ← Relay Server
│   └── openclaw-relay-server/
│       └── (estructura de SERVER.md)
├── docs/                               ← Esta documentación
└── README.md                           ← Instrucciones de alto nivel
```
