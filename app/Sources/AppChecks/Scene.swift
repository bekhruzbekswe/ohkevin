import AppKit
import CallKit
import CallViews
import Ears
import SwiftUI
import VoiceCore
@testable import OhKevinKit

/// `AppChecks --check <folder>` draws the figures of design/final.html, wide and narrow, light and dark, into PNGs: the real window
/// and views on a real CallModel and Turns, driven by the server's own events and the recogniser's own results, with a clock
/// and a voice that stand still (nothing is heard, played or sent). `--scene <call link>` also runs a made-up call through the
/// real Call against a stand-in server that only records what it is sent (Tests/stub-server.mjs): live.png.
enum Scene {
    /// A voice and a clock for a still frame: a sentence is ready at once and plays until told it ended; timers run when time is moved.
    final class Rehearsal: Ears.Host {
        var t = 0.0, playedSeconds = 0.0, queue: [(due: Double, timer: Timer)] = [], ended: (() -> Void)?
        final class Timer { var fn: (() -> Void)?; init(_ fn: @escaping () -> Void) { self.fn = fn } }
        struct Sentence: Clip { let duration: Double }
        lazy var turns = Turns(host: self)
        func now() -> Double { t }
        func after(_ ms: Double, _ fn: @escaping () -> Void) -> Cancel { let x = Timer(fn); queue.append((t + ms, x)); return Cancel { x.fn = nil } }
        func advance(_ ms: Double) {
            let end = t + ms
            while let i = queue.indices.filter({ queue[$0].due <= end }).min(by: { queue[$0].due < queue[$1].due }) {
                let x = queue.remove(at: i); t = max(t, x.due); x.timer.fn?()
            }
            t = end
        }
        func post(_ path: String, _ body: [String: Any]) {}
        func fetch(_ text: String, voice: String, _ done: @escaping (Clip?) -> Void) { done(Sentence(duration: 3)) }
        func play(_ clip: Clip, _ ended: @escaping () -> Void) { self.ended = ended }
        func stop() { ended = nil }
        func suspend() {}
        func resume() {}
        func played() -> Double { playedSeconds }
        func tone() {}
        func log(_ line: String) {}
        func changed() {}
    }

    /// One call as the window shows it.
    final class Rig {
        let host = Rehearsal()
        var date = Date()
        lazy var model = CallModel(turns: host.turns, post: { _, _ in }, clock: { [unowned self] in date })
        init(voices: [String] = ["af_heart", "af_bella", "af_nicole", "am_michael", "am_adam", "bf_emma", "bm_george"]) {
            send(["type": "hello", "project": "/Users/you/Lab/api", "voices": voices])
        }
        func send(_ e: [String: Any]) {
            host.turns.server(e)
            model.apply(line: "data: " + String(decoding: try! JSONSerialization.data(withJSONObject: e), as: UTF8.self), event: e)
        }
        /// Live, for this many seconds.
        func live(_ seconds: Double = 252) -> Rig {
            host.turns.start(echoCancelled: true); model.stage = .live; model.since = date.addingTimeInterval(-seconds); model.update(); return self
        }
        func ended(_ seconds: Double = 12 * 60 + 48) { model.since = date.addingTimeInterval(-seconds); model.until = date; model.update() }
        func board(_ workers: [(String, String, String, String)]) { // name, state, task, step
            send(["type": "board", "state": "working", "workers": workers.map { ["name": $0.0, "state": $0.1, "task": $0.2, "step": $0.3, "model": $0.0 == "web" ? "sonnet" : "opus"] }])
        }
        func api(_ state: String = "working", _ step: String = "Bash npm test") {
            board([("api", state, state == "idle" ? "" : "Run the tests and tell me what fails", state == "idle" ? "" : step)])
        }
        /// You said it, as the recogniser reports it.
        func you(_ text: String, final: Bool = true) { host.turns.results([Heard(text, final)], from: 0) }
        /// The voice says these, one after the other; the last is still playing.
        func voice(_ sentences: String...) {
            sentences.forEach { send(["type": "say", "text": $0]) }
            for _ in sentences.dropFirst() { host.ended?(); host.advance(300) }
        }
        /// The voice has finished and the turn is over.
        func quiet() { host.ended?(); host.advance(300); send(["type": "turn_end"]) }
        func before() { you("Run the tests in api and tell me what fails."); voice("On it.", "I’ve asked Claude Code to run them."); }
        /// You talk over the voice: it stops mid-word, the rest of its sentence faint.
        func pause(_ sentence: String) {
            voice(sentence); host.playedSeconds = 1.5; host.advance(400)
            host.turns.level(-20); host.advance(150); host.turns.level(-20)
        }
    }

    typealias Shot = (name: String, build: (Rig) -> Void)

    // The conversation design/final.html tells, here as the server's own events. Each worker's sentence is what the
    // app really says for its step (VoiceCore's plainWords), so it may differ from the drawing's words.
    static let hi = "Hi. What shall we do?"
    static func a(_ r: Rig) { r.you("Run the tests and tell me what fails."); r.voice("On it. I’ve opened a worker in api.") }
    static func b(_ r: Rig) {
        a(r); r.quiet(); r.you("Open web and docs too."); r.you("Shrink the bundle in web, then push.")
        r.voice("Opening web and docs."); r.quiet(); r.voice("api found three failing date tests. It’s fixing them."); r.quiet() // two bubbles in one run
        r.you("Good. What’s docs doing?"); r.voice("Rewriting the setup page. About halfway."); r.quiet(); r.you("Tell me when it’s done.")
    }
    typealias W = (String, String, String, String)
    static let api: W = ("api", "working", "Run the tests and tell me what fails", "Bash npm test"), web: W = ("web", "working", "Shrink the bundle", "Bash npm run build")
    static let docs: W = ("docs", "working", "Rewrite the setup page", "Edit docs/setup.md"), app: W = ("app", "working", "Add the sign-in screen", "Write src/SignIn.tsx")
    static let data: W = ("data", "working", "Check last night’s import", "Read imports/2026-11-18.csv")
    static func ask(_ r: Rig, _ id: String, _ worker: String, _ command: String, voice: Bool) {
        r.send(["type": "ask", "id": id, "detail": "\(worker): Bash \(command)", "worker": worker, "voice": voice, "full": command])
    }

    /// The figures of "The app", by their ids in final.html (no stuck figure: the voice tells it).
    static let shots: [Shot] = [
        ("before", { $0.model.stage = .idle }),
        ("setup", { $0.model.stage = .idle }), // Node and Claude Code missing (Scene.machines)
        ("line-move", { $0.model.stage = .idle }), ("line-ready", { $0.model.stage = .idle }), ("line-updating", { $0.model.stage = .idle }),
        ("line-updated", { $0.model.stage = .idle }), ("line-failed", { $0.model.stage = .idle }), ("line-current", { $0.model.stage = .idle }),
        ("signin", { $0.model.stage = .idle }), // only the sign-in left
        ("start", { r in _ = r.live(3) }),
        ("one", { r in _ = r.live(40); a(r); r.board([api]) }),
        ("three", { r in _ = r.live(300); b(r); r.voice("I will."); r.board([api, web, docs]); r.send(["type": "session", "id": "s2", "worker": "web"]); r.model.openCard = "web" }),
        ("settings", { r in _ = r.live(300); b(r); r.voice("I will."); r.quiet(); r.board([api, web, docs]) }),
        ("voicelist", { r in _ = r.live(300); b(r); r.voice("I will."); r.quiet(); r.board([api, web, docs]) }),
        ("modellist", { r in _ = r.live(300); b(r); r.voice("I will."); r.quiet(); r.board([api, web, docs]) }),
        ("folderdirect", { r in _ = r.live(300); b(r); r.voice("I will."); r.quiet(); r.board([api, web, docs]) }),
        ("folderlist", { r in _ = r.live(300); b(r); r.voice("I will."); r.quiet(); r.board([api, web, docs]) }),
        ("five", { r in _ = r.live(320); b(r); r.voice("I will."); r.board([api, web, docs, app, data]) }),
        ("ask1", { r in
            _ = r.live(340); b(r); r.board([api, ("web", "waiting", "Shrink the bundle", ""), docs]); ask(r, "a1", "web", "git push origin main", voice: true)
            r.voice("web wants to push your commits. Shall it go ahead?"); r.quiet()
        }),
        ("ask2", { r in
            _ = r.live(360); b(r); r.board([api, ("data", "waiting", "Clean the build", ""), docs, ("web", "waiting", "Shrink the bundle", "")])
            ask(r, "a1", "data", "rm -rf dist build", voice: false); ask(r, "a2", "web", "git push origin main", voice: true)
            r.voice("data wants to delete the old build files. That needs a click on screen.", "web has a question after that."); r.quiet()
        }),
        ("fiveask", { r in
            _ = r.live(380); b(r); r.board([api, web, ("data-pipeline", "waiting", "Copy the import", ""), docs, app])
            ask(r, "a1", "data-pipeline", "pg_dump --data-only imports_2026_11_18 | psql test_db", voice: true)
            r.voice("data-pipeline wants to copy last night’s import. Shall it go ahead?"); r.quiet()
        }),
        ("done", { r in
            _ = r.live(400); b(r); r.board([api, web, docs]); r.date += 1; r.board([api, web, ("docs", "idle", "Rewrite the setup page", "")])
            r.voice("docs is done. The setup page is rewritten.")
        }),
        ("problem", { r in
            _ = r.live(90); a(r); r.quiet(); r.board([api]); r.you("What failed?")
            r.send(["type": "error", "text": "The voice could not answer (error 529). Say it again in a moment."]); r.send(["type": "turn_end"]) // as call/server.mjs: the error, then the end of the turn
        }),
        ("mic", { r in _ = r.live(60); a(r); r.quiet(); r.board([api]); r.model.deaf = .microphone }),
        ("reconnecting", { r in _ = r.live(420); b(r); r.voice("I will."); r.quiet(); r.board([api, web, docs]); r.model.reconnecting = true }),
        ("lost", { r in _ = r.live(420); b(r); r.voice("I will."); r.quiet(); r.board([api, web, docs]); r.model.stage = .failed(.stopped); r.ended(420) }),
        ("ended", { r in _ = r.live(); r.model.stage = .ended; r.ended() }),
    ]

    /// The voice's words, as the bar shows them: each state of the call bar on its own (final.html "voice" and "lost").
    static let bars: [(String, (Rig) -> Void)] = [
        ("listening", { r in _ = r.live(); r.voice(hi); r.quiet() }),
        ("speaking", { r in _ = r.live(); r.voice(hi) }),
        ("thinking", { r in _ = r.live(); r.voice(hi); r.quiet(); r.you("Run the tests.") }),
        ("muted", { r in _ = r.live(); r.host.turns.setMuted(true) }),
        ("mic", { r in _ = r.live(); r.model.deaf = .microphone }),
        ("lost", { r in _ = r.live(); r.model.stage = .failed(.stopped) }),
    ]

    /// The launcher's states, as final.html "The launcher" names them (setup steps and Reconnecting: this app has neither).
    static let launcher: [(String, (Rig) -> Void)] = [
        ("Idle", { $0.model.stage = .idle }),
        ("First run: no project", { $0.model.stage = .idle }),
        ("Setup, two steps left", { $0.model.stage = .idle }),
        ("Setup, one step left", { $0.model.stage = .idle }),
        ("Call: listening", { r in _ = r.live(724); r.voice("On it."); r.quiet() }),
        ("Call: speaking", { r in _ = r.live(724); r.voice("On it.") }),
        ("Call: thinking", { r in _ = r.live(724); r.you("Run the tests.") }),
        ("Muted", { r in _ = r.live(724); r.host.turns.setMuted(true) }),
        ("Something needs you", { r in _ = r.live(724); r.board([api]); ask(r, "a1", "api", "git push", voice: true); r.voice("api wants to push. Shall it go ahead?"); r.quiet() }),
        ("Muted, and something needs you", { r in _ = r.live(724); r.board([api]); ask(r, "a1", "api", "git push", voice: true); r.host.turns.setMuted(true) }),
        ("Mic blocked", { r in _ = r.live(724); r.model.deaf = .microphone }),
        ("Call lost", { r in _ = r.live(724); r.model.stage = .failed(.stopped); r.ended(724) }),
        ("Call ended", { r in _ = r.live(); r.model.stage = .ended; r.ended() }),
    ]
    /// The setup screen's states, as onboarding.html draws them: the Claude row (signin, signing, done), the Microphone row, a project or
    /// none, and the download's parts.
    static let onboarding: [(String, String, SetupInput.Mic, Bool, [SetupInput.Part])] = [
        ("setup-1-first", "signin", .todo, false, []),
        ("setup-2-signing-in", "signing", .todo, false, []),
        ("setup-3-mic-asking", "done", .asking, false, []),
        ("setup-4-mic-refused", "done", .refused, false, []),
        ("setup-5-all-done", "done", .done, true, []),
        ("setup-6-downloading", "done", .done, true, [.init("Node and the call", progress: 1, weight: 265), .init("Kevin’s voice", progress: 0.4, weight: 700)]),
    ]
    /// The first call: "Say hello." as the app's own line, then the first finished card with its one-time hint.
    static let firstCall: [(String, (Rig) -> Void)] = [
        ("first-say-hello", { r in _ = r.live(); r.send(["type": "hello", "project": "/Users/you/Lab/shop", "voices": ["af_heart", "bm_fable"], "first": true, "hint": true]) }),
        ("first-done-hint", { r in
            _ = r.live(400); r.send(["type": "hello", "project": "/Users/you/Lab/shop", "voices": ["af_heart", "bm_fable"], "first": true, "hint": true])
            r.you("Hello Kevin."); r.voice("Hello. I hear you clearly.", "What shall we do first?"); r.quiet()
            r.you("Tell me what this project is."); r.voice("I’ll have a look."); r.quiet()
            r.board([("shop", "working", "Read the project", "Read README.md")]); r.date += 1; r.board([("shop", "idle", "Read the project", "")])
            r.voice("It’s a web shop: a Next.js storefront, an API in Node, and a docs site.", "Tests cover the API. The storefront has none yet."); r.quiet()
        }),
    ]
    /// Made-up machines for the setup pictures; `ready` has everything.
    static let folder = URL(fileURLWithPath: "/Users/you/oh-kevin/call"), claude = URL(fileURLWithPath: "/usr/local/bin/claude")
    static let ready = Machine(callFolder: folder, node: Node(url: URL(fileURLWithPath: "/usr/local/bin/node"), version: "22.12.0"), packages: true,
                               claude: claude, claudeVersion: "9.9.9", signedIn: true)
    static let machines: [String: Machine] = {
        var none = ready; none.node = nil; none.claude = nil; none.claudeVersion = nil; none.signedIn = nil
        var signIn = ready; signIn.signedIn = false
        return ["setup": none, "signin": signIn, "Setup, two steps left": none, "Setup, one step left": signIn]
    }()

    /// The start window's update line in each state the design draws (updates.html frames 17–20), from the shared rule (VoiceCore).
    static let lines: [String: PanelLine] = {
        func line(_ f: (inout UpdateLineInput) -> Void) -> PanelLine? { var i = UpdateLineInput(); f(&i); return VoiceCore.updateLine(i, product: appName) }
        return ["line-move": line { $0.moveOffered = true }, "line-ready": line { $0.state = .available("0.2"); $0.automatic = false },
                "line-updating": line { $0.state = .downloading(0.62); $0.automatic = false }, "line-updated": line { $0.state = .installed("0.2") },
                "line-failed": line { $0.state = .failed("") }, "line-current": line { $0.state = .upToDate }].compactMapValues { $0 }
    }()

    /// A template image in ink, as the menu bar would tint it.
    static func tinted(_ image: NSImage) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect); NSColor(CV.ink).set(); rect.fill(using: .sourceAtop); return true
        }
    }

    /// Waits while AppKit delivers events (real clicks and pointer moves): spinning the run loop alone leaves them queued.
    static func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) { NSApp.sendEvent(e) } }
    }

    /// REAL_POINTER=1 only, on screen with the real keyboard and pointer: the start opens with no focus ring, Escape closes an open
    /// list before Settings, and a list row lights only as a full row under the pointer. Exits 1 on a wrong answer.
    static func liveChecks(_ w: OhKevinKit.Window, snap: (String) -> Void) {
        func key(_ code: CGKeyCode) {
            for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap) }
            pump(0.4)
        }
        func point(_ fromTop: NSPoint) { // window points, measured from the top left
            let p = w.window.convertPoint(toScreen: NSPoint(x: fromTop.x, y: w.window.contentLayoutRect.height - fromTop.y))
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x, y: NSScreen.screens[0].frame.height - p.y), mouseButton: .left)?.post(tap: .cghidEventTap)
            pump(0.4)
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        w.window.setContentSize(NSSize(width: 1280, height: 800)); w.window.center()
        w.settings.shown = false; w.settings.openForPicture = nil
        w.reset(); w.show(); pump(1.0)
        let responder = String(describing: type(of: w.window.firstResponder as Any))
        snap("live-start")
        w.openSettings(); w.settings.openForPicture = "Voice"; pump(0.8)
        let opened = w.settings.listOpen
        point(NSPoint(x: 1280 - 8 - 200, y: 375)); snap("live-listhover")
        key(53) // Escape
        let first = (w.settings.listOpen, w.settings.shown)
        key(53)
        let second = w.settings.shown
        let ok = opened && first == (false, true) && !second
        print("live: first responder at the start \(responder); list open \(opened); Escape 1: list \(first.0) settings \(first.1); Escape 2: settings \(second): \(ok ? "ok" : "WRONG")")
        w.settings.openForPicture = nil
        if !ok { exit(1) }
    }

    static func run(_ w: OhKevinKit.Window, folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // recent projects that exist (the list leaves out folders that are gone), in a temporary folder removed at the end
        let lab = FileManager.default.temporaryDirectory.appending(path: "cv-figures-\(ProcessInfo.processInfo.processIdentifier)")
        for name in ["docs", "web", "api", "shop"] { try? FileManager.default.createDirectory(at: lab.appending(path: name), withIntermediateDirectories: true); w.settings.call.choose(lab.appending(path: name).path) }
        w.settings.voice = CallModel.defaultVoice // a fresh install
        w.settings.saw(["af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "am_adam", "am_eric", "am_michael", "bf_emma", "bf_isabella", "bm_fable", "bm_george", "bm_lewis"])
        w.window.alphaValue = 0; w.window.ignoresMouseEvents = true; w.window.orderFrontRegardless() // drawn, never seen: nothing shows on the screen
        func snap(_ name: String, _ win: NSWindow) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.4)) // SwiftUI lays out and draws
            let v = win.contentView!.superview!, rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: name + ".png"))
        }
        for (look, dark) in [("light", false), ("dark", true)] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for (size, suffix) in [(NSSize(width: 1280, height: 800), ""), (NSSize(width: 480, height: 760), "-n")] {
                w.window.setContentSize(size)
                for shot in shots {
                    let r = Rig(); shot.build(r); r.model.update()
                    w.settings.setup = Setup(machine: machines[shot.name] ?? ready)
                    w.settings.linePicture = lines[shot.name]
                    w.window.makeFirstResponder(nil) // as the window opens: nothing holds the keyboard, no focus ring
                    w.setModel(r.model); w.settings.shown = ["settings", "voicelist", "modellist", "folderlist", "folderdirect"].contains(shot.name)
                    let recents = w.settings.call.recents
                    if shot.name == "folderdirect" { w.settings.call.recents = w.settings.call.project.map { [$0] } ?? [] } // no other project: Finder at once
                    defer { w.settings.call.recents = recents }
                    w.settings.openForPicture = ["modellist": "Model", "voicelist": "Voice", "folderlist": "Project folder"][shot.name]; snap("\(shot.name)\(suffix)-\(look)", w.window)
                }
                // the bar alone, in each state, as the drawing's cell (bar 760 wide; 448 narrow)
                let rigs = bars.map { b -> Rig in let r = Rig(); b.1(r); r.model.update(); return r }
                let two = suffix == "-n"
                w.content.rootView = AnyView(VStack(spacing: CV.s2) { ForEach(Array(rigs.enumerated()), id: \.offset) { _, r in CallBar(model: r.model, two: two) } }
                    .padding(two ? CV.s2 : CV.s4).frame(width: two ? 480 : 840).background(CV.ground).fixedSize())
                w.window.setContentSize(w.content.fittingSize)
                snap("voice\(suffix)-\(look)", w.window)
            }
            // the one setup screen (onboarding.html) in this app's window, 920 × 660, in each state the design draws; then the first call
            w.window.setContentSize(Window.setupSize)
            let shop = w.settings.call.project
            for (name, claude, mic, project, parts) in onboarding {
                let s = Setup(machine: claude == "signin" || claude == "signing" ? machines["signin"]! : ready)
                s.signingIn = claude == "signing"; s.mic = mic
                w.settings.setup = s; w.settings.call.project = project ? shop : nil; w.settings.firstCall = true; w.settings.downloadPicture = parts
                w.settings.openForPicture = "setup" // the bar drawn still
                let r = Rig(); r.model.stage = .idle; r.model.update(); w.setModel(r.model)
                snap("\(name)-\(look)", w.window)
            }
            w.settings.call.project = shop; w.settings.downloadPicture = nil; w.settings.openForPicture = nil; w.settings.setup = Setup(machine: ready)
            w.window.setContentSize(NSSize(width: 1280, height: 800))
            for (name, build) in firstCall {
                let r = Rig(); build(r); r.model.update(); w.setModel(r.model)
                snap("\(name)-\(look)", w.window)
            }
            w.settings.firstCall = false
            // hover: Mute and End on a live bar, Allow, Call again. REAL_POINTER=1: the window shows and the system pointer moves onto
            // each segment; otherwise mouse events are sent to the invisible window
            let real = ProcessInfo.processInfo.environment["REAL_POINTER"] == "1"
            w.window.acceptsMouseMovedEvents = true
            if real { w.window.alphaValue = 1; w.window.ignoresMouseEvents = false; w.window.level = .floating; w.window.center(); w.window.makeKeyAndOrderFront(nil); NSApp.activate() }
            for (name, build, fromRight) in [("mute", bars[0].1, 126.0), ("end", bars[0].1, 40.0), ("allow", bars[4].1, 126.0), ("again", bars[5].1, 126.0)] {
                let r = Rig(); build(r); r.model.update()
                w.content.rootView = AnyView(CallBar(model: r.model, two: false).id(name).padding(CV.s4).frame(width: 840).background(CV.ground).fixedSize())
                w.window.setContentSize(w.content.fittingSize)
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                let size = w.content.fittingSize, at = NSPoint(x: size.width - CV.s4 - fromRight, y: size.height / 2)
                if real { // the real pointer, moved by the system onto the segment from outside the bar
                    if let front = NSWorkspace.shared.frontmostApplication, front != .current { NSRunningApplication.current.activate(from: front, options: []) }
                    NSApp.activate(ignoringOtherApps: true); w.window.makeKeyAndOrderFront(nil)
                    if !NSApp.isActive { // a background app may not take focus by itself: one click on a blank corner of its own window
                        let blank = w.window.convertPoint(toScreen: NSPoint(x: 12, y: 12)), c = CGPoint(x: blank.x, y: NSScreen.screens[0].frame.height - blank.y)
                        for t in [CGEventType.leftMouseDown, .leftMouseUp] { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap) }
                    }
                    pump(0.4)
                    let top = NSScreen.screens[0].frame.height, to = w.window.convertPoint(toScreen: at)
                    for p in [NSPoint(x: to.x, y: to.y + 60), NSPoint(x: to.x, y: to.y + 20), to] {
                        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x, y: top - p.y), mouseButton: .left)?.post(tap: .cghidEventTap)
                        pump(0.12)
                    }
                    pump(0.4)
                    snap("hover-\(name)-\(look)", w.window)
                    continue
                }
                // the pointer enters each tracking area under it, then moves onto the segment: what the window server sends for a real pointer
                func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
                for v in views(w.window.contentView!) {
                    for area in v.trackingAreas where area.rect.contains(v.convert(at, from: nil)) {
                        let n = Int(bitPattern: Unmanaged.passUnretained(area).toOpaque())
                        if let e = NSEvent.enterExitEvent(with: .mouseEntered, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: w.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: n, userData: nil) {
                            (area.owner as? NSResponder)?.mouseEntered(with: e)
                        }
                    }
                }
                if let e = NSEvent.mouseEvent(with: .mouseMoved, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) { w.window.sendEvent(e) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                snap("hover-\(name)-\(look)", w.window)
            }
            // the launcher's panel and menu-bar item, on this app's call: the states final.html draws that this app has
            let none = AppSettings(persist: false)
            let cells = launcher.map { (cap, build) -> (String, PanelData) in
                let r = Rig(); let first = cap == "First run: no project"; build(r); r.model.update()
                w.settings.setup = Setup(machine: machines[cap] ?? ready)
                return (cap, PanelData(r.model.panelInput(first ? none : w.settings)))
            }
            w.content.rootView = AnyView(LazyVGrid(columns: Array(repeating: GridItem(.fixed(PanelView.size.width), spacing: 24, alignment: .top), count: 3), alignment: .leading, spacing: 28) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(c.0).font(.system(size: 13)).foregroundStyle(CV.ink2)
                        Image(nsImage: tinted(MenuBarItem.image(c.1.shape))).frame(maxWidth: .infinity).padding(.vertical, 3)
                            .background(CV.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(alignment: .leading) { if MenuBarItem.asking(c.1.shape) { Circle().fill(Palette.marigold).frame(width: 8, height: 8).offset(x: (PanelView.size.width - 52) / 2 + 34) } }
                        PanelView(data: c.1, active: true, still: true) { _ in }.frame(width: PanelView.size.width, height: PanelView.size.height)
                    }
                }
            }.padding(28).background(CV.ground).fixedSize())
            w.window.setContentSize(w.content.fittingSize)
            snap("launcher-\(look)", w.window)
        }
        // Escape's hand-off with the shared sheet: the first closes only the open list, the second Settings
        w.window.setContentSize(NSSize(width: 1280, height: 800))
        let er = Rig(); _ = er.live(); er.model.update(); w.setModel(er.model)
        w.settings.openForPicture = "Voice"; w.settings.shown = true; pump(0.5)
        let opened = w.settings.listOpen; _ = w.escape(); pump(0.3)
        let first = (w.settings.listOpen, w.settings.shown); _ = w.escape(); pump(0.3)
        let ok = opened && first == (false, true) && !w.settings.shown
        print("escape: list open \(opened); after the first, list \(first.0) settings \(first.1); after the second, settings \(w.settings.shown): \(ok ? "ok" : "WRONG")")
        w.settings.openForPicture = nil
        if !ok { exit(1) }
        if ProcessInfo.processInfo.environment["REAL_POINTER"] == "1" { liveChecks(w, snap: { snap($0, w.window) }) }
        print("app menu: " + (NSApp.mainMenu?.item(at: 0)?.submenu?.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | ") ?? "none"))
        try? FileManager.default.removeItem(at: lab) // the figures are drawn: the made-up projects go
        MainActor.assumeIsolated { IconBoard.draw(to: folder) } // the app icon in Docks (the figure run is on the main queue)
        // the name where the system shows it: the About panel (Dock, menu and Activity Monitor take it from the bundle)
        for (look, dark) in [("light", false), ("dark", true)] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            MainActor.assumeIsolated { NSApp.applicationIconImage = IconBoard.icon } // a debug run's About shows the app's icon too
            let about = w.aboutWindow; about.alphaValue = 0; about.orderFrontRegardless(); pump(0.4)
            snap("about-\(look)", about); about.orderOut(nil)
        }
        let done = { print("drew \(shots.count + 1) figures wide and narrow, and Settings, light and dark, in \(folder.path)"); NSApp.terminate(nil) }
        guard let link = arg("--scene").flatMap(URL.init(string:)) else { return done() }
        w.window.setContentSize(NSSize(width: 1280, height: 800))
        live(w, link: link, snap: { snap($0, w.window) }, done: done)
    }

    /// A made-up call through the real Call and the stand-in server, over the wire: the stand-in sends what call/server.mjs
    /// sends when a worker asks (its canUseTool: id, detail, worker, voice, full, step), the cards are answered by click, and
    /// the stand-in's record must hold both answers as POST /permit, exactly. Then every other control once, and the end.
    /// A wrong answer on the wire fails the run (exit 1).
    static func live(_ w: OhKevinKit.Window, link: URL, snap: @escaping (String) -> Void, done: @escaping () -> Void) {
        guard let server = try? Server(link: link) else { return done() }
        NSApp.appearance = NSAppearance(named: .aqua)
        let c = Call(server: server, log: nil)
        w.call = c; w.setModel(c.model)
        c.turns.start(echoCancelled: true); c.model.stage = .live; c.model.since = Date()
        server.listen({ c.receive($0, $1) }, failed: { print("the stand-in server stopped: \($0)"); c.fail(.stoppedStarting, $0) }, dropped: { c.dropped(true) }, back: { c.dropped(false) })
        let emit = { (e: [String: Any]) in server.post("/_emit", e) }
        func when(_ ok: @escaping () -> Bool, _ then: @escaping () -> Void, tries: Int = 100) {
            if ok() || tries == 0 { return then() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { when(ok, then, tries: tries - 1) }
        }
        func wrong(_ why: String) -> Never { FileHandle.standardError.write(Data("approvals over the wire: \(why)\n".utf8)); exit(1) }
        when({ c.model.status.live }) {
            emit(["type": "hello", "project": "/Users/you/Lab/api", "voices": ["af_heart", "am_michael"], "spokenYes": "safe"])
            emit(["type": "board", "state": "waiting", "workers": [["name": "api", "state": "waiting", "task": "fix the date tests", "step": "", "model": "opus"]]])
            emit(["type": "ask", "id": "a1", "detail": "Bash git commit -am fix", "worker": "api", "voice": true, "full": "git commit -am fix", "step": "run git commit"])
            emit(["type": "ask", "id": "a2", "detail": "Bash rm -rf dist", "worker": "api", "voice": false, "full": "rm -rf dist", "step": "run rm"])
            when({ c.model.cards.count == 2 }) {
                guard c.model.cards.map(\.ask.id) == ["a1", "a2"], c.model.cards.map(\.byVoice) == [true, false] else { wrong("the cards are \(c.model.cards.map(\.ask)), open \(c.model.status.asks.map(\.id)), live \(c.model.status.live), stage \(c.model.stage)") }
                snap("live")
                c.model.answer("a1", allow: true); c.model.answer("a2", allow: false)
                server.flush(5) {
                    Task { @MainActor in
                        let log = (try? await URLSession.shared.data(from: server.url("/_log"))).flatMap { try? JSONSerialization.jsonObject(with: $0.0) as? [[String: Any]] } ?? []
                        let permits = log.filter { $0["path"] as? String == "/permit" }.map { $0["body"] as? [String: Any] ?? [:] }
                        let got = permits.map { b in "\(b["id"] as? String ?? "?") \((b["allow"] as? Bool).map { String($0) } ?? "not a bool")" }
                        // server.mjs reads allow === true: a JSON boolean, not a number
                        guard got == ["a1 true", "a2 false"], permits.allSatisfy({ $0.count == 2 && CFGetTypeID($0["allow"] as CFTypeRef) == CFBooleanGetTypeID() }) else { wrong("the stand-in got \(permits)") }
                        // RECONNECT=1: the test stops the stand-in when told, and starts it again a few seconds later
                        func reconnect() {
                            print("DROP NOW"); fflush(stdout)
                            when({ c.model.reconnecting }, {
                                let word = c.model.capsule.rawValue; snap("live-reconnecting")
                                when({ !c.model.reconnecting }, {
                                    let ok = word == "Reconnecting" && c.model.stage == .live
                                    print("reconnect: dropped, the bar said \(word); came back, stage \(c.model.stage), bar \(c.model.capsule.rawValue): \(ok ? "ok" : "WRONG")")
                                    c.end(); if !ok { exit(1) }; done()
                                }, tries: 400)
                            }, tries: 200)
                        }
                        print("approvals over the wire: two cards from the stand-in's ask events; Approve and Deny posted /permit a1 true, a2 false")
                        emit(["type": "asked", "id": "a1", "allow": true]); emit(["type": "asked", "id": "a2", "allow": false]) // as call/server.mjs answers
                        when({ c.model.cards.isEmpty && c.model.answered.count == 2 }) {
                            if c.model.answered.count != 2 { wrong("the answers were not kept: \(c.model.answered)") }
                            snap("live-answered")
                            if ProcessInfo.processInfo.environment["RECONNECT"] == "1" { return reconnect() }
                            if ProcessInfo.processInfo.environment["RECONNECT"] == "lost" { // the stand-in never comes back: Call lost after 15 s
                                print("DROP NOW"); fflush(stdout)
                                return when({ { if case .failed = c.model.stage { true } else { false } }() }, {
                                    let ok = c.model.capsule == .lost
                                    print("reconnect gave up: stage \(c.model.stage), bar \(c.model.capsule.rawValue): \(ok ? "ok" : "WRONG")"); snap("live-lost")
                                    if !ok { exit(1) }; done()
                                }, tries: 500)
                            }
                            c.type("run the tests"); c.model.choose("am_michael"); c.setMuted(true); c.model.stop("api")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { c.setMuted(false); c.end(); snap("live-over"); done() }
                        }
                    }
                }
            }
        }
    }
}
