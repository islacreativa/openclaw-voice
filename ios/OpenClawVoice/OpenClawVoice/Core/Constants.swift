import Foundation

enum Constants {
    static let defaultPort = 8765
    static let heartbeatInterval: TimeInterval = 15
    static let heartbeatTimeout: TimeInterval = 10
    static let reconnectMaxAttempts = 10
    static let maxMessageSize = 1_048_576 // 1MB
    static let keychainServiceName = "com.dckstudios.openclaw-voice"
    static let keychainTokenKey = "server-auth-token"
    static let keychainElevenLabsKey = "elevenlabs-api-key"
    static let keychainServerURLKey = "server-url"
}
