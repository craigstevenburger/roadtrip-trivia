import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: GameCoordinator
    @State private var showJoinSheet = false

    let displayName: String
    let age: Int

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Text("Road Trip Trivia")
                    .font(.largeTitle.bold())
                Text("Welcome back, \(displayName).")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await coordinator.startNewGame(displayName: displayName, age: age) }
                } label: {
                    Label("Start a Game", systemImage: "car.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showJoinSheet = true
                } label: {
                    Label("Join a Game", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)

            if coordinator.isLoading {
                ProgressView().padding(.top, 8)
            }
            if let errorMessage = coordinator.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinGameView(displayName: displayName, age: age)
        }
    }
}
