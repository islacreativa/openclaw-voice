import SwiftUI

struct SystemStatusView: View {
    let configService: RemoteConfigService

    @State private var refreshTimer: Timer?
    @State private var isLoading = false

    var body: some View {
        List {
            if let mac = configService.systemStatus?.mac {
                Section("Mac") {
                    KeyValueRow(label: "Hostname", value: mac.hostname)
                    KeyValueRow(label: "OS", value: mac.osVersion)
                    KeyValueRow(
                        label: "CPU",
                        value: mac.cpuUsage.map { "\(String(format: "%.1f", $0))%" } ?? "—",
                        secondary: mac.cpuCores.map { "\($0) cores" }
                    )
                    KeyValueRow(
                        label: "RAM",
                        value: "\(String(format: "%.1f", mac.memoryUsedGb)) / \(String(format: "%.1f", mac.memoryTotalGb)) GB"
                    )
                    if let disk = mac.diskFreeGb {
                        KeyValueRow(label: "Disco libre", value: "\(String(format: "%.0f", disk)) GB")
                    }
                    if let battery = mac.batteryPercent {
                        let charging = mac.batteryCharging == true ? " ⚡" : ""
                        KeyValueRow(label: "Batería", value: "\(battery)%\(charging)")
                    }
                    KeyValueRow(label: "Uptime", value: "\(String(format: "%.1f", mac.uptimeHours)) h")
                }
            }

            if let oc = configService.systemStatus?.openclaw {
                Section("OpenClaw") {
                    HStack {
                        Circle()
                            .fill(oc.status == "running" ? .green : (oc.status == "starting" ? .yellow : .gray))
                            .frame(width: 10, height: 10)
                        Text(oc.status.capitalized)
                        Spacer()
                        if oc.processing {
                            Text("procesando")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let agent = oc.currentAgent {
                        KeyValueRow(label: "Agente", value: agent.name)
                    }
                    if let session = oc.sessionId {
                        KeyValueRow(label: "Sesión", value: String(session.prefix(12)) + "…")
                    }
                }
            }

            if let relay = configService.systemStatus?.relay {
                Section("Relay") {
                    KeyValueRow(label: "Estado", value: relay.status)
                    KeyValueRow(label: "Conexiones", value: "\(relay.connections)")
                    KeyValueRow(label: "Uptime", value: formatUptime(relay.uptimeSeconds))
                    KeyValueRow(label: "Mensajes", value: "\(relay.messagesProcessed)")
                    KeyValueRow(label: "Memoria", value: "\(String(format: "%.1f", relay.memoryMb)) MB")
                }
            }

            if let net = configService.systemStatus?.network {
                Section("Red") {
                    KeyValueRow(label: "IP local", value: net.localIp)
                    if let ts = net.tailscaleIp {
                        KeyValueRow(label: "Tailscale", value: ts)
                    } else {
                        KeyValueRow(label: "Tailscale", value: net.tailscaleStatus)
                    }
                }
            }

            if configService.systemStatus == nil {
                Section { Text(isLoading ? "Cargando…" : "Sin datos").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Sistema")
        .refreshable { await refresh() }
        .task {
            await refresh()
            startAutoRefresh()
        }
        .onDisappear { stopAutoRefresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        try? await configService.get(section: "system")
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in try? await configService.get(section: "system") }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func formatUptime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

struct KeyValueRow: View {
    let label: String
    let value: String
    var secondary: String? = nil

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            VStack(alignment: .trailing) {
                Text(value).foregroundStyle(.secondary)
                if let secondary {
                    Text(secondary).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
