import Foundation
import AVFoundation
import Observation

/// Real-time conversational AI via ElevenLabs Agents.
/// Opens a WebSocket to wss://api.elevenlabs.io/v1/convai/conversation,
/// streams microphone audio (PCM 16-bit, sample rate negotiated with the
/// agent) to the agent, and plays back the agent's audio responses as they
/// arrive.
///
/// Supports both public agents (agent_id in query) and private agents
/// (requires `xi-api-key` header).
///
/// The agent's `agent_output_audio_format` is parsed from the
/// `conversation_initiation_metadata` event so playback uses the same rate
/// as the TTS (otherwise audio sounds "chipmunked" or low-pitched).
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
    private var inputConverter: AVAudioConverter?
    private var inputTargetFormat: AVAudioFormat?
    private var playbackFormat: AVAudioFormat?
    private var conversationId: String?
    private var inputSampleRate: Double = 16_000
    private var outputSampleRate: Double = 16_000
    private var pendingAudioChunks: [Data] = []
    private var hasPlaybackChain = false

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
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAgent = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedAgent.isEmpty else {
            await MainActor.run {
                self.lastError = "Falta API key o Agent ID"
                self.state = .error("Falta API key o Agent ID")
            }
            return
        }

        // 1) Microphone permission. Without it the audio engine starts but
        //    inputNode delivers silent buffers, and ElevenLabs interprets
        //    that as the user saying nothing — no replies. Surface the
        //    real cause early.
        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            await MainActor.run {
                self.lastError = "Permiso de micrófono denegado — Ajustes → OpenClaw Voice → Micrófono"
                self.state = .error("Permiso de micrófono denegado")
            }
            return
        }

        await MainActor.run {
            self.state = .connecting
            self.lastError = nil
            self.userTranscript = ""
            self.agentResponse = ""
            self.pendingAudioChunks.removeAll()
        }

        let urlString = "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=\(trimmedAgent)"
        guard let url = URL(string: urlString) else {
            await MainActor.run { self.state = .error("Invalid agent URL") }
            return
        }

        var request = URLRequest(url: url)
        request.setValue(trimmedKey, forHTTPHeaderField: "xi-api-key")

        let cfg = URLSessionConfiguration.default
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: OperationQueue())
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        let initMessage: [String: Any] = ["type": "conversation_initiation_client_data"]
        if let data = try? JSONSerialization.data(withJSONObject: initMessage),
           let json = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(json)) { _ in }
        }

        startReceiving()
        await MainActor.run { self.state = .connected }

        // 2) If we never receive conversation_initiation_metadata within 8s
        //    something is wrong (bad agent ID, bad key, blocked by network)
        //    — surface a clear error instead of leaving the UI silent.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            await MainActor.run {
                if !self.hasPlaybackChain, self.conversationId == nil {
                    self.lastError = "No llegó conversation_initiation_metadata. Comprueba Agent ID, API key y que el agente exista."
                    print("[ElevenLabs] \(self.lastError ?? "")")
                    if case .error = self.state {} else {
                        self.state = .error("Sin respuesta del agente")
                    }
                }
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                session.requestRecordPermission { cont.resume(returning: $0) }
            }
        }
    }

    func stop() {
        stopAudioCapture()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        hasPlaybackChain = false
        state = .idle
    }

    // MARK: - Audio capture (microphone → server)

    /// Start capture once we know the target sample rate (from metadata) so
    /// the converter and the player chain match the agent's expectations.
    private func startAudioCaptureAndPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        // voiceChat enables hardware AEC. Avoid defaultToSpeaker — routing to
        // the loudspeaker breaks AEC and the mic picks up the agent's own
        // voice. Earpiece / headphones / Bluetooth give the cleanest loop.
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothA2DP, .allowAirPlay]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            print("[ElevenLabs] Could not enable voice processing: \(error)")
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let pcm16Format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "ElevenLabs", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PCM format"])
        }
        self.inputTargetFormat = pcm16Format

        guard let converter = AVAudioConverter(from: inputFormat, to: pcm16Format) else {
            throw NSError(domain: "ElevenLabs", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        self.inputConverter = converter

        // Playback chain — set up with the agent's output sample rate so we
        // don't pitch-shift its voice.
        guard let pcm16Play = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "ElevenLabs", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create playback format"])
        }
        self.playbackFormat = pcm16Play

        if !hasPlaybackChain {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: pcm16Play)
            hasPlaybackChain = true
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        playerNode.play()

        // Drain any audio chunks that arrived before playback was ready.
        for chunk in pendingAudioChunks {
            playAudioChunk(chunk)
        }
        pendingAudioChunks.removeAll()

        Task { @MainActor in self.state = .listening }
        print("[ElevenLabs] Audio chain ready — input \(Int(inputSampleRate))Hz / output \(Int(outputSampleRate))Hz")
    }

    private func stopAudioCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
        inputConverter = nil
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Gate the mic while the agent is speaking. Even with AEC this
        // prevents feedback in awkward acoustics. Real interruptions are
        // signalled by ElevenLabs via the "interruption" event, after which
        // we transition back to .listening and the gate opens again.
        if case .agentSpeaking = state {
            return
        }

        guard let converter = inputConverter, let targetFormat = inputTargetFormat else { return }

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )
        guard frameCapacity > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

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

        let byteCount = Int(outputBuffer.frameLength) * 2
        guard let channelData = outputBuffer.int16ChannelData?[0] else { return }
        let data = Data(bytes: channelData, count: byteCount)
        sendAudioChunk(data)
    }

    private func sendAudioChunk(_ data: Data) {
        let base64 = data.base64EncodedString()
        let message: [String: Any] = ["user_audio_chunk": base64]
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
                            await self.handleServerMessage(data)
                        }
                    case .data(let data):
                        await self.handleServerMessage(data)
                    @unknown default:
                        break
                    }
                } catch {
                    print("[ElevenLabs] Receive error: \(error)")
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                        self.state = .error(error.localizedDescription)
                    }
                    break
                }
            }
        }
    }

    @MainActor
    private func handleServerMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "conversation_initiation_metadata":
            handleInitiationMetadata(json)

        case "audio":
            if let audioEvent = json["audio_event"] as? [String: Any],
               let base64 = audioEvent["audio_base_64"] as? String,
               let data = Data(base64Encoded: base64) {
                if hasPlaybackChain {
                    playAudioChunk(data)
                } else {
                    pendingAudioChunks.append(data)
                }
                state = .agentSpeaking
                scheduleReturnToListening()
            }

        case "user_transcript":
            if let event = json["user_transcription_event"] as? [String: Any],
               let transcript = event["user_transcript"] as? String {
                userTranscript = transcript
            }

        case "agent_response":
            if let event = json["agent_response_event"] as? [String: Any],
               let response = event["agent_response"] as? String {
                agentResponse = response
            }

        case "agent_response_correction":
            if let event = json["agent_response_correction_event"] as? [String: Any],
               let response = event["corrected_agent_response"] as? String {
                agentResponse = response
            }

        case "ping":
            if let pingEvent = json["ping_event"] as? [String: Any],
               let eventId = pingEvent["event_id"] as? Int {
                let pong: [String: Any] = ["type": "pong", "event_id": eventId]
                if let pongData = try? JSONSerialization.data(withJSONObject: pong),
                   let pongStr = String(data: pongData, encoding: .utf8) {
                    webSocket?.send(.string(pongStr)) { _ in }
                }
            }

        case "interruption":
            playerNode.stop()
            playerNode.play()
            state = .listening

        case "internal_vad_score", "internal_turn_probability", "internal_tentative_agent_response":
            break

        default:
            print("[ElevenLabs] Unhandled message type: \(type)")
        }
    }

    private func handleInitiationMetadata(_ json: [String: Any]) {
        guard let meta = json["conversation_initiation_metadata_event"] as? [String: Any] else { return }
        if let id = meta["conversation_id"] as? String {
            conversationId = id
        }
        let userFmt = meta["user_input_audio_format"] as? String ?? "pcm_16000"
        let agentFmt = meta["agent_output_audio_format"] as? String ?? "pcm_16000"
        inputSampleRate = pcmSampleRate(from: userFmt) ?? 16_000
        outputSampleRate = pcmSampleRate(from: agentFmt) ?? 16_000

        print("[ElevenLabs] Conversation \(conversationId ?? "?") — input=\(userFmt), output=\(agentFmt)")

        if !isPCM(agentFmt) {
            lastError = "Formato no PCM (\(agentFmt)) no soportado. Configura el agente con un output PCM (16/22.05/24/44.1 kHz)."
            print("[ElevenLabs] WARNING: \(lastError ?? "")")
        }

        do {
            try startAudioCaptureAndPlayback()
        } catch {
            lastError = "Audio chain failed: \(error.localizedDescription)"
            state = .error(error.localizedDescription)
        }
    }

    private func pcmSampleRate(from format: String) -> Double? {
        // "pcm_16000" → 16000, "pcm_24000" → 24000, etc.
        guard format.hasPrefix("pcm_") else { return nil }
        let n = format.dropFirst("pcm_".count)
        return Double(n)
    }

    private func isPCM(_ format: String) -> Bool {
        format.hasPrefix("pcm_")
    }

    /// Debounce return to .listening after the agent stops emitting audio.
    /// ElevenLabs doesn't send a clean "audio_end" event so we rely on a
    /// timeout since the last chunk.
    private var returnToListeningWorkItem: DispatchWorkItem?

    private func scheduleReturnToListening() {
        returnToListeningWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if case .agentSpeaking = self.state {
                self.state = .listening
            }
        }
        returnToListeningWorkItem = work
        // Allow longer silences between sentences before reopening the mic.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    // MARK: - Audio playback

    private func playAudioChunk(_ data: Data) {
        guard let format = playbackFormat else { return }
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawBuffer in
            if let src = rawBuffer.bindMemory(to: Int16.self).baseAddress,
               let dst = buffer.int16ChannelData?[0] {
                dst.update(from: src, count: Int(frameCount))
            }
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
}

// MARK: - URLSessionDelegate

extension ElevenLabsConversationalService: URLSessionDelegate, URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[ElevenLabs] WebSocket opened")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        print("[ElevenLabs] WebSocket closed: \(closeCode.rawValue) \(reasonStr)")
        Task { @MainActor in
            if case .error = self.state { return }
            self.state = .idle
        }
    }
}
