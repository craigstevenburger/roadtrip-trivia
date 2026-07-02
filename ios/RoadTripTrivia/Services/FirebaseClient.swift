import FirebaseAuth
import FirebaseFunctions
import Foundation

enum FirebaseClientError: LocalizedError {
    case notSignedIn
    case functionError(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Couldn't connect. Check your connection and try again."
        case .functionError(let message):
            return message
        }
    }
}

/// Thin wrapper around the Cloud Functions defined in
/// backend/functions/src/gameFunctions.ts. No game logic lives here —
/// every call is a pass-through so client and (future Android) behavior
/// stays identical. See docs/api-contract.md for the full contract.
final class FirebaseClient {
    static let shared = FirebaseClient()

    private lazy var functions = Functions.functions()

    private init() {}

    // MARK: - Auth

    /// Anonymous auth only — no accounts. The resulting uid is what the
    /// backend uses as playerId (see gameFunctions.ts).
    @discardableResult
    func ensureSignedIn() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    var currentUserId: String? { Auth.auth().currentUser?.uid }

    // MARK: - Callable wrappers

    private func call(_ name: String, _ data: [String: Any]) async throws -> [String: Any] {
        do {
            let result = try await functions.httpsCallable(name).call(data)
            guard let dict = result.data as? [String: Any] else { return [:] }
            return dict
        } catch let error as NSError {
            throw FirebaseClientError.functionError(error.localizedDescription)
        }
    }

    func createGame(hostDisplayName: String, age: Int) async throws -> (gameCode: String, playerId: String) {
        try await ensureSignedIn()
        let data = try await call("createGame", ["hostDisplayName": hostDisplayName, "age": age])
        guard let gameCode = data["gameCode"] as? String, let playerId = data["playerId"] as? String else {
            throw FirebaseClientError.functionError("Unexpected response creating the game.")
        }
        return (gameCode, playerId)
    }

    func joinGame(gameCode: String, displayName: String, age: Int) async throws -> String {
        try await ensureSignedIn()
        let data = try await call("joinGame", ["gameCode": gameCode, "displayName": displayName, "age": age])
        guard let playerId = data["playerId"] as? String else {
            throw FirebaseClientError.functionError("Unexpected response joining the game.")
        }
        return playerId
    }

    func setDriver(gameCode: String) async throws {
        try await ensureSignedIn()
        _ = try await call("setDriver", ["gameCode": gameCode])
    }

    func startGame(gameCode: String) async throws {
        try await ensureSignedIn()
        _ = try await call("startGame", ["gameCode": gameCode])
    }

    func submitAnswer(gameCode: String, questionIndex: Int, choice: String?) async throws {
        try await ensureSignedIn()
        _ = try await call("submitAnswer", [
            "gameCode": gameCode,
            "questionIndex": questionIndex,
            "choice": choice ?? NSNull(),
        ])
    }

    func advanceQuestion(gameCode: String) async throws {
        try await ensureSignedIn()
        _ = try await call("advanceQuestion", ["gameCode": gameCode])
    }

    func pauseGame(gameCode: String) async throws {
        try await ensureSignedIn()
        _ = try await call("pauseGame", ["gameCode": gameCode])
    }

    func resumeGame(gameCode: String) async throws {
        try await ensureSignedIn()
        _ = try await call("resumeGame", ["gameCode": gameCode])
    }
}
