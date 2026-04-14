// GameModel.swift
// EmojiTicTacToe
//
// Data types for game state: emoji team definitions, game status enum,
// and the Game struct that holds all state for a single match.
// This file is pure Swift with no UI or Ditto dependencies.

import Foundation

// MARK: - Emoji Teams
// Each team provides a set of themed emoji. The first emoji in the array
// is used as the player's piece on the board and as the team's icon.

struct EmojiTeam: Identifiable, Hashable {
    let id: String
    let name: String
    let emojis: [String]
}

let emojiTeams: [EmojiTeam] = [
    .init(id: "cats",   name: "Cats",   emojis: ["🐱", "😺", "😸", "🙀", "😻"]),
    .init(id: "dogs",   name: "Dogs",   emojis: ["🐶", "🐕", "🦮", "🐩", "🐕‍🦺"]),
    .init(id: "ocean",  name: "Ocean",  emojis: ["🐙", "🦑", "🐠", "🐡", "🦈"]),
    .init(id: "space",  name: "Space",  emojis: ["🚀", "🌟", "🪐", "👾", "🛸"]),
    .init(id: "fruits", name: "Fruits", emojis: ["🍎", "🍊", "🍋", "🍇", "🍓"]),
]

// MARK: - Game Status

/// Lifecycle of a game document:
///   waiting   -> A game has been created, host is waiting for an opponent.
///   playing   -> Two players are actively playing.
///   finished  -> A winner or draw has been determined.
///   abandoned -> One player left mid-game; the other is notified.
enum GameStatus: String {
    case waiting, playing, finished, abandoned
}

// MARK: - Game

/// The complete state of a single tic-tac-toe match.
///
/// This struct is designed to round-trip through Ditto's document store:
/// `toDictionary()` serializes it for DQL INSERT, and `from(_:)` parses
/// a Ditto document value dictionary back into a Game.
struct Game: Equatable {
    var id: String
    var board: [String]         // 9 cells indexed 0-8. "" = empty, otherwise an emoji.
    var currentTurn: String     // "X" or "O" indicating whose turn it is.
    var playerXDevice: String   // Device ID of the game creator (player X).
    var playerXEmoji: String    // Emoji used by player X on the board.
    var playerODevice: String   // Device ID of the joiner (player O). Empty while waiting.
    var playerOEmoji: String    // Emoji used by player O.
    var winner: String          // "X", "O", "draw", or "" if undecided.
    var status: String          // Raw value of GameStatus.
    var abandonedBy: String     // Device ID of the player who left, or "".

    /// Sentinel value used to safely resume a CheckedContinuation when
    /// the join flow is cancelled before a real game arrives.
    static let empty = Game(
        id: "", board: [], currentTurn: "", playerXDevice: "", playerXEmoji: "",
        playerODevice: "", playerOEmoji: "", winner: "", status: "", abandonedBy: ""
    )

    /// Create a new game in the "waiting" state.
    /// `firstTurn` is randomized by the caller so neither player always goes first.
    static func new(id: String, deviceId: String, emoji: String, firstTurn: String = "X") -> Game {
        Game(
            id: id,
            board: Array(repeating: "", count: 9),
            currentTurn: firstTurn,
            playerXDevice: deviceId,
            playerXEmoji: emoji,
            playerODevice: "",
            playerOEmoji: "",
            winner: "",
            status: GameStatus.waiting.rawValue,
            abandonedBy: ""
        )
    }

    // MARK: Win / Draw Detection

    /// The eight lines that can win: 3 rows, 3 columns, 2 diagonals.
    static let winLines = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
        [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
        [0, 4, 8], [2, 4, 6],            // diagonals
    ]

    /// Check if the game has been won or drawn, updating `winner` and `status`.
    mutating func checkOutcome() {
        for line in Self.winLines {
            let a = board[line[0]]
            let b = board[line[1]]
            let c = board[line[2]]
            if !a.isEmpty && a == b && b == c {
                // The winning emoji belongs to either X or O.
                winner = (a == playerXEmoji) ? "X" : "O"
                status = GameStatus.finished.rawValue
                return
            }
        }
        // If every cell is filled and nobody won, it's a draw.
        if board.allSatisfy({ !$0.isEmpty }) {
            winner = "draw"
            status = GameStatus.finished.rawValue
        }
    }

    // MARK: Ditto Serialization

    /// Convert to a dictionary suitable for DQL INSERT/UPDATE.
    func toDictionary() -> [String: Any] {
        [
            "_id": id,
            "board": board,
            "currentTurn": currentTurn,
            "playerXDevice": playerXDevice,
            "playerXEmoji": playerXEmoji,
            "playerODevice": playerODevice,
            "playerOEmoji": playerOEmoji,
            "winner": winner,
            "status": status,
            "abandonedBy": abandonedBy,
        ]
    }

    /// Parse a Game from a Ditto document value dictionary.
    /// Returns nil if required fields are missing or invalid.
    static func from(_ d: [String: Any]) -> Game? {
        guard
            let id = d["_id"] as? String, !id.isEmpty,
            let board = d["board"] as? [String], board.count == 9,
            let turn = d["currentTurn"] as? String,
            let status = d["status"] as? String
        else { return nil }

        return Game(
            id: id,
            board: board,
            currentTurn: turn,
            playerXDevice: d["playerXDevice"] as? String ?? "",
            playerXEmoji:  d["playerXEmoji"]  as? String ?? "",
            playerODevice: d["playerODevice"] as? String ?? "",
            playerOEmoji:  d["playerOEmoji"]  as? String ?? "",
            winner:        d["winner"]        as? String ?? "",
            status:        status,
            abandonedBy:   d["abandonedBy"]   as? String ?? ""
        )
    }
}
