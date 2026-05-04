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
    private var turnStartedAt: [String: Date] = [:]
    private var ttsStartedAt: [String: Date] = [:]

    init(appState: AppState, webSocket: WebSocketManager, speechRecognizer: SpeechRecognizer, elevenLabs: ElevenLabsService, audioPlayer: AudioPlayerService) {
        self.appState = appState
        self.webSocket = webSocket
        self.speechRecognizer = speechRecognizer
        self.elevenLabs = elevenLabs
        self.audioPlayer = audioPlayer
        self.streamPlayer = AudioStreamPlayer()
        self.messages = ChatHistoryStore.shared.load()

        setupMessageHandler()
    }

    func clearHistory() {
        messages.removeAll()
        ChatHistoryStore.shared.clear()
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
        turnStartedAt[commandId] = Date()

        messages.append(ChatMessage(id: commandId, role: .user, text: text))
        ChatHistoryStore.shared.saveDebounced(messages)
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
        turnStartedAt[commandId] = Date()

        messages.append(ChatMessage(id: commandId, role: .user, text: text))
        ChatHistoryStore.shared.saveDebounced(messages)
        isProcessing = true
        appState.isProcessing = true
    }

    // MARK: - Handle server messages

    private func handleServerMessage(_ msg: ServerMessage) {
        defer { ChatHistoryStore.shared.saveDebounced(messages) }

        switch msg {
        case .responseStart(let commandId, _):
            // Create placeholder for assistant response
            messages.append(ChatMessage(id: "resp-\(commandId)", role: .assistant, text: "", isStreaming: true))

        case .responseChunk(let commandId, _, let text, _):
            // Append chunk to streaming message
            if let index = messages.lastIndex(where: { $0.id == "resp-\(commandId)" }) {
                messages[index].text += (messages[index].text.isEmpty ? "" : " ") + text
            }

        case .responseEnd(let commandId, _, let fullText, let processingMs, let ttfbMs, let transport):
            if let index = messages.lastIndex(where: { $0.id == "resp-\(commandId)" }) {
                messages[index].text = fullText
                messages[index].isStreaming = false
                messages[index].latency = ChatMessage.Latency(
                    serverProcessingMs: processingMs,
                    timeToFirstChunkMs: ttfbMs,
                    timeToFirstAudioMs: nil,
                    transport: transport
                )
            }
            isProcessing = false
            appState.isProcessing = false
            currentCommandId = nil

            speakResponse(fullText, commandId: commandId)

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

    private func speakResponse(_ text: String, commandId: String) {
        guard !appState.elevenLabsAPIKey.isEmpty else { return }

        appState.isSpeaking = true
        ttsTask?.cancel()

        let config = ElevenLabsService.VoiceConfig(
            voiceId: appState.selectedVoiceId,
            modelId: appState.selectedModelId
        )
        let sampleRate = 22050
        let turnStart = turnStartedAt[commandId]

        // Split into "first sentence + remainder" so we can start TTS on the
        // first sentence ASAP and synthesize the rest in parallel. For short
        // replies (one sentence) this collapses to a single call; for longer
        // ones we cut time-to-first-audio roughly in half on the tail.
        let segments = splitForSpeech(text)

        ttsTask = Task { @MainActor in
            do {
                try streamPlayer.startStream(sampleRate: Double(sampleRate))

                var firstAudioRecorded = false
                for (segmentIndex, segment) in segments.enumerated() {
                    if Task.isCancelled { break }
                    let stream = elevenLabs.streamSpeechPCM(text: segment, sampleRate: sampleRate, config: config)
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        streamPlayer.enqueue(chunk)
                        if !firstAudioRecorded && segmentIndex == 0 {
                            firstAudioRecorded = true
                            if let start = turnStart,
                               let index = messages.lastIndex(where: { $0.id == "resp-\(commandId)" }) {
                                let ms = Int(Date().timeIntervalSince(start) * 1000)
                                var latency = messages[index].latency ?? ChatMessage.Latency()
                                latency.timeToFirstAudioMs = ms
                                messages[index].latency = latency
                            }
                        }
                    }
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

    /// Cuts the text into 1-2 chunks: the first sentence (or first ~120
    /// characters), and the rest. Keeps the first chunk small so the first
    /// audio starts ASAP, while still respecting natural pauses.
    private func splitForSpeech(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 60 else { return [trimmed] }

        let punctuation: Set<Character> = [".", "!", "?", "…", "\n"]
        let minHead = 24
        let maxHead = 160
        var head: String = ""
        var tail: String = ""
        var splitIndex: String.Index?

        for index in trimmed.indices {
            head.append(trimmed[index])
            if head.count >= minHead, punctuation.contains(trimmed[index]) {
                splitIndex = trimmed.index(after: index)
                break
            }
            if head.count >= maxHead {
                splitIndex = trimmed.index(after: index)
                break
            }
        }

        guard let cut = splitIndex, cut < trimmed.endIndex else {
            return [trimmed]
        }
        let headPart = String(trimmed[..<cut]).trimmingCharacters(in: .whitespaces)
        let tailPart = String(trimmed[cut...]).trimmingCharacters(in: .whitespaces)
        tail = tailPart
        if headPart.isEmpty { return [trimmed] }
        if tail.isEmpty { return [headPart] }
        return [headPart, tail]
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
