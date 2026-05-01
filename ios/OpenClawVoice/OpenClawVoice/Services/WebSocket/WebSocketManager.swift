import Foundation
import Observation
import UIKit

@Observable
final class WebSocketManager {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var sessionDelegate: SelfSignedCertDelegate?
    private var candidateURLs: [URL] = []
    private var currentCandidateIndex = 0
    private var authToken: String = ""
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    var connectionStatus: ConnectionStatus = .disconnected
    var onMessage: ((ServerMessage) -> Void)?

    // MARK: - Connect

    func connect(to urlString: String, token: String, fallback: String? = nil) {
        var urls: [URL] = []
        if let u = URL(string: urlString) { urls.append(u) }
        if let fb = fallback?.trimmingCharacters(in: .whitespaces),
           !fb.isEmpty, fb != urlString,
           let u = URL(string: fb) {
            urls.append(u)
        }
        guard !urls.isEmpty else {
            connectionStatus = .error("Invalid URL")
            return
        }

        self.candidateURLs = urls
        self.currentCandidateIndex = 0
        self.authToken = token
        self.reconnectAttempt = 0
        performConnect()
    }

    private func performConnect() {
        connectionStatus = .connecting

        // Create session that trusts self-signed certs. Retain the delegate
        // strongly so its challenge methods remain available.
        let delegate = SelfSignedCertDelegate()
        self.sessionDelegate = delegate
        let operationQueue = OperationQueue()
        operationQueue.qualityOfService = .userInitiated
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: operationQueue)

        guard currentCandidateIndex < candidateURLs.count else { return }
        let url = candidateURLs[currentCandidateIndex]
        print("[WS] Connecting to \(url) (candidate \(currentCandidateIndex + 1)/\(candidateURLs.count))")
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        connectionStatus = .authenticating
        sendAuth()
        startReceiving()
        startConnectTimeout()
    }

    // Times out the current candidate if we don't receive authOk in time.
    // On timeout, we try the next candidate (e.g. Tailscale fallback).
    private func startConnectTimeout() {
        connectTimeoutTask?.cancel()
        let attemptIndex = currentCandidateIndex
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.connectAttemptTimeout))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentCandidateIndex == attemptIndex,
                      !self.connectionStatus.isConnected else { return }
                print("[WS] Candidate \(attemptIndex + 1) timed out, trying next")
                self.tryNextCandidateOrFail(reason: "Connection timed out")
            }
        }
    }

    private func tryNextCandidateOrFail(reason: String) {
        connectTimeoutTask?.cancel()
        receiveTask?.cancel()
        webSocket?.cancel(with: .abnormalClosure, reason: nil)
        webSocket = nil

        if currentCandidateIndex + 1 < candidateURLs.count {
            currentCandidateIndex += 1
            performConnect()
        } else {
            connectionStatus = .error(reason)
        }
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

    /// Send a raw JSON-serializable dictionary. Used by RemoteConfigService.
    func sendRaw(_ dict: [String: Any]) {
        sendJSON(dict)
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
                    print("[WS] Receive error: \(error.localizedDescription)")
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
            connectTimeoutTask?.cancel()
            connectionStatus = .connected
            reconnectAttempt = 0
            DisconnectNotifier.shared.notifyReconnected()
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
        // If we're still negotiating a candidate (not yet connected), failure
        // here means try the next URL instead of entering reconnect loop.
        if !connectionStatus.isConnected {
            if case .reconnecting = connectionStatus {} else {
                tryNextCandidateOrFail(reason: "Connection failed")
                return
            }
        }

        heartbeatTask?.cancel()
        // After a successful connection, restart from the first candidate so
        // the next session prefers the primary URL again (network may have
        // changed).
        currentCandidateIndex = 0
        reconnectAttempt += 1

        if reconnectAttempt > Constants.reconnectMaxAttempts {
            connectionStatus = .error("Max reconnection attempts reached")
            DisconnectNotifier.shared.notifyDisconnected(reason: "Se perdió la conexión con el Mac.")
            return
        }

        if reconnectAttempt == 1 {
            DisconnectNotifier.shared.notifyDisconnected(reason: "Intentando reconectar con el Mac…")
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
        connectTimeoutTask?.cancel()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        connectionStatus = .disconnected
    }
}

// MARK: - Self-signed cert delegate
//
// Accepts any TLS cert from the relay server. The relay uses a self-signed
// cert generated on first run; this delegate bypasses the default trust
// evaluation to allow it.
//
// Handles BOTH session-level and task-level authentication challenges
// because URLSessionWebSocketTask routes server-trust challenges via the
// task delegate, not the session delegate, on some iOS versions.

private class SelfSignedCertDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        print("[TLS] Session challenge: \(challenge.protectionSpace.authenticationMethod) host=\(challenge.protectionSpace.host)")
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        print("[TLS] Task challenge: \(challenge.protectionSpace.authenticationMethod) host=\(challenge.protectionSpace.host)")
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[WS] Opened with protocol: \(`protocol` ?? "none")")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[WS] Closed: \(closeCode)")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("[WS] Task completed with error: \(error)")
        }
    }

    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            print("[TLS] Accepting self-signed cert for host: \(challenge.protectionSpace.host)")
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
