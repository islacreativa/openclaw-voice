import SwiftUI

/// Sheet that asks the user for the security PIN before performing a sensitive
/// remote action. The PIN is sent to the relay; not cached locally.
struct PINGateView: View {
    @Binding var isPresented: Bool
    let title: String
    let actionLabel: String
    let onConfirm: (String) -> Void

    @State private var pin: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top)

                SecureField("PIN (4-6 dígitos)", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.password)
                    .multilineTextAlignment(.center)
                    .font(.title2)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($focused)
                    .padding(.horizontal)

                Button(actionLabel) {
                    onConfirm(pin)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidPin)

                Spacer()
            }
            .padding()
            .navigationTitle("Verificación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { isPresented = false }
                }
            }
            .onAppear { focused = true }
        }
    }

    private var isValidPin: Bool {
        pin.count >= 4 && pin.count <= 6 && pin.allSatisfy(\.isNumber)
    }
}
