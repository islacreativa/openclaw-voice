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
            if appState.connectionStatus.isConnected, let chatVM = chatViewModel {
                MainTabView(chatViewModel: chatVM, appState: appState, webSocket: webSocket)
            } else {
                ConnectionSetupView(appState: appState, webSocket: webSocket) {
                    setupServices()
                }
            }
        }
        .onAppear {
            loadSavedConfig()
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
