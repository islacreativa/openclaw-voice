import Foundation
import AVFoundation
import Observation

// Lightweight VAD that derives an audio-level signal (0..1) from a live
// AVAudioPCMBuffer tap. Can be fed by SpeechRecognizer (for mic input) or
// by a playback tap (for a waveform while the assistant speaks).
//
// Publishes two things:
//   * `audioLevel` — smoothed RMS for UI waveforms.
//   * `isSpeechActive` — true when sustained audio is above threshold.
//
// Silence detection fires `onSilenceDetected` after `silenceDuration` seconds
// below threshold while previously speaking. Use this to auto-stop listening.
@Observable
final class VoiceActivityDetector {
    // Tunables
    var activationThreshold: Float = 0.03
    var silenceDuration: TimeInterval = 1.2
    var smoothing: Float = 0.25

    // State
    private(set) var audioLevel: Float = 0
    private(set) var isSpeechActive: Bool = false

    // Callbacks
    var onSpeechStarted: (() -> Void)?
    var onSilenceDetected: (() -> Void)?

    private var lastAboveThresholdAt: Date?
    private var silenceTimer: Timer?

    func reset() {
        audioLevel = 0
        isSpeechActive = false
        lastAboveThresholdAt = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // Call from any audio tap. Safe to call from an audio thread; we hop to
    // main for state updates.
    func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameCount))

        DispatchQueue.main.async { [weak self] in
            self?.update(level: rms)
        }
    }

    private func update(level: Float) {
        audioLevel = (smoothing * audioLevel) + ((1 - smoothing) * level)

        if audioLevel >= activationThreshold {
            lastAboveThresholdAt = Date()
            if !isSpeechActive {
                isSpeechActive = true
                onSpeechStarted?()
            }
            silenceTimer?.invalidate()
            silenceTimer = nil
        } else if isSpeechActive, silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
                guard let self, self.isSpeechActive else { return }
                self.isSpeechActive = false
                self.onSilenceDetected?()
            }
        }
    }
}
