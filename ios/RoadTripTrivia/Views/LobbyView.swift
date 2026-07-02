import SwiftUI

struct LobbyView: View {
    @EnvironmentObject private var coordinator: GameCoordinator
    let session: GameSession

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 4) {
                Text("Game Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.gameCode)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .kerning(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Players (\(session.players.count))")
                    .font(.headline)
                ForEach(session.sortedPlayers) { player in
                    HStack {
                        Text(player.displayName)
                        if player.isDriver {
                            Image(systemName: "car.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Driver")
                        }
                        Spacer()
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.08)))
            .padding(.horizontal, 32)

            Spacer()

            if coordinator.isHost {
                Button {
                    Task { await coordinator.startGame() }
                } label: {
                    Text("Start Game")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
            } else {
                Text("Waiting for the host to start the game…")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = coordinator.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Leave Game", role: .destructive) {
                coordinator.leaveGame()
            }
            .padding(.bottom, 24)
        }
    }
}
