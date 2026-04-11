import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: Role
    var text: String
    let timestamp: Date
    var isStreaming: Bool

    enum Role: String {
        case user
        case assistant
        case system
    }

    init(id: String = UUID().uuidString, role: Role, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = Date()
        self.isStreaming = isStreaming
    }
}
