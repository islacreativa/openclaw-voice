import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: String
    let role: Role
    var text: String
    let timestamp: Date
    var isStreaming: Bool
    var latency: Latency?

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    /// Per-turn timing data attached to assistant messages so the UI can
    /// surface where the seconds went without spelunking through logs.
    struct Latency: Equatable, Codable {
        var serverProcessingMs: Int?
        var timeToFirstChunkMs: Int?
        var timeToFirstAudioMs: Int?
        var transport: String?
    }

    init(id: String = UUID().uuidString,
         role: Role,
         text: String,
         isStreaming: Bool = false,
         latency: Latency? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = Date()
        self.isStreaming = isStreaming
        self.latency = latency
    }
}
