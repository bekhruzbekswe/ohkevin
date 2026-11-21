import CallKit
import Foundation
import VoiceCore

/// The call server, reached as the page reaches it: GET /events, GET /tts, POST /say, /hush, /live, with the call's key.
final class Server {
    let base: URL, key: String
    var own: Process? = nil, stdin: Pipe? = nil
    var last: Task<Void, Never>? = nil, events: Task<Void, Never>? = nil
    var exited: (String) -> Void = { _ in } // its own server stopped by itself: why, in plain words

    /// A call link as the server prints it: http://127.0.0.1:<port>/?k=<key>
    init(link: URL) throws {
        guard let c = URLComponents(url: link, resolvingAgainstBaseURL: false), let port = c.port,
              let k = c.queryItems?.first(where: { $0.name == "k" })?.value else { throw Failure("Not a call link: \(link)") }
        base = URL(string: "http://127.0.0.1:\(port)")!; key = k
    }

    /// Where the call server runs (CallPlace): the app's own copy in Application Support, from the call/ inside the app; a developer's
    /// folder with OH_KEVIN_CALL_FOLDER or the DeveloperCallFolder default; the repository with `swift run` (no bundle).
    static let place = CallPlace.resolve(
        override: ProcessInfo.processInfo.environment["OH_KEVIN_CALL_FOLDER"] ?? UserDefaults.standard.string(forKey: "DeveloperCallFolder"),
        bundled: Bundle.main.url(forResource: "call", withExtension: nil), home: FileManager.default.homeDirectoryForCurrentUser,
        source: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../call").standardized)
    static var callFolder: URL { place.folder }
    /// A new log for a call server in ~/Library/Logs/Claude Voice/, where the launcher keeps its own; the last three are kept.
    /// Only the user can read it: it holds the call's key.
    static func freshLog() throws -> URL {
        let fm = FileManager.default, folder = CallLog.folder(home: fm.homeDirectoryForCurrentUser)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("native-") }.sorted().dropLast(2)
        for name in old { try? fm.removeItem(at: folder.appending(path: name)) }
        let log = folder.appending(path: "native-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false).timeSeparator(.omitted))).log")
        guard fm.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw Failure("Cannot write \(log.path)") }
        return log
    }

    /// Starts `node server.mjs` in the call folder on the project: the app's own copy on the shared pinned Node, a developer's folder
    /// as a terminal would; "open a worker on …" looks beside the project. CALL_LAUNCHER=1: it hangs up by itself if this app dies. Its output goes to log.
    /// `shell` and `claude`: the login shell's environment and the Claude Code the setup check found. The app's own copy runs Node
    /// directly, so it gets the PATH a terminal has from them (the launcher's way); a developer's folder starts a login shell itself.
    static func start(log: URL, project: URL, model: Model, handOver: Bool, shell: [String: String]?, claude: URL?) throws -> Server {
        let call = callFolder
        var env = ProcessInfo.processInfo.environment
        if place.ownCopy {
            if let shell { env = shell } // started from this app's own environment, so a test's PORT or WORKER_MODEL is in it too
            env["CLAUDE_PATH"] = claude?.path
        }
        guard let port = env["PORT"].flatMap(Int.init) ?? freePort(in: CallSettings.ports) else { throw Failure("No free port in 4747-4757") }
        let key = UUID().uuidString
        let p = Process(), pipe = Pipe()
        if place.ownCopy {
            p.executableURL = place.node
            p.arguments = [call.appending(path: "server.mjs").path, project.path]
        } else {
            p.executableURL = URL(fileURLWithPath: env["SHELL"] ?? "/bin/zsh")
            p.arguments = ["-i", "-l", "-c", "exec node server.mjs \"$0\"", project.path] // -i -l: finds node the way Terminal does
        }
        p.currentDirectoryURL = call
        // The model from Settings, unless this app's environment names one (a test's WORKER_MODEL=haiku wins); VOICE_APPROVE as it is here.
        // OPEN_IN_APP: at hang-up the server hands every worker to the Claude app, each from its own folder (handover.mjs)
        p.environment = env.merging(["NO_OPEN": "1", "OPEN_IN_APP": handOver ? "1" : "0", "CALL_LAUNCHER": "1", "CALL_KEY": key, "PORT": "\(port)",
                                     "PROJECTS_DIR": project.deletingLastPathComponent().path, "WORKER_MODEL": env["WORKER_MODEL"] ?? model.rawValue]) { $1 }
        // The local voice: where the launcher looks (VoiceCore), the server's own default otherwise.
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let kokoro = findKokoro(kokoroPlaces(saved: nil, shell: env, home: home, project: nil)) { p.environment?["KOKORO_DIR"] = kokoro.path }
        p.standardInput = pipe
        let out = try FileHandle(forWritingTo: log)
        p.standardOutput = out; p.standardError = out
        let s = try Server(link: URL(string: "http://127.0.0.1:\(port)/?k=\(key)")!)
        p.terminationHandler = { [weak s] p in
            DispatchQueue.main.async {
                guard let s, s.own != nil else { return } // ended on purpose
                s.exited(p.terminationStatus == 127 ? (place.ownCopy ? "The call could not start: its download is not finished. Quit Oh Kevin and open it again." : "The call server did not start: Node was not found. Is it installed (node --version in Terminal)?")
                          : "The call server stopped (exit \(p.terminationStatus)). Its output: \(log.path)")
            }
        }
        try p.run()
        s.own = p; s.stdin = pipe
        return s
    }
    /// Hangs up. The project is the user's own folder: nothing in it is touched.
    /// Hangs up its own server the way Ctrl-C does, so it hands every worker's session to the Claude app from that worker's own
    /// folder before it leaves (call/server.mjs hangUp). done: whether all opened (exit 0; 3 is "printed the command instead").
    func hangUp(_ done: @escaping (Bool) -> Void) {
        events?.cancel()
        guard let p = own else { return done(false) }
        own = nil
        var once = false
        let finish = { (ok: Bool) in DispatchQueue.main.async { if !once { once = true; done(ok) } } }
        p.terminationHandler = { finish($0.terminationStatus == 0) }
        p.interrupt() // SIGINT: hang up and open the work; then stdin closing is the launcher's second word, which waits for it
        try? stdin?.fileHandleForWriting.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + NativeTune.handOverSeconds) { if p.isRunning { p.terminate() }; finish(false) }
    }
    func end() {
        events?.cancel()
        guard let p = own else { return }
        own = nil
        p.terminate(); try? stdin?.fileHandleForWriting.close() // either one hangs up an OPEN_IN_APP=0 server at once
    }
    /// done runs on the main queue once every post so far is answered, or after seconds: a hang-up must leave before the app does.
    func flush(_ seconds: Double, _ done: @escaping () -> Void) {
        var once = false
        let finish = { if !once { once = true; done() } }
        let pending = last
        Task { await pending?.value; DispatchQueue.main.async(execute: finish) }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: finish)
    }

    func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!*'()") // encodeURIComponent: "+" must not read as a space
        c.percentEncodedQueryItems = ([("k", key)] + query.map { ($0.key, $0.value) })
            .map { URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: safe)) }
        return c.url!
    }

    /// The event stream, each line and the JSON object in it, on the main queue. Retries until the server answers (it may be starting).
    /// The event stream. Before it first connects it is tried for as long as a slow start may take; once connected, a drop
    /// (a sleep, a hiccup, a server restarting) calls `dropped` and is tried again quietly every second for reconnectSeconds,
    /// as the page's EventSource does: `back` when it returns, `failed` when it does not.
    func listen(_ on: @escaping (String, [String: Any]) -> Void, failed: @escaping (String) -> Void,
                dropped: @escaping () -> Void = {}, back: @escaping () -> Void = {}) {
        events = Task {
            var connected = false, lostAt: Date? = nil
            for attempt in 0... {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(from: url("/events"))
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure("The call server refused the key") }
                    if lostAt != nil { lostAt = nil; DispatchQueue.main.async(execute: back) }
                    connected = true
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        if let e = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any] { DispatchQueue.main.async { on(line, e) } }
                    }
                    throw Failure("The call server closed the stream")
                } catch {
                    if Task.isCancelled { return }
                    if connected {
                        if lostAt == nil { lostAt = Date(); DispatchQueue.main.async(execute: dropped) }
                        if Date().timeIntervalSince(lostAt!) > NativeTune.reconnectSeconds { DispatchQueue.main.async { failed("The call dropped and did not come back.") }; return }
                        try? await Task.sleep(for: .seconds(1))
                        continue
                    }
                    if attempt > NativeTune.retries { DispatchQueue.main.async { failed("Could not reach the call server: \(error)") }; return } // a busy Mac starts Node slowly
                    try? await Task.sleep(for: .milliseconds(NativeTune.retryMs))
                }
            }
        }
    }

    /// Posts in order, so a /say never overtakes the /hush before it (the page's hushed.then).
    func post(_ path: String, _ body: [String: Any], failed: (() -> Void)? = nil) {
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "content-type"); req.setValue(key, forHTTPHeaderField: "x-key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        last = Task { [last] in
            await last?.value
            let ok = ((try? await URLSession.shared.data(for: req))?.1 as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            if !ok, let failed { DispatchQueue.main.async(execute: failed) }
        }
    }

    /// A sentence in the local Kokoro voice, as WAV bytes; nil when the server cannot make it.
    func tts(_ text: String, voice: String, _ done: @escaping (Data?) -> Void) {
        Task {
            let r = try? await URLSession.shared.data(from: url("/tts", ["voice": voice, "text": text]))
            let ok = (r?.1 as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { done(ok ? r?.0 : nil) }
        }
    }
}
