import Foundation

// MARK: - Messages from Client to Server

struct ClientAuthMessage: Codable {
    let type: String
    let token: String
    let clientInfo: ClientInfo?

    enum CodingKeys: String, CodingKey {
        case type, token
        case clientInfo = "client_info"
    }

    struct ClientInfo: Codable {
        let device: String
        let osVersion: String
        let appVersion: String
        let isCarplay: Bool

        enum CodingKeys: String, CodingKey {
            case device
            case osVersion = "os_version"
            case appVersion = "app_version"
            case isCarplay = "is_carplay"
        }
    }
}

struct ClientCommandMessage: Codable {
    let type: String
    let id: String
    let payload: Payload

    struct Payload: Codable {
        let text: String
        let source: String
        let language: String
    }
}

struct ClientPingMessage: Codable {
    let type: String
    let timestamp: String
}

struct ClientCancelMessage: Codable {
    let type: String
    let commandId: String

    enum CodingKeys: String, CodingKey {
        case type
        case commandId = "command_id"
    }
}

// MARK: - Messages from Server to Client

enum ServerMessage {
    case authOk(sessionId: String)
    case authError(code: String, message: String)
    case responseStart(commandId: String, responseId: String)
    case responseChunk(commandId: String, responseId: String, text: String, chunkIndex: Int)
    case responseEnd(commandId: String, responseId: String, fullText: String, processingTimeMs: Int?)
    case status(openclawStatus: String)
    case error(code: String, message: String, commandId: String?)
    case pong(timestamp: String)
    case unknown(type: String)

    static func parse(from data: Data) -> ServerMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "auth_ok":
            let sessionId = json["session_id"] as? String ?? ""
            return .authOk(sessionId: sessionId)

        case "auth_error":
            let code = json["code"] as? String ?? "UNKNOWN"
            let message = json["message"] as? String ?? "Authentication failed"
            return .authError(code: code, message: message)

        case "response_start":
            let commandId = json["command_id"] as? String ?? ""
            let responseId = json["response_id"] as? String ?? ""
            return .responseStart(commandId: commandId, responseId: responseId)

        case "response_chunk":
            let commandId = json["command_id"] as? String ?? ""
            let responseId = json["response_id"] as? String ?? ""
            let payload = json["payload"] as? [String: Any]
            let text = payload?["text"] as? String ?? ""
            let chunkIndex = payload?["chunk_index"] as? Int ?? 0
            return .responseChunk(commandId: commandId, responseId: responseId, text: text, chunkIndex: chunkIndex)

        case "response_end":
            let commandId = json["command_id"] as? String ?? ""
            let responseId = json["response_id"] as? String ?? ""
            let payload = json["payload"] as? [String: Any]
            let fullText = payload?["full_text"] as? String ?? ""
            let metadata = payload?["metadata"] as? [String: Any]
            let processingTime = metadata?["processing_time_ms"] as? Int
            return .responseEnd(commandId: commandId, responseId: responseId, fullText: fullText, processingTimeMs: processingTime)

        case "status":
            let status = json["openclaw_status"] as? String ?? "unknown"
            return .status(openclawStatus: status)

        case "error":
            let code = json["code"] as? String ?? "UNKNOWN"
            let message = json["message"] as? String ?? "Unknown error"
            let commandId = json["command_id"] as? String
            return .error(code: code, message: message, commandId: commandId)

        case "pong":
            let timestamp = json["timestamp"] as? String ?? ""
            return .pong(timestamp: timestamp)

        default:
            return .unknown(type: type)
        }
    }
}
