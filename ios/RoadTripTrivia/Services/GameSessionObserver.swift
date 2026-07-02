import FirebaseFirestore
import Foundation

/// Realtime listener on games/{gameCode}. Firestore security rules only
/// allow reads once the caller's uid appears in the doc's `players` map
/// (see backend/firestore.rules), so this should only be started after a
/// successful createGame/joinGame call.
@MainActor
final class GameSessionObserver: ObservableObject {
    @Published private(set) var session: GameSession?
    @Published private(set) var error: Error?

    private var listener: ListenerRegistration?

    func start(gameCode: String) {
        stop()
        listener = Firestore.firestore()
            .collection("games")
            .document(gameCode)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.error = error
                    return
                }
                guard let snapshot, snapshot.exists else {
                    self.session = nil
                    return
                }
                do {
                    self.session = try snapshot.data(as: GameSession.self)
                } catch {
                    self.error = error
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    deinit {
        listener?.remove()
    }
}
