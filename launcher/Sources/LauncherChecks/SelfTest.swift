import AppKit
@testable import LauncherKit
import VoiceCore

/// The real thing: a real call server started through the launcher's own code, and the real call window in a throwaway
/// Chrome profile with a silent fake microphone. It checks the server becomes ready, the page connects and starts the
/// call by itself, Stop and End Call work, the window closes with the call, and nothing is left running. Then a helper
/// holding a call is killed with SIGKILL, as a crash or a force quit would, and its server must follow. Everything it
/// writes stays inside the folder it is given. No word reaches Claude Code and no sound is made: a stand-in for the
/// local voice is saved in the settings, so the real one is never started.
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok    \(what)" : "FAIL  \(what)")
        fflush(stdout)
        if !ok { failures += 1 }
    }

    /// The checks run on the developer's own Node, borrowed into a scratch Runtime folder (with its npm, as installRuntime
    /// finds it): the pinned one is downloaded only by --clean-install.
    static func borrowNode(into support: URL) {
        let fm = FileManager.default, runtime = Runtime.folder(support: support)
        guard let env = Shell.environment(), let shim = Shell.which("node", path: env["PATH"]),
              let out = VoiceCore.run(shim, ["-p", "process.execPath"], environment: env), out.status == 0,
              (try? fm.createDirectory(at: runtime.appending(path: "bin"), withIntermediateDirectories: true)) != nil else { return }
        let real = URL(filePath: String(decoding: out.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        try? fm.createSymbolicLink(at: Runtime.node(support: support), withDestinationURL: real)
        try? fm.createSymbolicLink(at: runtime.appending(path: "lib"), withDestinationURL: real.deletingLastPathComponent().appending(path: "../lib"))
    }

    /// A launcher on port `port` that keeps everything inside `folder`.
    static func launcher(folder: URL, port: Int, profile: String) -> Launcher {
        let fm = FileManager.default
        let project = folder.appending(path: "project"), voice = folder.appending(path: "voice")
        try? fm.createDirectory(at: project, withIntermediateDirectories: true)
        try? fm.createDirectory(at: voice.appending(path: "espeak-ng-data"), withIntermediateDirectories: true)
        // A stand-in local voice: the server starts it and it reads nothing until the call ends. The real one never runs.
        try? "#!/bin/sh\nexec cat > /dev/null\n".write(to: voice.appending(path: "kokoro-runner"), atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: voice.appending(path: "kokoro-runner").path)
        for part in ["libonnxruntime.dylib", "libespeak-ng.dylib", "espeak-ng-data/phontab", "kokoro-v1.0.onnx", "voices-v1.0.bin"] {
            fm.createFile(atPath: voice.appending(path: part).path, contents: Data())
        }
        let silence = folder.appending(path: "silence.wav")
        try? silentWAV().write(to: silence)
        var s = CallSettings()
        s.choose(project.path)
        s.workerModel = .haiku
        s.openInClaudeApp = false
        s.kokoroFolder = voice.path
        let support = folder.appending(path: "support")
        borrowNode(into: support)
        return Launcher(settings: s, defaults: nil, home: folder.appending(path: "home"),
                        setup: Setup(support: support, ports: port...port, chromeProfile: folder.appending(path: profile),
                                     chromeArguments: ["--headless=new", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
                                                       "--use-file-for-fake-audio-capture=\(silence.path)", "--remote-debugging-port=9333"]))
    }

    static func run(folder: URL) async -> Int32 {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            print("The self-test needs an empty folder that exists: \(folder.path)")
            return 2
        }
        let me = launcher(folder: folder, port: 4810, profile: "chrome-profile")
        print("Self-test of \(Product.name), in \(folder.path)")
        await me.checkHealth().value
        check(me.missingItems == [], "nothing a call needs is missing (\(me.missingItems?.map(\.title) ?? []))")
        check(me.kokoro?.path == folder.appending(path: "voice").path, "the stand-in local voice is the one used")

        let started = Date()
        await me.startCall()
        check(await until(30) { me.phase == .live }, "the launcher sees the call server become ready")
        print(String(format: "      ready in %.1f s", Date().timeIntervalSince(started)))
        check(me.status.workers.map(\.model) == ["haiku"] && me.status.workers.first?.state == "idle", "one worker, on Haiku, idle")
        check(await until(5) { me.status.voice == "listening" }, "the server tells the launcher what the voice is doing")
        check(await until(20) { me.status.pages == 1 }, "the call window opened and its page connected; the launcher's own feed is not counted")
        let page = await pageState()
        check(page.contains("\"button\":\"End call\"") && page.contains("\"live\":true") && page.contains("\"note\":\"\""),
              "the page started the call by itself, with talking over the voice on: \(page)")
        guard let pid = me.serverPID, let window = me.callWindow else { return finish() }
        let tree = [pid] + descendants(of: pid)
        let ps = String(decoding: VoiceCore.run(URL(filePath: "/bin/ps"), ["-ax", "-ww", "-o", "pid=,command="])?.output ?? Data(), as: UTF8.self)
        let sdkRuns = ps.split(separator: "\n").filter { line in tree.contains { line.split(separator: " ").first.flatMap { Int32($0) } == $0 } && line.contains("--input-format stream-json") }
        check(!sdkRuns.isEmpty && sdkRuns.allSatisfy { !$0.contains("node_modules") },
              "the SDK runs the user's own Claude Code, not one inside node_modules (\(sdkRuns.first.map { String($0.prefix(90)) } ?? "none running"))")
        print("      server \(pid) and \(tree.count - 1) processes under it")

        let stopped = (try? await EventFeed.post("/stop", port: me.port, key: me.key)) != nil
        check(stopped, "Stop is accepted by the server")

        me.endCall()
        check(me.phase == .ending, "End call shows the call ending")
        // headless Chrome ignores the polite quit, so the launcher's forced one (after 3 s) is what closes it there
        check(await until(5) { window.isTerminated }, "the call window closes as the ending begins")
        check(await until(25) { if case .ended = me.phase { true } else { false } }, "the call ends cleanly")
        check(await until(10) { !tree.contains(where: alive) }, "no server process is left (\(tree.filter(alive)))")
        check(portIsFree(4810), "port 4810 is free again")
        let log = (try? String(contentsOf: me.logURL, encoding: .utf8)) ?? ""
        check(log.contains("Claude Code: haiku"), "the log holds the server's output")

        await crash(folder: folder)
        return finish()
    }

    /// The page's own state, read through Chrome's debugging port of the throwaway profile.
    private static func pageState() async -> String {
        guard let data = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:9333/json/list")!).0,
              let targets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let ws = targets.first(where: { ($0["url"] as? String)?.contains("go=1") == true })?["webSocketDebuggerUrl"] as? String
        else { return "no page" }
        let socket = URLSession.shared.webSocketTask(with: URL(string: ws)!)
        socket.resume()
        defer { socket.cancel() }
        let expression = "JSON.stringify({button: document.getElementById('call').textContent, live, note: document.getElementById('note')?.textContent ?? ''})"
        let request = try! JSONSerialization.data(withJSONObject: ["id": 1, "method": "Runtime.evaluate", "params": ["expression": expression, "returnByValue": true]])
        try? await socket.send(.string(String(decoding: request, as: UTF8.self)))
        guard case .string(let reply)? = try? await socket.receive(),
              let json = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any],
              let value = ((json["result"] as? [String: Any])?["result"] as? [String: Any])?["value"] as? String
        else { return "no answer" }
        return value
    }

    /// Thirty seconds of silence, 16 kHz mono: the fake microphone hears nothing, so the page never sends words.
    private static func silentWAV() -> Data {
        let samples = 16000 * 30, bytes = samples * 2
        var d = Data("RIFF".utf8)
        func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        le(UInt32(36 + bytes)); d.append(Data("WAVEfmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
        le(UInt32(16000)); le(UInt32(32000)); le(UInt16(2)); le(UInt16(16)); d.append(Data("data".utf8)); le(UInt32(bytes))
        d.append(Data(count: bytes))
        return d
    }

    /// Starts a call from a helper process, kills the helper with SIGKILL, and checks the server does not outlive it.
    private static func crash(folder: URL) async {
        let pidFile = folder.appending(path: "held.pid")
        let helper = Process()
        helper.executableURL = Bundle.main.executableURL
        helper.arguments = ["--hold-call", folder.path]
        helper.standardOutput = FileHandle.nullDevice
        do { try helper.run() } catch { return check(false, "the crash helper starts: \(error)") }
        let ready = await until(40) { FileManager.default.fileExists(atPath: pidFile.path) }
        guard ready, let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text) else {
            helper.terminate()
            return check(false, "a call held by a helper process becomes ready")
        }
        let tree = [pid] + descendants(of: pid)
        kill(helper.processIdentifier, SIGKILL)
        let gone = await until(20) { !tree.contains(where: alive) }
        check(gone, "after the launcher is killed, its server and \(tree.count - 1) processes under it exit by themselves")
        check(portIsFree(4811), "port 4811 is free again")
        if !gone { for p in tree where alive(p) { kill(p, SIGKILL) } }
        // The helper's call window is left behind, as after a real crash; the app takes such a window over on its next
        // call (the UI test checks that). Here it is closed so nothing stays.
        let profile = folder.appending(path: "helper-profile")
        _ = await until(10) { runningInstance(profile: profile) != nil }
        if let orphan = runningInstance(profile: profile) {
            orphan.terminate()
            _ = await until(5) { orphan.isTerminated }
            if !orphan.isTerminated { orphan.forceTerminate() } // headless Chrome ignores the polite quit
        }
    }

    /// The helper: holds a call open until it is killed, after writing the server's process id.
    static func hold(folder: URL) async {
        let me = launcher(folder: folder, port: 4811, profile: "helper-profile")
        await me.startCall()
        guard await until(30, { me.phase == .live }), let pid = me.serverPID else { exit(1) }
        try? String(pid).write(to: folder.appending(path: "held.pid"), atomically: true, encoding: .utf8)
    }

    /// One real hand-over, run once by hand: a call through the launcher's own code with the hand-over on, one spoken
    /// line to Claude Code (on Haiku), then End Call. It reports what happened and judges nothing: it costs a model call
    /// and leaves a session in the Claude app.
    static func handOver(folder: URL) async -> Int32 {
        let me = launcher(folder: folder, port: 4810, profile: "chrome-profile")
        me.settings.openInClaudeApp = true
        await me.checkHealth().value
        await me.startCall()
        guard await until(30, { me.phase == .live }), await until(20, { me.status.pages == 1 }), let pid = me.serverPID else {
            print("the call did not start: \(me.phase)"); me.endCall(); return 1
        }
        let line = "Ask Claude Code to list the files in this folder."
        do { try await EventFeed.post("/say", ["text": line], port: me.port, key: me.key); print("said once: \(line)") }
        catch { print("POST /say failed: \(error)"); me.endCall(); return 1 }
        let t0 = Date()
        var last = ""
        var settled = false
        for _ in 0..<900 { // up to 3 minutes, a look every 0.2 s
            let board = me.status.workers.map { "\($0.name) \($0.state) “\($0.step)”" }.joined(separator: ", ")
            let now = "board: \(board); sessions: \(me.status.sessions.count)"
            if now != last { print(String(format: "%5.1f s  %@", Date().timeIntervalSince(t0), now)); last = now }
            if !me.status.sessions.isEmpty, me.status.workers.allSatisfy({ $0.state == "idle" }) { settled = true; break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        print(settled ? "the worker answered and the board is idle" : "no worker answer within 3 minutes (sessions: \(me.status.sessions.count))")
        let tree = [pid] + descendants(of: pid)
        me.endCall()
        print("End Call: \(me.handingOver ? "hand-over (SIGINT)" : "plain (SIGTERM)")")
        let ended = await until(60) { if case .ended = me.phase { true } else { false } }
        if case .ended(let e) = me.phase { print("the launcher shows: Call ended · \(e.line ?? "(no line)")") } else { print("not ended after 60 s: \(me.phase)") }
        let log = (try? String(contentsOf: me.logURL, encoding: .utf8)) ?? ""
        print("— the call log's last lines:")
        for l in log.split(separator: "\n").suffix(15) { print("  | \(l)") }
        _ = await until(10) { !tree.contains(where: alive) }
        print("processes left: \(tree.filter(alive)); port 4810 free: \(portIsFree(4810))")
        return ended ? 0 : 1
    }

    private static func finish() -> Int32 {
        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}
