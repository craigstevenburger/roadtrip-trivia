import SwiftUI

/// Phone-side gameplay for the current player (tap-to-answer). This is
/// the Phase 2 "phone-only" loop used to validate the game engine — the
/// voice-only CarPlay driver experience (Phase 3) plugs into the same
/// submitAnswer/advanceQuestion Cloud Functions.
struct GameplayView: View {
    @EnvironmentObject private var coordinator: GameCoordinator
    let session: GameSession

    @State private var selectedChoice: String?
    @State private var timeRemaining: Int = 20
    @State private var advancedForIndex: Int?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let answerWindowSeconds = 20

    private var myPlayerId: String? { coordinator.playerId }
    private var myAnswer: PlayerAnswer? {
        guard let myPlayerId else { return nil }
        return session.players[myPlayerId]?.answers["\(session.currentQuestionIndex)"]
    }
    private var hasAnswered: Bool { myAnswer != nil }
    private var allPlayersAnswered: Bool {
        session.players.values.allSatisfy { $0.answers["\(session.currentQuestionIndex)"] != nil }
    }

    var body: some View {
        if session.status == .paused {
            pausedView
        } else {
            activeGameplayView
        }
    }

    private var pausedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Game Paused for a Rest Stop")
                .font(.title2.bold())
            Text("Question \(session.currentQuestionIndex + 1) of \(session.questions.count) — pick up where you left off whenever you're ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if coordinator.motionSuggestion == .resume {
                motionBanner(
                    message: "Looks like you're moving again — resume the game?",
                    actionTitle: "Resume"
                )
            }
            Button {
                Task { await coordinator.resumeGame() }
            } label: {
                Text("Resume Game")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var activeGameplayView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Question \(session.currentQuestionIndex + 1) of \(session.questions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(timeRemaining)s", systemImage: "timer")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(timeRemaining <= 5 ? .red : .secondary)
                Button {
                    Task { await coordinator.pauseGame() }
                } label: {
                    Image(systemName: "pause.circle")
                }
            }
            .padding(.horizontal)

            if let question = session.currentQuestion {
                Text(question.question)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(question.options, id: \.self) { option in
                        answerButton(option: option, question: question)
                    }
                }
                .padding(.horizontal)
            } else {
                Text("Waiting for the next question…")
                    .foregroundStyle(.secondary)
            }

            if hasAnswered {
                Text(allPlayersAnswered ? "Everyone's answered — next question coming up." : "Answer locked in. Waiting on other players…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            LeaderboardStrip(session: session)
        }
        .padding(.top)
        .onAppear { resetForCurrentQuestion() }
        .onChange(of: session.currentQuestionIndex) { _ in resetForCurrentQuestion() }
        .onReceive(timer) { _ in tick() }
        .safeAreaInset(edge: .bottom) {
            if coordinator.motionSuggestion == .pause {
                motionBanner(
                    message: "Looks like you've stopped — pause for a rest stop?",
                    actionTitle: "Pause"
                )
            }
        }
    }

    @ViewBuilder
    private func motionBanner(message: String, actionTitle: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.leading)
            Spacer()
            Button("Not now") {
                coordinator.dismissMotionSuggestion()
            }
            .font(.footnote)
            Button(actionTitle) {
                Task { await coordinator.acceptMotionSuggestion() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.12)))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func answerButton(option: String, question: GameQuestion) -> some View {
        let isSelected = selectedChoice == option
        Button {
            guard !hasAnswered else { return }
            selectedChoice = option
            Task {
                await coordinator.submitAnswer(questionIndex: session.currentQuestionIndex, choice: option)
            }
        } label: {
            Text(option)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )
        }
        .disabled(hasAnswered)
        .foregroundStyle(.primary)
    }

    private func resetForCurrentQuestion() {
        selectedChoice = myAnswer?.choice
        guard let started = session.questionStartedAt?.dateValue() else {
            timeRemaining = answerWindowSeconds
            return
        }
        let elapsed = Int(Date().timeIntervalSince(started))
        timeRemaining = max(0, answerWindowSeconds - elapsed)
    }

    private func tick() {
        guard let started = session.questionStartedAt?.dateValue() else { return }
        let elapsed = Int(Date().timeIntervalSince(started))
        timeRemaining = max(0, answerWindowSeconds - elapsed)

        let windowElapsed = timeRemaining == 0
        guard coordinator.isHost, advancedForIndex != session.currentQuestionIndex else { return }
        guard windowElapsed || allPlayersAnswered else { return }

        advancedForIndex = session.currentQuestionIndex
        Task { await coordinator.advanceQuestion() }
    }
}

private struct LeaderboardStrip: View {
    let session: GameSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(session.sortedPlayers) { player in
                    VStack(spacing: 2) {
                        Text(player.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                        Text("\(player.score)")
                            .font(.headline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.08)))
                }
            }
            .padding(.horizontal)
        }
    }
}
