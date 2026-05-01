import Foundation
import Observation

/// Talks to the relay's Remote Config API over the existing WebSocket.
/// Pending requests are matched by id; subscribers get streaming updates.
@MainActor
@Observable
final class RemoteConfigService {
    private let webSocket: WebSocketManager
    private var pendingRequests: [String: CheckedContinuation<ResponseEnvelope, Error>] = [:]
    private var pendingSections: [String: String] = [:]

    /// Live state mirrored from the server.
    var systemStatus: SystemStatus?
    var openclawConfig: OpenClawConfigData?
    var relayConfig: RelayConfigData?
    var mcps: [MCPInfo] = []
    var pinIsSet: Bool = false
    var lastError: String?
    var logBuffer: [LogEntry] = []
    var logsSubscribed: Bool = false
    private let logBufferLimit = 500

    init(webSocket: WebSocketManager) {
        self.webSocket = webSocket
    }

    // MARK: - Message routing

    /// Plug this into `WebSocketManager.onMessage` (or chain with the existing
    /// callback) to feed config-related messages into the service.
    func handle(_ message: ServerMessage) {
        switch message {
        case .configData(let requestId, let section, let data):
            ingestConfigData(section: section, data: data)
            if let id = requestId, let cont = pendingRequests.removeValue(forKey: id) {
                cont.resume(returning: .data(section: section, data: data))
                pendingSections.removeValue(forKey: id)
            }

        case .configResult(let requestId, let success, let message, let raw):
            if let id = requestId, let cont = pendingRequests.removeValue(forKey: id) {
                cont.resume(returning: .result(success: success, message: message, raw: raw))
                pendingSections.removeValue(forKey: id)
            }

        case .logEntry(let entry):
            logBuffer.append(entry)
            if logBuffer.count > logBufferLimit {
                logBuffer.removeFirst(logBuffer.count - logBufferLimit)
            }

        default:
            break
        }
    }

    private func ingestConfigData(section: String, data: Data) {
        let decoder = JSONDecoder()
        switch section {
        case "system":
            systemStatus = try? decoder.decode(SystemStatus.self, from: data)
        case "openclaw":
            openclawConfig = try? decoder.decode(OpenClawConfigData.self, from: data)
        case "relay":
            relayConfig = try? decoder.decode(RelayConfigData.self, from: data)
        case "mcps":
            if let list = try? decoder.decode(MCPListData.self, from: data) {
                mcps = list.installed
            }
        case "security":
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                pinIsSet = dict["pin_set"] as? Bool ?? false
            }
        default:
            break
        }
    }

    // MARK: - Requests

    enum ResponseEnvelope {
        case data(section: String, data: Data)
        case result(success: Bool, message: String, raw: Data)
    }

    @discardableResult
    func get(section: String) async throws -> ResponseEnvelope {
        let id = UUID().uuidString
        pendingSections[id] = section
        return try await sendAndAwait(["type": "config_get", "id": id, "payload": ["section": section]], id: id)
    }

    @discardableResult
    func set(section: String, key: String, value: Any, pin: String? = nil) async throws -> ResponseEnvelope {
        let id = UUID().uuidString
        var payload: [String: Any] = ["section": section, "key": key, "value": value]
        if let pin { payload["security_pin"] = pin }
        return try await sendAndAwait(["type": "config_set", "id": id, "payload": payload], id: id)
    }

    @discardableResult
    func action(_ action: String, params: [String: Any] = [:], pin: String? = nil) async throws -> ResponseEnvelope {
        let id = UUID().uuidString
        var payload: [String: Any] = ["action": action]
        for (k, v) in params { payload[k] = v }
        if let pin { payload["security_pin"] = pin }
        return try await sendAndAwait(["type": "config_action", "id": id, "payload": payload], id: id)
    }

    func subscribeLogs(source: String? = nil, level: String = "info", lines: Int = 100) async throws {
        let id = UUID().uuidString
        var payload: [String: Any] = ["level": level, "lines": lines]
        if let source { payload["source"] = source }
        _ = try await sendAndAwait(["type": "logs_subscribe", "id": id, "payload": payload], id: id)
        logsSubscribed = true
    }

    func unsubscribeLogs() async {
        let id = UUID().uuidString
        webSocket.sendRaw(["type": "logs_unsubscribe", "id": id])
        logsSubscribed = false
    }

    func clearLogBuffer() {
        logBuffer.removeAll()
    }

    private func sendAndAwait(_ dict: [String: Any], id: String, timeout: TimeInterval = 10) async throws -> ResponseEnvelope {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResponseEnvelope, Error>) in
            self.pendingRequests[id] = continuation
            self.webSocket.sendRaw(dict)

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self else { return }
                if let cont = self.pendingRequests.removeValue(forKey: id) {
                    self.pendingSections.removeValue(forKey: id)
                    cont.resume(throwing: RemoteConfigError.timeout)
                }
            }
        }
    }
}

enum RemoteConfigError: LocalizedError {
    case timeout
    case server(String)
    case decode

    var errorDescription: String? {
        switch self {
        case .timeout: return "Tiempo de espera agotado"
        case .server(let msg): return msg
        case .decode: return "No se pudo decodificar la respuesta"
        }
    }
}
