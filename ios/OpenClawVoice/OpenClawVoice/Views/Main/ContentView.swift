import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var webSocket = WebSocketManager()
    @State private var speechRecognizer = SpeechRecognizer()
    @State private var audioPlayer = AudioPlayerService()
    @State private var elevenLabs: ElevenLabsService?
    @State private var chatViewModel: ChatViewModel?
    @State private var showConnectionSetup = false

    var body: some View {
        Group {
            if webSocket.connectionStatus.isConnected, let chatVM = chatViewModel {
                MainTabView(chatViewModel: chatVM, appState: appState, webSocket: webSocket)
            } else {
                ConnectionSetupView(appState: appState, webSocket: webSocket) {
                    setupServices()
                }
            }
        }
        .onAppear {
            loadSavedConfig()
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

        if let apiKey = KeychainManager.shared.load(forKey: Constants.keychainElevenLabsKey) {
            appState.elevenLabsAPIKey = apiKey
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

    var body: some View {
        TabView {
            ChatView(viewModel: chatViewModel, appState: appState)
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView(appState: appState, webSocket: webSocket)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
