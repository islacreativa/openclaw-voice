# App iOS Nativa — Especificación Técnica

## 1. Información del Proyecto Xcode

```
Nombre: OpenClawVoice
Bundle ID: com.dckstudios.openclaw-voice
Deployment Target: iOS 17.0
Swift Version: 5.9+
Frameworks: SwiftUI, Speech, AVFoundation, CarPlay, Network
```

## 2. Estructura del Proyecto

```
OpenClawVoice/
├── OpenClawVoiceApp.swift              ← Entry point
├── Info.plist                          ← Permisos y configuración
├── Entitlements/
│   └── OpenClawVoice.entitlements      ← CarPlay entitlement
│
├── Core/
│   ├── AppState.swift                  ← Estado global (@Observable)
│   ├── AppConfig.swift                 ← Configuración (URLs, keys)
│   └── Constants.swift                 ← Constantes de la app
│
├── Models/
│   ├── Message.swift                   ← Modelo de mensaje chat
│   ├── ServerMessage.swift             ← Mensajes WebSocket (Codable)
│   ├── ConnectionStatus.swift          ← Estados de conexión
│   └── VoiceSettings.swift             ← Config de voz ElevenLabs
│
├── Services/
│   ├── WebSocket/
│   │   ├── WebSocketManager.swift      ← Gestión de conexión WS
│   │   ├── WebSocketMessage.swift      ← Tipos de mensaje
│   │   └── ReconnectionHandler.swift   ← Reconexión automática
│   │
│   ├── Voice/
│   │   ├── SpeechRecognizer.swift      ← Apple Speech Framework STT
│   │   ├── ElevenLabsService.swift     ← TTS con ElevenLabs API
│   │   ├── AudioSessionManager.swift   ← Gestión AVAudioSession
│   │   └── VoiceActivityDetector.swift ← Detección de voz (VAD)
│   │
│   ├── Network/
│   │   ├── ConnectionMonitor.swift     ← NWPathMonitor
│   │   └── ServerDiscovery.swift       ← Bonjour/mDNS discovery
│   │
│   ├── Config/
│   │   ├── RemoteConfigService.swift   ← Comunicación de config con relay
│   │   └── SystemMonitorService.swift  ← Monitor del sistema Mac
│   │
│   └── Security/
│       ├── KeychainManager.swift       ← Almacenamiento seguro
│       └── TokenManager.swift          ← Gestión de auth tokens
│
├── ViewModels/
│   ├── ChatViewModel.swift             ← Lógica de la vista de chat
│   ├── SettingsViewModel.swift         ← Lógica de ajustes
│   ├── ConnectionViewModel.swift       ← Lógica de conexión
│   ├── ConfigViewModel.swift           ← Lógica de config remota OpenClaw
│   ├── MCPViewModel.swift              ← Lógica de gestión de MCPs
│   └── LogViewModel.swift              ← Lógica del visor de logs
│
├── Views/
│   ├── Main/
│   │   ├── ContentView.swift           ← Vista principal con tabs
│   │   ├── ChatView.swift              ← Vista de conversación
│   │   └── VoiceButton.swift           ← Botón de grabación
│   │
│   ├── Connection/
│   │   ├── ConnectionSetupView.swift   ← Configuración inicial
│   │   ├── QRScannerView.swift         ← Escaneo QR para vincular
│   │   └── ConnectionStatusView.swift  ← Estado de conexión
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift          ← Pantalla de ajustes
│   │   ├── VoiceSettingsView.swift     ← Selección de voz ElevenLabs
│   │   ├── ServerSettingsView.swift    ← Config del servidor
│   │   ├── OpenClawConfigView.swift    ← Config remota de OpenClaw
│   │   ├── MCPManagementView.swift     ← Gestión de MCPs
│   │   ├── MCPDetailView.swift         ← Detalle de un MCP
│   │   ├── LogViewerView.swift         ← Visor de logs en tiempo real
│   │   ├── SystemStatusView.swift      ← Estado del sistema Mac
│   │   └── RelayConfigView.swift       ← Config del relay server
│   │
│   └── Components/
│       ├── MessageBubble.swift         ← Burbuja de chat
│       ├── WaveformView.swift          ← Visualización de audio
│       ├── PulsingMicButton.swift      ← Botón mic animado
│       └── StatusIndicator.swift       ← Indicador de estado
│
├── CarPlay/
│   ├── CarPlaySceneDelegate.swift      ← Delegate de CarPlay
│   ├── CarPlayTemplateManager.swift    ← Gestión de templates
│   └── CarPlayVoiceController.swift    ← Control de voz en CarPlay
│
└── Resources/
    ├── Assets.xcassets                 ← Iconos y colores
    └── Localizable.strings             ← Strings localizadas (es/en)
```

## 3. Componentes Principales

### 3.1 AppState — Estado Global

```swift
@Observable
final class AppState {
    // Conexión
    var connectionStatus: ConnectionStatus = .disconnected
    var serverURL: String = ""
    var authToken: String = ""
    
    // Chat
    var messages: [Message] = []
    var isProcessing: Bool = false
    
    // Voz
    var isListening: Bool = false
    var isSpeaking: Bool = false
    var currentTranscription: String = ""
    var selectedVoice: ElevenLabsVoice = .default
    
    // CarPlay
    var isCarPlayConnected: Bool = false
}
```

### 3.2 WebSocketManager

```swift
final class WebSocketManager: ObservableObject {
    private var webSocket: URLSessionWebSocketTask?
    private let reconnectionHandler = ReconnectionHandler()
    
    // Funciones principales
    func connect(to url: URL, token: String) async throws
    func disconnect()
    func send(_ message: ClientMessage) async throws
    func receiveMessages() -> AsyncStream<ServerMessage>
    
    // Heartbeat
    private func startHeartbeat()
    private func handlePong()
    
    // Reconexión
    private func handleDisconnection()
}
```

### 3.3 SpeechRecognizer

```swift
final class SpeechRecognizer: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var transcription: String = ""
    @Published var isListening: Bool = false
    @Published var isFinal: Bool = false
    
    func startListening() async throws
    func stopListening()
    
    // Configuración para modo continuo vs push-to-talk
    var mode: ListeningMode = .pushToTalk
    
    enum ListeningMode {
        case pushToTalk    // Mantener pulsado para hablar
        case continuous    // Escucha continua con VAD
        case wakeWord      // Activación por palabra clave
    }
}
```

### 3.4 ElevenLabsService

```swift
final class ElevenLabsService {
    private let apiKey: String
    private let baseURL = "https://api.elevenlabs.io/v1"
    
    // TTS Streaming
    func synthesize(text: String, voice: ElevenLabsVoice) -> AsyncStream<Data>
    func synthesizeStreaming(textStream: AsyncStream<String>, voice: ElevenLabsVoice) -> AsyncStream<Data>
    
    // Gestión de voces
    func listVoices() async throws -> [ElevenLabsVoice]
    func previewVoice(_ voice: ElevenLabsVoice) async throws -> Data
    
    // Configuración
    struct VoiceSettings: Codable {
        var stability: Double = 0.5
        var similarityBoost: Double = 0.75
        var style: Double = 0.0
        var useSpeakerBoost: Bool = true
    }
}
```

### 3.5 AudioSessionManager

```swift
final class AudioSessionManager {
    private let session = AVAudioSession.sharedInstance()
    
    // Configurar para grabación + reproducción
    func configureForVoiceChat() throws
    
    // Configurar para solo reproducción (mientras OpenClaw responde)
    func configureForPlayback() throws
    
    // CarPlay: configurar para ruta de audio del coche
    func configureForCarPlay() throws
    
    // Manejar interrupciones (llamada telefónica, Siri, etc.)
    func handleInterruption(_ notification: Notification)
    
    // Manejar cambio de ruta (auriculares, CarPlay, altavoz)
    func handleRouteChange(_ notification: Notification)
}
```

## 4. Permisos Necesarios (Info.plist)

```xml
<!-- Micrófono -->
<key>NSMicrophoneUsageDescription</key>
<string>OpenClaw Voice necesita acceso al micrófono para reconocimiento de voz</string>

<!-- Reconocimiento de voz -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>OpenClaw Voice utiliza reconocimiento de voz para enviar comandos</string>

<!-- Cámara (para QR) -->
<key>NSCameraUsageDescription</key>
<string>OpenClaw Voice usa la cámara para escanear el código QR de conexión</string>

<!-- Red local -->
<key>NSLocalNetworkUsageDescription</key>
<string>OpenClaw Voice se conecta a tu Mac en la red local</string>

<!-- Bonjour -->
<key>NSBonjourServices</key>
<array>
    <string>_openclaw._tcp</string>
</array>

<!-- Background modes -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>

<!-- CarPlay -->
<key>com.apple.developer.carplay-messaging</key>
<true/>
```

## 5. Flujos de UI

### 5.1 Primera Ejecución
```
Splash → Permisos (mic + speech) → Configuración servidor (QR o manual) → Chat principal
```

### 5.2 Uso Normal (iPhone)
```
App abre → Conexión automática → Vista de Chat → 
  Pulsar botón mic → Hablar → Soltar → 
  Ver transcripción → Ver respuesta → Escuchar voz
```

### 5.3 Modo CarPlay
```
CarPlay conecta → Template de voz → 
  Pulsar botón en pantalla coche → Hablar → 
  Respuesta por altavoces del coche → 
  Texto mínimo en pantalla (seguridad)
```

## 6. Gestión de Estado

Se usa el patrón `@Observable` de iOS 17 con inyección de dependencias:

```swift
@main
struct OpenClawVoiceApp: App {
    @State private var appState = AppState()
    @State private var webSocketManager = WebSocketManager()
    @State private var speechRecognizer = SpeechRecognizer()
    @State private var elevenLabs = ElevenLabsService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(webSocketManager)
                .environment(speechRecognizer)
                .environment(elevenLabs)
        }
    }
}
```

## 7. Dependencias Externas

| Paquete | Uso | SPM URL |
|---------|-----|---------|
| **Starscream** (opcional) | WebSocket avanzado | `https://github.com/nicklockwood/Starscream` |
| **KeychainAccess** | Keychain simplificado | `https://github.com/kishikawakatsumi/KeychainAccess` |
| **CodeScanner** | Escaneo QR | `https://github.com/twostraws/CodeScanner` |

> **Nota**: Se prefiere usar URLSessionWebSocketTask nativo cuando sea posible para minimizar dependencias.

## 8. Testing

```
Tests/
├── Unit/
│   ├── WebSocketManagerTests.swift
│   ├── SpeechRecognizerTests.swift
│   ├── ElevenLabsServiceTests.swift
│   └── MessageParsingTests.swift
├── Integration/
│   ├── ConnectionFlowTests.swift
│   └── VoicePipelineTests.swift
└── UI/
    ├── ChatViewTests.swift
    └── SettingsViewTests.swift
```
