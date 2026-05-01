import SwiftUI

struct SecurityView: View {
    let configService: RemoteConfigService

    @State private var newPin: String = ""
    @State private var confirmPin: String = ""
    @State private var currentPin: String = ""
    @State private var statusMessage: String?
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: configService.pinIsSet ? "lock.fill" : "lock.open")
                        .foregroundStyle(configService.pinIsSet ? .green : .secondary)
                    Text(configService.pinIsSet ? "PIN configurado" : "Sin PIN")
                    Spacer()
                }
            } header: {
                Text("Estado")
            } footer: {
                Text("El PIN protege acciones sensibles: regenerar token, instalar/desinstalar MCPs, modificar API keys.")
            }

            if !configService.pinIsSet {
                Section("Configurar PIN") {
                    SecureField("Nuevo PIN (4-6 dígitos)", text: $newPin)
                        .keyboardType(.numberPad)
                    SecureField("Confirmar PIN", text: $confirmPin)
                        .keyboardType(.numberPad)
                    Button("Guardar PIN") {
                        run {
                            guard newPin == confirmPin else {
                                statusMessage = "Los PINs no coinciden"
                                return
                            }
                            _ = try await configService.action("set_pin", params: ["new_pin": newPin])
                            newPin = ""
                            confirmPin = ""
                            try? await configService.get(section: "security")
                        }
                    }
                    .disabled(isWorking || !isValid(newPin) || newPin != confirmPin)
                }
            } else {
                Section("Cambiar PIN") {
                    SecureField("PIN actual", text: $currentPin)
                        .keyboardType(.numberPad)
                    SecureField("Nuevo PIN", text: $newPin)
                        .keyboardType(.numberPad)
                    Button("Cambiar PIN") {
                        run {
                            _ = try await configService.action(
                                "change_pin",
                                params: ["new_pin": newPin],
                                pin: currentPin
                            )
                            currentPin = ""
                            newPin = ""
                        }
                    }
                    .disabled(isWorking || !isValid(currentPin) || !isValid(newPin))
                }

                Section {
                    Button(role: .destructive) {
                        run {
                            _ = try await configService.action("clear_pin", pin: currentPin)
                            currentPin = ""
                            try? await configService.get(section: "security")
                        }
                    } label: {
                        Label("Eliminar PIN", systemImage: "lock.slash")
                    }
                    .disabled(isWorking || !isValid(currentPin))
                }
            }

            if let msg = statusMessage {
                Section { Text(msg).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Seguridad")
        .task { try? await configService.get(section: "security") }
    }

    private func isValid(_ s: String) -> Bool {
        s.count >= 4 && s.count <= 6 && s.allSatisfy(\.isNumber)
    }

    private func run(_ work: @escaping () async throws -> Void) {
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
}
