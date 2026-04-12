import Foundation
import Observation
import UIKit

@Observable
final class WebSocketManager {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var serverURL: URL?
    private var authToken: String = ""
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    var connectionStatus: ConnectionStatus = .disconnected
    var onMessage: ((ServerMessage) -> Void)?

    // MARK: - Connect

    func connect(to urlString: String, token: String) {
        guard let url = URL(string: urlString) else {
            connectionStatus = .error("Invalid URL")
            return
        }

        self.serverURL = url
        self.authToken = token
        self.reconnectAttempt = 0
        performConnect()
    }

    private func performConnect() {
        connectionStatus = .connecting

        // Create session that trusts self-signed certs
        let delegate = SelfSignedCertDelegate()
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = serverURL else { return }
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        connectionStatus = .authenticating
        sendAuth()
        startReceiving()
    }

    // MARK: - Auth

    private func sendAuth() {
        let device = UIDevice.current
        let auth = ClientAuthMessage(
            type: "auth",
            token: authToken,
            clientInfo: .init(
                device: device.model,
                osVersion: device.systemVersion,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                isCarplay: false
            )
        )

        guard let data = try? JSONEncoder().encode(auth),
              let json = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(json)) { [weak self] error in
            if let error {
                self?.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Send

    func sendCommand(text: String, source: String = "text", language: String = "es") -> String {
        let commandId = UUID().uuidString
        let command = ClientCommandMessage(
            type: "command",
            id: commandId,
            payload: .init(text: text, source: source, language: language)
        )

        guard let data = try? JSONEncoder().encode(command),
              let json = String(data: data, encoding: .utf8) else { return commandId }

        webSocket?.send(.string(json)) { error in
            if let error {
                print("Send error: \(error)")
            }
        }
        return commandId
    }

    func sendCancel(commandId: String) {
        let cancel = ClientCancelMessage(type: "cancel", commandId: commandId)
        guard let data = try? JSONEncoder().encode(cancel),
              let json = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(json)) { _ in }
    }

    func sendListAgents() {
        let msg: [String: Any] = ["type": "list_agents", "id": UUID().uuidString]
        sendJSON(msg)
    }

    func sendSwitchAgent(agentId: String) {
        let msg: [String: Any] = [
            "type": "switch_agent",
            "id": UUID().uuidString,
            "payload": ["agent_id": agentId]
        ]
        sendJSON(msg)
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(json)) { _ in }
    }

    func sendPing() {
        let ping = ClientPingMessage(type: "ping", timestamp: ISO8601DateFormatter().string(from: Date()))
        guard let data = try? JSONEncoder().encode(ping),
              let json = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(json)) { _ in }
    }

    // MARK: - Receive

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let ws = self?.webSocket else { break }
                do {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let serverMsg = ServerMessage.parse(from: data) {
                            await MainActor.run {
                                self?.handleServerMessage(serverMsg)
                            }
                        }
                    case .data(let data):
                        if let serverMsg = ServerMessage.parse(from: data) {
                            await MainActor.run {
                                self?.handleServerMessage(serverMsg)
                            }
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    await MainActor.run {
                        self?.handleDisconnection()
                    }
                    break
                }
            }
        }
    }

    var onAgentsUpdate: (([Agent], Agent?) -> Void)?

    private func handleServerMessage(_ msg: ServerMessage) {
        switch msg {
        case .authOk(let sessionId, let currentAgent, let availableAgents):
            connectionStatus = .connected
            reconnectAttempt = 0
            startHeartbeat()
            print("Authenticated, session: \(sessionId)")
            onAgentsUpdate?(availableAgents, currentAgent)

        case .authError(let code, let message):
            connectionStatus = .error("\(code): \(message)")
            disconnect()

        case .agentsList(let agents, let currentId):
            let current = agents.first { $0.id == currentId }
            onAgentsUpdate?(agents, current)

        case .agentSwitched(let success, let agent, _):
            if success, let agent {
                onAgentsUpdate?([], agent)
            }

        case .pong:
            break

        default:
            break
        }

        onMessage?(msg)
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.heartbeatInterval))
                self?.sendPing()
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnection() {
        guard connectionStatus.isConnected || {
            if case .reconnecting = connectionStatus { return true }
            return false
        }() else { return }

        heartbeatTask?.cancel()
        reconnectAttempt += 1

        if reconnectAttempt > Constants.reconnectMaxAttempts {
            connectionStatus = .error("Max reconnection attempts reached")
            return
        }

        connectionStatus = .reconnecting(attempt: reconnectAttempt)

        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        Task {
            try? await Task.sleep(for: .seconds(delay))
            performConnect()
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        heartbeatTask?.cancel()
        receiveTask?.cancel()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        connectionStatus = .disconnected
    }
}

// MARK: - Self-signed cert delegate

private class SelfSignedCertDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Trust self-signed certificates for local relay server
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
