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
    case authOk(sessionId: String, currentAgent: Agent?, availableAgents: [Agent])
    case authError(code: String, message: String)
    case responseStart(commandId: String, responseId: String)
    case responseChunk(commandId: String, responseId: String, text: String, chunkIndex: Int)
    case responseEnd(commandId: String, responseId: String, fullText: String, processingTimeMs: Int?, timeToFirstChunkMs: Int?, transport: String?)
    case status(openclawStatus: String)
    case error(code: String, message: String, commandId: String?)
    case pong(timestamp: String)
    case agentsList(agents: [Agent], currentAgentId: String?)
    case agentSwitched(success: Bool, agent: Agent?, error: String?)
    case configData(requestId: String?, section: String, data: Data)
    case configResult(requestId: String?, success: Bool, message: String, raw: Data)
    case logEntry(entry: LogEntry)
    case unknown(type: String)

    static func parse(from data: Data) -> ServerMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "auth_ok":
            let sessionId = json["session_id"] as? String ?? ""
            let serverInfo = json["server_info"] as? [String: Any]
            var currentAgent: Agent?
            var availableAgents: [Agent] = []

            if let agentDict = serverInfo?["current_agent"] as? [String: Any] {
                currentAgent = parseAgent(from: agentDict)
            }
            if let agentsArr = serverInfo?["available_agents"] as? [[String: Any]] {
                availableAgents = agentsArr.compactMap { parseAgent(from: $0) }
            }
            return .authOk(sessionId: sessionId, currentAgent: currentAgent, availableAgents: availableAgents)

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
            let ttfb = metadata?["time_to_first_chunk_ms"] as? Int
            let transport = metadata?["transport"] as? String
            return .responseEnd(commandId: commandId, responseId: responseId, fullText: fullText,
                                processingTimeMs: processingTime, timeToFirstChunkMs: ttfb, transport: transport)

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

        case "agents_list":
            let payload = json["payload"] as? [String: Any]
            let agentsArr = payload?["agents"] as? [[String: Any]] ?? []
            let currentId = payload?["current_agent_id"] as? String
            let agents = agentsArr.compactMap { parseAgent(from: $0) }
            return .agentsList(agents: agents, currentAgentId: currentId)

        case "agent_switched":
            let payload = json["payload"] as? [String: Any]
            let success = payload?["success"] as? Bool ?? false
            let error = payload?["error"] as? String
            var agent: Agent?
            if let agentDict = payload?["agent"] as? [String: Any] {
                agent = parseAgent(from: agentDict)
            }
            return .agentSwitched(success: success, agent: agent, error: error)

        case "config_data":
            let requestId = json["request_id"] as? String
            let payload = json["payload"] as? [String: Any] ?? [:]
            let section = payload["section"] as? String ?? "unknown"
            let dataPayload = payload["data"] ?? [:]
            let dataBytes = (try? JSONSerialization.data(withJSONObject: dataPayload)) ?? Data()
            return .configData(requestId: requestId, section: section, data: dataBytes)

        case "config_result":
            let requestId = json["request_id"] as? String
            let payload = json["payload"] as? [String: Any] ?? [:]
            let success = payload["success"] as? Bool ?? false
            let message = payload["message"] as? String ?? ""
            return .configResult(requestId: requestId, success: success, message: message, raw: data)

        case "log_entry":
            let payload = json["payload"] as? [String: Any] ?? [:]
            let entry = LogEntry(
                level: payload["level"] as? String ?? "info",
                source: payload["source"] as? String ?? "relay",
                message: payload["message"] as? String ?? "",
                timestamp: payload["timestamp"] as? String ?? ""
            )
            return .logEntry(entry: entry)

        default:
            return .unknown(type: type)
        }
    }

    private static func parseAgent(from dict: [String: Any]) -> Agent? {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String else { return nil }
        return Agent(
            id: id,
            name: name,
            description: dict["description"] as? String,
            command: dict["command"] as? String,
            isCurrent: dict["isCurrent"] as? Bool ?? false
        )
    }
}
