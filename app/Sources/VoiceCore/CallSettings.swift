import Foundation

public enum Model: String, Codable, Sendable {
    case opus, sonnet, haiku, fable
    public var title: String { rawValue.capitalized }
    /// Claude Code's choices. The voice always runs on Haiku, the fastest.
    public static let forWork: [Model] = [.opus, .sonnet, .haiku, .fable]
}

/// What a spoken "yes" may approve on a call (the server's VOICE_APPROVE).
public enum SpokenYes: String, Codable, Sendable {
    case safeSteps = "1", anyStep = "all", nothing = "0"
}

/// Everything a call can be configured with, kept in the app's defaults.
public struct CallSettings: Codable, Equatable, Sendable {
    public var project: String?
    public var recents: [String] = []
    public var workerModel = Model.opus
    public var spokenYes = SpokenYes.safeSteps
    public var openInClaudeApp = true
    /// Where the local voice was found.
    public var kokoroFolder: String?

    public init() {}

    public static let maxRecents = 6
    /// The call's port: 4747, or the next free one.
    public static let ports = 4747...4757

    public static func defaultKokoro(home: URL) -> URL {
        home.appending(path: "Library/Application Support/\(Product.folder)/Kokoro", directoryHint: .isDirectory)
    }

    /// Makes folder the project and moves it to the top of the recent projects.
    public mutating func choose(_ folder: String) {
        project = folder
        recents = Array(([folder] + recents.filter { $0 != folder }).prefix(Self.maxRecents))
    }
}

// MARK: - Storage

extension CallSettings {
    static let storageKey = "settings"

    public static func load(from defaults: UserDefaults = .standard) -> CallSettings { decode(defaults.data(forKey: storageKey)) }

    public func save(to defaults: UserDefaults = .standard) { defaults.set(encoded, forKey: Self.storageKey) }

    var encoded: Data? { try? JSONEncoder().encode(self) }

    /// Saved settings over the defaults, so a field added in a later version simply starts at its default, and one
    /// removed (the port, the shortcut, the voice model, the limit-warning switch) is ignored.
    static func decode(_ data: Data?) -> CallSettings {
        guard let data,
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fresh = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(CallSettings())) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: fresh.merging(saved) { $1 }),
              let settings = try? JSONDecoder().decode(CallSettings.self, from: merged)
        else { return CallSettings() }
        return settings
    }
}
