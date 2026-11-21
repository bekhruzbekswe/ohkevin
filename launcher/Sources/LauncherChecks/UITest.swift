import AppKit
import CallViews
import Carbon.HIToolbox
import SwiftUI
@testable import LauncherKit
import VoiceCore

/// Drives the real app with no person at the screen and no model called. The launcher starts a stub server
/// (Tests/stub-server.mjs) that speaks the call server's event stream, serves a stand-in call page that only connects,
/// and records what it is sent; a stand-in login shell puts a stand-in Claude Code CLI on the PATH. The real call window
/// opens in a throwaway Chrome profile. The test works the app the way VoiceOver does, through its accessibility tree:
/// it finds controls by what they say, presses them, and reads what the panel says. One first click is a real mouse
/// event, on a panel that opened by itself. Every state is drawn, light and dark, into the snapshots folder.
@MainActor
enum UITest {
    private static var failures = 0
    static var app: AppDelegate!
    static var me: Launcher!
    private static var folder: URL!
    private static var scratch: URL!
    private static var suffix = ""

    private static func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok    \(what)" : "FAIL  \(what)")
        fflush(stdout)
        if !ok { failures += 1 }
    }

    static func run(snapshots: URL) async -> Int32 {
        folder = snapshots
        try? FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        scratch = FileManager.default.temporaryDirectory.appending(path: "launcher-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard prepare() else { print("FAIL  could not prepare the stand-ins"); return 1 }
        // What an assistive app sets: SwiftUI then builds the accessibility tree this test reads and presses.
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: attribute)
        }

        var s = CallSettings()
        s.choose(scratch.appending(path: "code/web").path)
        s.choose(scratch.appending(path: "code/a-project-with-a-rather-long-name").path)
        s.choose(scratch.appending(path: "code/api").path)
        s.hasCalled = true; s.launchedBefore = true
        me = Launcher(settings: s, defaults: nil, home: scratch.appending(path: "home"),
                      setup: Setup(callFolder: scratch.appending(path: "call"), support: scratch.appending(path: "support"), ports: 4810...4810, chromeProfile: scratch.appending(path: "chrome-profile"),
                                   chromeArguments: ["--headless=new"], spotlight: false)) // no local voice on this stand-in Mac
        app = AppDelegate(launcher: me)
        NSApp.delegate = app
        let left = await openOrphanWindow()
        check(left != nil, "a call window is left running, as after a crash")
        app.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        check(await until(6) { left?.isTerminated ?? true }, "the launcher closes it as it starts: it may still be listening")
        await me.checkHealth().value
        check(me.missingItems?.map(\.id) == [.packages, .signIn], "missing on this stand-in Mac: the packages and the sign-in (\(me.missingItems?.map(\.title) ?? []))")

        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            suffix = dark ? "dark" : "light"
            print("— \(suffix)")
            await scenario(first: !dark)
        }
        await settingsWindow()
        menuBarIcons()
        app.close()
        _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        check(app.panel.isVisible, "opening the app again opens the panel: the way in when macOS hides the icon")
        app.close()
        check(runningInstance(profile: scratch.appending(path: "chrome-profile")) == nil, "no call window is left open")
        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }

    // MARK: The story, through the real controls

    private static func ready() -> Bool { shows("Oh Kevin") }

    private static func scenario(first: Bool) async {
        // Setup: each step done from the door, then Ready by itself.
        try? FileManager.default.removeItem(at: scratch.appending(path: "signed-in"))
        await me.checkHealth().value
        app.close(); app.item.button?.performClick(nil) // closed first: a click on an open panel would close it
        // The panel points at the setup screen (the three rows); the download starts by itself and is never a step.
        check(await until(3) { shows("1 thing to go") && shows("Next: sign in to Claude.") && button("Continue") != nil }, "setup: “1 thing to go”, “Next: sign in to Claude.”, the door is Continue")
        check(button("Start call") == nil, "…and no Start call")
        key(kVK_Return)
        try? await Task.sleep(for: .milliseconds(500))
        check(me.phase == .idle && me.serverPID == nil, "Return does nothing while something is missing")
        if first {
            check(await until(180) { me.missingItems?.contains { $0.id == .packages } == false }, "the download starts by itself and finishes (npm ci, for real, in a scratch copy)")
        }
        check(me.setupScreen.rows[0].control == .button("Sign in", .gold, .signIn), "the setup screen's first row: Sign in, the one gold")
        snap("2-setup")
        me.handle(SetupIntent.signIn)
        check(await until(3) { shows("Finish in your browser.") }, "Sign in is pressed on the setup screen: the panel says “Finish in your browser.”")
        snap("2c-signing-in")
        check(await until(12) { button("Start call") != nil && ready() }, "the stand-in CLI signed in through a lent terminal; the panel is Ready by itself")

        // Ready, and the first run.
        check(shows("A voice call with Claude Code.") && shows("Project, api"), "Ready: one line, the project, Start call")
        let more = tree(panelView).first { ($0.value(forKey: "accessibilityLabel") as? String) == "More" }
        let role = more?.value(forKey: "accessibilityRole") as? String ?? "none"
        check(role == "AXMenuButton" || role == "AXPopUpButton", "the corner control is a menu (\(role))")
        snap("1-ready")
        let saved = me.settings
        me.settings.project = nil
        check(await until(2) { shows("1 thing to go") && shows("Next: the project.") && button("Continue") != nil }, "no project: a thing to go, “Next: the project.”")
        snap("0-first-run")
        me.settings = saved
        check(await until(3) { button("Start call") != nil && ready() }, "the project is back: the panel redraws as Ready") // pressed only once it has

        // Cancel, in the first moment (the health check) and while connecting: back to Ready, nothing ends.
        check(press("Start call"), "Start call is pressed")
        _ = await until(1) { me.phase == .starting }
        key(kVK_Escape)
        try? await Task.sleep(for: .seconds(1.5))
        check(me.phase == .idle && me.serverPID == nil && ready() && !shows("Call ended"), "Escape during the check cancels: no call starts")
        touch("slow-check") // the sign-in check takes 2 s, so the next Start lands inside the first one's check
        let before = starts()
        check(press("Start call"), "Start call, with a slow check")
        _ = await until(1) { me.phase == .starting }
        key(kVK_Escape)
        _ = await until(1) { me.phase == .idle && button("Start call") != nil } // the panel redrawn as Ready
        check(press("Start call"), "…Escape, and Start call again inside the same check")
        check(await until(5) { me.serverPID != nil }, "…a server starts")
        try? await Task.sleep(for: .seconds(3)) // past the end of both checks
        check(starts() - before == 1 && servers() == 1, "Cancel then Start inside the check starts exactly one server (\(starts() - before) started, \(servers()) running)")
        remove("slow-check")
        check(press("End call"), "End call")
        check(await until(6) { servers() == 0 && shows("Call ended.") }, "…and none is left")
        app.close(); app.item.button?.performClick(nil)
        _ = await until(2) { button("Start call") != nil }
        check(press("Start call"), "Start call again")
        check(await until(3) { shows("Starting the call.") && me.serverPID != nil }, "Starting the call., with a server started")
        snap("3-starting")
        let started = me.serverPID
        check(press("Cancel"), "Cancel is pressed")
        check(await until(2) { me.phase == .idle && ready() && !shows("Call ended") && !shows("Ending") }, "Cancel goes back to Ready, never “Call ended.”")
        check(await until(3) { started.map { !alive($0) } ?? false }, "…and its server is gone")

        // A server that breaks while starting: no work existed.
        touch("call/die")
        check(press("Start call"), "Start call, with a server that breaks at once")
        check(await until(4) { shows("The call didn’t start") && shows("Something went wrong as it started.") && button("Try again") != nil },
              "it says the call didn’t start, and offers Try again")
        snap("17b-broke-while-starting")
        remove("call/die")
        app.close(); app.item.button?.performClick(nil)
        check(await until(2) { ready() && button("Start call") != nil }, "closing the panel lets a failure go: Ready again")

        // On a call, with the real call window (the stand-in page) connected.
        check(press("Start call"), "Start call")
        check(await until(8) { shows("On a call") }, "“On a call”")
        check(await until(20) { me.status.pages == 1 }, "the call window opened in its own Chrome and its page connected")
        if first, let window = me.callWindow { // a lock that outlived its Chrome, its number now another Chrome's (or not Chrome)
            let profile = me.setup.chromeProfile, other = scratch.appending(path: "chrome-profile-old")
            try? FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            for pid in [window.processIdentifier, getpid()] {
                let lock = other.appending(path: "SingletonLock")
                try? FileManager.default.removeItem(at: lock)
                try? FileManager.default.createSymbolicLink(atPath: lock.path, withDestinationPath: "host-\(pid)")
                check(runningInstance(profile: other) == nil, "a stale lock naming \(pid == getpid() ? "a process that is not Chrome" : "a Chrome on another profile") is not taken as the call window")
            }
            check(runningInstance(profile: profile)?.processIdentifier == window.processIdentifier, "…while the call window's own lock is")
        }
        check(shows("Show the call") && button("End call") != nil && !shows("api"), "on a call: the timer, the pill, “Show the call”; no folder, no workers")
        check(await until(3) { shows("Listening") }, "the voice is listening (the server says so on connect)")
        snap("4-listening")

        // The voice's state, as the server relays it.
        await emit(["type": "voice", "state": "speaking", "canMute": true])
        check(await until(2) { shows("Speaking") }, "the voice speaks: “Speaking”")
        snap("5-speaking")
        await emit(["type": "voice", "state": "thinking", "canMute": true])
        check(await until(2) { shows("Thinking") }, "…“Thinking”")
        snap("6-thinking")
        await emit(["type": "voice", "state": "listening", "canMute": true])

        // Mute: asked of the page, shown only when the page says so.
        check(press("Mute"), "Mute is pressed")
        check(await until(3) { count("/mute") == 1 }, "…POST /mute {on: true}")
        check(shows("Listening") && !shows("Muted"), "the panel does not claim it until the page says so")
        await emit(["type": "voice", "state": "muted", "canMute": true])
        check(await until(2) { shows("Muted") && button("Unmute") != nil }, "the page says muted: “Muted”, and the button reads Unmute")
        snap("7-muted")
        check(press("Unmute"), "Unmute is pressed")
        await emit(["type": "voice", "state": "listening", "canMute": true])
        await emit(["type": "voice", "state": "listening", "canMute": false])
        check(await until(2) { shows("Listening") }, "the page says it cannot mute")
        _ = press("Mute"); try? await Task.sleep(for: .milliseconds(400))
        check(await freshCount("/mute") == 2, "…Mute is disabled: pressing it sends nothing")
        await emit(["type": "voice", "state": "listening", "canMute": true])

        // Someone asks: a step a spoken yes can approve. The panel stays shut; the item gets its dot.
        app.close()
        await emit(["type": "ask", "id": "v1", "detail": "Bash git commit -m x", "worker": "api", "voice": true, "full": "git commit -m x"])
        try? await Task.sleep(for: .milliseconds(700))
        check(!app.panel.isVisible && app.asking, "a step your voice can approve: a marigold dot in the menu-bar item, the panel stays shut")
        app.item.button?.performClick(nil)
        check(await until(2) { shows("We need you") && button("Answer in the call") != nil && !shows("api") && !shows("git commit") }, "“We need you”, “Answer in the call”: no names, no counts, no folder")
        snap("8-ask")
        await emit(["type": "asked", "id": "v1", "allow": true])
        check(await until(2) { shows("On a call") && !app.asking }, "answered: the dot and the words go")

        // A step that needs a click: the panel opens by itself, not key, and the first real click counts.
        app.close()
        await emit(["type": "ask", "id": "c1", "detail": "Bash git push origin main", "worker": "api", "voice": false, "full": "git push origin main"])
        check(await until(2) { app.panel.isVisible && !app.panel.isKeyWindow }, "a step that needs a click opens the panel by itself, without the keyboard")
        await mouseClick(button("Mute"))
        check(await until(3) { count("/mute") == 3 }, "a first real click on the panel that opened by itself counts")
        await emit(["type": "asked", "id": "c1", "allow": false])
        check(await until(3) { !app.panel.isVisible }, "the panel that opened by itself closes a second after the last ask")

        // A dropped feed (sleep, a hiccup): open requests come again, but are not news.
        await emit(["type": "ask", "id": "c2", "detail": "Bash rm -rf dist", "worker": "api", "voice": false, "full": "rm -rf dist"])
        _ = await until(2) { app.panel.isVisible }
        app.close()
        await post("/_drop")
        try? await Task.sleep(for: .seconds(1.5))
        check(!app.panel.isVisible && me.status.asks.map(\.id) == ["c2"], "after the feed reconnects the request is still there, and the panel does not open again")
        await emit(["type": "asked", "id": "c2", "allow": false])

        // The page's microphone is blocked: the panel comes to you, says so, and opens the right settings.
        app.close()
        await emit(["type": "mic", "blocked": "mac"])
        check(await until(2) { app.panel.isVisible && !app.panel.isKeyWindow }, "a blocked microphone opens the panel by itself, without the keyboard")
        check(await until(2) { shows("Mic blocked") && shows("Claude Code can’t hear you.") && button("Allow microphone") != nil }, "“Mic blocked”, “Allow microphone”")
        _ = press("Mute"); try? await Task.sleep(for: .milliseconds(400))
        check(await freshCount("/mute") == 3, "…Mute is disabled: pressing it sends nothing")
        check(Launcher.macMicrophone.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
              "…macOS keeps it from Chrome: Privacy & Security › Microphone (not pressed here: System Settings stays shut)")
        snap("12-mic-blocked")
        check(Launcher.chromeMicrophone(port: me.port).absoluteString == "chrome://settings/content/siteDetails?site=http%3A%2F%2F127.0.0.1%3A\(me.port)",
              "…and Chrome's own settings for the call page's site (not pressed here either)")
        await emit(["type": "mic", "blocked": ""])
        check(await until(2) { !shows("Mic blocked") && shows("Listening") }, "it hears again: the pill is live")
        app.close(); app.item.button?.performClick(nil)

        // The call window closed: the call can't hear; Show the call opens it again.
        me.callWindow?.terminate()
        check(await until(8) { shows("Not listening") && shows("Its window isn’t open.") && button("Show the call") != nil }, "its window gone: “Not listening”, “Its window isn’t open.”")
        snap("12b-window-closed")
        check(press("Show the call"), "Show the call is pressed")
        check(await until(20) { me.status.pages == 1 && !shows("Its window isn’t open.") }, "…the window opens again")

        // End call with the hand-over: the window goes at once; the line says what really happened.
        await emit(["type": "session", "id": "s1", "worker": "api"])
        _ = await until(1) { !me.status.sessions.isEmpty }
        me.settings.openInClaudeApp = false // changed during the call: it applies to the next one
        let window = me.callWindow
        check(press("End call"), "End call is pressed")
        check(await until(2) { shows("Ending the call.") && shows("Then its work opens in the Claude app.") }, "“Ending the call.”: the work goes to the Claude app, as when the call started")
        // headless Chrome ignores the polite quit, so the launcher's forced one (after 3 s) is what closes it there
        check(await until(5) { window?.isTerminated ?? true }, "the call window closes as the ending begins, not when the server is gone")
        check(await until(2) { count("SIGINT") == 1 }, "…the server is asked to hand over (SIGINT, as Ctrl-C)")
        snap("14-ending")
        check(await until(6) { shows("Call ended.") && shows("Its work is open in the Claude app.") }, "the hand-over opened: “Its work is open in the Claude app.”")
        snap("15-call-ended")
        me.settings.openInClaudeApp = true
        app.close(); app.item.button?.performClick(nil)
        check(await until(2) { ready() && !shows("Call ended") }, "after the panel closes it is plain Ready")

        // The hand-over printed its command instead of opening: the line says the work is saved.
        touch("call/printed")
        await startAndWait()
        await emit(["type": "session", "id": "s2", "worker": "api"])
        _ = await until(1) { !me.status.sessions.isEmpty }
        check(press("End call"), "End Call, with a hand-over that will not open")
        _ = await until(1) { shows("Ending the call.") }
        await post("/hangup") // a second word while it hands over (the page's End, racing the window's close)
        check(await until(6) { shows("Call ended.") && shows("Its work is saved in Claude Code.") }, "it did not open: “Its work is saved in Claude Code.”")
        check(count("SIGINT") == 1 && logSays("exited with code 3"), "…a second word during the hand-over did not cut it short: one SIGINT, exit code 3")
        snap("15b-call-ended-saved")
        remove("call/printed")
        app.close(); app.item.button?.performClick(nil)

        // The page's own End, even when the launcher's feed misses the event.
        await startAndWait()
        await emit(["type": "session", "id": "s3", "worker": "api"])
        _ = await until(1) { !me.status.sessions.isEmpty }
        await post("/_drop")
        await post("/hangup")
        try? await Task.sleep(for: .milliseconds(150))
        check(me.phase == .live, "the page's End, with the launcher's feed down: the event is missed")
        check(await until(6) { shows("Call ended.") && shows("Its work is open in the Claude app.") },
              "…the call still ends when the server does, and says “Its work is open in the Claude app.”")
        app.close(); app.item.button?.performClick(nil)

        // A call that breaks is started again once, on the same address with the same key: the same window reconnects and the
        // call goes on in it. A second break is a lost call, and "Call again" brings it back the same way.
        await startAndWait()
        let window0 = me.callWindow?.processIdentifier, key0 = me.key, port0 = me.port
        /// A call that is live again on a server other than `old`: the old one gone, the new one answering, the page back on it.
        func restarted(from old: Int32?) -> Bool { me.serverPID != nil && me.serverPID != old && me.phase == .live && me.status.live && me.status.pages == 1 }
        let pid0 = me.serverPID
        app.close()
        await post("/_exit")
        check(await until(10) { restarted(from: pid0) }, "the server broke mid-call: it is started again and the same window reconnects")
        check(me.key == key0 && me.port == port0 && me.callWindow?.processIdentifier == window0 && servers() == 1, "…same port, same key, same window, one server")
        check(!shows("Call lost") && !app.panel.isVisible, "…and no “Call lost” anywhere")
        let pid1 = me.serverPID // the second break comes only once the restarted server is the one answering
        await post("/_exit")
        check(await until(8) { app.panel.isVisible && shows("Call lost") && button("Call again") != nil }, "a second break is a lost call: the panel comes to you, with Call again")
        check(me.callWindow.map { !$0.isTerminated } ?? false, "…and its window is left open, for Call again to bring back")
        snap("16-call-stopped")
        app.close(); app.item.button?.performClick(nil)
        check(await until(2) { shows("Call lost") && button("Call again") != nil }, "closing the panel does not forget it: still “Call lost”, while its window is there to come back to")
        check(press("Call again"), "Call again is pressed")
        check(await until(10) { restarted(from: pid1) }, "…the same window reconnects to the call, started again")
        check(me.key == key0 && me.port == port0 && me.callWindow?.processIdentifier == window0 && servers() == 1, "…same key, same window, one server")
        check(press("End call"), "End call")
        _ = await until(6) { shows("Call ended.") }
        app.close(); app.item.button?.performClick(nil)

        // A server that never answers: 30 seconds, enforced.
        if first {
            touch("call/silent")
            let t0 = Date()
            check(press("Start call"), "Start Call, with a server that never answers")
            check(await until(34) { shows("Nothing answered for 30 seconds.") }, "a server that never answers: “The call didn’t start”")
            check(abs(Date().timeIntervalSince(t0) - 30) < 3, String(format: "…after 30 seconds (%.1f s)", Date().timeIntervalSince(t0)))
            snap("17-didnt-start")
            remove("call/silent")
            app.close(); app.item.button?.performClick(nil)
        }

        // A call the page ended whose server never finishes: ended for it after 30 seconds.
        if first {
            touch("call/stuck")
            await startAndWait()
            await emit(["type": "session", "id": "s4", "worker": "api"])
            _ = await until(1) { !me.status.sessions.isEmpty }
            let t0 = Date()
            await post("/hangup")
            check(await until(2) { shows("Ending the call.") }, "the page's End, on a server whose ending never finishes: “Ending the call…”")
            check(await until(34) { shows("Call ended.") }, "…force-ended")
            check(abs(Date().timeIntervalSince(t0) - 30) < 3, String(format: "…after 30 seconds (%.1f s)", Date().timeIntervalSince(t0)))
            check(shows("Its work is saved in Claude Code.") && logSays("exited with code 9"), "…it says the work is saved, not opened; the server was killed")
            remove("call/stuck")
            app.close(); app.item.button?.performClick(nil)
        }

        // A Node that cannot be launched: the product's own words.
        touch("node-broken")
        check(press("Start call"), "Start Call, with a Node that cannot be launched")
        check(await until(5) { shows("Node couldn’t be started on this Mac.") }, "it says “Node couldn’t be started on this Mac.”")
        snap("17c-node")
        remove("node-broken")
        app.close(); app.item.button?.performClick(nil)

        // A call window left by a launcher that crashed is taken over, and closed with the next call.
        let orphan = await openOrphanWindow()
        check(orphan != nil, "a call window is left running, as after a crash")
        await startAndWait(pageToo: false)
        check(me.callWindow?.processIdentifier == orphan?.processIdentifier, "the next call takes it over as its own window")
        check(press("End call"), "End Call")
        check(await until(6) { orphan?.isTerminated ?? true }, "…and it closes with the call")
        _ = await until(5) { shows("Call ended.") }

        // A panel that opened by itself is taken into the keyboard by a click on the icon, not closed.
        app.close()
        app.open(keyboard: false, itself: true)
        app.clicked()
        check(app.panel.isVisible, "a click on the icon on a panel that opened by itself keeps it open")
        key(kVK_Escape)
        check(await until(1) { !app.panel.isVisible }, "Escape closes the panel")
        app.item.button?.performClick(nil)
    }

    /// pageToo: false when the window is a left-behind one: a headless Chrome never opens the call's page in it.
    private static func startAndWait(pageToo: Bool = true) async {
        check(press("Start call"), "Start Call")
        let live = await until(8) { shows("On a call") }
        var connected = true
        if pageToo { connected = await until(20) { me.status.pages == 1 } }
        check(live && connected, "…on a call\(pageToo ? ", its window connected" : "")")
    }

    // MARK: Settings

    private static func settingsWindow() async {
        for dark in [false, true] { // no local voice: the Download row
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            suffix = dark ? "dark" : "light"
            app.showSettings()
            guard let view = app.settings?.contentView else { return check(false, "Settings opens") }
            check(await until(2) { shows("A voice on this Mac: 381 MB.", in: view) && me.kokoro == nil }, "no local voice: Settings offers it")
            picture(SettingsView(launcher: me), "settings-0-no-voice", background: .windowBackgroundColor, radius: 0)
            app.settings?.close()
        }
        let voice = CallSettings.defaultKokoro(home: me.home) // a stand-in voice, as after the download
        for file in ["kokoro-runner", "libonnxruntime.dylib", "libespeak-ng.dylib", "espeak-ng-data/phontab", "kokoro-v1.0.onnx", "voices-v1.0.bin"] {
            try? FileManager.default.createDirectory(at: voice.appending(path: file).deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: voice.appending(path: file).path, contents: Data(), attributes: [.posixPermissions: 0o755])
        }
        await me.checkHealth().value
        check(me.kokoro?.path == voice.path, "the voice in the app's folder is found")
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            suffix = dark ? "dark" : "light"
            app.showSettings()
            guard let view = app.settings?.contentView else { return check(false, "Settings opens") }
            check(await until(2) { shows("Claude Code model", in: view) && shows("Speaks with", in: view) },
                  "Settings: one page, Calls and This Mac")
            check(!shows("Voice model", in: view) && !shows("shortcut", in: view) && !shows("Locate", in: view), "…no voice model, no shortcut, no Locate…")
            picture(SettingsView(launcher: me), "settings-1", background: .windowBackgroundColor, radius: 0)
            app.item.button?.performClick(nil)
            await startAndWait()
            app.showSettings()
            check(await until(2) { shows("You’re on a call. Changes apply to the next one.", in: view) }, "on a call it says changes apply to the next one")
            me.settings.spokenYes = .nothing
            picture(SettingsView(launcher: me), "settings-2-on-a-call", background: .windowBackgroundColor, radius: 0)
            me.settings.spokenYes = .safeSteps
            app.settings?.close()
            app.item.button?.performClick(nil)
            check(press("End call"), "End Call")
            _ = await until(5) { shows("Call ended") }
            app.close()
        }
    }

    // MARK: The menu-bar icon in each state

    private static func menuBarIcons() {
        let shapes: [MenuShape] = [.rest(setup: false), .rest(setup: true), .call(.listening, muted: false, asking: false), .call(.speaking, muted: false, asking: false),
                                   .call(.thinking, muted: false, asking: false), .call(.dots, muted: true, asking: false), .call(.listening, muted: false, asking: true),
                                   .call(.dots, muted: true, asking: true), .lost(asking: false), .lost(asking: true), .reconnecting(asking: false), .reconnecting(asking: true)]
        for dark in [false, true] {
            let images = shapes.map { Snapshots.menuImage($0, dark: dark) }
            let size = NSSize(width: images.map(\.size.width).reduce(0, +), height: images[0].size.height)
            write(size: size, to: folder.appending(path: "menu-bar-icons-\(dark ? "dark" : "light").png")) {
                var x: CGFloat = 0
                for image in images { image.draw(at: NSPoint(x: x, y: 0), from: .zero, operation: .sourceOver, fraction: 1); x += image.size.width }
            }
        }
    }

    // MARK: Stand-ins

    /// The stand-in call server and call folder, a login shell whose PATH puts a stand-in Claude Code CLI (and a Node
    /// that can be made to fail) first, and the projects.
    private static func prepare() -> Bool {
        let fm = FileManager.default
        guard let env = Shell.environment(), let node = Shell.which("node", path: env["PATH"]),
              let out = VoiceCore.run(node, ["-p", "process.execPath"], environment: env), out.status == 0 else { return false }
        let realNode = String(decoding: out.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let call = scratch.appending(path: "call"), bin = scratch.appending(path: "bin")
        for dir in [call, bin, scratch.appending(path: "code/api"), scratch.appending(path: "code/web"),
                    scratch.appending(path: "code/a-project-with-a-rather-long-name")] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let stub = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Tests/stub-server.mjs").standardized
        try? fm.copyItem(at: stub, to: call.appending(path: "server.mjs"))
        for file in ["package.json", "package-lock.json"] { try? fm.copyItem(at: repoCallFolder.appending(path: file), to: call.appending(path: file)) }
        let s = scratch.path
        let support = scratch.appending(path: "support"), nodeShim = Runtime.node(support: support).path.replacingOccurrences(of: s + "/", with: "")
        try? fm.createDirectory(at: scratch.appending(path: nodeShim).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(at: Runtime.folder(support: support).appending(path: "lib"), withDestinationURL: URL(filePath: realNode).deletingLastPathComponent().appending(path: "../lib")) // its npm
        let scripts = [
            "bin/claude": """
            #!/bin/sh
            # A stand-in Claude Code CLI: signed in once "auth login" ran in a terminal.
            case "$1 $2" in
              "auth status") [ -e '\(s)/slow-check' ] && sleep 2
                [ -e '\(s)/signed-in' ] && echo '{"loggedIn": true}' || echo '{"loggedIn": false}' ;;
              "auth login") [ -t 0 ] && [ -t 1 ] || exit 1; sleep 1; touch '\(s)/signed-in' ;;
              *) exit 1 ;;
            esac
            """,
            nodeShim: """
            #!/bin/sh
            # The real Node, as the app's Runtime, unless the test has broken it on purpose.
            if [ -e '\(s)/node-broken' ] && [ "$1" = "-p" ]; then printf '/nonexistent/node\\n24.15.0\\n'; exit 0; fi
            exec '\(realNode)' "$@"
            """,
            "shell": """
            #!/bin/sh
            # A stand-in login shell: its PATH has the stand-ins first, then the real Node's folder for npm.
            PATH='\(bin.path):\(URL(filePath: realNode).deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin'; export PATH
            for last; do :; done
            exec /bin/sh -c "$last"
            """,
        ]
        for (path, text) in scripts {
            let url = scratch.appending(path: path)
            guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return false }
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        setenv("SHELL", scratch.appending(path: "shell").path, 1)
        return true
    }

    /// Call servers running from the stand-in call folder.
    private static func servers() -> Int {
        guard let ps = VoiceCore.run(URL(filePath: "/bin/ps"), ["-ax", "-ww", "-o", "command="]) else { return -1 }
        return String(decoding: ps.output, as: UTF8.self).split(separator: "\n").filter { $0.contains(scratch.appending(path: "call/server.mjs").path) }.count
    }

    private static func starts() -> Int {
        ((try? String(contentsOf: scratch.appending(path: "call/starts"), encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    private static func logSays(_ text: String) -> Bool { ((try? String(contentsOf: me.logURL, encoding: .utf8)) ?? "").contains(text) }

    private static func touch(_ path: String) { FileManager.default.createFile(atPath: scratch.appending(path: path).path, contents: Data()) }
    private static func remove(_ path: String) { try? FileManager.default.removeItem(at: scratch.appending(path: path)) }

    /// A Chrome on the call window's profile, started the way the launcher starts it, then left behind.
    private static func openOrphanWindow() async -> NSRunningApplication? {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else { return nil }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--user-data-dir=\(me.setup.chromeProfile.path)", "--app=data:text/html,left behind", "--no-first-run", "--no-default-browser-check"] + ["--headless=new"]
        let opened = try? await NSWorkspace.shared.openApplication(at: chrome, configuration: config)
        _ = await until(10) { runningInstance(profile: me.setup.chromeProfile) != nil }
        return opened
    }

    // MARK: Reading and working the app, as VoiceOver does

    private static var panelView: NSView { app.panel.hostingView }

    private static func tree(_ e: Any) -> [NSObject] {
        let kids: [Any] = (e as? NSView)?.accessibilityChildren() ?? ((e as? NSObject)?.value(forKey: "accessibilityChildren") as? [Any]) ?? []
        return kids.compactMap { $0 as? NSObject }.flatMap { [$0] + tree($0) }
    }

    private static func words(_ e: NSObject) -> String {
        let label = e.value(forKey: "accessibilityLabel") as? String, value = e.value(forKey: "accessibilityValue") as? String
        return label == value ? label ?? "" : [label, value].compactMap { $0 }.joined(separator: " ")
    }

    static func shows(_ text: String, in view: NSView? = nil) -> Bool {
        guard view != nil || app.panel.isVisible else { return false }
        return tree(view ?? panelView).contains { words($0).contains(text) }
    }

    private static func button(_ label: String, in group: String? = nil) -> NSObject? {
        var scope = tree(panelView)
        if let group, let card = scope.first(where: { ($0.value(forKey: "accessibilityLabel") as? String)?.contains(group) == true }) { scope = tree(card) }
        return scope.first { ($0.value(forKey: "accessibilityRole") as? String) == "AXButton" && ($0.value(forKey: "accessibilityLabel") as? String) == label }
    }

    @discardableResult
    static func press(_ label: String, in group: String? = nil) -> Bool {
        guard app.panel.isVisible, let b = button(label, in: group) else { return false }
        return b.perform(NSSelectorFromString("accessibilityPerformPress")) != nil
    }

    /// Presses the button whose words hold text (the card's command, which opens when pressed).
    @discardableResult
    private static func press(buttonContaining text: String) -> Bool {
        guard let e = tree(panelView).first(where: { ($0.value(forKey: "accessibilityRole") as? String) == "AXButton" && words($0).contains(text) }) else { return false }
        return e.perform(NSSelectorFromString("accessibilityPerformPress")) != nil
    }

    private static func scrolls(in group: String) -> Bool {
        guard let card = tree(panelView).first(where: { ($0.value(forKey: "accessibilityLabel") as? String)?.contains(group) == true }) else { return false }
        return tree(card).contains { ($0.value(forKey: "accessibilityRole") as? String) == "AXScrollArea" }
    }

    /// The command line shown in a card.
    private static func exactText(of question: String) -> String? {
        guard let card = tree(panelView).first(where: { ($0.value(forKey: "accessibilityLabel") as? String)?.contains(question) == true }) else { return nil }
        return tree(card).map(words).first { !$0.isEmpty && !$0.contains("?") && !["Deny", "Approve"].contains($0) && !$0.contains("say") && !$0.contains("click") && $0 != $0.uppercased() }
    }

    /// A real mouse click, down and up, at the control's place on screen: what a person's first click does.
    private static func mouseClick(_ element: NSObject?) async {
        guard let element, let frame = element.value(forKey: "accessibilityFrame") as? NSRect else { return check(false, "the control is there to click") }
        let p = app.panel.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: app.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func key(_ code: Int, command: Bool = false) {
        app.panel.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: app.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                             isARepeat: false, keyCode: UInt16(code))!)
    }

    // MARK: The stub server

    private static func board(_ workers: [(String, String, String, String, String)]) -> [String: Any] {
        ["type": "board", "state": workers.contains { $0.1 != "idle" } ? "working" : "idle",
         "workers": workers.map { ["name": $0.0, "state": $0.1, "task": $0.2, "step": $0.3, "model": $0.4] }]
    }

    private static func emit(_ event: [String: Any]) async {
        await post("/_emit", event)
        try? await Task.sleep(for: .milliseconds(150))
    }

    private static func post(_ path: String, _ body: [String: Any] = [:]) async {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(me.port)\(path)")!)
        request.httpMethod = "POST"
        request.setValue(me.key, forHTTPHeaderField: "x-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    private static var lastLog: [[String: Any]] = []
    private static func refreshLog() {
        Task {
            guard let data = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(me.port)/_log?k=\(me.key)")!).0,
                  let log = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            lastLog = log
        }
    }

    private static func posted(_ path: String, id: String, allow: Bool) -> Bool {
        refreshLog()
        return lastLog.contains { ($0["path"] as? String) == path && ($0["body"] as? [String: Any])?["id"] as? String == id && ($0["body"] as? [String: Any])?["allow"] as? Bool == allow }
    }

    /// The count as the server has it now: count() answers from the last look, which a single check may precede.
    private static func freshCount(_ path: String) async -> Int {
        if let data = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(me.port)/_log?k=\(me.key)")!).0,
           let log = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { lastLog = log }
        return lastLog.filter { ($0["path"] as? String) == path }.count
    }

    private static func count(_ path: String) -> Int {
        refreshLog()
        return lastLog.filter { ($0["path"] as? String) == path }.count
    }

    // MARK: Pictures

    /// The panel as it is now: the app's own panel view on its live state, drawn afresh, because with the screen locked
    /// the window server does not draw the window itself. The system material does not draw into a picture: the panel's
    /// colour from the mockups stands in.
    private static func snap(_ name: String) {
        let dark = suffix == "dark"
        picture(PanelView(data: me.panel, active: false, still: true, send: { _ in }), "panel-\(name)",
                background: dark ? NSColor(srgbRed: 0.165, green: 0.165, blue: 0.173, alpha: 1) : NSColor(srgbRed: 0.945, green: 0.945, blue: 0.953, alpha: 1), radius: 14)
    }

    private static func picture<V: View>(_ view: V, _ name: String, background: NSColor, radius: CGFloat) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: suffix == "dark" ? .darkAqua : .aqua)
        window.contentView = host
        host.setFrameSize(host.fittingSize)
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let size = host.bounds.size
        write(size: size, to: folder.appending(path: "\(name)-\(suffix).png")) {
            background.setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: radius, yRadius: radius).fill()
            rep.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        window.contentView = nil
    }

    /// Draws at twice the size in points, as a Retina screen shows it.
    static func write(size: NSSize, to url: URL, draw: () -> Void) {
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        try? out.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Waits up to seconds for condition to hold, looking every tenth of a second.
@MainActor
func until(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !condition() {
        if Date() > end { return false }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return true
}
