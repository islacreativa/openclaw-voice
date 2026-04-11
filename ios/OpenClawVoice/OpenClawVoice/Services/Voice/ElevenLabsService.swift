import Foundation
import AVFoundation

final class ElevenLabsService {
    private let baseURL = "https://api.elevenlabs.io/v1"
    private var apiKey: String

    struct VoiceConfig {
        var voiceId: String = "pNInz6obpgDQGcFmaJgB"
        var modelId: String = "eleven_multilingual_v2"
        var stability: Double = 0.5
        var similarityBoost: Double = 0.75
        var style: Double = 0.0
        var useSpeakerBoost: Bool = true
        var outputFormat: String = "mp3_44100_128"
    }

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func updateAPIKey(_ key: String) {
        self.apiKey = key
    }

    // MARK: - Streaming TTS

    func streamSpeech(text: String, config: VoiceConfig = VoiceConfig()) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !apiKey.isEmpty else {
                        continuation.finish(throwing: ElevenLabsError.noAPIKey)
                        return
                    }

                    let url = URL(string: "\(baseURL)/text-to-speech/\(config.voiceId)/stream")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

                    let body: [String: Any] = [
                        "text": text,
                        "model_id": config.modelId,
                        "voice_settings": [
                            "stability": config.stability,
                            "similarity_boost": config.similarityBoost,
                            "style": config.style,
                            "use_speaker_boost": config.useSpeakerBoost
                        ]
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ElevenLabsError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 401 {
                        continuation.finish(throwing: ElevenLabsError.invalidAPIKey)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: ElevenLabsError.apiError(statusCode: httpResponse.statusCode))
                        return
                    }

                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 4096 {
                            continuation.yield(buffer)
                            buffer = Data()
                        }
                    }

                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Simple TTS (non-streaming, returns full audio)

    func synthesize(text: String, config: VoiceConfig = VoiceConfig()) async throws -> Data {
        guard !apiKey.isEmpty else { throw ElevenLabsError.noAPIKey }

        let url = URL(string: "\(baseURL)/text-to-speech/\(config.voiceId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": config.modelId,
            "voice_settings": [
                "stability": config.stability,
                "similarity_boost": config.similarityBoost,
                "style": config.style,
                "use_speaker_boost": config.useSpeakerBoost
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ElevenLabsError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return data
    }

    // MARK: - List Voices

    func listVoices() async throws -> [Voice] {
        guard !apiKey.isEmpty else { throw ElevenLabsError.noAPIKey }

        var request = URLRequest(url: URL(string: "\(baseURL)/voices")!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return response.voices
    }

    // MARK: - Models

    struct Voice: Codable, Identifiable {
        let voiceId: String
        let name: String
        let category: String?

        var id: String { voiceId }

        enum CodingKeys: String, CodingKey {
            case voiceId = "voice_id"
            case name, category
        }
    }

    struct VoicesResponse: Codable {
        let voices: [Voice]
    }

    enum ElevenLabsError: LocalizedError {
        case noAPIKey
        case invalidAPIKey
        case invalidResponse
        case apiError(statusCode: Int)
        case quotaExceeded

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "ElevenLabs API key not set"
            case .invalidAPIKey: return "Invalid ElevenLabs API key"
            case .invalidResponse: return "Invalid response from ElevenLabs"
            case .apiError(let code): return "ElevenLabs API error (HTTP \(code))"
            case .quotaExceeded: return "ElevenLabs quota exceeded"
            }
        }
    }
}
