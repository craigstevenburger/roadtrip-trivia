import Foundation

/// Owns the current game's identity (code + this device's playerId) and
/// the realtime session observer. One instance lives for the app's
/// lifetime and is handed down via the environment.
@MainActor
final class GameCoordinator: ObservableObject {
    @Published var gameCode: String?
    @Published var playerId: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let observer = GameSessionObserver()

    private let client = FirebaseClient.shared
    private let localStore = LocalPlayerStore.shared

    var isHost: Bool {
        guard let session = observer.session, let playerId else { return false }
        return session.hostDeviceId == playerId
    }

    func startNewGame(displayName: String, age: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (code, pid) = try await client.createGame(hostDisplayName: displayName, age: age)
            attach(gameCode: code, playerId: pid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func joinExistingGame(code: String, displayName: String, age: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let pid = try await client.joinGame(gameCode: normalized, displayName: displayName, age: age)
            attach(gameCode: normalized, playerId: pid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called at launch if a game code was cached locally (e.g. after a
    /// rest-stop pause) so the player can rejoin without re-typing it.
    func rejoinCachedGameIfAvailable() {
        guard let code = localStore.lastGameCode, let playerId = client.currentUserId else { return }
        attach(gameCode: code, playerId: playerId)
    }

    func startGame() async {
        guard let gameCode else { return }
        errorMessage = nil
        do {
            try await client.startGame(gameCode: gameCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitAnswer(questionIndex: Int, choice: String?) async {
        guard let gameCode else { return }
        do {
            try await client.submitAnswer(gameCode: gameCode, questionIndex: questionIndex, choice: choice)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func advanceQuestion() async {
        guard let gameCode else { return }
        do {
            try await client.advanceQuestion(gameCode: gameCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rest-stop pause. The game doc (and this device's cached game code)
    /// survives so the trip can resume later — see docs/api-contract.md.
    func pauseGame() async {
        guard let gameCode else { return }
        do {
            try await client.pauseGame(gameCode: gameCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeGame() async {
        guard let gameCode else { return }
        do {
            try await client.resumeGame(gameCode: gameCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leaveGame() {
        observer.stop()
        gameCode = nil
        playerId = nil
        localStore.clearLastGameCode()
    }

    private func attach(gameCode: String, playerId: String) {
        self.gameCode = gameCode
        self.playerId = playerId
        localStore.lastGameCode = gameCode
        observer.start(gameCode: gameCode)
    }
}
