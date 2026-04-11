import SwiftUI

struct VoiceButton: View {
    let isListening: Bool
    let isSpeaking: Bool
    let isProcessing: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressing = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Pulse ring when listening
            if isListening {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 3)
                    .scaleEffect(pulseScale)
                    .frame(width: 52, height: 52)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            pulseScale = 1.3
                        }
                    }
                    .onDisappear {
                        pulseScale = 1.0
                    }
            }

            Circle()
                .fill(buttonColor)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .scaleEffect(isPressing ? 0.9 : 1.0)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressing && !isProcessing {
                        isPressing = true
                        withAnimation(.easeInOut(duration: 0.1)) {}
                        onPress()
                    }
                }
                .onEnded { _ in
                    isPressing = false
                    onRelease()
                }
        )
        .disabled(isProcessing || isSpeaking)
        .animation(.easeInOut(duration: 0.15), value: isPressing)
    }

    private var buttonColor: Color {
        if isProcessing { return .orange }
        if isSpeaking { return .green }
        if isListening { return .red }
        return .blue
    }

    private var iconName: String {
        if isProcessing { return "hourglass" }
        if isSpeaking { return "speaker.wave.3" }
        if isListening { return "waveform" }
        return "mic.fill"
    }
}
