import SwiftUI

struct JoinGameView: View {
    @EnvironmentObject private var coordinator: GameCoordinator
    @Environment(\.dismiss) private var dismiss

    let displayName: String
    let age: Int

    @State private var code: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter the 6-character code shown on the driver's screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                TextField("ABC123", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.system(.largeTitle, design: .monospaced))
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).stroke(.secondary))
                    .padding(.horizontal, 32)

                Button {
                    Task {
                        await coordinator.joinExistingGame(code: code, displayName: displayName, age: age)
                        if coordinator.errorMessage == nil { dismiss() }
                    }
                } label: {
                    Text("Join")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(code.trimmingCharacters(in: .whitespaces).count < 6)
                .padding(.horizontal, 32)

                if let errorMessage = coordinator.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Join a Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
