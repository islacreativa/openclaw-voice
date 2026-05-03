import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private let webSocket: WebSocketManager
    private let speechRecognizer: SpeechRecognizer
    private let elevenLabs: ElevenLabsService
    private let audioPlayer: AudioPlayerService
    private let streamPlayer: AudioStreamPlayer
    private let appState: AppState

    var inputText: String = ""
    var messages: [ChatMessage] = []
    var isProcessing: Bool = false
    var currentCommandId: String?
    private var ttsTask: Task<Void, Never>?

    init(appState: AppState, webSocket: WebSocketManager, speechRecognizer: SpeechRecognizer, elevenLabs: ElevenLabsService, audioPlayer: AudioPlayerService) {
        self.appState = appState
        self.webSocket = webSocket
        self.speechRecognizer = speechRecognizer
        self.elevenLabs = elevenLabs
        self.audioPlayer = audioPlayer
        self.streamPlayer = AudioStreamPlayer()

        setupMessageHandler()
    }

    private func setupMessageHandler() {
        webSocket.onMessage = { [weak self] msg in
            self?.handleServerMessage(msg)
        }
    }

    // MARK: - Send text command

    func sendTextCommand() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        let commandId = webSocket.sendCommand(text: text)
        currentCommandId = commandId

        messages.append(ChatMessage(id: commandId, role: .user, text: text))
        isProcessing = true
        appState.isProcessing = true
    }

    // MARK: - Voice command

    func startVoiceCommand() {
        do {
            try speechRecognizer.startListening()
            appState.isListening = true
        } catch {
            messages.append(ChatMessage(role: .system, text: "Microphone error: \(error.localizedDescription)"))
        }
    }

    func stopVoiceCommand() {
        speechRecognizer.stopListening()
        appState.isListening = false

        let text = speechRecognizer.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let commandId = webSocket.sendCommand(text: text, source: "voice", language: appState.speechLocale)
        currentCommandId = commandId

        messages.append(ChatMessage(id: commandId, role: .user, text: text))
        isProcessing = true
        appState.isProcessing = true
    }

    // MARK: - Handle server messages

    private func handleServerMessage(_ msg: ServerMessage) {
        switch msg {
        case .responseStart(let commandId, _):
            // Create placeholder for assistant response
            messages.append(ChatMessage(id: "resp-\(commandId)", role: .assistant, text: "", isStreaming: true))

        case .responseChunk(let commandId, _, let text, _):
            // Append chunk to streaming message
            if let index = messages.lastIndex(where: { $0.id == "resp-\(commandId)" }) {
                messages[index].text += (messages[index].text.isEmpty ? "" : " ") + text
            }

        case .responseEnd(let commandId, _, let fullText, _):
            // Finalize message
            if let index = messages.lastIndex(where: { $0.id == "resp-\(commandId)" }) {
                messages[index].text = fullText
                messages[index].isStreaming = false
            }
            isProcessing = false
            appState.isProcessing = false
            currentCommandId = nil

            // Speak the response
            speakResponse(fullText)

        case .error(let code, let message, _):
            messages.append(ChatMessage(role: .system, text: "Error [\(code)]: \(message)"))
            isProcessing = false
            appState.isProcessing = false

        case .status(let openclawStatus):
            if openclawStatus != "ready" {
                messages.append(ChatMessage(role: .system, text: "OpenClaw status: \(openclawStatus)"))
            }

        default:
            break
        }
    }

    // MARK: - TTS

    private func speakResponse(_ text: String) {
        guard !appState.elevenLabsAPIKey.isEmpty else { return }

        appState.isSpeaking = true
        ttsTask?.cancel()

        let config = ElevenLabsService.VoiceConfig(
            voiceId: appState.selectedVoiceId,
            modelId: appState.selectedModelId
        )
        let sampleRate = 22050

        ttsTask = Task { @MainActor in
            do {
                try streamPlayer.startStream(sampleRate: Double(sampleRate))

                let stream = elevenLabs.streamSpeechPCM(text: text, sampleRate: sampleRate, config: config)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    streamPlayer.enqueue(chunk)
                }
                streamPlayer.finishStream()

                // Wait for the queue to drain so the UI's "speaking" indicator
                // stays up until audio actually ends.
                while streamPlayer.isPlaying, !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch is CancellationError {
                // Cancelled by user — nothing to clean up beyond stop().
            } catch {
                print("[TTS] Stream error: \(error)")
                streamPlayer.stop()
            }
            appState.isSpeaking = false
        }
    }

    func cancelCommand() {
        if let commandId = currentCommandId {
            webSocket.sendCancel(commandId: commandId)
        }
        ttsTask?.cancel()
        ttsTask = nil
        audioPlayer.stop()
        streamPlayer.stop()
        isProcessing = false
        appState.isProcessing = false
        appState.isSpeaking = false
    }
}
