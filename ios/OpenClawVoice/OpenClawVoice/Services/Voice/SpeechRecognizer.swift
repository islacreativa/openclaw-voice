import Foundation
import Speech
import AVFoundation
import Observation

@Observable
final class SpeechRecognizer {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var transcription: String = ""
    var isListening: Bool = false
    var isFinal: Bool = false
    var isAuthorized: Bool = false
    var error: String?

    init(locale: String = "es-ES") {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
    }

    func updateLocale(_ identifier: String) {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        isAuthorized = status == .authorized
        return isAuthorized
    }

    // MARK: - Start Listening

    func startListening() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.notAvailable
        }

        // Cancel previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        transcription = ""
        isFinal = false
        error = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw SpeechError.requestCreationFailed }

        recognitionRequest.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.transcription = result.bestTranscription.formattedString
                self.isFinal = result.isFinal
            }

            if error != nil || result?.isFinal == true {
                self.stopListening()
            }

            if let error {
                self.error = error.localizedDescription
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }

    // MARK: - Stop Listening

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Errors

    enum SpeechError: LocalizedError {
        case notAuthorized
        case notAvailable
        case requestCreationFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Speech recognition not authorized"
            case .notAvailable: return "Speech recognition not available"
            case .requestCreationFailed: return "Failed to create recognition request"
            }
        }
    }
}
