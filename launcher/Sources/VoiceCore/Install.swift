import CryptoKit
import Foundation

// What a call runs on, fetched once into the app's own folder: a pinned Node, the Agent SDK the server imports and, when asked for,
// the local voice. Everything downloaded is checked against a hash pinned here before it is used.

/// The pinned Node (nodejs.org, darwin-arm64) and where it lives under the app's support folder.
public enum Runtime {
    public static let version = "v24.22.3"
    public static let sha256 = "1d64136c8a43d648d1b3bad10797a4c995b1ca032d2bde8799de43b37f058fe5" // SHASUMS256.txt, nodejs.org/dist/\(version)
    static let name = "node-\(version)-darwin-arm64"
    public static let url = URL(string: "https://nodejs.org/dist/\(version)/\(name).tar.xz")!
    /// The oldest Claude Code the pinned Agent SDK is known to work with (SDK 0.3.325 with CLI 2.1.323, checked).
    public static let minimumClaudeCode = "2.1.323"

    /// Only the Node program (bin/node and its licence) from nodejs.org's archive: no npm, headers, docs or corepack, which a call
    /// never runs (the one package it needs is AgentSDK, fetched on its own). Under Node/, never Runtime/: an earlier version of either app empties Runtime/
    /// of every Node but its own, and still needs its full Node's npm.
    public static func folder(support: URL) -> URL { support.appending(path: "Node/\(name)", directoryHint: .isDirectory) }
    /// The full Node an earlier version installed (Runtime/): the same program, used as it is rather than fetched again.
    static func earlier(support: URL) -> URL { support.appending(path: "Runtime/\(name)/bin/node") }
    public static func node(support: URL) -> URL {
        let own = folder(support: support).appending(path: "bin/node"), earlier = earlier(support: support)
        return !FileManager.default.isExecutableFile(atPath: own.path) && FileManager.default.isExecutableFile(atPath: earlier.path) ? earlier : own
    }
    /// What is taken out of the archive: the program and its licence.
    static let members = ["\(name)/bin/node", "\(name)/LICENSE"]
}

/// Anthropic's Claude Agent SDK from npm, the one package the server imports: its bundled sdk.mjs needs nothing but Node's own
/// modules (launcher/pack-call.sh checks that). Not shipped in the apps: fetched onto the user's Mac under Anthropic's terms. The
/// version and integrity are call/package-lock.json's (a test keeps them equal).
public enum AgentSDK {
    public static let version = "0.3.325"
    public static let integrity = "sha512-MhSm2Fhk3DA/hhjdCKXDZWlnykpPWJjX42SogllAHMplY9ZKT+Ltb8QPtQxpe225Imfs4A8IKaNE4biivA+fHg=="
    public static let url = URL(string: "https://registry.npmjs.org/@anthropic-ai/claude-agent-sdk/-/claude-agent-sdk-\(version).tgz")!
    /// What is taken out of the archive: the code, how Node finds it, and the terms.
    static let members = ["package/sdk.mjs", "package/package.json", "package/LICENSE.md", "package/README.md"]
    static let folder = "node_modules/@anthropic-ai/claude-agent-sdk"
}

/// The npm form of a sha512 ("sha512-" and base64), as package-lock.json writes it.
func integrity(of file: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    var hash = SHA512()
    while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
    return "sha512-" + Data(hash.finalize()).base64EncodedString()
}

/// Puts the pinned Agent SDK into callFolder's node_modules: the tarball from npm, kept only if its integrity is the pinned one,
/// unpacked beside and moved in whole. No npm is needed.
func installSDK(into callFolder: URL, url: URL = AgentSDK.url, integrity pinned: String = AgentSDK.integrity) async -> Bool {
    let fm = FileManager.default
    guard let (file, response) = try? await URLSession.shared.download(from: url) else { return false }
    defer { try? fm.removeItem(at: file) }
    guard (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true, integrity(of: file) == pinned else { return false }
    let to = callFolder.appending(path: AgentSDK.folder), new = to.deletingLastPathComponent().appending(path: ".sdk.new")
    try? fm.removeItem(at: new)
    try? fm.createDirectory(at: new, withIntermediateDirectories: true)
    guard run(URL(filePath: "/usr/bin/tar"), ["-xzf", file.path, "-C", new.path, "--strip-components=1"] + AgentSDK.members, timeout: 120)?.status == 0
    else { try? fm.removeItem(at: new); return false }
    try? fm.removeItem(at: to)
    guard (try? fm.moveItem(at: new, to: to)) != nil else { try? fm.removeItem(at: new); return false }
    return true
}

func sha256(of file: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Downloads url to a temporary file, kept only if its sha256 is the pinned one.
func fetch(_ url: URL, sha256 pinned: String) async -> URL? {
    guard let (file, response) = try? await URLSession.shared.download(from: url) else { return nil }
    if (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true, sha256(of: file) == pinned { return file }
    try? FileManager.default.removeItem(at: file)
    return nil
}

/// Fetches an archive (one top folder, dropped) and unpacks it into folder, which is made fresh; nothing is left there when it fails.
/// `members`: only these paths of the archive (all of it when empty).
func unpack(_ url: URL, sha256 pinned: String, flags: String, into folder: URL, members: [String] = []) async -> Bool {
    guard let archive = await fetch(url, sha256: pinned) else { return false }
    defer { try? FileManager.default.removeItem(at: archive) }
    try? FileManager.default.removeItem(at: folder)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let tar = run(URL(filePath: "/usr/bin/tar"), [flags, archive.path, "-C", folder.path, "--strip-components=1"] + members, timeout: 300)
    if tar?.status == 0 { return true }
    try? FileManager.default.removeItem(at: folder)
    return false
}

// MARK: - Node and the packages

/// The server's files from the app, into the support folder's copy: a file (or folder) is swapped in whole only when it differs (so
/// a check that finds nothing new changes nothing, and an install under way never sees one missing), and a file the app no longer
/// has goes. The copy's own node_modules (the fetched SDK) and its install mark stay; an earlier app that carried them still
/// brings them.
public func syncCall(from bundled: URL, to call: URL) {
    let fm = FileManager.default
    try? fm.createDirectory(at: call, withIntermediateDirectories: true)
    let names = ((try? fm.contentsOfDirectory(atPath: bundled.path)) ?? []).filter { !$0.hasPrefix(".") || $0 == installedMark }
    for name in names where !fm.contentsEqual(atPath: bundled.appending(path: name).path, andPath: call.appending(path: name).path) {
        let to = call.appending(path: name), new = call.appending(path: ".\(name).new")
        try? fm.removeItem(at: new)
        guard (try? fm.copyItem(at: bundled.appending(path: name), to: new)) != nil else { continue }
        if fm.fileExists(atPath: to.path) { _ = try? fm.replaceItemAt(to, withItemAt: new) } else { try? fm.moveItem(at: new, to: to) }
    }
    for name in (try? fm.contentsOfDirectory(atPath: call.path)) ?? [] where !names.contains(name) && name != "node_modules" && name != installedMark {
        try? fm.removeItem(at: call.appending(path: name))
    }
}

/// The download (Node, the server's packages) starts by itself, at launch and after an update, whenever it is missing: it never has a
/// screen of its own and never waits for a press.
public func installsByItself(missing: [Missing]) -> Bool { missing.contains { $0.id == .packages } }

public let installedMark = ".installed"
public let sdk = "node_modules/@anthropic-ai/claude-agent-sdk/package.json"

/// The SDK is there and, in the app's own copy (`locked`), was installed from the package-lock.json beside it.
public func packagesCurrent(callFolder: URL, locked: Bool) -> Bool {
    guard FileManager.default.fileExists(atPath: callFolder.appending(path: sdk).path) else { return false }
    guard locked else { return true } // a repository's own node_modules: not ours to judge
    let mark = try? String(contentsOf: callFolder.appending(path: installedMark), encoding: .utf8)
    return mark != nil && mark == sha256(of: callFolder.appending(path: "package-lock.json"))
}

/// Everything a call runs on: the pinned Node's program, the server's files from the app (`bundledCall`, put in place first), then
/// the Agent SDK. The app's own copy (`locked`) fetches the pinned SDK from npm (installSDK); a repository's own call folder runs
/// `npm ci` with the npm a terminal finds. True when all of it is there.
public func installRuntime(support: URL, callFolder: URL, bundledCall: URL?, environment env: [String: String],
                           node: (url: URL, sha256: String) = (Runtime.url, Runtime.sha256)) async -> Bool {
    let fm = FileManager.default, runtime = Runtime.folder(support: support), all = runtime.deletingLastPathComponent(), new = all.appending(path: ".new")
    if !fm.isExecutableFile(atPath: Runtime.node(support: support).path) {
        guard await unpack(node.url, sha256: node.sha256, flags: "-xJf", into: new, members: Runtime.members) else { return false }
        for old in (try? fm.contentsOfDirectory(atPath: all.path)) ?? [] where old != ".new" { try? fm.removeItem(at: all.appending(path: old)) } // an older Node goes
        guard (try? fm.moveItem(at: new, to: runtime)) != nil else { try? fm.removeItem(at: new); return false } // unpacked beside, moved whole: never half there
    }
    if let bundledCall { syncCall(from: bundledCall, to: callFolder) }
    let locked = bundledCall != nil
    if packagesCurrent(callFolder: callFolder, locked: locked) { return true }
    if locked {
        guard await installSDK(into: callFolder) else { return false }
        try? sha256(of: callFolder.appending(path: "package-lock.json"))?.write(to: callFolder.appending(path: installedMark), atomically: true, encoding: .utf8)
        return true
    }
    var env = env
    env["PATH"] = "\(Runtime.node(support: support).deletingLastPathComponent().path):\(env["PATH"] ?? "/usr/bin:/bin")"
    env["npm_config_cache"] = support.appending(path: "npm-cache").path
    env["npm_config_userconfig"] = "/dev/null" // the user's own ~/.npmrc (registry, prefix, scripts) is not ours to follow
    guard let npm = Shell.which("npm", path: env["PATH"]),
          run(npm, ["ci", "--ignore-scripts", "--no-audit", "--no-fund"], environment: env, in: callFolder, timeout: 600)?.status == 0
    else { return false }
    return fm.fileExists(atPath: callFolder.appending(path: sdk).path)
}

// MARK: - The local voice

/// Kokoro's model files, pinned. The runner and the rest of its parts are in RunnerFiles (InstallRunner.swift).
public enum VoiceFiles {
    // The release's own voices file: an older 26 MB copy in circulation lists the same 28 a/b voices, so the one with a published source wins.
    public static let models = [
        ("kokoro-v1.0.onnx", "7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5"),
        ("voices-v1.0.bin", "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d"),
    ]
    public static let base = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"
}

/// Installs the local voice into folder with the app's own runner (kokoro-runner, in the app bundle): installKokoroRunner. Without
/// a runner there is nothing to install with, and it fails. callFolder and environment are not used any more (the Python voice is
/// gone); they stay until the Mac app's call to this drops them.
public func installKokoro(into folder: URL, callFolder: URL, environment base: [String: String], runner: URL? = nil,
                          files: [(String, String)] = VoiceFiles.models, from source: String = VoiceFiles.base) async -> Bool {
    guard let runner, FileManager.default.isExecutableFile(atPath: runner.path) else { return false }
    return await installKokoroRunner(into: folder, runner: runner, files: files, from: source)
}
