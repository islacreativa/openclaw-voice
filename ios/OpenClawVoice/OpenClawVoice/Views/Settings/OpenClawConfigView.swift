import SwiftUI

struct OpenClawConfigView: View {
    let configService: RemoteConfigService

    @State private var workdirEdit: String = ""
    @State private var commandEdit: String = ""
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var pinSheet: PendingPinAction?

    var body: some View {
        Form {
            Section("Estado") {
                if let oc = configService.systemStatus?.openclaw {
                    HStack {
                        Circle()
                            .fill(oc.status == "running" ? .green : .gray)
                            .frame(width: 10, height: 10)
                        Text(oc.status.capitalized)
                        Spacer()
                        if oc.processing {
                            Text("procesando").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    perform { try await configService.action("restart_openclaw") }
                } label: {
                    Label("Reiniciar OpenClaw", systemImage: "arrow.clockwise.circle")
                }
                .disabled(isWorking)
            }

            if let agent = configService.openclawConfig?.agent {
                Section("Agente activo") {
                    KeyValueRow(label: "ID", value: agent.id)
                    KeyValueRow(label: "Nombre", value: agent.name)
                    HStack {
                        Text("Comando")
                        Spacer()
                        TextField("Command", text: $commandEdit, prompt: Text(agent.command))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Workdir")
                        Spacer()
                        TextField("Workdir", text: $workdirEdit, prompt: Text(agent.workdir))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.secondary)
                    }
                    Button("Guardar cambios") {
                        Task { await saveAgentEdits(currentCommand: agent.command, currentWorkdir: agent.workdir) }
                    }
                    .disabled(isWorking || (workdirEdit.isEmpty && commandEdit.isEmpty))
                }
            }

            if let env = configService.openclawConfig?.env, !env.isEmpty {
                Section {
                    ForEach(env.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        KeyValueRow(label: kv.key, value: kv.value)
                    }
                } header: {
                    Text("Variables de entorno (enmascaradas)")
                } footer: {
                    Text("Editar API keys requiere PIN de seguridad")
                }
            }

            if let path = configService.openclawConfig?.fileConfigPath {
                Section("Archivo de config") {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if let agents = configService.openclawConfig?.availableAgents, !agents.isEmpty {
                Section("Agentes disponibles") {
                    ForEach(agents) { a in
                        HStack {
                            Text(a.name)
                            if a.isCurrent == true {
                                Text("activo").font(.caption).foregroundStyle(.green)
                            }
                            Spacer()
                            if a.isCurrent != true {
                                Button("Cambiar") {
                                    perform {
                                        try await configService.action("switch_agent", params: ["agent_id": a.id])
                                        try await configService.get(section: "openclaw")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isWorking)
                            }
                        }
                    }
                }
            }

            if let msg = statusMessage {
                Section {
                    Text(msg).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("OpenClaw")
        .task {
            try? await configService.get(section: "openclaw")
            try? await configService.get(section: "system")
        }
        .sheet(item: $pinSheet) { pending in
            PINGateView(
                isPresented: Binding(get: { pinSheet != nil }, set: { if !$0 { pinSheet = nil } }),
                title: pending.title,
                actionLabel: "Confirmar"
            ) { pin in
                pending.run(pin)
            }
        }
    }

    private func saveAgentEdits(currentCommand: String, currentWorkdir: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            if !commandEdit.isEmpty, commandEdit != currentCommand {
                _ = try await configService.set(section: "openclaw", key: "command", value: commandEdit)
            }
            if !workdirEdit.isEmpty, workdirEdit != currentWorkdir {
                _ = try await configService.set(section: "openclaw", key: "workdir", value: workdirEdit)
            }
            statusMessage = "Guardado. Reinicia OpenClaw para aplicar."
            try? await configService.get(section: "openclaw")
            commandEdit = ""
            workdirEdit = ""
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await work()
                statusMessage = "OK"
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    struct PendingPinAction: Identifiable {
        let id = UUID()
        let title: String
        let run: (String) -> Void
    }
}
