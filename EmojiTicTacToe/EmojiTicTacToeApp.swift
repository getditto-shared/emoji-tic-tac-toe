// EmojiTicTacToeApp.swift
// EmojiTicTacToe
//
// App entry point and DittoManager: the single class that owns all
// interaction with the Ditto SDK. No other file imports DittoSwift.
//
// Architecture:
//   - DittoManager is @Observable so SwiftUI views react to state changes.
//   - Game state lives in a single Ditto document in the "games" collection.
//   - Sync is restricted to P2P only (SmallPeersOnly) so game data never
//     leaves the local mesh of nearby devices.
//   - The lobby observer watches for "waiting" games from other devices.
//   - The game observer watches the active game document and drives the UI.

import SwiftUI
import DittoSwift

// MARK: - DittoManager

@Observable
final class DittoManager {
    let ditto: Ditto

    /// The active game being played (nil when in the lobby).
    var game: Game?

    /// This device's role in the current game: "X" (creator) or "O" (joiner).
    var myRole = ""

    /// Unique identifier for this device.
    var deviceId = ""

    /// True once Ditto has started syncing successfully.
    var isReady = false

    /// Games from nearby peers that are waiting for a second player.
    /// Drives the "Join Nearby Game" list in the lobby.
    var nearbyGames: [Game] = []

    /// When true, the GameView should dismiss back to the lobby.
    /// Set when the opponent leaves or the game document is deleted.
    var opponentLeft = false

    // Private observer/subscription references. Stored so they stay alive
    // for the duration of the game and can be cancelled on leave.
    private var observer: DittoStoreObserver?
    private var subscription: DittoSyncSubscription?
    private var lobbyObserver: DittoStoreObserver?
    private var lobbySubscription: DittoSyncSubscription?

    // Used by joinGame() to await the first game document from the mesh
    // without sleeping. The observer callback resumes this continuation
    // the moment data arrives.
    private var gameContinuation: CheckedContinuation<Game, Never>?

    // MARK: Initialization

    init() {
        // Online Playground identity for development/demos.
        // Credentials come from DittoConfig.swift (gitignored).
        ditto = Ditto(
            identity: DittoIdentity.onlinePlayground(
                appID: DittoConfig.appID,
                token: DittoConfig.playgroundToken,
                enableDittoCloudSync: false,
                customAuthURL: URL(string: DittoConfig.authURL)
            )
        )
        deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    /// Finish async setup: configure sync scopes and start the mesh.
    /// Called once from a .task modifier on the root view.
    func start() async {
        do {
            // Allow flexible document schemas during development.
            _ = try await ditto.store.execute(
                query: "ALTER SYSTEM SET DQL_STRICT_MODE = false"
            )
            // Restrict "games" to peer-to-peer sync only. No cloud involved.
            // This means games only appear on devices that can reach each
            // other directly over Bluetooth, WiFi Direct, or LAN.
            _ = try await ditto.store.execute(
                query: "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :scopes",
                arguments: ["scopes": ["games": "SmallPeersOnly"]]
            )
            try ditto.sync.start()
            isReady = true
            startLobbyObserver()
        } catch {
            print("Ditto failed to start: \(error.localizedDescription)")
        }
    }

    // MARK: - Lobby: Discover Nearby Games

    /// Subscribe to all games with status "waiting" so they replicate to
    /// this device via the P2P mesh. An observer updates `nearbyGames`
    /// whenever the result set changes.
    private func startLobbyObserver() {
        let query = "SELECT * FROM games WHERE status = 'waiting'"
        lobbySubscription = try? ditto.sync.registerSubscription(query: query)
        lobbyObserver = try? ditto.store.registerObserver(query: query) { [weak self] result in
            let games = result.items.compactMap { item -> Game? in
                let dict = item.value.compactMapValues { $0 }
                return Game.from(dict)
            }
            Task { @MainActor in
                guard let self else { return }
                // Filter out our own waiting game so we don't see it in the list.
                self.nearbyGames = games.filter { $0.playerXDevice != self.deviceId }
            }
        }
    }

    // MARK: - Create Game

    /// Create a new game and wait for an opponent to join.
    /// The creator is always player X. First turn is randomized.
    func createGame(emoji: String) async {
        let id = String(UUID().uuidString.prefix(6).uppercased())
        let firstTurn = Bool.random() ? "X" : "O"
        let g = Game.new(id: id, deviceId: deviceId, emoji: emoji, firstTurn: firstTurn)
        myRole = "X"
        game = g

        _ = try? await ditto.store.execute(
            query: "INSERT INTO games DOCUMENTS (:newGame) ON ID CONFLICT DO UPDATE",
            arguments: ["newGame": g.toDictionary()]
        )
        startObserving(gameId: id)
    }

    // MARK: - Join Game

    /// Join an existing game by ID.
    ///
    /// Flow:
    ///  1. Start observing the game document (triggers mesh sync).
    ///  2. Await the first observer callback via CheckedContinuation (no sleep).
    ///  3. Validate the game isn't already full.
    ///  4. Pick an emoji: honor the player's selection unless it conflicts
    ///     with the host, in which case pick a different one automatically.
    ///  5. Write player O's details and set status to "playing".
    ///
    /// Returns false if the game is already full.
    @discardableResult
    func joinGame(id: String, preferredEmoji: String) async -> Bool {
        myRole = "O"
        startObserving(gameId: id)

        // Wait reactively for the game document to arrive from the mesh.
        let hostGame = await withCheckedContinuation { continuation in
            self.gameContinuation = continuation
        }

        // Guard: game already has two players.
        if !hostGame.playerODevice.isEmpty {
            leaveGame()
            return false
        }

        // Honor the player's emoji choice unless it collides with the host.
        let emoji: String
        if preferredEmoji != hostGame.playerXEmoji {
            emoji = preferredEmoji
        } else {
            let available = emojiTeams.map(\.emojis[0]).filter { $0 != hostGame.playerXEmoji }
            emoji = available.randomElement() ?? "🐶"
        }

        // Atomically claim the O slot. The WHERE clause ensures we only
        // update if the game is still in the "waiting" state.
        _ = try? await ditto.store.execute(
            query: """
                UPDATE games
                SET playerODevice = :device,
                    playerOEmoji  = :emoji,
                    status        = 'playing'
                WHERE _id = :id AND status = 'waiting'
            """,
            arguments: ["device": deviceId, "emoji": emoji, "id": id]
        )
        return true
    }

    // MARK: - Leave Game

    /// Clean up when navigating back to the lobby.
    ///
    /// Behavior depends on the game's state:
    ///   - waiting:   Delete the document (nobody joined, nothing to preserve).
    ///   - playing:   Mark as abandoned so the opponent gets notified.
    ///   - finished/abandoned: Delete the document (game is over).
    func leaveGame() {
        let currentGame = game

        // Tear down observers and subscriptions immediately.
        observer?.cancel()
        observer = nil
        subscription?.cancel()
        subscription = nil
        if let c = gameContinuation { c.resume(returning: .empty); gameContinuation = nil }
        game = nil
        myRole = ""
        opponentLeft = false

        guard let g = currentGame else { return }

        Task {
            switch g.status {
            case GameStatus.waiting.rawValue:
                // Nobody joined. Delete the game so it disappears from lobbies.
                _ = try? await ditto.store.execute(
                    query: "DELETE FROM games WHERE _id = :id",
                    arguments: ["id": g.id]
                )
            case GameStatus.playing.rawValue:
                // Mid-game exit. Mark abandoned so the other player is notified.
                _ = try? await ditto.store.execute(
                    query: """
                        UPDATE games SET status = 'abandoned', abandonedBy = :device
                        WHERE _id = :id
                    """,
                    arguments: ["device": deviceId, "id": g.id]
                )
            default:
                // Finished or already abandoned. Clean up.
                _ = try? await ditto.store.execute(
                    query: "DELETE FROM games WHERE _id = :id",
                    arguments: ["id": g.id]
                )
            }
        }
    }

    // MARK: - Make Move

    /// Place the current player's emoji on the board at the given index.
    /// Validates: it's our turn, the cell is empty, the game is active.
    func makeMove(index: Int) async {
        guard var g = game,
              g.currentTurn == myRole,
              g.board[index].isEmpty,
              g.status == GameStatus.playing.rawValue
        else { return }

        // Place our emoji and switch turns.
        g.board[index] = (myRole == "X") ? g.playerXEmoji : g.playerOEmoji
        g.currentTurn = (g.currentTurn == "X") ? "O" : "X"
        g.checkOutcome()
        game = g

        // Persist. Ditto syncs the change to the opponent in milliseconds.
        _ = try? await ditto.store.execute(
            query: "INSERT INTO games DOCUMENTS (:updated) ON ID CONFLICT DO UPDATE",
            arguments: ["updated": g.toDictionary()]
        )
    }

    // MARK: - Reset (Play Again)

    /// Clear the board for a rematch. Randomize who goes first.
    func resetGame() async {
        guard var g = game else { return }
        g.board = Array(repeating: "", count: 9)
        g.currentTurn = Bool.random() ? "X" : "O"
        g.winner = ""
        g.status = GameStatus.playing.rawValue
        game = g

        _ = try? await ditto.store.execute(
            query: "INSERT INTO games DOCUMENTS (:updated) ON ID CONFLICT DO UPDATE",
            arguments: ["updated": g.toDictionary()]
        )
    }

    // MARK: - Observe Game Document

    /// Register a Ditto subscription (enables mesh replication for this
    /// specific game) and an observer (fires a callback whenever the
    /// local copy of the game document changes).
    private func startObserving(gameId: String) {
        let query = "SELECT * FROM games WHERE _id = :id"
        let args: [String: Any] = ["id": gameId]

        // Subscription: tells the mesh to replicate this document to us.
        subscription = try? ditto.sync.registerSubscription(query: query, arguments: args)

        // Observer: fires every time the local store changes for this query.
        observer = try? ditto.store.registerObserver(
            query: query, arguments: args
        ) { [weak self] result in
            guard let self else { return }

            // Empty result means the document was deleted (opponent left or cleanup).
            if result.items.isEmpty {
                Task { @MainActor in
                    if self.game != nil { self.opponentLeft = true }
                }
                return
            }

            guard let item = result.items.first else { return }
            let dict = item.value.compactMapValues { $0 }
            guard let g = Game.from(dict) else { return }

            // If joinGame() is awaiting the first document, resume it now.
            if let continuation = self.gameContinuation {
                self.gameContinuation = nil
                continuation.resume(returning: g)
            }

            Task { @MainActor in
                // Detect if the opponent abandoned mid-game.
                if g.status == GameStatus.abandoned.rawValue,
                   g.abandonedBy != self.deviceId {
                    self.opponentLeft = true
                }
                self.game = g
            }
        }
    }
}

// MARK: - App Entry Point

@main
struct EmojiTicTacToeApp: App {
    @State private var manager = DittoManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(manager)
                .task { await manager.start() }
        }
    }
}
