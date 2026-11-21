import AppKit
import CallViews
import SwiftUI
@testable import LauncherKit
import VoiceCore

/// `--first-run <folder>`: a Mac with nothing on it, walked from zero with pictures and timings, never touching the real Application
/// Support or Logs folders (everything lives in <folder>/work). Node and the packages are downloaded for real; the local voice is only
/// offered, never downloaded; the call is a stand-in server (Tests/stub-server.mjs) with a headless Chrome window, so nothing is spoken
/// and nothing reaches Claude. Pictures (NN-step.png, offscreen renders of the panel) and a log go to <folder>.
@MainActor
enum FirstRun {
    private static var log = ""
    private static var out: URL!

    private static func say(_ s: String) { print(s); fflush(stdout); log += s + "\n" }
    private static func load() -> String { var l = [Double](repeating: 0, count: 3); getloadavg(&l, 3); return String(format: "load %.1f", l[0]) }
    private static func time(_ since: Date) -> String { String(format: "%.1f s", Date().timeIntervalSince(since)) }

    private static func words(_ me: Launcher) -> String {
        let d = me.panel
        let l2: String
        switch d.line2 { case .text(let t): l2 = t; case .timer: l2 = "(clock)" }
        return "“\(d.line1)” / “\(l2)” / door “\(d.door.label)”\(d.door.enabled ? "" : " (disabled)")"
    }

    private static func picture(_ me: Launcher, _ name: String) {
        let view = PanelView(data: me.panel, active: false, still: true, send: { _ in }).environment(\.colorScheme, .light)
        if let image = Snapshots.render(view, dark: false) { Snapshots.write(image, out.appending(path: "\(name).png")) }
        say("      picture \(name).png — \(words(me))")
    }

    private static func post(_ me: Launcher, _ path: String, _ body: [String: Any]) async {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(me.port)\(path)")!)
        request.httpMethod = "POST"; request.setValue(me.key, forHTTPHeaderField: "x-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func wait(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition() { if Date() > end { return false }; try? await Task.sleep(for: .milliseconds(100)) }
        return true
    }

    static func run(folder: URL) async -> Int32 {
        let fm = FileManager.default
        out = folder
        let work = folder.appending(path: "work") // everything the walk makes lives here
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        let home = work.appending(path: "home"), bundle = work.appending(path: "bundle"), project = work.appending(path: "code/my-project")
        for d in [home, bundle, project] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
        // The "app's" call files, packed as build.sh packs them (pack-call.sh: no packages), with the stand-in server in place
        // of the real one (so no model is ever called).
        let launcherFolder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../..").standardized
        guard VoiceCore.run(launcherFolder.appending(path: "pack-call.sh"), [bundle.path], timeout: 300)?.status == 0 else { say("pack-call.sh failed"); return 1 }
        try? fm.removeItem(at: bundle.appending(path: "server.mjs"))
        try? fm.copyItem(at: launcherFolder.appending(path: "Tests/stub-server.mjs"), to: bundle.appending(path: "server.mjs"))
        let support = home.appending(path: "Library/Application Support/\(Product.folder)", directoryHint: .isDirectory)
        let setup = Setup(callFolder: support.appending(path: "Call"), bundledCall: bundle, support: support, ports: 4811...4899,
                          chromeProfile: work.appending(path: "chrome"), chromeArguments: ["--headless=new"], spotlight: false)
        unsetenv("KOKORO_DIR")
        say("First run, from zero, in \(folder.path)   (\(load()), \(Date()))")
        let me = Launcher(settings: CallSettings(), defaults: nil, home: home, setup: setup)
        picture(me, "01-launch-before-the-first-check")

        var t = Date()
        await me.checkHealth().value
        say("02  health check: \(time(t))  \(load())  missing: \(me.missingItems?.map(\.title) ?? [])")
        picture(me, "02-first-check-done")

        // The door first asks for a project (a folder panel in the real app): it is chosen for it here, then the door says Install.
        me.settings.choose(project.path)
        picture(me, "03-project-chosen-install-offered")
        t = Date()
        me.installMissingPackages()
        var nodeAt: Date?, seen: [String] = [], pictured = false
        let node = Runtime.node(support: support)
        let done = await wait(900) {
            if nodeAt == nil, fm.isExecutableFile(atPath: node.path) { nodeAt = Date() }
            let w = words(me); if seen.last != w { seen.append(w) }
            if !pictured, Date().timeIntervalSince(t) > 2 { pictured = true; picture(me, "04-installing") }
            return !me.installing && me.missingItems?.contains { $0.id == .packages } == false
        }
        say("04  install (Node's program, then the Agent SDK from npm): \(done ? "done" : "NOT DONE") in \(time(t))  (Node in place after \(nodeAt.map { String(format: "%.1f s", $0.timeIntervalSince(t)) } ?? "?"))  \(load())")
        say("      what the panel said meanwhile: " + seen.joined(separator: "  →  "))
        let size = VoiceCore.run(URL(filePath: "/usr/bin/du"), ["-sk", support.path]).flatMap { Double(String(decoding: $0.output, as: UTF8.self).split(separator: "\t").first ?? "") } ?? 0
        say(String(format: "      the support folder now holds %.0f MB", size / 1024))
        let sdkFile = support.appending(path: "Call/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs")
        let sdkSize = ((try? FileManager.default.attributesOfItem(atPath: sdkFile.path))?[.size] as? Int) ?? 0
        say(String(format: "      the Agent SDK fetched from npm: %@ (sdk.mjs %.1f MB)", sdkSize > 0 ? "yes" : "NO", Double(sdkSize) / 1_048_576))
        picture(me, "05-installed-ready")
        say("      missing now: \(me.missingItems?.map(\.title) ?? [])")

        // Settings, where the local voice is offered (never downloaded here).
        let settings = SettingsView(launcher: me).environment(\.colorScheme, .light)
        if let image = Snapshots.render(settings, dark: false) { Snapshots.write(image, out.appending(path: "06-settings-voice-offer.png")) }
        say("06  Settings: the local voice is offered as a quiet “Download” (381 MB); not pressed")

        // The first call, on the stand-in server.
        t = Date()
        await me.startCall()
        picture(me, "07-starting-the-call")
        let live = await wait(60) { me.phase == .live && me.status.live }
        say("07  start call → live: \(live ? "yes" : "NO") after \(time(t))  \(load())")
        let paged = await wait(30) { me.status.pages == 1 }
        say("08  call window up and connected: \(paged ? "yes" : "NO") after \(time(t))")
        try? await Task.sleep(for: .milliseconds(600))
        picture(me, "08-live")

        await post(me, "/_emit", ["type": "mic", "blocked": "mac"])
        _ = await wait(3) { !me.status.mic.isEmpty }
        picture(me, "09-microphone-blocked")
        await post(me, "/_emit", ["type": "mic", "blocked": ""])
        _ = await wait(3) { me.status.mic.isEmpty }

        t = Date()
        me.endCall()
        _ = await wait(30) { if case .ended = me.phase { true } else { false } }
        picture(me, "10-call-ended")
        say("10  end call → ended: \(time(t))")
        me.closeCallWindow()
        _ = await wait(5) { me.callWindow == nil }
        say("Done. \(load())")
        try? log.write(to: out.appending(path: "log.txt"), atomically: true, encoding: .utf8)
        return 0
    }
}
