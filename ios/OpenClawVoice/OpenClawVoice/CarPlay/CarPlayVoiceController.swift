import Foundation
import CarPlay
import AVFoundation

final class CarPlayVoiceController {
    private let speechRecognizer: SpeechRecognizer
    private let elevenLabs: ElevenLabsService
    private let webSocket: WebSocketManager
    private let audioPlayer: AudioPlayerService
    private let appState: AppState

    weak var templateManager: CarPlayTemplateManager?

    enum VoiceState {
        case idle, listening, processing, speaking
    }

    private(set) var state: VoiceState = .idle {
        didSet { updateCarPlayState() }
    }

    init(appState: AppState, webSocket: WebSocketManager, speechRecognizer: SpeechRecognizer, elevenLabs: ElevenLabsService, audioPlayer: AudioPlayerService) {
        self.appState = appState
        self.webSocket = webSocket
        self.speechRecognizer = speechRecognizer
        self.elevenLabs = elevenLabs
        self.audioPlayer = audioPlayer
    }

    // MARK: - Voice Interaction

    func startVoiceInteraction() async {
        state = .listening
        appState.isListening = true

        do {
            // Configure audio for CarPlay
            let session = AVAudioSession.sharedInstance()
            // Use runtime-compatible bluetooth option across iOS SDK versions.
            var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .defaultToSpeaker]
            #if swift(>=6.0)
            if #available(iOS 18.2, *) {
                options.insert(.allowBluetoothHFP)
            } else {
                options.insert(.allowBluetooth)
            }
            #else
            options.insert(.allowBluetooth)
            #endif
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try session.setActive(true)

            // Start listening
            try speechRecognizer.startListening()

            // Wait for final transcription (with timeout)
            let text = await waitForTranscription(timeout: 10)
            speechRecognizer.stopListening()
            appState.isListening = false

            guard !text.isEmpty else {
                state = .idle
                return
            }

            // Send command
            state = .processing
            appState.isProcessing = true
            let commandId = webSocket.sendCommand(text: text, source: "voice", language: appState.speechLocale)

            // Wait for response
            let response = await waitForResponse(commandId: commandId, timeout: 60)
            appState.isProcessing = false

            guard !response.isEmpty else {
                state = .idle
                return
            }

            // Speak response
            state = .speaking
            appState.isSpeaking = true

            let config = ElevenLabsService.VoiceConfig(
                voiceId: appState.selectedVoiceId,
                modelId: appState.selectedModelId
            )

            let audioData = try await elevenLabs.synthesize(text: response, config: config)
            try audioPlayer.play(data: audioData)

            // Wait for audio playback to finish
            while audioPlayer.isPlaying {
                try await Task.sleep(for: .milliseconds(200))
            }

            appState.isSpeaking = false
            state = .idle

        } catch {
            print("CarPlay voice error: \(error)")
            appState.isListening = false
            appState.isProcessing = false
            appState.isSpeaking = false
            state = .idle
        }
    }

    // MARK: - Helpers

    private func waitForTranscription(timeout: TimeInterval) async -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if speechRecognizer.isFinal {
                return speechRecognizer.transcription
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return speechRecognizer.transcription
    }

    private func waitForResponse(commandId: String, timeout: TimeInterval) async -> String {
        var responseText = ""
        let deadline = Date().addingTimeInterval(timeout)

        webSocket.onMessage = { msg in
            switch msg {
            case .responseChunk(let id, _, let text, _) where id == commandId:
                responseText += (responseText.isEmpty ? "" : " ") + text
            case .responseEnd(let id, _, let fullText, _) where id == commandId:
                responseText = fullText
            default:
                break
            }
        }

        while Date() < deadline {
            // Check if we got a complete response
            if !responseText.isEmpty {
                // Small delay to see if more chunks come
                try? await Task.sleep(for: .milliseconds(500))
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        return responseText
    }

    private func updateCarPlayState() {
        switch state {
        case .idle: templateManager?.activateState("idle")
        case .listening: templateManager?.activateState("listening")
        case .processing: templateManager?.activateState("processing")
        case .speaking: templateManager?.activateState("speaking")
        }
    }
}
