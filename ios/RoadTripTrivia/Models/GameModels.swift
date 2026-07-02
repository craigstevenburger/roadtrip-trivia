import FirebaseFirestore
import Foundation

// Mirrors backend/functions/src/types.ts and docs/api-contract.md exactly.
// All game-state mutation happens server-side via Cloud Functions; these
// types are read-only projections of the Firestore document.

enum GameStatus: String, Codable {
    case waiting
    case active
    case paused
    case completed
}

enum Difficulty: String, Codable {
    case easy
    case medium
    case hard
}

enum AgeTier: String, Codable {
    case child
    case teen
    case adult

    /// Mirrors difficulty.ts ageTierFor(). UI-only convenience — the
    /// server recomputes and stores the authoritative tier at join time.
    static func forAge(_ age: Int) -> AgeTier {
        if age < 14 { return .child }
        if age <= 18 { return .teen }
        return .adult
    }
}

struct GameQuestion: Codable, Identifiable {
    var id: String
    var category: String
    var difficulty: Difficulty
    var question: String
    var correctAnswer: String
    var options: [String]
}

struct PlayerAnswer: Codable {
    var choice: String?
    var correct: Bool
    var pointsEarned: Int
    var answeredAt: Timestamp
}

struct Player: Codable, Identifiable {
    var id: String { playerId }

    // playerId is the key under GameSession.players, not a field in the
    // Firestore document value — excluding it from CodingKeys makes
    // decoding use the default "" instead of failing on a missing key.
    // GameSession.sortedPlayers fills in the real value from the map key.
    var playerId: String = ""
    var displayName: String
    var age: Int
    var ageTier: AgeTier
    var isDriver: Bool
    var score: Int
    var answers: [String: PlayerAnswer]

    enum CodingKeys: String, CodingKey {
        case displayName, age, ageTier, isDriver, score, answers
    }
}

struct GameSession: Codable, Identifiable {
    @DocumentID var id: String?
    var status: GameStatus
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
    var pausedAt: Timestamp?
    var currentQuestionIndex: Int
    var questionStartedAt: Timestamp?
    var hostDeviceId: String
    var driverPlayerId: String?
    var questions: [GameQuestion]
    var players: [String: Player]

    var gameCode: String { id ?? "" }

    var currentQuestion: GameQuestion? {
        guard currentQuestionIndex >= 0, currentQuestionIndex < questions.count else { return nil }
        return questions[currentQuestionIndex]
    }

    var sortedPlayers: [Player] {
        players.map { key, value in
            var p = value
            p.playerId = key
            return p
        }.sorted { $0.score > $1.score }
    }
}
