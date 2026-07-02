import SwiftUI

/// Required once per device before any game can be created or joined —
/// no account, just a locally-stored age used to compute question
/// difficulty and per-tier scoring (see docs/api-contract.md).
struct AgeGateView: View {
    let onComplete: (String, Int) -> Void

    @State private var displayName: String = ""
    @State private var ageText: String = ""

    private var age: Int? { Int(ageText) }
    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty && (age.map { $0 >= 1 && $0 <= 119 } ?? false)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Road Trip Trivia")
                    .font(.largeTitle.bold())
                Text("Before you play, tell us a little about you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. Jamie", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your age")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. 12", text: $ageText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                Text("We use age only to pick fair questions and scoring for this trip. It stays on this device.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                guard let age else { return }
                onComplete(displayName.trimmingCharacters(in: .whitespaces), age)
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}
