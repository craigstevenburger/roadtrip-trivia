import Combine
import Foundation
import MediaPlayer

/// Reflects GameCoordinator.shared's live session onto the CarPlay Now
/// Playing template via MPNowPlayingInfoCenter. Read-only in this pass —
/// narration and spoken-answer capture are a separate follow-up.
@MainActor
final class CarPlayGameDisplay {
    private var cancellables = Set<AnyCancellable>()
    private var becameDriverForGameCode: String?

    func start() {
        let coordinator = GameCoordinator.shared

        coordinator.$gameCode
            .sink { [weak self] gameCode in
                self?.handleGameCodeChange(gameCode)
            }
            .store(in: &cancellables)

        coordinator.observer.$session
            .sink { [weak self] session in
                self?.updateNowPlayingInfo(for: session)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        becameDriverForGameCode = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func handleGameCodeChange(_ gameCode: String?) {
        guard let gameCode, gameCode != becameDriverForGameCode else { return }
        becameDriverForGameCode = gameCode
        Task { await GameCoordinator.shared.becomeDriver() }
    }

    private func updateNowPlayingInfo(for session: GameSession?) {
        let center = MPNowPlayingInfoCenter.default()
        var info: [String: Any] = [:]

        guard let session else {
            info[MPMediaItemPropertyTitle] = "Join a game on your phone"
            center.nowPlayingInfo = info
            center.playbackState = .paused
            return
        }

        switch session.status {
        case .waiting:
            info[MPMediaItemPropertyTitle] = "Waiting for players"
            info[MPMediaItemPropertyArtist] = "Game code \(session.gameCode)"
            center.playbackState = .paused
        case .active:
            info[MPMediaItemPropertyTitle] = "Question \(session.currentQuestionIndex + 1) of \(session.questions.count)"
            info[MPMediaItemPropertyArtist] = session.currentQuestion?.category
            center.playbackState = .playing
        case .paused:
            info[MPMediaItemPropertyTitle] = "Paused for a rest stop"
            center.playbackState = .paused
        case .completed:
            let myScore = GameCoordinator.shared.playerId.flatMap { session.players[$0]?.score }
            info[MPMediaItemPropertyTitle] = "Game complete"
            if let myScore {
                info[MPMediaItemPropertyArtist] = "Final score: \(myScore)"
            }
            center.playbackState = .stopped
        }

        center.nowPlayingInfo = info
    }
}
