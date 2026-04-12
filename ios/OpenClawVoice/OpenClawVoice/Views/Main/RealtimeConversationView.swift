import SwiftUI

struct RealtimeConversationView: View {
    let appState: AppState
    @State private var service = ElevenLabsConversationalService()
    @State private var showSetup = false
    @State private var tempAgentId: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Status indicator
            stateIndicator

            Spacer()

            // Transcripts
            VStack(spacing: 16) {
                if !service.userTranscript.isEmpty {
                    transcriptCard(
                        icon: "person.fill",
                        label: "You",
                        text: service.userTranscript,
                        color: .blue
                    )
                }

                if !service.agentResponse.isEmpty {
                    transcriptCard(
                        icon: "waveform.circle.fill",
                        label: "Agent",
                        text: service.agentResponse,
                        color: .purple
                    )
                }
            }
            .padding(.horizontal)

            Spacer()

            // Start/stop button
            actionButton

            if let error = service.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .navigationTitle("Real-time Voice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSetup) {
            NavigationStack {
                Form {
                    Section("ElevenLabs Agent") {
                        TextField("Agent ID", text: $tempAgentId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Text("Find your Agent ID at elevenlabs.io/app/conversational-ai")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Setup")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSetup = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            appState.elevenLabsAgentId = tempAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
                            try? KeychainManager.shared.save(appState.elevenLabsAgentId, forKey: Constants.keychainElevenLabsAgentIdKey)
                            showSetup = false
                        }
                    }
                }
            }
        }
        .onDisappear {
            service.stop()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        ZStack {
            Circle()
                .fill(stateColor.opacity(0.15))
                .frame(width: 180, height: 180)

            if case .listening = service.state {
                Circle()
                    .stroke(Color.red.opacity(0.4), lineWidth: 4)
                    .frame(width: 180, height: 180)
                    .scaleEffect(1.05)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: service.state)
            }

            Circle()
                .fill(stateColor)
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: stateIcon)
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                }
        }
    }

    private var stateColor: Color {
        switch service.state {
        case .idle: return .gray
        case .connecting: return .orange
        case .connected: return .blue
        case .listening: return .red
        case .agentSpeaking: return .green
        case .error: return .red
        }
    }

    private var stateIcon: String {
        switch service.state {
        case .idle: return "mic.slash"
        case .connecting: return "hourglass"
        case .connected: return "dot.radiowaves.left.and.right"
        case .listening: return "waveform"
        case .agentSpeaking: return "speaker.wave.3.fill"
        case .error: return "exclamationmark.triangle"
        }
    }

    @ViewBuilder
    private func transcriptCard(icon: String, label: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                Text(text)
                    .font(.body)
            }
            Spacer()
        }
        .padding()
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var actionButton: some View {
        if service.state == .idle || (service.state.isErrorState) {
            Button {
                if appState.elevenLabsAgentId.isEmpty {
                    tempAgentId = appState.elevenLabsAgentId
                    showSetup = true
                } else {
                    startConversation()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: appState.elevenLabsAgentId.isEmpty ? "gear" : "mic.fill")
                    Text(appState.elevenLabsAgentId.isEmpty ? "Configure Agent" : "Start Conversation")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
        } else {
            Button {
                service.stop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                    Text("End Conversation")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
        }
    }

    private func startConversation() {
        Task {
            await service.start(
                apiKey: appState.elevenLabsAPIKey,
                agentId: appState.elevenLabsAgentId
            )
        }
    }
}

private extension ElevenLabsConversationalService.State {
    var isErrorState: Bool {
        if case .error = self { return true }
        return false
    }
}
