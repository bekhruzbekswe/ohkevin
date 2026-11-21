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

/// Everything a call can be configured with. The launcher always sets every call variable of the server, so nothing
/// leaks in from the user's shell; what used to be a variable for the builder (port, folders) is now a rule.
public struct CallSettings: Codable, Equatable, Sendable {
    public var project: String?
    public var recents: [String] = []
    public var workerModel = Model.opus
    public var spokenYes = SpokenYes.safeSteps
    public var openInClaudeApp = true
    /// Where the local voice was found.
    public var kokoroFolder: String?
    /// The app has been launched before: the panel opens by itself only the first time.
    public var launchedBefore = false
    /// A call has been started before: the first-run note is gone.
    public var hasCalled = false
    /// The call's Chrome was allowed the microphone (setup's Microphone row), or a call has been made, which needs it.
    public var micAllowed = false

    public init() {}

    public static let maxRecents = 6
    /// The call's port: 4747 so Chrome remembers the microphone for it, or the next free one.
    public static let ports = 4747...4757

    public static func defaultKokoro(home: URL) -> URL {
        home.appending(path: "Library/Application Support/\(Product.folder)/Kokoro", directoryHint: .isDirectory)
    }

    /// Makes folder the project and moves it to the top of the recent projects.
    public mutating func choose(_ folder: String) {
        project = folder
        recents = Array(([folder] + recents.filter { $0 != folder }).prefix(Self.maxRecents))
    }

    /// The call server's environment: the login shell's, with every call variable set from these settings (CLAUDE_PATH only when claude is given). They are
    /// fixed for the call: a change in Settings applies to the next one. "Open a worker on …" looks next to the project.
    public func environment(base: [String: String], project: URL, key: String, port: Int, kokoro: URL, claude: URL? = nil) -> [String: String] {
        var env = base
        env["KOKORO_PYTHON"] = nil // follows KOKORO_DIR
        env["VOICE_THREADS"] = nil // tts.py picks the fast cores itself; the shell's own value must not leak in
        env.merge([
            "CALL_LAUNCHER": "1", "NO_OPEN": "1", "CALL_KEY": key, "PORT": String(port),
            "WORKER_MODEL": workerModel.rawValue, "TALKER_MODEL": Model.haiku.rawValue,
            "VOICE_APPROVE": spokenYes.rawValue, "SPEAK_FIRST": "1", "OPEN_IN_APP": openInClaudeApp ? "1" : "0",
            "PROJECTS_DIR": project.deletingLastPathComponent().path, "KOKORO_DIR": kokoro.path,
        ]) { $1 }
        env["CLAUDE_PATH"] = claude?.path // the user's own Claude Code, which the server's SDK runs; nil leaves it to the SDK
        return env
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
