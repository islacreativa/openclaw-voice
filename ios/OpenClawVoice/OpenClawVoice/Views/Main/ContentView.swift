import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var webSocket = WebSocketManager()
    @State private var speechRecognizer = SpeechRecognizer()
    @State private var audioPlayer = AudioPlayerService()
    @State private var elevenLabs: ElevenLabsService?
    @State private var chatViewModel: ChatViewModel?
    @State private var configService: RemoteConfigService?
    @State private var showConnectionSetup = false

    var body: some View {
        Group {
            if webSocket.connectionStatus.isConnected, let chatVM = chatViewModel, let configService {
                MainTabView(chatViewModel: chatVM, appState: appState, webSocket: webSocket, configService: configService)
            } else {
                ConnectionSetupView(appState: appState, webSocket: webSocket) {
                    setupServices()
                }
            }
        }
        .onAppear {
            loadSavedConfig()
            DisconnectNotifier.shared.requestAuthorization()
            // Pre-initialize services so the chat view model is ready on first connect
            if chatViewModel == nil {
                setupServices()
            }
        }
        .onChange(of: webSocket.connectionStatus) { _, newStatus in
            appState.connectionStatus = newStatus
        }
    }

    private func loadSavedConfig() {
        if let url = KeychainManager.shared.load(forKey: Constants.keychainServerURLKey),
           let token = KeychainManager.shared.load(forKey: Constants.keychainTokenKey) {
            appState.serverURL = url
            appState.authToken = token
        }

        if let fallback = KeychainManager.shared.load(forKey: Constants.keychainFallbackURLKey) {
            appState.fallbackURL = fallback
        }

        if let apiKey = KeychainManager.shared.load(forKey: Constants.keychainElevenLabsKey) {
            appState.elevenLabsAPIKey = apiKey
        }

        if let agentId = KeychainManager.shared.load(forKey: Constants.keychainElevenLabsAgentIdKey) {
            appState.elevenLabsAgentId = agentId
        }
    }

    private func setupServices() {
        let el = ElevenLabsService(apiKey: appState.elevenLabsAPIKey)
        self.elevenLabs = el
        self.chatViewModel = ChatViewModel(
            appState: appState,
            webSocket: webSocket,
            speechRecognizer: speechRecognizer,
            elevenLabs: el,
            audioPlayer: audioPlayer
        )

        // Remote config (logs, MCPs, system status, etc.) shares the WS.
        let cfg = RemoteConfigService(webSocket: webSocket)
        self.configService = cfg

        // Chain WS message handler so config + chat both get updates.
        let existing = webSocket.onMessage
        webSocket.onMessage = { [weak cfg] msg in
            existing?(msg)
            cfg?.handle(msg)
        }

        // Make services available to the CarPlay scene.
        CarPlayCoordinator.shared.register(
            appState: appState,
            webSocket: webSocket,
            speechRecognizer: speechRecognizer,
            elevenLabs: el,
            audioPlayer: audioPlayer
        )

        // Wire up agent updates from the server
        webSocket.onAgentsUpdate = { [weak appState] agents, currentAgent in
            Task { @MainActor in
                guard let appState else { return }
                if !agents.isEmpty {
                    appState.availableAgents = agents
                }
                if let currentAgent {
                    appState.currentAgent = currentAgent
                    // Update the matching entry in availableAgents
                    if let idx = appState.availableAgents.firstIndex(where: { $0.id == currentAgent.id }) {
                        appState.availableAgents[idx].isCurrent = true
                    }
                    for i in appState.availableAgents.indices where appState.availableAgents[i].id != currentAgent.id {
                        appState.availableAgents[i].isCurrent = false
                    }
                }
            }
        }
    }
}

struct MainTabView: View {
    let chatViewModel: ChatViewModel
    let appState: AppState
    let webSocket: WebSocketManager
    let configService: RemoteConfigService

    var body: some View {
        TabView {
            ChatView(viewModel: chatViewModel, appState: appState)
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }

            NavigationStack {
                RealtimeConversationView(appState: appState)
            }
            .tabItem {
                Label("Realtime", systemImage: "waveform.circle")
            }

            SettingsView(appState: appState, webSocket: webSocket, configService: configService)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
