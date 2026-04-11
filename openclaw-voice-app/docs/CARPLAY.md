# Integración Apple CarPlay

## 1. Visión General

OpenClaw Voice en CarPlay permite interactuar con OpenClaw mientras conduces, usando exclusivamente voz. La interfaz de CarPlay es intencionadamente minimalista para no distraer al conductor.

## 2. Tipo de App CarPlay

Se usará la categoría **Communication** (messaging/VoIP), que permite:
- Templates de voz
- Interfaz de lista simple
- Notificaciones
- Audio en background

### 2.1 Entitlement Necesario

```
com.apple.developer.carplay-communication
```

> **Importante**: Este entitlement requiere solicitud a Apple a través del portal de desarrollador. Se debe justificar el caso de uso.

## 3. Arquitectura CarPlay

```
┌────────────────────────────────────────────┐
│              CarPlay Display                │
│                                            │
│  ┌──────────────────────────────────────┐  │
│  │         CPVoiceControlTemplate        │  │
│  │                                      │  │
│  │  ┌────────────────────────────────┐  │  │
│  │  │      "Habla con OpenClaw"      │  │  │
│  │  │                                │  │  │
│  │  │    ╭──────────────────────╮    │  │  │
│  │  │    │    🎤 Escuchando...  │    │  │  │
│  │  │    ╰──────────────────────╯    │  │  │
│  │  │                                │  │  │
│  │  │  "Buscando oportunidades..."   │  │  │
│  │  └────────────────────────────────┘  │  │
│  └──────────────────────────────────────┘  │
│                                            │
│  ┌────────┐ ┌────────┐ ┌────────────────┐ │
│  │  Voz   │ │Historial│ │  Configuración │ │
│  └────────┘ └────────┘ └────────────────┘ │
└────────────────────────────────────────────┘
```

## 4. Implementación

### 4.1 Scene Configuration (Info.plist)

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <true/>
    <key>UISceneConfigurations</key>
    <dict>
        <!-- Escena principal iPhone -->
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>Default Configuration</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
            </dict>
        </array>
        <!-- Escena CarPlay -->
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>CarPlay Configuration</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

### 4.2 CarPlaySceneDelegate

```swift
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    var interfaceController: CPInterfaceController?
    private var templateManager: CarPlayTemplateManager?
    
    // MARK: - Scene Lifecycle
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        self.templateManager = CarPlayTemplateManager(
            interfaceController: interfaceController
        )
        
        // Configurar template raíz
        templateManager?.setupRootTemplate()
        
        // Notificar al AppState
        NotificationCenter.default.post(name: .carPlayDidConnect, object: nil)
    }
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.templateManager = nil
        
        NotificationCenter.default.post(name: .carPlayDidDisconnect, object: nil)
    }
}

extension Notification.Name {
    static let carPlayDidConnect = Notification.Name("carPlayDidConnect")
    static let carPlayDidDisconnect = Notification.Name("carPlayDidDisconnect")
}
```

### 4.3 CarPlayTemplateManager

```swift
import CarPlay

final class CarPlayTemplateManager {
    
    private let interfaceController: CPInterfaceController
    private var voiceController: CarPlayVoiceController?
    
    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }
    
    // MARK: - Setup Root Template
    
    func setupRootTemplate() {
        let tabBar = CPTabBarTemplate(templates: [
            createVoiceTab(),
            createHistoryTab(),
            createStatusTab()
        ])
        
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }
    
    // MARK: - Voice Tab (Principal)
    
    private func createVoiceTab() -> CPTemplate {
        // Usar CPVoiceControlTemplate para la interfaz de voz
        let voiceTemplate = CPVoiceControlTemplate(voiceControlStates: [
            createIdleState(),
            createListeningState(),
            createProcessingState(),
            createSpeakingState()
        ])
        
        voiceTemplate.tabTitle = "OpenClaw"
        voiceTemplate.tabImage = UIImage(systemName: "mic.circle.fill")
        
        return voiceTemplate
    }
    
    private func createIdleState() -> CPVoiceControlState {
        CPVoiceControlState(
            identifier: "idle",
            titleVariants: ["Toca para hablar con OpenClaw"],
            image: UIImage(systemName: "mic.circle"),
            repeats: false
        )
    }
    
    private func createListeningState() -> CPVoiceControlState {
        CPVoiceControlState(
            identifier: "listening",
            titleVariants: ["Escuchando..."],
            image: UIImage(systemName: "waveform"),
            repeats: true
        )
    }
    
    private func createProcessingState() -> CPVoiceControlState {
        CPVoiceControlState(
            identifier: "processing",
            titleVariants: ["Procesando..."],
            image: UIImage(systemName: "brain"),
            repeats: true
        )
    }
    
    private func createSpeakingState() -> CPVoiceControlState {
        CPVoiceControlState(
            identifier: "speaking",
            titleVariants: ["OpenClaw responde..."],
            image: UIImage(systemName: "speaker.wave.3"),
            repeats: true
        )
    }
    
    // MARK: - History Tab
    
    private func createHistoryTab() -> CPTemplate {
        let section = CPListSection(items: [])
        let listTemplate = CPListTemplate(
            title: "Historial",
            sections: [section]
        )
        listTemplate.tabTitle = "Historial"
        listTemplate.tabImage = UIImage(systemName: "clock")
        return listTemplate
    }
    
    // MARK: - Status Tab
    
    private func createStatusTab() -> CPTemplate {
        let connectionItem = CPListItem(
            text: "Conexión",
            detailText: "Conectado a MacBook Pro"
        )
        connectionItem.setImage(UIImage(systemName: "wifi"))
        
        let section = CPListSection(items: [connectionItem])
        let listTemplate = CPListTemplate(
            title: "Estado",
            sections: [section]
        )
        listTemplate.tabTitle = "Estado"
        listTemplate.tabImage = UIImage(systemName: "gear")
        return listTemplate
    }
}
```

### 4.4 CarPlayVoiceController

```swift
import CarPlay
import AVFoundation

final class CarPlayVoiceController {
    
    private let speechRecognizer: SpeechRecognizer
    private let elevenLabs: ElevenLabsService
    private let webSocket: WebSocketManager
    private let audioPlayer: StreamingAudioPlayer
    
    weak var templateManager: CarPlayTemplateManager?
    
    enum VoiceState {
        case idle
        case listening
        case processing
        case speaking
    }
    
    var state: VoiceState = .idle {
        didSet {
            updateCarPlayState()
        }
    }
    
    // MARK: - Voice Flow
    
    func startVoiceInteraction() async throws {
        state = .listening
        
        // 1. Escuchar
        try speechRecognizer.startListening()
        
        // Esperar transcripción final
        let userText = await waitForFinalTranscription()
        
        state = .processing
        
        // 2. Enviar a OpenClaw
        try await webSocket.send(.command(text: userText))
        
        // 3. Recibir respuesta
        state = .speaking
        let responseText = await webSocket.receiveFullResponse()
        
        // 4. Reproducir con ElevenLabs
        let audioStream = elevenLabs.streamSpeech(text: responseText)
        try await audioPlayer.playStream(audioStream)
        
        state = .idle
    }
    
    private func updateCarPlayState() {
        // Actualizar el template de voz según el estado
        switch state {
        case .idle:
            templateManager?.activateState("idle")
        case .listening:
            templateManager?.activateState("listening")
        case .processing:
            templateManager?.activateState("processing")
        case .speaking:
            templateManager?.activateState("speaking")
        }
    }
}
```

## 5. Consideraciones de Seguridad Vial

### 5.1 Reglas de Apple para CarPlay
- **Texto mínimo**: máximo 2 líneas de texto en pantalla
- **Sin interacción manual compleja**: solo toques simples
- **Audio como canal principal**: toda la información importante por voz
- **No mostrar contenido que distraiga**: sin animaciones llamativas

### 5.2 Nuestra implementación respeta
- Solo se muestra estado actual ("Escuchando...", "Procesando...")
- Respuestas completas siempre por audio
- Un solo botón para iniciar interacción
- Historial accesible solo con coche parado (detección opcional)

## 6. Testing CarPlay

### 6.1 Simulador CarPlay
```bash
# En Xcode: Window → Devices and Simulators → CarPlay
# O usar el simulador de CarPlay integrado en el Simulator de iOS
```

### 6.2 Configuración en Xcode
```
Target → Signing & Capabilities → + Capability → CarPlay
Seleccionar: Communication
```

### 6.3 Checklist de Testing
- [ ] App aparece en la pantalla de CarPlay
- [ ] Botón de voz funciona
- [ ] Reconocimiento de voz funciona con audio del coche
- [ ] Respuesta de ElevenLabs se reproduce por altavoces del coche
- [ ] App maneja desconexión de CarPlay sin crash
- [ ] Audio se pausa si entra llamada telefónica
- [ ] App funciona simultáneamente en iPhone y CarPlay

## 7. Proceso de Solicitud del Entitlement

1. Ir a https://developer.apple.com/contact/carplay/
2. Seleccionar categoría "Communication"
3. Describir la app: "Voice-based AI assistant client that connects to a personal AI system"
4. Esperar aprobación (puede tardar 2-4 semanas)
5. Una vez aprobado, se genera el entitlement en el portal
6. Descargar y añadir el provisioning profile actualizado

> **Mientras se espera el entitlement**: se puede desarrollar y probar con el simulador de CarPlay de Xcode sin necesidad del entitlement real.
