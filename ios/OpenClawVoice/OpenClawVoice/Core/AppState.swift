import Foundation
import Observation

@Observable
final class AppState {
    // Connection
    var connectionStatus: ConnectionStatus = .disconnected
    var serverURL: String = ""
    var authToken: String = ""
    var sessionId: String?

    // Chat
    var messages: [ChatMessage] = []
    var isProcessing: Bool = false

    // Voice
    var isListening: Bool = false
    var isSpeaking: Bool = false
    var currentTranscription: String = ""

    // CarPlay
    var isCarPlayConnected: Bool = false

    // Config
    var elevenLabsAPIKey: String = ""
    var selectedVoiceId: String = "pNInz6obpgDQGcFmaJgB" // Adam default
    var selectedModelId: String = "eleven_multilingual_v2"
    var speechLocale: String = "es-ES"
    var listeningMode: ListeningMode = .pushToTalk

    enum ListeningMode: String, CaseIterable {
        case pushToTalk = "Push to Talk"
        case continuous = "Continuous"
    }
}
