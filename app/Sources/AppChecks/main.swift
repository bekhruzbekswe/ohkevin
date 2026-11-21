import AppKit
import AVFoundation
import Speech
import CallKit
import Ears
@testable import OhKevinKit
import VoiceCore

// Checks and measurements that drive the real app's code. Never shipped: the app is the OhKevin product alone (build.sh).
//   --check <folder> [--scene <link>]  draws every state of the design (light and dark) to <folder>, quits; --scene also drives a
//                                       call against a stand-in server (Tests/stub-server.mjs)
//   --offscreen <folder>              the menu-bar panel in every state and the Settings card, light and dark, with no window
//   --icon <folder.iconset> / --icon-dark <folder.iconset>  the app icon from design/logo, as PNGs (build.sh makes AppIcon.icns)
//   --replay <log.jsonl>               the ported turn-taking on a recorded call, in virtual time; prints what it posted and played
//                                       (--replay - : calls on stdin, one JSON array of events per line; Tests/measure/differ.mjs)
//   --file <wav> --call <link> --log <out.jsonl> [--end-talking <s>]
//                                       a measurement: the WAV in real time in place of the microphone, nothing played aloud;
//                                       --end-talking: s seconds after the voice starts, End call (and let go of the call), exit 4 s on
//   --engine-check <file>              the live audio engine with voice processing, muted, built a few ways; a report
//   --install-model                    downloads Apple's newer English speech model (SpeechTranscriber)
//   --check-call <project> --app <Oh Kevin.app> [--hold <s>] [--no-spotlight] [--wav <file>]
//                                       a built app's setup and call server with no window and no sound: brings its call copy up to date
//                                       (its download: Node, the voice, the speech model, if missing), starts the server on <project>,
//                                       prints where it runs and its pid, waits until it answers, holds it s seconds (default 5), ends it.
//                                       --no-spotlight: a voice is looked for only where the app puts it (a clean Mac, even on this one);
//                                       --wav: one sentence through the server's own /tts into <file> (written, never played)
func fail(_ why: Any) -> Never { FileHandle.standardError.write(Data("\(why)\n".utf8)); exit(1) }

if let folder = arg("--offscreen") { // the panel and Settings, drawn with no window: see Offscreen.swift
    let code = MainActor.assumeIsolated { Offscreen.run(folder: URL(fileURLWithPath: folder)) }
    exit(code)
}
if let folder = arg("--icon") ?? arg("--icon-dark") { // the icon needs no window: drawn and written, then quit
    do { try AppIcon.write(to: URL(fileURLWithPath: folder), dark: arg("--icon") == nil); exit(0) } catch { fail(error) }
}

if let path = arg("--engine-check") { // the live audio engine, muted: see EngineCheck.swift
    Task { await EngineCheck.run(report: URL(fileURLWithPath: path)); exit(0) }
    dispatchMain()
}

if let project = arg("--check-call") {
    guard let built = arg("--app").map({ URL(fileURLWithPath: $0) }) else { fail("--check-call needs --app <the built Oh Kevin.app>") }
    Server.place = CallPlace.resolve(override: nil, bundled: built.appending(path: "Contents/Resources/call"),
                                     home: FileManager.default.homeDirectoryForCurrentUser, source: Server.place.folder)
    let setup = Setup()
    setup.download.runner = bundledRunner(in: Bundle(url: built) ?? .main)
    if args.contains("--no-spotlight") { setup.download.spotlight = false }
    func say(_ s: String) { print(s); fflush(stdout) }
    func serve() {
        let missing = (setup.missing ?? []).map(\.id.rawValue)
        say("place: \(Server.place.folder.path) (own copy: \(Server.place.ownCopy)); missing: \(missing.isEmpty ? "nothing" : missing.joined(separator: ", "))")
        let d = setup.download
        say("download: \(d.done ? "all there" : d.running ? "running \(Int(d.fraction * 100))%, left: \(d.parts?.map(\.rawValue) ?? [])" : "failed: \(d.failed?.rawValue ?? "?")")")
        guard !missing.contains("node"), !missing.contains("packages") else { fail("The call cannot run: \(missing)") }
        do {
            let log = try Server.freshLog()
            let s = try Server.start(log: log, project: URL(fileURLWithPath: project), model: .haiku, handOver: false, shell: setup.environment, claude: setup.claude)
            say("server pid: \(s.own!.processIdentifier)  log: \(log.path)")
            s.exited = { fail("The server stopped: \($0)") }
            Task {
                for _ in 0..<60 where (try? await URLSession.shared.data(from: s.url("/"))) == nil { try? await Task.sleep(for: .milliseconds(500)) }
                say("answering: \(s.base)")
                if let wav = arg("--wav") { // the local voice, end to end: the server asks Kokoro for one sentence
                    let started = Date()
                    var data: Data?
                    for _ in 0..<240 where data == nil {
                        if let (d, r) = try? await URLSession.shared.data(from: s.url("/tts", ["voice": "af_heart", "text": "Hello. I hear you clearly."])),
                           (r as? HTTPURLResponse)?.statusCode == 200 { data = d } else { try? await Task.sleep(for: .milliseconds(500)) }
                    }
                    guard let data, (try? data.write(to: URL(fileURLWithPath: wav))) != nil else { fail("The local voice did not answer.") }
                    say(String(format: "voice: %d bytes of WAV in %.1f s (from the server's start of asking) -> %@", data.count, Date().timeIntervalSince(started), wav))
                }
                try? await Task.sleep(for: .seconds(Double(arg("--hold") ?? "5") ?? 5))
                DispatchQueue.main.async { s.end(); say("ended"); exit(0) }
            }
        } catch { fail(error) }
    }
    setup.check {
        // the download starts by itself after this first check (Setup): waited for, whatever it has to fetch
        var shown = -1
        func wait() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let d = setup.download, pct = Int(d.fraction * 100)
                if d.running, pct / 10 != shown / 10 { shown = pct; say("downloading \(pct)%, left: \(d.parts?.map(\.rawValue) ?? [])") }
                setup.installing || d.running ? wait() : serve()
            }
        } // dispatchMain: no run loop, so no Timer
        wait()
    }
    dispatchMain()
}

if args.contains("--install-model") {
    Task { do { try await Recognizer.installModel(); exit(0) } catch { fail(error) } }
    dispatchMain()
}

if let path = arg("--replay") {
    // A log file is one call; "-" reads calls from stdin, one JSON array of events per line (Tests/measure/differ.mjs). One JSON line out per call.
    guard let text = path == "-" ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : try? String(contentsOfFile: path, encoding: .utf8) else { fail("Cannot read \(path)") }
    let lines = text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
    for events in path == "-" ? lines.compactMap({ $0 as? [[String: Any]] }) : [lines.compactMap { $0 as? [String: Any] }] {
        let r = Replay(), tape = Tape(r)
        r.turns = Turns(host: tape)
        r.run(events)
        let out: [String: Any] = ["posts": r.posts.map { ["t": $0.t, "path": $0.path, "body": $0.body] },
                                  "logs": r.logs.map { ["t": $0.t, "text": $0.line] }, "media": tape.media]
        print(String(decoding: try! JSONSerialization.data(withJSONObject: out, options: [.withoutEscapingSlashes]), as: UTF8.self))
    }
    exit(0)
}

var current: Call? // the one call of a measurement, held as the window holds its call
if let wav = arg("--file") {
    guard let link = arg("--call").flatMap(URL.init(string:)), let log = arg("--log") else { fail("--file needs --call <link> and --log <file>") }
    do { current = Call(server: try Server(link: link), log: URL(fileURLWithPath: log)) } catch { fail(error) }
    current?.fileDone = { current?.record("done"); exit(0) }
    current?.start(microphone: false, file: URL(fileURLWithPath: wav), mute: true) { error in
        if let error { fail(error) }
        print("listening with \(current?.recogniser ?? "") to \(wav)")
    }
    if let s = arg("--end-talking").flatMap(Double.init) { // the check that End while the voice talks leaves nothing behind
        func watch() {
            guard current?.turns.speaking == true else { return DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: watch) }
            DispatchQueue.main.asyncAfter(deadline: .now() + s) {
                current?.record("end"); current?.end(); current = nil // only the window's hold on the call, as after End call
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
            }
        }
        watch()
    }
    dispatchMain()
}

runApp(window: { let w = Window(drawing: arg("--check") != nil); if let folder = arg("--check") { w.drawn = { Scene.run($0, folder: URL(fileURLWithPath: folder)) } }; return w }())

/// Replay's host, writing down what the voice did (plays, stops, pauses, resumes) for Tests/measure/differ.mjs to compare with voice.mjs.
final class Tape: Ears.Host {
    let r: Replay
    var media: [[String: Any]] = [], playing = false, paused = false
    init(_ r: Replay) { self.r = r }
    struct Named: Clip { let text: String, duration: Double }
    func note(_ k: String, _ more: [String: Any] = [:]) { media.append(more.merging(["t": r.now(), "k": k]) { $1 }) }
    func now() -> Double { r.now() }
    func after(_ ms: Double, _ fn: @escaping () -> Void) -> Cancel { r.after(ms, fn) }
    func post(_ path: String, _ body: [String: Any]) { r.post(path, body) }
    func fetch(_ text: String, voice: String, _ done: @escaping (Clip?) -> Void) { r.fetch(text, voice: voice) { done($0.map { Named(text: text, duration: $0.duration) }) } }
    func play(_ clip: Clip, _ ended: @escaping () -> Void) {
        note("play", ["text": (clip as? Named)?.text ?? "", "dur": clip.duration]); playing = true
        r.play(clip) { [self] in playing = false; ended() }
    }
    func stop() { if playing { note("stop"); playing = false }; r.stop() }
    func suspend() { if !paused { note("suspend"); paused = true }; r.suspend() }
    func resume() { if paused { note("resume"); paused = false }; r.resume() }
    func played() -> Double { r.played() }
    func tone() { r.tone() }
    func log(_ line: String) { r.log(line) }
    func changed() { r.changed() }
}
