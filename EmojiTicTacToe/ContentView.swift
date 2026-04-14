// ContentView.swift
// EmojiTicTacToe
//
// The lobby screen. Players pick their emoji team, create a new game,
// or join a nearby game discovered via the Ditto P2P mesh.

import SwiftUI

struct ContentView: View {
    @Environment(DittoManager.self) var manager
    @State private var selectedTeam = emojiTeams[0]
    @State private var navigateToGame = false
    @State private var showFullGameAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                Text("Emoji Tic-Tac-Toe").font(.largeTitle.bold())
                Text("Pick your team!").font(.title3).foregroundStyle(.secondary)

                // Emoji team picker: horizontal scroll of team buttons.
                // The selected team is highlighted in blue.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(emojiTeams) { team in
                            Button { selectedTeam = team } label: {
                                VStack {
                                    Text(team.emojis[0]).font(.system(size: 44))
                                    Text(team.name).font(.caption.bold())
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selectedTeam.id == team.id
                                              ? Color.blue.opacity(0.25)
                                              : Color(uiColor: .systemGray6))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                Divider().padding(.horizontal)

                // Create a new game and wait for an opponent.
                Button {
                    Task {
                        await manager.createGame(emoji: selectedTeam.emojis[0])
                        navigateToGame = true
                    }
                } label: {
                    Label("Create Game", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.horizontal)

                // Nearby games: populated by the lobby observer in DittoManager.
                // Shows games from other devices on the P2P mesh that are
                // waiting for a second player.
                nearbyGamesSection

                Spacer()
                Text("Powered by Ditto P2P Mesh")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .navigationDestination(isPresented: $navigateToGame) {
                GameView()
                    .onDisappear {
                        // Clean up when leaving the game screen.
                        // Deletes/abandons the game document as appropriate.
                        manager.leaveGame()
                    }
            }
            .alert("Game Full", isPresented: $showFullGameAlert) {
                Button("OK") {}
            } message: {
                Text("This game already has two players.")
            }
        }
    }

    // MARK: - Nearby Games Section

    @ViewBuilder
    private var nearbyGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Join Nearby Game")
                .font(.headline)
                .padding(.horizontal)

            if manager.nearbyGames.isEmpty {
                // Empty state: show a faded placeholder so the user knows
                // nearby games will appear here when available.
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title)
                            .foregroundStyle(.quaternary)
                        Text("No nearby games found")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Text("Another device on the same network\ncan create a game for you to join.")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .systemGray6).opacity(0.5))
                )
                .padding(.horizontal)
            } else {
                // List of joinable games, each showing the host's emoji.
                ForEach(manager.nearbyGames, id: \.id) { nearby in
                    Button {
                        Task {
                            let joined = await manager.joinGame(
                                id: nearby.id,
                                preferredEmoji: selectedTeam.emojis[0]
                            )
                            if joined {
                                navigateToGame = true
                            } else {
                                showFullGameAlert = true
                            }
                        }
                    } label: {
                        HStack {
                            Text(nearby.playerXEmoji).font(.largeTitle)
                            VStack(alignment: .leading) {
                                Text("Game \(nearby.id)")
                                    .font(.body.monospaced().bold())
                                Text("Waiting for opponent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
    }
}
