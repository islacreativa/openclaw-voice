import Foundation
import CarPlay
import AVFoundation

@MainActor
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

    private var responseBuffer: String = ""
    private var responseFinal: Bool = false
    private var activeCommandId: String?
    private var previousMessageHandler: ((ServerMessage) -> Void)?

    init(appState: AppState, webSocket: WebSocketManager, speechRecognizer: SpeechRecognizer, elevenLabs: ElevenLabsService, audioPlayer: AudioPlayerService) {
        self.appState = appState
        self.webSocket = webSocket
        self.speechRecognizer = speechRecognizer
        self.elevenLabs = elevenLabs
        self.audioPlayer = audioPlayer
    }

    // MARK: - Voice flow

    func startVoiceInteraction() async {
        state = .listening
        appState.isListening = true

        do {
            try configureCarPlayAudioSession()
            try speechRecognizer.startListening()

            let text = await waitForTranscription(timeout: 10)
            speechRecognizer.stopListening()
            appState.isListening = false

            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                state = .idle
                return
            }

            // Append the captured WS handler so we don't clobber chat handler.
            previousMessageHandler = webSocket.onMessage
            webSocket.onMessage = { [weak self] msg in
                self?.previousMessageHandler?(msg)
                self?.handleResponse(msg)
            }

            state = .processing
            appState.isProcessing = true
            responseBuffer = ""
            responseFinal = false
            activeCommandId = webSocket.sendCommand(text: text, source: "voice", language: appState.speechLocale)

            let response = await waitForResponse(timeout: 60)

            // Restore previous handler.
            webSocket.onMessage = previousMessageHandler
            previousMessageHandler = nil
            appState.isProcessing = false

            guard !response.isEmpty else {
                state = .idle
                return
            }

            state = .speaking
            appState.isSpeaking = true

            let cfg = ElevenLabsService.VoiceConfig(
                voiceId: appState.selectedVoiceId,
                modelId: appState.selectedModelId
            )
            let audio = try await elevenLabs.synthesize(text: response, config: cfg)
            try audioPlayer.play(data: audio)

            while audioPlayer.isPlaying {
                try await Task.sleep(for: .milliseconds(200))
            }

            appState.isSpeaking = false
            state = .idle
        } catch {
            print("[CarPlay] voice error: \(error)")
            speechRecognizer.stopListening()
            audioPlayer.stop()
            appState.isListening = false
            appState.isProcessing = false
            appState.isSpeaking = false
            state = .idle
        }
    }

    // MARK: - Helpers

    private func configureCarPlayAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .defaultToSpeaker]
        if #available(iOS 18.2, *) {
            options.insert(.allowBluetoothHFP)
        } else {
            options.insert(.allowBluetooth)
        }
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        try session.setActive(true)
    }

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

    private func handleResponse(_ msg: ServerMessage) {
        switch msg {
        case .responseChunk(let id, _, let text, _) where id == activeCommandId:
            responseBuffer += (responseBuffer.isEmpty ? "" : " ") + text
        case .responseEnd(let id, _, let fullText, _) where id == activeCommandId:
            responseBuffer = fullText
            responseFinal = true
        case .error(_, let message, let cmd) where cmd == activeCommandId:
            responseBuffer = "Error: \(message)"
            responseFinal = true
        default:
            break
        }
    }

    private func waitForResponse(timeout: TimeInterval) async -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !responseFinal {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return responseBuffer
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
