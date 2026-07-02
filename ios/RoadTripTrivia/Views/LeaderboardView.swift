import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var coordinator: GameCoordinator
    let session: GameSession

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Final Scores")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                ForEach(Array(session.sortedPlayers.enumerated()), id: \.element.id) { index, player in
                    HStack {
                        Text("\(index + 1).")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        Text(player.displayName)
                            .font(.body.weight(index == 0 ? .bold : .regular))
                        Spacer()
                        Text("\(player.score) pts")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.08)))
            .padding(.horizontal, 32)

            Spacer()

            Button {
                coordinator.leaveGame()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}
