import SwiftUI

struct MCPManagementView: View {
    let configService: RemoteConfigService

    @State private var statusMessage: String?

    var body: some View {
        List {
            if configService.mcps.isEmpty {
                ContentUnavailableView(
                    "Sin MCPs",
                    systemImage: "puzzlepiece.extension",
                    description: Text("No se ha encontrado un archivo de MCPs en este Mac, o aún no hay ninguno instalado.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Activos") {
                    ForEach(configService.mcps.filter { $0.status == "running" }) { mcp in
                        MCPRow(mcp: mcp, configService: configService)
                    }
                }
                Section("Inactivos") {
                    ForEach(configService.mcps.filter { $0.status != "running" }) { mcp in
                        MCPRow(mcp: mcp, configService: configService)
                    }
                }
            }

            if let msg = statusMessage {
                Section { Text(msg).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("MCPs")
        .refreshable { try? await configService.get(section: "mcps") }
        .task { try? await configService.get(section: "mcps") }
    }
}

private struct MCPRow: View {
    let mcp: MCPInfo
    let configService: RemoteConfigService

    var body: some View {
        HStack {
            Circle()
                .fill(mcp.status == "running" ? .green : .gray)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(mcp.name).font(.headline)
                if let count = mcp.toolsCount {
                    Text("\(count) herramientas").font(.caption).foregroundStyle(.secondary)
                } else if let v = mcp.version {
                    Text("v\(v)").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { mcp.status == "running" },
                set: { newValue in
                    Task {
                        let action = newValue ? "enable_mcp" : "disable_mcp"
                        _ = try? await configService.action(action, params: ["mcp_id": mcp.id])
                        try? await configService.get(section: "mcps")
                    }
                }
            ))
            .labelsHidden()
        }
    }
}
