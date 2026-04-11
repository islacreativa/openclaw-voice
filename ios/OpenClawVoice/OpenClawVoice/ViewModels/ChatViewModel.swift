import Foundation
import Observation

@Observable
final class ChatViewModel {
    private let webSocket: WebSocketManager
    private let speechRecognizer: SpeechRecognizer
    private let elevenLabs: ElevenLabsService
    private let audioPlayer: AudioPlayerService
    private let appState: AppState

    var inputText: String = ""
    var messages: [ChatMessage] = []
    var isProcessing: Bool = false
    var currentCommandId: String?

    init(appState: AppState, webSocket: WebSocketManager, speechRecognizer: SpeechRecognizer, elevenLabs: ElevenLabsService, audioPlayer: AudioPlayerService) {
        self.appState = appState
        self.webSocket = webSocket
        self.speechRecognizer = speechRecognizer
        self.elevenLabs = elevenLabs
        self.audioPlayer = audioPlayer

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
        let config = ElevenLabsService.VoiceConfig(
            voiceId: appState.selectedVoiceId,
            modelId: appState.selectedModelId
        )

        Task {
            do {
                let audioData = try await elevenLabs.synthesize(text: text, config: config)
                try audioPlayer.play(data: audioData)
                // Wait for playback to finish
                while audioPlayer.isPlaying {
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                print("TTS error: \(error)")
            }
            await MainActor.run {
                appState.isSpeaking = false
            }
        }
    }

    func cancelCommand() {
        if let commandId = currentCommandId {
            webSocket.sendCancel(commandId: commandId)
        }
        audioPlayer.stop()
        isProcessing = false
        appState.isProcessing = false
        appState.isSpeaking = false
    }
}
