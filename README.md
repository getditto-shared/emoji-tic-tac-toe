# Emoji Tic-Tac-Toe

A two-player tic-tac-toe game for iOS built with SwiftUI and [Ditto](https://ditto.live) peer-to-peer sync. No server, no Firebase, no internet required. Two iPhones in the same room sync every move in real time over Bluetooth or WiFi.

<!-- TODO: Add blog post URL once published -->
<!-- Read the full tutorial: [Build a Multiplayer Emoji Game in SwiftUI](https://ditto.com/blog/swiftui-multiplayer-game-tutorial) -->

![Emoji Tic-Tac-Toe screenshot](https://img.shields.io/badge/platform-iOS_17+-blue) ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange) ![License: MIT](https://img.shields.io/badge/license-MIT-green)

## How It Works

- Players pick emoji teams (Cats, Dogs, Ocean, Space, Fruits)
- One player creates a game; the other sees it appear in a **"Join Nearby Game"** list
- Moves sync instantly between devices using Ditto's peer-to-peer mesh
- Works over **Bluetooth**, **P2P WiFi**, or **LAN** with zero infrastructure
- Game data never touches the cloud (P2P only via Ditto sync scopes)

## Architecture

The entire multiplayer layer is ~100 lines in `DittoManager`. The game state is a single Ditto document:

```
games/{id}
├── board: ["🐱", "", "🐶", ...]   // 9 cells
├── currentTurn: "X"                // whose turn
├── playerXEmoji / playerOEmoji     // team emoji
├── playerXDevice / playerODevice   // device IDs
├── status: "playing"               // waiting → playing → finished
└── winner: ""                      // "X", "O", "draw"
```

Key patterns demonstrated:
- **P2P-only sync** via `SmallPeersOnly` sync scopes
- **Lobby discovery** using a Ditto observer on `status = 'waiting'`
- **Reactive joining** with `CheckedContinuation` (no polling or sleep)
- **Conflict-free** turn management (Ditto CRDTs handle edge cases)
- **Graceful disconnect** (abandoned games notify the other player)

## Getting Started

### Prerequisites

- Xcode 15.4+
- iOS 17+ device or simulator
- A free [Ditto account](https://portal.ditto.live)

### Setup

1. **Clone the repo**
   ```bash
   git clone https://github.com/getditto/emoji-tic-tac-toe.git
   cd emoji-tic-tac-toe
   ```

2. **Add your Ditto credentials**

   Copy the config template:
   ```bash
   cp Config/Ditto.env.template Config/Ditto.env
   ```

   Open `Config/Ditto.env` and paste your credentials from [portal.ditto.live](https://portal.ditto.live):
   ```
   DITTO_APP_ID=your-app-id
   DITTO_PLAYGROUND_TOKEN=your-token
   DITTO_AUTH_URL=https://xxxxx.cloud.dittolive.app
   DITTO_WEBSOCKET_URL=wss://xxxxx.cloud.dittolive.app
   ```
   Paste the values exactly as they appear in the portal.

   > `Config/Ditto.env` is gitignored so your credentials stay local.

3. **Open in Xcode**
   ```bash
   open EmojiTicTacToe.xcodeproj
   ```
   Xcode will automatically resolve the Ditto Swift Package dependency.

4. **Set your signing team** in Signing & Capabilities.

5. **Build and run** on two iOS devices (or one device + simulator).

### Play

- **Device A**: Open the app, pick an emoji team, tap **Create Game**.
- **Device B**: Open the app. The game appears under **Join Nearby Game**. Tap it.
- Take turns tapping cells. Watch moves appear instantly on the other device.
- Try turning off WiFi. The game still works over Bluetooth.

## Project Structure

```
EmojiTicTacToe/
├── Config/
│   ├── Ditto.env.template       # Credential template (committed)
│   └── Ditto.env                # Your credentials (gitignored)
├── EmojiTicTacToe/
│   ├── EmojiTicTacToeApp.swift  # App entry + DittoManager (all sync logic)
│   ├── DittoConfig.swift        # Reads credentials from Config/Ditto.env at runtime
│   ├── GameModel.swift          # Game struct, win detection, Ditto serialization
│   ├── ContentView.swift        # Lobby: team picker, create game, nearby games list
│   ├── GameView.swift           # Game board, player bar, result overlay
│   ├── Info.plist               # Bluetooth/WiFi permissions + xcconfig values
│   └── Assets.xcassets/         # App icon
├── .gitignore
└── README.md
```

## Requirements

| Requirement | Version |
|---|---|
| iOS | 17.0+ |
| Xcode | 15.4+ |
| Swift | 5.9+ |
| Ditto SDK | 4.14+ (via SPM) |

## License

MIT. See [LICENSE](LICENSE) for details.

## Links

- [Ditto Documentation](https://docs.ditto.live)
- [Ditto Swift Install Guide](https://docs.ditto.live/sdk/latest/install-guides/swift)
- [Ditto Portal (free account)](https://portal.ditto.live)
