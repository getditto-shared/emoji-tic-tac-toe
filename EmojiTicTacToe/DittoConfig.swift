// DittoConfig.swift
// EmojiTicTacToe
//
// Reads Ditto credentials from Config/Ditto.env at runtime.
// Paste values exactly as they appear in the Ditto portal.
//
// Setup:
//   1. cp Config/Ditto.env.template Config/Ditto.env
//   2. Paste your credentials from https://portal.ditto.live
//   3. Build and run

import Foundation

enum DittoConfig {
    static let appID            = value(for: "DITTO_APP_ID")
    static let playgroundToken  = value(for: "DITTO_PLAYGROUND_TOKEN")
    static let authURL          = value(for: "DITTO_AUTH_URL")
    static let websocketURL     = value(for: "DITTO_WEBSOCKET_URL")

    // MARK: - .env Parser

    /// All key-value pairs from Config/Ditto.env, parsed once at launch.
    private static let env: [String: String] = {
        // The .env file is bundled as a resource via the Xcode project.
        guard let url = Bundle.main.url(forResource: "Ditto", withExtension: "env"),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError(
                """
                Config/Ditto.env not found in the app bundle.
                Copy Config/Ditto.env.template to Config/Ditto.env
                and add your credentials from https://portal.ditto.live.
                """
            )
        }
        var dict: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            dict[String(parts[0]).trimmingCharacters(in: .whitespaces)]
                = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        return dict
    }()

    private static func value(for key: String) -> String {
        guard let v = env[key], !v.isEmpty, !v.contains("YOUR_") else {
            fatalError(
                """
                Missing Ditto credential: \(key).
                Copy Config/Ditto.env.template to Config/Ditto.env
                and paste your credentials from https://portal.ditto.live.
                """
            )
        }
        return v
    }
}
