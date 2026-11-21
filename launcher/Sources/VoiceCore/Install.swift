import CryptoKit
import Foundation

// What a call runs on, fetched once into the app's own folder: a pinned Node and, when asked for, the local voice. The server's
// packages come inside the app (pack-call.sh). Everything downloaded is checked against a sha256 pinned here before it is used.

/// The pinned Node (nodejs.org, darwin-arm64) and where it lives under the app's support folder.
public enum Runtime {
    public static let version = "v24.22.3"
    public static let sha256 = "1d64136c8a43d648d1b3bad10797a4c995b1ca032d2bde8799de43b37f058fe5" // SHASUMS256.txt, nodejs.org/dist/\(version)
    static let name = "node-\(version)-darwin-arm64"
    public static let url = URL(string: "https://nodejs.org/dist/\(version)/\(name).tar.xz")!
    /// The oldest Claude Code the pinned Agent SDK is known to work with (SDK 0.3.325 with CLI 2.1.323, checked).
    public static let minimumClaudeCode = "2.1.323"

    /// Only the Node program (bin/node and its licence) from nodejs.org's archive: no npm, headers, docs or corepack, which a call
    /// never runs (the packages come inside the app). Under Node/, never Runtime/: an earlier version of either app empties Runtime/
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
/// has goes. The app's packages (node_modules, made by pack-call.sh) and their install mark come with it; an app without them (an
/// earlier one) leaves the copy's own node_modules and mark where they are.
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

/// Everything a call runs on: the pinned Node's program, then the server's files with their packages, both from the app
/// (`bundledCall`, put in place first). Only a call folder whose packages are not there (a repository's own, or an earlier app's copy)
/// runs `npm ci`, with the npm a terminal finds (or an earlier version's full Node's). True when all of it is there.
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
    var env = env
    env["PATH"] = "\(Runtime.node(support: support).deletingLastPathComponent().path):\(env["PATH"] ?? "/usr/bin:/bin")"
    env["npm_config_cache"] = support.appending(path: "npm-cache").path
    env["npm_config_userconfig"] = "/dev/null" // the user's own ~/.npmrc (registry, prefix, scripts) is not ours to follow
    let full = support.appending(path: "Runtime/\(Runtime.name)/lib/node_modules/npm/bin/npm-cli.js")
    let npm: (URL, [String])? = fm.fileExists(atPath: full.path) ? (Runtime.node(support: support), [full.path]) : Shell.which("npm", path: env["PATH"]).map { ($0, []) }
    guard let npm, run(npm.0, npm.1 + ["ci", "--ignore-scripts", "--no-audit", "--no-fund"] + (locked ? ["--omit=optional"] : []), environment: env, in: callFolder, timeout: 600)?.status == 0,
          FileManager.default.fileExists(atPath: callFolder.appending(path: sdk).path) else { return false }
    if locked { try? sha256(of: callFolder.appending(path: "package-lock.json"))?.write(to: callFolder.appending(path: installedMark), atomically: true, encoding: .utf8) }
    return true
}

// MARK: - The local voice

/// Kokoro's pinned parts: uv (to fetch Python 3.12 and the hashed packages of call/kokoro-requirements.txt) and the model files.
public enum VoiceFiles {
    public static let uv = (url: URL(string: "https://github.com/astral-sh/uv/releases/download/0.13.9/uv-aarch64-apple-darwin.tar.gz")!,
                     sha256: "5aeca67f2283f75235de40d0bd9c0a5bbc5fce23b6d48b3bf9fa1b2db08382ca")
    // The release's own voices file: an older 26 MB copy in circulation lists the same 28 a/b voices with tts.py, so the one with a published source wins.
    public static let models = [
        ("kokoro-v1.0.onnx", "7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5"),
        ("voices-v1.0.bin", "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d"),
    ]
    public static let base = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"
}

/// Installs the local voice into folder. With the app's own `runner` (kokoro-runner, in the app bundle) it is the runner layout, no
/// Python (installKokoroRunner); without one, the Python layout as before (installKokoroPython). The Python layout stays working.
public func installKokoro(into folder: URL, callFolder: URL, environment base: [String: String], runner: URL? = nil,
                          uv: (url: URL, sha256: String) = VoiceFiles.uv, files: [(String, String)] = VoiceFiles.models, from source: String = VoiceFiles.base) async -> Bool {
    if let runner, FileManager.default.isExecutableFile(atPath: runner.path) {
        return await installKokoroRunner(into: folder, runner: runner, files: files, from: source)
    }
    return await installKokoroPython(into: folder, callFolder: callFolder, environment: base, uv: uv, files: files, from: source)
}

/// Python 3.12 and the pinned packages in its own environment, then both model files, then runs call/tts.py once to see it say
/// ready. On any failure the folder is deleted: never half a voice.
func installKokoroPython(into folder: URL, callFolder: URL, environment base: [String: String],
                         uv: (url: URL, sha256: String) = VoiceFiles.uv, files: [(String, String)] = VoiceFiles.models, from source: String = VoiceFiles.base) async -> Bool {
    let fm = FileManager.default
    if kokoroReady(folder) { return true }
    try? fm.removeItem(at: folder)
    func fail() -> Bool { try? fm.removeItem(at: folder); return false }
    guard await unpack(uv.url, sha256: uv.sha256, flags: "-xzf", into: folder.appending(path: "bin")) else { return fail() }
    var env = base.filter { !$0.key.hasPrefix("UV_") } // the user's own uv settings (index, cache, config) are not ours to follow
    env.merge(["UV_PYTHON_INSTALL_DIR": folder.appending(path: "python").path, "UV_CACHE_DIR": folder.appending(path: "cache").path,
               "UV_NO_CONFIG": "1", "UV_PYTHON_PREFERENCE": "only-managed", "UV_NO_PROGRESS": "1"]) { $1 }
    let uvBinary = folder.appending(path: "bin/uv"), venv = folder.appending(path: "kokoro-env"), python = venv.appending(path: "bin/python")
    guard run(uvBinary, ["venv", "--python", "3.12", venv.path], environment: env, timeout: 900)?.status == 0,
          run(uvBinary, ["pip", "install", "--python", python.path, "--only-binary", ":all:", "--require-hashes", "-r",
                         callFolder.appending(path: "kokoro-requirements.txt").path], environment: env, timeout: 900)?.status == 0
    else { return fail() }
    for (name, sha) in files {
        guard let file = await fetch(URL(string: source + name)!, sha256: sha),
              (try? fm.moveItem(at: file, to: folder.appending(path: name))) != nil else { return fail() }
    }
    for scrap in ["cache", "bin"] { try? fm.removeItem(at: folder.appending(path: scrap)) } // only the install needed them
    // espeak reads its data from a path of at most 159 characters (measured): a user name over 33 characters puts this folder
    // past it, and then the check below fails and the install says so, instead of leaving a voice that cannot speak.
    // tts.py, started as the server starts it, must answer {"ready": true} before the voice counts as installed
    let check = "import json,subprocess,sys\np=subprocess.Popen([sys.executable,sys.argv[1],sys.argv[2]],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)\nline=p.stdout.readline();p.stdin.close();p.terminate()\nsys.exit(0 if json.loads(line).get('ready') else 1)"
    return run(python, ["-I", "-c", check, callFolder.appending(path: "tts.py").path, folder.path], timeout: 180)?.status == 0 || fail()
}
