import SwiftUI

struct RootView: View {
    @StateObject private var coordinator = GameCoordinator()
    @State private var displayName: String?
    @State private var age: Int?

    var body: some View {
        Group {
            if displayName == nil || age == nil {
                AgeGateView { name, playerAge in
                    LocalPlayerStore.shared.displayName = name
                    LocalPlayerStore.shared.age = playerAge
                    displayName = name
                    age = playerAge
                }
            } else if let session = coordinator.observer.session {
                switch session.status {
                case .waiting:
                    LobbyView(session: session)
                case .active, .paused:
                    GameplayView(session: session)
                case .completed:
                    LeaderboardView(session: session)
                }
            } else {
                HomeView(displayName: displayName ?? "", age: age ?? 0)
            }
        }
        .environmentObject(coordinator)
        .onAppear {
            displayName = LocalPlayerStore.shared.displayName
            age = LocalPlayerStore.shared.age
            Task {
                _ = try? await FirebaseClient.shared.ensureSignedIn()
                coordinator.rejoinCachedGameIfAvailable()
            }
        }
    }
}
