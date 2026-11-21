import Foundation

/// The Node that runs the call server: the real binary, not a version manager's shim, so every call starts the same one.
public struct Node: Equatable, Sendable {
    public let url: URL
    public let version: String
    public init(url: URL, version: String) { self.url = url; self.version = version }

    /// The Agent SDK needs Node 18.14 or later.
    public var supported: Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return parts.count >= 2 && (parts[0], parts[1]) >= (18, 14)
    }
}

/// What a call needs from this Mac. `probe` reads it; tests make it up.
public struct Machine: Equatable, Sendable {
    public var callFolder: URL
    /// server.mjs is where this app was built to find it.
    public var server: Bool
    public var node: Node?
    public var packages: Bool
    public var claude: URL?
    /// What `claude --version` says (for example "2.1.323"), when it said.
    public var claudeVersion: String?
    public var signedIn: Bool?
    public var chrome: URL?
    /// The local voice's folder, when one was found.
    public var kokoro: URL?
    /// Probed with the app's own Runtime (`support:`): a missing Node is then part of "One more download", not a Node to go and get.
    public var runtime: Bool
    /// The call folder is the app's own copy (`locked:`): a missing server is brought back by the same download.
    public var locked: Bool

    public init(callFolder: URL, server: Bool = true, node: Node? = nil, packages: Bool = false, claude: URL? = nil,
                claudeVersion: String? = nil, signedIn: Bool? = nil, chrome: URL? = nil, kokoro: URL? = nil, runtime: Bool = false, locked: Bool = false) {
        self.callFolder = callFolder; self.server = server; self.node = node; self.packages = packages; self.claude = claude
        self.claudeVersion = claudeVersion; self.runtime = runtime; self.locked = locked
        self.signedIn = signedIn; self.chrome = chrome; self.kokoro = kokoro
    }

    /// Slow (it starts node and claude once each, and may ask Spotlight), so call it off the main thread. With `support`,
    /// the Node is the app's own Runtime there (never one found on PATH), and `locked` (the app's own copy of the
    /// call folder) wants the packages installed from the lock beside them.
    public static func probe(environment env: [String: String], callFolder: URL, chrome: URL?, kokoroPlaces: [URL], spotlight: Bool = true,
                             support: URL? = nil, locked: Bool = false) -> Machine {
        let fm = FileManager.default
        var m = Machine(callFolder: callFolder, server: fm.fileExists(atPath: callFolder.appending(path: "server.mjs").path), chrome: chrome, runtime: support != nil, locked: locked)
        if let shim = support.map({ Runtime.node(support: $0) }) ?? Shell.which("node", path: env["PATH"]),
           fm.isExecutableFile(atPath: shim.path),
           let out = run(shim, ["-p", "process.execPath + '\\n' + process.versions.node"], environment: env, in: callFolder),
           out.status == 0 {
            let lines = String(decoding: out.output, as: UTF8.self).split(separator: "\n").map(String.init)
            if lines.count >= 2 { m.node = Node(url: URL(filePath: lines[0]), version: lines[1]) }
        }
        m.packages = packagesCurrent(callFolder: callFolder, locked: locked)
        m.claude = Shell.which("claude", path: env["PATH"])
        m.claudeVersion = m.claude.flatMap { run($0, ["--version"], environment: env, timeout: 15) }
            .flatMap { String(decoding: $0.output, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map(String.init) }
        m.signedIn = m.claude.flatMap { authStatus(claude: $0, environment: env) }
        m.kokoro = findKokoro(kokoroPlaces, spotlight: spotlight ? spotlightKokoro : { [] })
        return m
    }
}

// MARK: - The local voice, found without asking

/// Kokoro as the server starts it: the runner layout (runnerReady), or the Python environment and both model files in one folder.
public func kokoroReady(_ folder: URL) -> Bool {
    if runnerReady(folder) { return true }
    let fm = FileManager.default
    return fm.isExecutableFile(atPath: folder.appending(path: "kokoro-env/bin/python").path)
        && fm.fileExists(atPath: folder.appending(path: "kokoro-v1.0.onnx").path)
        && fm.fileExists(atPath: folder.appending(path: "voices-v1.0.bin").path)
}

/// Where to look first, in order: the folder saved before, KOKORO_DIR from the login shell, the app's own folder, and a
/// `kokoro` folder beside the project. No one's own layout is written in here.
public func kokoroPlaces(saved: String?, shell: [String: String], home: URL, project: URL?) -> [URL] {
    [saved, shell["KOKORO_DIR"]].compactMap { $0.map { URL(filePath: $0) } }
        + [CallSettings.defaultKokoro(home: home)]
        + (project.map { [$0.deletingLastPathComponent().appending(path: "kokoro")] } ?? [])
}

/// The first place that holds Kokoro; failing all of them, the folders Spotlight knows with its model file in them.
public func findKokoro(_ places: [URL], spotlight: () -> [URL] = spotlightKokoro) -> URL? {
    places.first(where: kokoroReady) ?? spotlight().first(where: kokoroReady)
}

public func spotlightKokoro() -> [URL] {
    guard let out = run(URL(filePath: "/usr/bin/mdfind"), ["-name", "kokoro-v1.0.onnx"], timeout: 5) else { return [] }
    return String(decoding: out.output, as: UTF8.self).split(separator: "\n")
        .filter { $0.hasSuffix("/kokoro-v1.0.onnx") }
        .map { URL(filePath: String($0)).deletingLastPathComponent() }
}

// MARK: - What is missing, and the one button that fixes it

public struct Missing: Identifiable, Equatable, Sendable {
    public enum Item: String, Sendable { case node, packages, claude, claudeOld, signIn, chrome, moved }
    public enum Fix: Equatable, Sendable { case open(String, URL), install, signIn }
    public let id: Item
    public let title: String
    public let detail: String
    public let fix: Fix?
}

let nodeSite = URL(string: "https://nodejs.org/en/download")!
let claudeSite = URL(string: "https://code.claude.com/docs/en/overview")!
let chromeSite = URL(string: "https://www.google.com/chrome/")!

/// Only what is missing, in the order a person would fix it. The local voice is never listed: it is optional.
public func missing(_ m: Machine) -> [Missing] {
    var out: [Missing] = []
    let nodeBad = m.node.map { !$0.supported } ?? true
    if !m.server && !m.locked { // the app's own copy of the server is put back by the download below
        out.append(Missing(id: .moved, title: "\(Product.name) was moved", detail: "Build it again from its folder.", fix: nil))
    }
    if m.runtime { // one download brings the Node, the server's files and the packages
        if nodeBad || !m.packages || !m.server {
            out.append(Missing(id: .packages, title: "One more download", detail: "The parts a call runs on.", fix: .install))
        }
    } else if nodeBad {
        out.append(Missing(id: .node, title: "Node is needed", detail: "Calls run on Node 18.14 or later.", fix: .open("Get Node", nodeSite)))
    } else if m.server && !m.packages {
        out.append(Missing(id: .packages, title: "One more download", detail: "The parts a call runs on.", fix: .install))
    }
    if m.claude == nil {
        out.append(Missing(id: .claude, title: "Claude Code isn’t installed", detail: "Claude Code does the work on a call.", fix: .open("Get Claude Code", claudeSite)))
    } else if m.claudeVersion.map({ !isAtLeast($0, Runtime.minimumClaudeCode) }) ?? false {
        out.append(Missing(id: .claudeOld, title: "Claude Code needs an update", detail: "Calls need version \(Runtime.minimumClaudeCode) or later.", fix: .open("Get Claude Code", claudeSite))) // the launcher offers to run `claude update` itself
    } else if m.signedIn == false {
        out.append(Missing(id: .signIn, title: "Claude Code isn’t signed in", detail: "Calls use your Claude Code account.", fix: .signIn))
    }
    if m.chrome == nil {
        out.append(Missing(id: .chrome, title: "Chrome isn’t installed", detail: "The call listens through Chrome.", fix: .open("Get Chrome", chromeSite)))
    }
    return out
}

/// Whether dotted version v (2.1.323) is minimum or later; numbers compared one by one.
func isAtLeast(_ v: String, _ minimum: String) -> Bool {
    let a = v.split(separator: ".").map { Int($0) ?? 0 }, b = minimum.split(separator: ".").map { Int($0) ?? 0 }
    return !a.lexicographicallyPrecedes(b)
}

/// Whether Claude Code is signed in, as `claude auth status` says; nil when it cannot say.
public func authStatus(claude: URL, environment env: [String: String]) -> Bool? {
    guard let out = run(claude, ["auth", "status"], environment: env, timeout: 15),
          let json = try? JSONSerialization.jsonObject(with: out.output) as? [String: Any] else { return nil }
    return json["loggedIn"] as? Bool
}

/// `claude auth login` or `claude update`, which want a terminal, so `script` lends one, as call/handover.mjs does for
/// the hand-over; they read nothing, so their input is /dev/null. Returned ready to run.
public func claudeProcess(claude: URL, _ arguments: [String], environment env: [String: String]) -> Process {
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/script")
    p.arguments = ["-q", "/dev/null", claude.path] + arguments
    p.environment = env
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    return p
}

public func signInProcess(claude: URL, environment env: [String: String]) -> Process { claudeProcess(claude: claude, ["auth", "login"], environment: env) }

/// Installs the call server's packages (`npm ci`) with the login shell's environment, for a launcher that has no Runtime
/// of its own (`installRuntime` is the one that has). True when it worked.
public func installPackages(callFolder: URL, environment env: [String: String]) -> Bool {
    guard let npm = Shell.which("npm", path: env["PATH"]),
          let out = run(npm, ["ci", "--no-audit", "--no-fund"], environment: env, in: callFolder, timeout: 600)
    else { return false }
    return out.status == 0 && FileManager.default.fileExists(atPath: callFolder.appending(path: sdk).path)
}
