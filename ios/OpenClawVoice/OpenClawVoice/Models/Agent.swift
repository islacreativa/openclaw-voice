import Foundation

struct Agent: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let command: String?
    var isCurrent: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, command
        case isCurrent = "isCurrent"
    }
}
