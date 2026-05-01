import Foundation

// MARK: - System status

struct SystemStatus: Codable, Equatable {
    var mac: MacInfo
    var openclaw: OpenClawInfo
    var relay: RelayInfo
    var network: NetworkInfo

    struct MacInfo: Codable, Equatable {
        var hostname: String
        var osVersion: String
        var cpuUsage: Double?
        var cpuCores: Int?
        var memoryUsedGb: Double
        var memoryTotalGb: Double
        var diskFreeGb: Double?
        var batteryPercent: Int?
        var batteryCharging: Bool?
        var uptimeHours: Double

        enum CodingKeys: String, CodingKey {
            case hostname
            case osVersion = "os_version"
            case cpuUsage = "cpu_usage"
            case cpuCores = "cpu_cores"
            case memoryUsedGb = "memory_used_gb"
            case memoryTotalGb = "memory_total_gb"
            case diskFreeGb = "disk_free_gb"
            case batteryPercent = "battery_percent"
            case batteryCharging = "battery_charging"
            case uptimeHours = "uptime_hours"
        }
    }

    struct OpenClawInfo: Codable, Equatable {
        var status: String
        var processing: Bool
        var currentAgent: AgentRef?
        var sessionId: String?

        enum CodingKeys: String, CodingKey {
            case status, processing
            case currentAgent = "current_agent"
            case sessionId = "session_id"
        }
    }

    struct AgentRef: Codable, Equatable {
        var id: String
        var name: String
    }

    struct RelayInfo: Codable, Equatable {
        var status: String
        var connections: Int
        var uptimeSeconds: Int
        var messagesProcessed: Int
        var memoryMb: Double

        enum CodingKeys: String, CodingKey {
            case status, connections
            case uptimeSeconds = "uptime_seconds"
            case messagesProcessed = "messages_processed"
            case memoryMb = "memory_mb"
        }
    }

    struct NetworkInfo: Codable, Equatable {
        var localIp: String
        var tailscaleIp: String?
        var tailscaleStatus: String

        enum CodingKeys: String, CodingKey {
            case localIp = "local_ip"
            case tailscaleIp = "tailscale_ip"
            case tailscaleStatus = "tailscale_status"
        }
    }
}

// MARK: - OpenClaw config

struct OpenClawConfigData: Codable, Equatable {
    var agent: AgentDetails?
    var availableAgents: [AvailableAgent]
    var currentAgentId: String?
    var fileConfig: [String: AnyCodable]?
    var fileConfigPath: String?
    var env: [String: String]

    enum CodingKeys: String, CodingKey {
        case agent
        case availableAgents = "available_agents"
        case currentAgentId = "current_agent_id"
        case fileConfig = "file_config"
        case fileConfigPath = "file_config_path"
        case env
    }

    struct AgentDetails: Codable, Equatable {
        var id: String
        var name: String
        var command: String
        var args: [String]
        var workdir: String
        var description: String
    }

    struct AvailableAgent: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var description: String?
        var command: String?
        var isCurrent: Bool?
    }
}

// MARK: - Relay config

struct RelayConfigData: Codable, Equatable {
    var port: Int
    var heartbeatIntervalMs: Int
    var commandTimeoutMs: Int
    var localUrl: String
    var tailscaleUrl: String?
    var elevenlabsApiKeySet: Bool
    var elevenlabsApiKeyMasked: String
    var certsPath: String
    var authTokenMasked: String

    enum CodingKeys: String, CodingKey {
        case port
        case heartbeatIntervalMs = "heartbeat_interval_ms"
        case commandTimeoutMs = "command_timeout_ms"
        case localUrl = "local_url"
        case tailscaleUrl = "tailscale_url"
        case elevenlabsApiKeySet = "elevenlabs_api_key_set"
        case elevenlabsApiKeyMasked = "elevenlabs_api_key_masked"
        case certsPath = "certs_path"
        case authTokenMasked = "auth_token_masked"
    }
}

// MARK: - MCPs

struct MCPListData: Codable, Equatable {
    var installed: [MCPInfo]
}

struct MCPInfo: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var status: String
    var version: String?
    var toolsCount: Int?
    var lastUsed: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, version
        case toolsCount = "tools_count"
        case lastUsed = "last_used"
    }
}

// MARK: - Logs

struct LogEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var level: String
    var source: String
    var message: String
    var timestamp: String

    enum CodingKeys: String, CodingKey {
        case level, source, message, timestamp
    }

    var levelColor: String {
        switch level {
        case "error": return "red"
        case "warn": return "orange"
        case "debug": return "gray"
        default: return "primary"
        }
    }
}

// MARK: - Result

struct ConfigActionResult: Codable, Equatable {
    var success: Bool
    var message: String
    var requiresPin: Bool?
    var requiresRestart: Bool?

    enum CodingKeys: String, CodingKey {
        case success, message
        case requiresPin = "requires_pin"
        case requiresRestart = "requires_restart"
    }
}

// MARK: - AnyCodable (for arbitrary file_config payload)

struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let b as Bool: try container.encode(b)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let s as String: try container.encode(s)
        case let arr as [Any]: try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull): return true
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        default: return false
        }
    }
}
