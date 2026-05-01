import SwiftUI

struct SettingsView: View {
    let appState: AppState
    let webSocket: WebSocketManager
    let configService: RemoteConfigService

    @State private var elevenLabsKey: String = ""
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            List {
                // Agent section
                Section {
                    NavigationLink {
                        AgentPickerView(appState: appState, webSocket: webSocket)
                    } label: {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.purple)
                            Text("AI Agent")
                            Spacer()
                            Text(appState.currentAgent?.name ?? "—")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Active Agent")
                }

                // Remote configuration (relay-side)
                Section("Mac (remoto)") {
                    NavigationLink {
                        SystemStatusView(configService: configService)
                    } label: {
                        Label("Sistema", systemImage: "cpu")
                    }
                    NavigationLink {
                        OpenClawConfigView(configService: configService)
                    } label: {
                        Label("OpenClaw", systemImage: "brain")
                    }
                    NavigationLink {
                        MCPManagementView(configService: configService)
                    } label: {
                        Label("MCPs", systemImage: "puzzlepiece.extension")
                    }
                    NavigationLink {
                        LogViewerView(configService: configService)
                    } label: {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink {
                        RelayConfigView(configService: configService)
                    } label: {
                        Label("Relay Server", systemImage: "server.rack")
                    }
                    NavigationLink {
                        SecurityView(configService: configService)
                    } label: {
                        Label("Seguridad (PIN)", systemImage: configService.pinIsSet ? "lock.fill" : "lock.open")
                    }
                }

                // Connection section
                Section("Connection") {
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.connectionStatus.isConnected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(appState.connectionStatus.displayText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Server")
                        Spacer()
                        Text(appState.serverURL)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if appState.connectionStatus.isConnected {
                        Button("Disconnect", role: .destructive) {
                            webSocket.disconnect()
                        }
                    } else {
                        Button("Reconnect") {
                            webSocket.connect(
                                to: appState.serverURL,
                                token: appState.authToken,
                                fallback: appState.fallbackURL
                            )
                        }
                    }
                }

                // Voice section
                Section("Voice") {
                    Picker("Language (STT)", selection: Binding(
                        get: { appState.speechLocale },
                        set: { appState.speechLocale = $0 }
                    )) {
                        Text("Spanish").tag("es-ES")
                        Text("English").tag("en-US")
                        Text("Catalan").tag("ca-ES")
                    }

                    Picker("Listening Mode", selection: Binding(
                        get: { appState.listeningMode },
                        set: { appState.listeningMode = $0 }
                    )) {
                        ForEach(AppState.ListeningMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }

                // ElevenLabs section
                Section("ElevenLabs (TTS)") {
                    HStack {
                        if showKey {
                            TextField("API Key", text: $elevenLabsKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("API Key", text: $elevenLabsKey)
                        }
                        Button(showKey ? "Hide" : "Show") {
                            showKey.toggle()
                        }
                        .font(.caption)
                    }

                    Button("Save API Key") {
                        appState.elevenLabsAPIKey = elevenLabsKey
                        try? KeychainManager.shared.save(elevenLabsKey, forKey: Constants.keychainElevenLabsKey)
                    }
                    .disabled(elevenLabsKey.isEmpty)
                }

                // About section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Project")
                        Spacer()
                        Text("DCK Studios")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                elevenLabsKey = appState.elevenLabsAPIKey
            }
        }
    }
}
