import Foundation
import AVFoundation
import Observation

@Observable
final class AudioPlayerService {
    private var audioPlayer: AVAudioPlayer?
    var isPlaying: Bool = false

    // Play MP3 data directly (for non-streaming or accumulated chunks)
    func play(data: Data) throws {
        try configureAudioSession()
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.delegate = PlaybackDelegate { [weak self] in
            self?.isPlaying = false
        }
        audioPlayer?.play()
        isPlaying = true
    }

    // Play streaming audio: accumulates all chunks then plays
    func playStream(_ stream: AsyncThrowingStream<Data, Error>) async throws {
        var allData = Data()
        for try await chunk in stream {
            allData.append(chunk)
        }
        guard !allData.isEmpty else { return }
        try play(data: allData)
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }
}

private class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
