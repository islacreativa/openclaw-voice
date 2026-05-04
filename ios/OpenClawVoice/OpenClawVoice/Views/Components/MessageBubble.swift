import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .system ? .secondary : .primary)

                if message.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Streaming...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let latency = message.latency, message.role == .assistant {
                    LatencyBadge(latency: latency)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return .blue.opacity(0.2)
        case .assistant: return .gray.opacity(0.15)
        case .system: return .orange.opacity(0.1)
        }
    }
}

private struct LatencyBadge: View {
    let latency: ChatMessage.Latency

    var body: some View {
        HStack(spacing: 6) {
            if let total = latency.serverProcessingMs {
                metric("⌛", "\(formatMs(total))")
            }
            if let ttfb = latency.timeToFirstChunkMs {
                metric("📨", "\(formatMs(ttfb))")
            }
            if let ttfa = latency.timeToFirstAudioMs {
                metric("🔊", "\(formatMs(ttfa))")
            }
            if let transport = latency.transport, transport != "unknown" {
                Text(transport)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(icon).font(.system(size: 9))
            Text(value)
        }
    }

    private func formatMs(_ ms: Int) -> String {
        if ms >= 1000 {
            return String(format: "%.1fs", Double(ms) / 1000)
        }
        return "\(ms)ms"
    }
}
