import SwiftUI

struct AgentPickerView: View {
    let appState: AppState
    let webSocket: WebSocketManager

    @State private var isSwitching = false
    @State private var switchingToId: String?

    var body: some View {
        List {
            Section {
                if appState.availableAgents.isEmpty {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading agents...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(appState.availableAgents) { agent in
                        Button {
                            switchAgent(to: agent)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: agentIcon(for: agent.id))
                                    .font(.title2)
                                    .foregroundStyle(agent.isCurrent ? Color.accentColor : .secondary)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .fontWeight(agent.isCurrent ? .semibold : .regular)
                                        .foregroundStyle(.primary)
                                    if let desc = agent.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if let command = agent.command {
                                        Text(command)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if switchingToId == agent.id {
                                    ProgressView().scaleEffect(0.7)
                                } else if agent.isCurrent {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(isSwitching)
                    }
                }
            } header: {
                Text("Available Agents")
            } footer: {
                Text("Switch between different AI assistants. Each agent runs as its own process on your Mac.")
            }

            Section {
                Button {
                    webSocket.sendListAgents()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .navigationTitle("AI Agent")
        .onAppear {
            if appState.availableAgents.isEmpty {
                webSocket.sendListAgents()
            }
        }
    }

    private func switchAgent(to agent: Agent) {
        guard !agent.isCurrent, !isSwitching else { return }
        isSwitching = true
        switchingToId = agent.id
        webSocket.sendSwitchAgent(agentId: agent.id)

        // Reset UI state after a delay — the onAgentsUpdate callback will refresh state
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                isSwitching = false
                switchingToId = nil
            }
        }
    }

    private func agentIcon(for agentId: String) -> String {
        switch agentId.lowercased() {
        case "openclaw": return "pawprint.circle.fill"
        case "nemoclaw": return "fish.circle.fill"
        default: return "brain.head.profile"
        }
    }
}
