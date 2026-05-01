import SwiftUI

struct LogViewerView: View {
    let configService: RemoteConfigService

    @State private var sourceFilter: String = "all"
    @State private var levelFilter: String = "info"
    @State private var autoScroll: Bool = true

    private let sources = ["all", "relay", "openclaw", "agent"]
    private let levels = ["debug", "info", "warn", "error"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Fuente", selection: $sourceFilter) {
                    ForEach(sources, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)

                Picker("Nivel", selection: $levelFilter) {
                    ForEach(levels, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: levelFilter) { _, _ in Task { await resubscribe() } }

                Spacer()

                Button {
                    autoScroll.toggle()
                } label: {
                    Image(systemName: autoScroll ? "arrow.down.to.line.compact" : "arrow.down")
                }
                .help(autoScroll ? "Auto-scroll ON" : "Auto-scroll OFF")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredEntries) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: configService.logBuffer.count) { _, _ in
                    if autoScroll, let last = filteredEntries.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        Task {
                            _ = try? await configService.action("clear_logs")
                            configService.clearLogBuffer()
                        }
                    } label: {
                        Label("Limpiar logs en servidor", systemImage: "trash")
                    }
                    Button {
                        configService.clearLogBuffer()
                    } label: {
                        Label("Limpiar buffer local", systemImage: "eraser")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await resubscribe()
        }
        .onDisappear {
            Task { await configService.unsubscribeLogs() }
        }
    }

    private var filteredEntries: [LogEntry] {
        configService.logBuffer.filter { entry in
            sourceFilter == "all" || entry.source == sourceFilter
        }
    }

    private func resubscribe() async {
        if configService.logsSubscribed {
            await configService.unsubscribeLogs()
        }
        try? await configService.subscribeLogs(
            source: sourceFilter == "all" ? nil : sourceFilter,
            level: levelFilter,
            lines: 200
        )
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeOnly)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(entry.source.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0))
                .font(.caption2.monospaced())
                .foregroundStyle(sourceColor)
            Text(entry.level.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0))
                .font(.caption2.monospaced())
                .foregroundStyle(levelColor)
            Text(entry.message)
                .font(.caption.monospaced())
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timeOnly: String {
        // ISO timestamp → just HH:mm:ss
        guard let dot = entry.timestamp.firstIndex(of: "T") else { return entry.timestamp }
        let after = entry.timestamp.index(after: dot)
        let end = entry.timestamp.firstIndex(of: ".") ?? entry.timestamp.firstIndex(of: "Z") ?? entry.timestamp.endIndex
        return String(entry.timestamp[after..<end])
    }

    private var levelColor: Color {
        switch entry.level {
        case "error": return .red
        case "warn":  return .orange
        case "debug": return .gray
        default:      return .blue
        }
    }

    private var sourceColor: Color {
        switch entry.source {
        case "openclaw": return .purple
        case "relay":    return .teal
        default:         return .secondary
        }
    }
}
