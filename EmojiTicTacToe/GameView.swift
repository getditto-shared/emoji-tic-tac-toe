// GameView.swift
// EmojiTicTacToe
//
// The game board. Shows a player identity bar ("You vs Opponent"),
// a turn indicator, the 3x3 grid, and win/draw/play-again UI.
// Dismisses automatically if the opponent leaves.

import SwiftUI

struct GameView: View {
    @Environment(DittoManager.self) var manager
    @Environment(\.dismiss) private var dismiss

    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let game = manager.game
        let finished = game?.status == GameStatus.finished.rawValue

        VStack(spacing: 20) {
            if let game {
                // Shows "You (emoji) vs Opponent (emoji)" so you always
                // know which side you are, even when it's not your turn.
                playerBar(game)
                statusBanner(game)
            }

            // 3x3 game board. Each cell is a large tappable square.
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<9, id: \.self) { i in
                    CellView(emoji: game?.board[i] ?? "") {
                        Task { await manager.makeMove(index: i) }
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.blue.opacity(0.08)))
            .padding(.horizontal)

            // Result + play again button (only when game is finished).
            if finished, let game {
                resultView(game)
                    .transition(.scale.combined(with: .opacity))

                Button {
                    Task { await manager.resetGame() }
                } label: {
                    Label("Play Again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.horizontal)
            }

            Spacer()
        }
        .animation(.spring(duration: 0.4), value: game?.board)
        .animation(.spring(duration: 0.4), value: game?.status)
        .navigationTitle("Emoji Tic-Tac-Toe")
        .navigationBarTitleDisplayMode(.inline)
        // Navigate back to the lobby when the opponent leaves or the game
        // document is deleted by the other player.
        .onChange(of: manager.opponentLeft) { _, left in
            if left { dismiss() }
        }
        .onChange(of: manager.game == nil) { _, isNil in
            if isNil && !manager.opponentLeft { dismiss() }
        }
    }

    // MARK: - Player Identity Bar

    /// Displays both players' emoji side by side with "You" and "Opponent"
    /// labels. The active player's side gets a subtle colored background.
    @ViewBuilder
    func playerBar(_ game: Game) -> some View {
        let myEmoji = (manager.myRole == "X") ? game.playerXEmoji : game.playerOEmoji
        let theirEmoji = (manager.myRole == "X") ? game.playerOEmoji : game.playerXEmoji
        let isMyTurn = (game.currentTurn == manager.myRole)

        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(myEmoji).font(.system(size: 36))
                Text("You").font(.caption2.bold()).foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isMyTurn ? Color.green.opacity(0.1) : .clear)
            .cornerRadius(12)

            Text("vs")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            VStack(spacing: 2) {
                Text(theirEmoji.isEmpty ? "?" : theirEmoji).font(.system(size: 36))
                Text("Opponent").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(!isMyTurn && !theirEmoji.isEmpty ? Color.orange.opacity(0.1) : .clear)
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    // MARK: - Status Banner

    @ViewBuilder
    func statusBanner(_ game: Game) -> some View {
        if game.status == GameStatus.waiting.rawValue {
            VStack(spacing: 4) {
                ProgressView()
                Text("Waiting for opponent...")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
        } else if game.status == GameStatus.playing.rawValue {
            let mine = (game.currentTurn == manager.myRole)
            let emoji = (game.currentTurn == "X") ? game.playerXEmoji : game.playerOEmoji
            Text(mine ? "Your turn \(emoji)" : "Opponent's turn \(emoji)")
                .font(.headline)
                .foregroundStyle(mine ? .green : .orange)
        }
    }

    // MARK: - Result View

    @ViewBuilder
    func resultView(_ game: Game) -> some View {
        let iWon = (game.winner == manager.myRole)
        let isDraw = (game.winner == "draw")
        VStack {
            Text(isDraw ? "🤝" : iWon ? "🎉" : "😢")
                .font(.system(size: 60))
            Text(isDraw ? "It's a Draw!" : iWon ? "You Win!" : "You Lose!")
                .font(.title.bold())
                .foregroundColor(isDraw ? .primary : iWon ? .green : .red)
        }
    }
}

// MARK: - Board Cell

/// A single cell in the 3x3 grid. Shows the placed emoji with a pop-in
/// animation, or an empty tappable square.
struct CellView: View {
    let emoji: String
    let onTap: () -> Void
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button {
            if emoji.isEmpty { onTap() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(emoji.isEmpty
                          ? Color(uiColor: .systemGray5)
                          : Color.orange.opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)

                if !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 48))
                        .scaleEffect(scale)
                        .onAppear {
                            scale = 0.3
                            withAnimation(.spring(duration: 0.35, bounce: 0.5)) {
                                scale = 1.0
                            }
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
