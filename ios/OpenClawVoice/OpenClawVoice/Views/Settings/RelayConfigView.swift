import SwiftUI

struct RelayConfigView: View {
    let configService: RemoteConfigService

    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var showingPin = false
    @State private var pinPurpose: PinPurpose?
    @State private var portEdit: String = ""
    @State private var elevenLabsKeyEdit: String = ""

    enum PinPurpose: Identifiable {
        case regenerateToken, restartRelay
        var id: String {
            switch self {
            case .regenerateToken: return "regen"
            case .restartRelay:    return "restart"
            }
        }
        var title: String {
            switch self {
            case .regenerateToken: return "Confirmar regeneración de token"
            case .restartRelay:    return "Confirmar reinicio del relay"
            }
        }
    }

    var body: some View {
        Form {
            if let relay = configService.relayConfig {
                Section("Conexión") {
                    KeyValueRow(label: "URL local", value: relay.localUrl)
                    if let ts = relay.tailscaleUrl {
                        KeyValueRow(label: "Tailscale", value: ts)
                    }
                    KeyValueRow(label: "Token", value: relay.authTokenMasked)
                    KeyValueRow(label: "Heartbeat", value: "\(relay.heartbeatIntervalMs / 1000)s")
                }

                Section("Puerto") {
                    HStack {
                        Text("Puerto")
                        Spacer()
                        TextField("Port", text: $portEdit, prompt: Text("\(relay.port)"))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 100)
                    }
                    Button("Guardar puerto") {
                        Task {
                            guard let p = Int(portEdit), p > 0 else { return }
                            await runAndRefresh {
                                _ = try await configService.set(section: "relay", key: "port", value: p)
                            }
                            portEdit = ""
                        }
                    }
                    .disabled(isWorking || portEdit.isEmpty)
                }

                Section("Acciones") {
                    Button(role: .destructive) {
                        if configService.pinIsSet {
                            pinPurpose = .regenerateToken
                            showingPin = true
                        } else {
                            run { _ = try await configService.action("regenerate_token") }
                        }
                    } label: {
                        Label("Regenerar token de auth", systemImage: "key.viewfinder")
                    }

                    Button {
                        if configService.pinIsSet {
                            pinPurpose = .restartRelay
                            showingPin = true
                        } else {
                            run { _ = try await configService.action("restart_relay") }
                        }
                    } label: {
                        Label("Reiniciar relay server", systemImage: "arrow.clockwise.circle")
                    }
                }

                if relay.elevenlabsApiKeySet || !elevenLabsKeyEdit.isEmpty {
                    Section("ElevenLabs (servidor)") {
                        KeyValueRow(label: "Estado", value: relay.elevenlabsApiKeySet ? "configurada" : "no configurada")
                        SecureField("Nueva API Key", text: $elevenLabsKeyEdit)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Guardar API Key") {
                            run {
                                _ = try await configService.set(section: "voice", key: "elevenlabs_api_key", value: elevenLabsKeyEdit)
                                elevenLabsKeyEdit = ""
                            }
                        }
                        .disabled(isWorking || elevenLabsKeyEdit.isEmpty)
                    }
                }
            } else {
                Section { Text("Cargando…").foregroundStyle(.secondary) }
            }

            if let msg = statusMessage {
                Section { Text(msg).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Relay")
        .task { try? await configService.get(section: "relay") }
        .sheet(item: $pinPurpose) { purpose in
            PINGateView(
                isPresented: $showingPin,
                title: purpose.title,
                actionLabel: "Confirmar"
            ) { pin in
                pinPurpose = nil
                run {
                    let action: String = (purpose == .regenerateToken) ? "regenerate_token" : "restart_relay"
                    _ = try await configService.action(action, pin: pin)
                }
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await work()
                statusMessage = "OK"
                try? await configService.get(section: "relay")
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func runAndRefresh(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            statusMessage = "OK"
            try? await configService.get(section: "relay")
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
