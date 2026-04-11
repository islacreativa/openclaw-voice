# Motor de Voz — ElevenLabs + Apple Speech

## 1. Arquitectura de Voz

```
                    ENTRADA DE VOZ (STT)
┌──────────┐    ┌────────────────┐    ┌──────────────┐
│ Micrófono │───►│ Apple Speech   │───►│ Texto final  │
│           │    │ Framework      │    │ (transcripción)│
└──────────┘    │ (on-device)    │    └──────────────┘
                └────────────────┘

                    SALIDA DE VOZ (TTS)
┌──────────────┐    ┌────────────────┐    ┌──────────┐
│ Texto resp.  │───►│ ElevenLabs     │───►│ Altavoz  │
│ (streaming)  │    │ Streaming API  │    │ / CarPlay│
└──────────────┘    └────────────────┘    └──────────┘
```

## 2. Speech-to-Text (STT) — Apple Speech Framework

### 2.1 ¿Por qué Apple Speech y no ElevenLabs STT?

- **Latencia ultra-baja**: procesamiento on-device, sin llamada de red
- **Funciona offline**: útil en túneles o zonas sin cobertura (CarPlay)
- **Gratis**: sin coste por uso, a diferencia de APIs cloud
- **Privacidad**: el audio no sale del dispositivo
- **Integración nativa**: óptima con CarPlay y AVAudioSession

### 2.2 Implementación del SpeechRecognizer

```swift
import Speech
import AVFoundation

@Observable
final class SpeechRecognizer {
    
    // MARK: - Properties
    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var transcription: String = ""
    var isListening: Bool = false
    var isFinal: Bool = false
    var error: SpeechError?
    
    // MARK: - Initialization
    init(locale: Locale = Locale(identifier: "es-ES")) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)!
        // Habilitar reconocimiento on-device cuando sea posible
        if speechRecognizer.supportsOnDeviceRecognition {
            // Se configurará en el request
        }
    }
    
    // MARK: - Authorization
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    // MARK: - Start Listening
    func startListening() throws {
        // Cancelar tarea previa si existe
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configurar sesión de audio
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Crear request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw SpeechError.requestCreationFailed }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        
        // Configurar audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Iniciar reconocimiento
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            
            if let result {
                self.transcription = result.bestTranscription.formattedString
                self.isFinal = result.isFinal
            }
            
            if error != nil || result?.isFinal == true {
                self.stopListening()
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }
    
    // MARK: - Stop Listening
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
    
    // MARK: - Errors
    enum SpeechError: Error {
        case notAuthorized
        case notAvailable
        case requestCreationFailed
    }
}
```

### 2.3 Modos de Escucha

#### Push-to-Talk (Modo Principal)
```
Usuario mantiene pulsado botón → Escucha → Suelta → Envía transcripción final
```
- Más fiable, sin falsos positivos
- Ideal para CarPlay (botón en volante o pantalla)

#### Continuo con VAD
```
App escucha siempre → Detecta inicio de habla → Graba → Detecta silencio → Envía
```
- Necesita Voice Activity Detection (VAD)
- Mayor consumo de batería
- Útil en modo manos libres total

#### Wake Word (Futuro)
```
App espera palabra clave ("Hey Claw") → Activa escucha → Procesa → Vuelve a esperar
```
- Requiere modelo on-device de detección de keyword
- Podría usar Apple's Vocal Shortcuts (iOS 18+)

## 3. Text-to-Speech (TTS) — ElevenLabs

### 3.1 API Endpoints

```
Base URL: https://api.elevenlabs.io/v1

POST /text-to-speech/{voice_id}                    ← TTS estándar
POST /text-to-speech/{voice_id}/stream             ← TTS streaming (usar este)
GET  /voices                                        ← Listar voces disponibles
GET  /voices/{voice_id}                             ← Detalles de una voz
```

### 3.2 Implementación del ElevenLabsService

```swift
import Foundation
import AVFoundation

final class ElevenLabsService {
    
    private let apiKey: String
    private let baseURL = "https://api.elevenlabs.io/v1"
    private var audioPlayer: AVAudioPlayer?
    private var audioQueue: [Data] = []
    
    struct VoiceConfig {
        var voiceId: String = "pNInz6obpgDQGcFmaJgB"  // Voz por defecto (Adam)
        var modelId: String = "eleven_multilingual_v2"   // Modelo multilingüe
        var stability: Double = 0.5
        var similarityBoost: Double = 0.75
        var style: Double = 0.0
        var useSpeakerBoost: Bool = true
        var outputFormat: String = "mp3_44100_128"       // Alta calidad
    }
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Streaming TTS (Método principal)
    func streamSpeech(text: String, config: VoiceConfig = VoiceConfig()) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let url = URL(string: "\(baseURL)/text-to-speech/\(config.voiceId)/stream")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
                
                let body: [String: Any] = [
                    "text": text,
                    "model_id": config.modelId,
                    "voice_settings": [
                        "stability": config.stability,
                        "similarity_boost": config.similarityBoost,
                        "style": config.style,
                        "use_speaker_boost": config.useSpeakerBoost
                    ],
                    "output_format": config.outputFormat
                ]
                
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continuation.finish(throwing: ElevenLabsError.apiError)
                    return
                }
                
                var buffer = Data()
                for try await byte in bytes {
                    buffer.append(byte)
                    
                    // Enviar chunks de audio cada 4KB para reproducción continua
                    if buffer.count >= 4096 {
                        continuation.yield(buffer)
                        buffer = Data()
                    }
                }
                
                // Enviar buffer restante
                if !buffer.isEmpty {
                    continuation.yield(buffer)
                }
                
                continuation.finish()
            }
        }
    }
    
    // MARK: - Streaming desde stream de texto (para respuestas de OpenClaw en streaming)
    func streamSpeechFromTextStream(
        textStream: AsyncStream<String>,
        config: VoiceConfig = VoiceConfig()
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Usar WebSocket streaming de ElevenLabs para input-streaming
                let wsURL = URL(string: "wss://api.elevenlabs.io/v1/text-to-speech/\(config.voiceId)/stream-input?model_id=\(config.modelId)")!
                
                let session = URLSession(configuration: .default)
                let wsTask = session.webSocketTask(with: wsURL)
                wsTask.resume()
                
                // Enviar configuración inicial (BOS - Beginning of Stream)
                let bosMessage: [String: Any] = [
                    "text": " ",
                    "voice_settings": [
                        "stability": config.stability,
                        "similarity_boost": config.similarityBoost
                    ],
                    "xi_api_key": apiKey,
                    "generation_config": ["chunk_length_schedule": [120, 160, 250, 290]]
                ]
                
                let bosData = try JSONSerialization.data(withJSONObject: bosMessage)
                try await wsTask.send(.string(String(data: bosData, encoding: .utf8)!))
                
                // Task para recibir audio chunks
                let receiveTask = Task {
                    while !Task.isCancelled {
                        let message = try await wsTask.receive()
                        if case .string(let text) = message,
                           let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let audioBase64 = json["audio"] as? String,
                           let audioData = Data(base64Encoded: audioBase64) {
                            continuation.yield(audioData)
                        }
                    }
                }
                
                // Enviar chunks de texto conforme llegan
                for await textChunk in textStream {
                    let chunkMessage = ["text": textChunk]
                    let chunkData = try JSONSerialization.data(withJSONObject: chunkMessage)
                    try await wsTask.send(.string(String(data: chunkData, encoding: .utf8)!))
                }
                
                // EOS - End of Stream
                let eosMessage = ["text": ""]
                let eosData = try JSONSerialization.data(withJSONObject: eosMessage)
                try await wsTask.send(.string(String(data: eosData, encoding: .utf8)!))
                
                // Esperar a que termine de recibir
                try await Task.sleep(for: .seconds(2))
                receiveTask.cancel()
                wsTask.cancel()
                continuation.finish()
            }
        }
    }
    
    // MARK: - Listar voces
    func listVoices() async throws -> [Voice] {
        var request = URLRequest(url: URL(string: "\(baseURL)/voices")!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return response.voices
    }
    
    // MARK: - Models
    struct Voice: Codable, Identifiable {
        let voiceId: String
        let name: String
        let category: String?
        let labels: [String: String]?
        
        var id: String { voiceId }
        
        enum CodingKeys: String, CodingKey {
            case voiceId = "voice_id"
            case name, category, labels
        }
    }
    
    struct VoicesResponse: Codable {
        let voices: [Voice]
    }
    
    enum ElevenLabsError: Error {
        case apiError
        case invalidResponse
        case quotaExceeded
    }
}
```

### 3.3 Reproductor de Audio Streaming

```swift
import AVFoundation

final class StreamingAudioPlayer: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    @Published var isPlaying: Bool = false
    
    init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }
    
    func playStream(_ audioStream: AsyncThrowingStream<Data, Error>) async throws {
        try audioEngine.start()
        playerNode.play()
        isPlaying = true
        
        for try await chunk in audioStream {
            // Convertir MP3 data a PCM buffer y programar reproducción
            if let buffer = convertToPCMBuffer(data: chunk) {
                playerNode.scheduleBuffer(buffer)
            }
        }
        
        isPlaying = false
    }
    
    func stop() {
        playerNode.stop()
        audioEngine.stop()
        isPlaying = false
    }
    
    private func convertToPCMBuffer(data: Data) -> AVAudioPCMBuffer? {
        // Implementar conversión MP3 → PCM buffer
        // Usar AVAudioConverter o vDSP
        return nil // Placeholder - implementar
    }
}
```

## 4. Pipeline de Voz Completo

```swift
final class VoicePipeline {
    let speechRecognizer: SpeechRecognizer
    let elevenLabs: ElevenLabsService
    let audioPlayer: StreamingAudioPlayer
    let webSocket: WebSocketManager
    
    // Flujo completo: Escuchar → Enviar → Recibir → Hablar
    func processVoiceCommand() async throws {
        // 1. Escuchar al usuario
        try speechRecognizer.startListening()
        
        // 2. Esperar a que termine de hablar (isFinal)
        let userText = await waitForFinalTranscription()
        
        // 3. Enviar a OpenClaw via WebSocket
        try await webSocket.send(.command(text: userText))
        
        // 4. Recibir respuesta (streaming)
        let responseStream = webSocket.receiveResponseStream()
        
        // 5. Convertir texto a voz en streaming
        let audioStream = elevenLabs.streamSpeechFromTextStream(
            textStream: responseStream,
            config: .init()
        )
        
        // 6. Reproducir audio
        try await audioPlayer.playStream(audioStream)
    }
}
```

## 5. Configuración de ElevenLabs Recomendada

### 5.1 Para uso conversacional (baja latencia)
```json
{
    "model_id": "eleven_turbo_v2_5",
    "voice_settings": {
        "stability": 0.5,
        "similarity_boost": 0.75,
        "style": 0.0,
        "use_speaker_boost": false
    },
    "output_format": "mp3_22050_32"
}
```

### 5.2 Para respuestas largas (mejor calidad)
```json
{
    "model_id": "eleven_multilingual_v2",
    "voice_settings": {
        "stability": 0.6,
        "similarity_boost": 0.80,
        "style": 0.15,
        "use_speaker_boost": true
    },
    "output_format": "mp3_44100_128"
}
```

### 5.3 Voces recomendadas para español
- **Adam** (pNInz6obpgDQGcFmaJgB): Voz masculina neutra, buena para asistente
- **Antoni** (ErXwobaYiN019PkySvjV): Voz masculina más cálida
- **Rachel** (21m00Tcm4TlvDq8ikWAM): Voz femenina clara
- **Clyde** (2EiwWnXFnvU5JabPnv8n): Voz masculina profunda

> Se recomienda clonar la voz propia o crear una voz personalizada en ElevenLabs para una experiencia más personal.

## 6. Gestión de Audio Session

### 6.1 Prioridades de audio
```
1. Llamada telefónica (interrumpe todo)
2. Siri / Dictado del sistema
3. OpenClaw Voice (nuestra app)
4. Música / Podcasts (se duckan cuando hablamos)
```

### 6.2 CarPlay Audio
```swift
// Configurar para CarPlay
try AVAudioSession.sharedInstance().setCategory(
    .playAndRecord,
    mode: .voiceChat,
    options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
)
```

## 7. Costes Estimados de ElevenLabs

| Plan | Caracteres/mes | Coste | Uso estimado |
|------|---------------|-------|-------------|
| Free | 10,000 | $0 | ~5 min TTS |
| Starter | 30,000 | $5/mes | ~15 min TTS |
| Creator | 100,000 | $22/mes | ~50 min TTS |
| Pro | 500,000 | $99/mes | ~4h TTS |
| Scale | 2,000,000 | $330/mes | ~16h TTS |

> Para uso diario intenso se recomienda plan Creator o Pro.
