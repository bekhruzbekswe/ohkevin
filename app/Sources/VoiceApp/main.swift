import AppKit
import AVFoundation
import Speech
import CallKit
import Ears

// VoiceApp                       the call window: Start Call talks to a call server of its own (or --call <link>)
// VoiceApp --file <wav> --call <link> --log <out.jsonl> [--end-talking <s>]
//                                 a measurement: the WAV in real time in place of the microphone, nothing played aloud;
//                                 --end-talking: s seconds after the voice starts, End call (and let go of the call), exit 4 s on
// VoiceApp --replay <log.jsonl>  the ported turn-taking on a recorded call, in virtual time; prints what it posted and played
//                                 (--replay - : calls on stdin, one JSON array of events per line)
// VoiceApp --check <folder>      draws every state of the design (light and dark) to <folder>, quits; --scene <link> also drives a call
//                                 against a stand-in server (launcher/Tests/stub-server.mjs)
// VoiceApp --install-model       downloads Apple's newer English model (SpeechTranscriber); the owner's choice
// VoiceApp --engine-check <file> the live audio engine with voice processing, muted, built a few ways; a report
// VoiceApp --permissions        prints whether this copy may use the microphone and speech recognition (the update rehearsal)
// VoiceApp --check-call <project> [--hold <s>]
//                                 the setup and the call server with no window and no sound: brings the app's call copy up to date
//                                 (its download: Node and the packages, the voice, the speech model, if missing), starts the server on <project>, prints where it runs
//                                 and its pid, waits until it answers, holds it s seconds (default 5), ends it
//                                 --no-spotlight: a voice is looked for only where the app puts it (a clean Mac, even on this one)
//                                 --wav <file>: one sentence through the server's own /tts into <file> (written, never played)
let args = CommandLine.arguments
func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
func fail(_ why: Any) -> Never { FileHandle.standardError.write(Data("\(why)\n".utf8)); exit(1) }

if let path = arg("--engine-check") { // the live audio engine, muted: see EngineCheck.swift
    Task { await EngineCheck.run(report: URL(fileURLWithPath: path)); exit(0) }
    dispatchMain()
}

// What macOS lets this copy of the app do, without asking and without opening anything: the update rehearsal compares it before and
// after an update (a stable signing identity keeps both; an ad-hoc one loses them).
if args.contains("--permissions") {
    let mic = ["not asked yet", "restricted", "denied", "allowed"][AVCaptureDevice.authorizationStatus(for: .audio).rawValue]
    let speech = ["not asked yet", "denied", "restricted", "allowed"][SFSpeechRecognizer.authorizationStatus().rawValue]
    print("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") \(Bundle.main.bundleIdentifier ?? "?"): microphone \(mic), speech recognition \(speech)")
    exit(0)
}

if let project = arg("--check-call") {
    let setup = Setup()
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
    // A log file is one call; "-" reads calls from stdin, one JSON array of events per line (measure/differ.mjs). One JSON line out per call.
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

let app = NSApplication.shared
let window = Window(check: arg("--check"))
app.delegate = window
func menu(_ title: String, _ items: [(String, Selector, String)]) -> NSMenuItem {
    let item = NSMenuItem(), sub = NSMenu(title: title)
    items.forEach { sub.addItem(withTitle: $0.0, action: $0.1, keyEquivalent: $0.2) }
    item.submenu = sub; return item
}
app.mainMenu = NSMenu()
// The app menu as every Mac app has it: About, (Check for Updates…, added by Window when the app can update), Settings…, Services,
// Hide, Hide Others, Show All, Quit. Its items aim at the app's delegate (Window) directly, so they work whatever window is in front.
let appMenu = NSMenu(title: appName)
func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", target: AnyObject? = nil, mods: NSEvent.ModifierFlags = .command) {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = target; item.keyEquivalentModifierMask = mods
}
add(appMenu, "About \(appName)", #selector(Window.showAbout), target: window)
appMenu.addItem(.separator())
add(appMenu, "Settings…", #selector(Window.openSettings), ",", target: window)
appMenu.addItem(.separator())
let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: ""); services.submenu = NSMenu(title: "Services"); app.servicesMenu = services.submenu
appMenu.addItem(services); appMenu.addItem(.separator())
add(appMenu, "Hide \(appName)", #selector(NSApplication.hide(_:)), "h")
add(appMenu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", mods: [.command, .option])
add(appMenu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
appMenu.addItem(.separator())
add(appMenu, "Quit \(appName)", #selector(NSApplication.terminate(_:)), "q")
let appItem = NSMenuItem(); appItem.submenu = appMenu
app.mainMenu?.addItem(appItem)
for m in [
          menu("File", [("Close", #selector(NSWindow.performClose(_:)), "w")]), // the call goes on
          menu("Edit", [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                        ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")])] { app.mainMenu?.addItem(m) }
app.setActivationPolicy(arg("--check") == nil ? .regular : ProcessInfo.processInfo.environment["REAL_POINTER"] == "1" ? .regular : .prohibited) // drawing figures: no Dock icon
app.run()

/// Replay's host, writing down what the voice did (plays, stops, pauses, resumes) for measure/differ.mjs to compare with voice.mjs.
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
