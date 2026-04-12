import Foundation
import AVFoundation
import Observation

/// Real-time conversational AI via ElevenLabs Agents.
/// Opens a WebSocket to wss://api.elevenlabs.io/v1/convai/conversation,
/// streams microphone audio (PCM 16kHz mono) to the agent, and plays
/// back the agent's audio responses as they arrive.
///
/// Supports both public agents (agent_id in query) and private agents
/// (requires signed URL from /v1/convai/conversation/get-signed-url).
@Observable
final class ElevenLabsConversationalService: NSObject {
    private(set) var state: State = .idle
    private(set) var userTranscript: String = ""
    private(set) var agentResponse: String = ""
    private(set) var lastError: String?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat?
    private var playbackFormat: AVAudioFormat?
    private var conversationId: String?

    enum State: Equatable {
        case idle
        case connecting
        case connected
        case listening
        case agentSpeaking
        case error(String)
    }

    // MARK: - Start / Stop

    func start(apiKey: String, agentId: String) async {
        guard !apiKey.isEmpty, !agentId.isEmpty else {
            await MainActor.run { self.state = .error("Missing API key or agent ID") }
            return
        }

        await MainActor.run { self.state = .connecting }

        // For private agents we'd first fetch a signed URL. Try direct
        // connection first (works for public agents); if it fails the error
        // handling below will surface a clear message.
        let urlString = "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=\(agentId)"
        guard let url = URL(string: urlString) else {
            await MainActor.run { self.state = .error("Invalid agent URL") }
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        // Send initial config
        let initMessage: [String: Any] = [
            "type": "conversation_initiation_client_data"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: initMessage),
           let json = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(json)) { _ in }
        }

        startReceiving()
        await MainActor.run { self.state = .connected }

        do {
            try startAudioCapture()
        } catch {
            await MainActor.run {
                self.lastError = "Audio capture failed: \(error.localizedDescription)"
                self.state = .error(error.localizedDescription)
            }
        }
    }

    func stop() {
        stopAudioCapture()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        state = .idle
    }

    // MARK: - Audio capture (microphone → server)

    private func startAudioCapture() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: PCM 16kHz mono (ElevenLabs expects 16-bit PCM @ 16kHz)
        let targetSampleRate = 16000.0
        guard let pcm16Format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: true) else {
            throw NSError(domain: "ElevenLabs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PCM format"])
        }
        self.audioFormat = pcm16Format

        guard let converter = AVAudioConverter(from: inputFormat, to: pcm16Format) else {
            throw NSError(domain: "ElevenLabs", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }

        // Setup playback
        audioEngine.attach(playerNode)
        let pcm16PlayFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        self.playbackFormat = pcm16PlayFormat
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: pcm16PlayFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self, converter, pcm16Format] buffer, _ in
            self?.handleInputBuffer(buffer, converter: converter, targetFormat: pcm16Format)
        }

        audioEngine.prepare()
        try audioEngine.start()
        playerNode.play()

        Task { @MainActor in self.state = .listening }
    }

    private func stopAudioCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return buffer
        }

        guard error == nil, outputBuffer.frameLength > 0 else { return }

        // Get raw PCM data
        let byteCount = Int(outputBuffer.frameLength) * 2 // int16 = 2 bytes
        guard let channelData = outputBuffer.int16ChannelData?[0] else { return }
        let data = Data(bytes: channelData, count: byteCount)

        sendAudioChunk(data)
    }

    private func sendAudioChunk(_ data: Data) {
        let base64 = data.base64EncodedString()
        let message: [String: Any] = [
            "user_audio_chunk": base64
        ]
        if let json = try? JSONSerialization.data(withJSONObject: message),
           let str = String(data: json, encoding: .utf8) {
            webSocket?.send(.string(str)) { _ in }
        }
    }

    // MARK: - Receive (server → app)

    private func startReceiving() {
        Task { [weak self] in
            while let self, !Task.isCancelled {
                guard let ws = self.webSocket else { break }
                do {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            self.handleServerMessage(data)
                        }
                    case .data(let data):
                        self.handleServerMessage(data)
                    @unknown default:
                        break
                    }
                } catch {
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                        self.state = .error(error.localizedDescription)
                    }
                    break
                }
            }
        }
    }

    private func handleServerMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "conversation_initiation_metadata":
            if let meta = json["conversation_initiation_metadata_event"] as? [String: Any],
               let id = meta["conversation_id"] as? String {
                conversationId = id
                print("[ElevenLabs] Conversation started: \(id)")
            }

        case "audio":
            if let audioEvent = json["audio_event"] as? [String: Any],
               let base64 = audioEvent["audio_base_64"] as? String,
               let data = Data(base64Encoded: base64) {
                playAudioChunk(data)
                Task { @MainActor in self.state = .agentSpeaking }
            }

        case "user_transcript":
            if let event = json["user_transcription_event"] as? [String: Any],
               let transcript = event["user_transcript"] as? String {
                Task { @MainActor in self.userTranscript = transcript }
            }

        case "agent_response":
            if let event = json["agent_response_event"] as? [String: Any],
               let response = event["agent_response"] as? String {
                Task { @MainActor in self.agentResponse = response }
            }

        case "ping":
            // Respond with pong to keep connection alive
            if let pingEvent = json["ping_event"] as? [String: Any],
               let eventId = pingEvent["event_id"] as? Int {
                let pong: [String: Any] = ["type": "pong", "event_id": eventId]
                if let pongData = try? JSONSerialization.data(withJSONObject: pong),
                   let pongStr = String(data: pongData, encoding: .utf8) {
                    webSocket?.send(.string(pongStr)) { _ in }
                }
            }

        case "interruption":
            // Agent was interrupted; clear audio queue
            playerNode.stop()
            playerNode.play()

        default:
            break
        }
    }

    // MARK: - Audio playback

    private func playAudioChunk(_ data: Data) {
        guard let format = playbackFormat else { return }
        let frameCount = AVAudioFrameCount(data.count / 2) // int16 = 2 bytes/sample
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawBuffer in
            if let src = rawBuffer.bindMemory(to: Int16.self).baseAddress,
               let dst = buffer.int16ChannelData?[0] {
                dst.assign(from: src, count: Int(frameCount))
            }
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
}

// MARK: - URLSessionDelegate (TLS; not strictly needed for ElevenLabs public API)

extension ElevenLabsConversationalService: URLSessionDelegate, URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[ElevenLabs] WebSocket opened")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[ElevenLabs] WebSocket closed: \(closeCode)")
        Task { @MainActor in self.state = .idle }
    }
}
