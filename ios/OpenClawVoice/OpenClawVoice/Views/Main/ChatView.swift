import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    let appState: AppState
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status bar
                if !appState.connectionStatus.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text(appState.connectionStatus.displayText)
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.8))
                }

                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input area
                HStack(spacing: 12) {
                    // Voice button
                    VoiceButton(
                        isListening: appState.isListening,
                        isSpeaking: appState.isSpeaking,
                        isProcessing: viewModel.isProcessing,
                        onPress: { viewModel.startVoiceCommand() },
                        onRelease: { viewModel.stopVoiceCommand() }
                    )

                    // Text input
                    TextField("Type a command...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            viewModel.sendTextCommand()
                        }

                    // Send / Cancel button
                    if viewModel.isProcessing {
                        Button {
                            viewModel.cancelCommand()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            viewModel.sendTextCommand()
                            isTextFieldFocused = false
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("OpenClaw Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Circle()
                        .fill(appState.connectionStatus.isConnected ? .green : .red)
                        .frame(width: 10, height: 10)
                }
            }
        }
    }
}
