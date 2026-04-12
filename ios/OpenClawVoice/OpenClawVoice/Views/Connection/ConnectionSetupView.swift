import SwiftUI
import AVFoundation

struct ConnectionSetupView: View {
    let appState: AppState
    let webSocket: WebSocketManager
    let onConnected: () -> Void

    @State private var serverURL: String = ""
    @State private var authToken: String = ""
    @State private var elevenLabsKey: String = ""
    @State private var isConnecting = false
    @State private var showManualEntry = true
    @State private var showQRScanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo area
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)
                        Text("OpenClaw Voice")
                            .font(.largeTitle.bold())
                        Text("Connect to your Mac")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Scan QR button
                    Button {
                        showQRScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                            Text("Scan QR Code")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    Text("or enter manually")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Manual entry
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Server Connection") {
                            VStack(spacing: 12) {
                                TextField("wss://192.168.1.X:8765/ws", text: $serverURL)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)

                                TextField("Auth Token", text: $authToken)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            .padding(.top, 8)
                        }

                        GroupBox("ElevenLabs (Voice)") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("API Key (optional)", text: $elevenLabsKey)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)

                                Text("Get your key at elevenlabs.io")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal)

                    // Connect button
                    Button {
                        connect()
                    } label: {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isConnecting ? "Connecting..." : "Connect")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canConnect ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canConnect || isConnecting)
                    .padding(.horizontal)

                    // Status
                    if case .error(let msg) = appState.connectionStatus {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                serverURL = appState.serverURL
                authToken = appState.authToken
                elevenLabsKey = appState.elevenLabsAPIKey
            }
            .onChange(of: appState.connectionStatus) { _, newValue in
                if newValue.isConnected {
                    isConnecting = false
                    onConnected()
                }
                if case .error = newValue {
                    isConnecting = false
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView(
                    onResult: { value in
                        if let pairing = PairingData.parse(from: value) {
                            serverURL = pairing.url
                            authToken = pairing.token
                        }
                        showQRScanner = false
                    },
                    onCancel: { showQRScanner = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    private var canConnect: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !authToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func connect() {
        isConnecting = true

        // Save to state
        appState.serverURL = serverURL
        appState.authToken = authToken
        appState.elevenLabsAPIKey = elevenLabsKey

        // Save to keychain
        try? KeychainManager.shared.save(serverURL, forKey: Constants.keychainServerURLKey)
        try? KeychainManager.shared.save(authToken, forKey: Constants.keychainTokenKey)
        if !elevenLabsKey.isEmpty {
            try? KeychainManager.shared.save(elevenLabsKey, forKey: Constants.keychainElevenLabsKey)
        }

        // Connect
        webSocket.connect(to: serverURL, token: authToken)

        // Request speech permissions
        Task {
            let speechRecognizer = SpeechRecognizer(locale: appState.speechLocale)
            _ = await speechRecognizer.requestAuthorization()
        }
    }
}
