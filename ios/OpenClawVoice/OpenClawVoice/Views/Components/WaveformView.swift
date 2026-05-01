import SwiftUI

// Animated bar waveform. Drive with any 0..1 `level` (e.g. VAD audioLevel
// while listening, or a simulated animation while the assistant speaks).
// When `level` is nil the view shows an idle sine wobble so it still looks
// alive without having to feed real data.
struct WaveformView: View {
    var level: Float?
    var color: Color = .accentColor
    var barCount: Int = 12
    var minHeight: CGFloat = 4
    var maxHeight: CGFloat = 40

    @State private var phase: Double = 0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: height(for: index))
                    .animation(.easeInOut(duration: 0.08), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase += 0.18
        }
        .accessibilityLabel("Audio level indicator")
    }

    private func height(for index: Int) -> CGFloat {
        let wobble = sin(phase + Double(index) * 0.6) * 0.5 + 0.5
        let amplitude: Double
        if let level {
            amplitude = min(1.0, max(0.05, Double(level) * 6.0))
        } else {
            amplitude = 0.35
        }
        let normalized = wobble * amplitude
        return minHeight + CGFloat(normalized) * (maxHeight - minHeight)
    }
}
