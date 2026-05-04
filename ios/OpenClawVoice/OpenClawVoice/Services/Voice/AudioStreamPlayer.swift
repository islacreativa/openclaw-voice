import Foundation
import AVFoundation
import Observation

/// Progressive PCM player. Each chunk handed to `enqueue(_:)` is scheduled
/// on an `AVAudioPlayerNode` immediately, so playback can start as soon as
/// the first chunk arrives — without waiting for the full file like
/// `AVAudioPlayer(data:)` does.
///
/// Used by `ChatViewModel` to stream ElevenLabs TTS PCM output. The format
/// is fixed at 16-bit signed PCM, mono, sample rate negotiated when the
/// stream starts (matches the agent's `output_format` query param).
@Observable
@MainActor
final class AudioStreamPlayer {
    var isPlaying: Bool = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var pcmFormat: AVAudioFormat?
    private var sampleRate: Double = 22_050
    private var pendingChunks = 0
    private var streamFinished = false

    /// Configure the audio chain for a new stream. Call before the first
    /// `enqueue(_:)`. Tearing down and rebuilding for each utterance avoids
    /// stale format mismatches.
    func startStream(sampleRate: Double = 22_050) throws {
        stop()
        self.sampleRate = sampleRate
        try configureSession()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "AudioStreamPlayer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid PCM format \(Int(sampleRate))Hz"])
        }
        self.pcmFormat = format

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        player.play()

        pendingChunks = 0
        streamFinished = false
        isPlaying = true
    }

    /// Schedule a PCM chunk for playback. Bytes must be 16-bit signed mono
    /// at the sample rate passed to `startStream`.
    func enqueue(_ data: Data) {
        guard let format = pcmFormat, !data.isEmpty else { return }
        let frameCount = AVAudioFrameCount(data.count / 2)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { raw in
            if let src = raw.bindMemory(to: Int16.self).baseAddress,
               let dst = buffer.int16ChannelData?[0] {
                dst.update(from: src, count: Int(frameCount))
            }
        }

        pendingChunks += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pendingChunks -= 1
                if self.streamFinished, self.pendingChunks <= 0 {
                    self.isPlaying = false
                }
            }
        }
    }

    /// Mark the producer side as done. Once the queue drains, `isPlaying`
    /// drops to false. Listeners can use that to know the utterance ended.
    func finishStream() {
        streamFinished = true
        if pendingChunks <= 0 {
            isPlaying = false
        }
    }

    func stop() {
        // Order matters: stop the engine before touching node connections.
        // disconnectNodeInput / detach throw an Obj-C NSException when the
        // node was never attached, so guard with attachedNodes first.
        let isAttached = engine.attachedNodes.contains(player)
        if engine.isRunning {
            if isAttached { player.stop() }
            engine.stop()
        }
        if isAttached {
            engine.disconnectNodeInput(player, bus: 0)
            engine.detach(player)
        }
        pcmFormat = nil
        pendingChunks = 0
        streamFinished = false
        isPlaying = false
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Match the player chain config used elsewhere — playback to speaker
        // by default, allow Bluetooth A2DP for AirPods. We don't enable
        // voiceChat here because that's only useful for capture; this player
        // is output-only.
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay]
        )
        try session.setActive(true)
    }
}
