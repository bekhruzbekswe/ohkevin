import AppKit
@testable import LauncherKit
import VoiceCore

/// A Mac with nothing on it, as a customer's is: the real launcher, with the call server's files from a copy of the built
/// app (<folder>/<name>.app, put there and quarantined as a download is, by whoever runs this), a support folder, Chrome
/// profile and preferences of its own inside <folder>, and a PATH that holds no Node, only the user's own Claude Code.
/// It presses Install and Download for real: Node from nodejs.org and Kokoro from GitHub and PyPI (the packages come inside the app).
/// No call is started, so nothing reaches Claude. Never part of `swift test`: it downloads about 410 MB (Node 27.5, voice 381).
@MainActor
enum CleanInstall {
    private static var failures = 0

    private static func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok    \(what)" : "FAIL  \(what)")
        fflush(stdout)
        if !ok { failures += 1 }
    }

    private static func megabytes(_ url: URL) -> String {
        let out = VoiceCore.run(URL(filePath: "/usr/bin/du"), ["-sk", url.path])
        return String(format: "%.0f MB", (Double(String(decoding: out?.output ?? Data(), as: UTF8.self).split(separator: "\t").first ?? "0") ?? 0) / 1024)
    }

    static func run(folder: URL) async -> Int32 {
        let fm = FileManager.default
        let app = folder.appending(path: "\(Product.fileName).app"), bundled = app.appending(path: "Contents/Resources/call")
        guard fm.fileExists(atPath: bundled.appending(path: "server.mjs").path) else {
            print("Put a copy of the built app in the folder first: \(app.path)")
            return 2
        }
        check(VoiceCore.run(URL(filePath: "/usr/bin/xattr"), ["-p", "com.apple.quarantine", app.path])?.status == 0, "the app copy carries the quarantine mark, as a download does")
        let home = folder.appending(path: "home"), bin = folder.appending(path: "bin")
        // The user's own Claude Code, found by their real login shell, on a PATH that has no Node.
        guard let env = Shell.environment(), let claude = Shell.which("claude", path: env["PATH"]) else { print("FAIL  no Claude Code on this Mac"); return 1 }
        try? fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(at: bin.appending(path: "claude"), withDestinationURL: claude.resolvingSymlinksInPath())
        let shell = folder.appending(path: "shell")
        try? "#!/bin/sh\nPATH='\(bin.path):/usr/bin:/bin'; export PATH\nfor last; do :; done\nexec /bin/sh -c \"$last\"\n".write(to: shell, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        setenv("SHELL", shell.path, 1)
        unsetenv("KOKORO_DIR")
        check(Shell.which("node", path: "\(bin.path):/usr/bin:/bin") == nil, "no Node on this Mac's PATH")

        let suite = "claude-voice-clean-install-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        var settings = CallSettings()
        settings.launchedBefore = true; settings.hasCalled = true
        var setup = Setup.standard(home: home)
        setup.bundledCall = bundled; setup.callFolder = setup.support.appending(path: "Call"); setup.spotlight = false
        setup.chromeArguments = ["--headless=new"]
        let me = Launcher(settings: settings, defaults: UserDefaults(suiteName: suite), home: home, setup: setup)
        UITest.me = me
        UITest.app = AppDelegate(launcher: me)
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: attribute)
        }
        NSApp.delegate = UITest.app
        UITest.app.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await me.checkHealth().value
        check(me.missingItems?.map(\.id).filter { $0 != .signIn } == [.packages] && me.kokoro == nil, "this Mac is missing one thing: “One more download” (\(me.missingItems?.map(\.title) ?? []))")

        // The download starts by itself at launch (the app's own start-up above), with no press.
        check(await until(3) { me.installing }, "the download started by itself, with no screen and no press")
        let started = Date(), node = Runtime.node(support: setup.support)
        var nodeAt: Date?
        check(await until(900) { if nodeAt == nil, fm.isExecutableFile(atPath: node.path) { nodeAt = Date() }; return !me.installing && me.missingItems?.contains { $0.id == .packages } == false }, "the download finishes")
        print(String(format: "      Node in place after %.1f s, everything after %.1f s", (nodeAt ?? started).timeIntervalSince(started), Date().timeIntervalSince(started)))
        let version = VoiceCore.run(node, ["--version"])
        check(String(decoding: version?.output ?? Data(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == Runtime.version, "the Runtime's Node is \(Runtime.version)")
        let call = setup.callFolder
        check(fm.fileExists(atPath: call.appending(path: sdk).path), "the Agent SDK is installed")
        check(!fm.fileExists(atPath: call.appending(path: "node_modules/@anthropic-ai/claude-agent-sdk-darwin-arm64").path), "…without its 347 MB Claude Code binary")
        check(packagesCurrent(callFolder: call, locked: true) && fm.fileExists(atPath: call.appending(path: "server.mjs").path), "the lock is marked as installed; the call files are in place")
        check(me.missingItems?.map(\.id).filter { $0 != .signIn } == [], "nothing is missing now (\(me.missingItems?.map(\.title) ?? []))")
        print("      Node \(megabytes(Runtime.folder(support: setup.support))), packages \(megabytes(call))")

        // Again: nothing is fetched and nothing changes.
        func stamp(_ url: URL) -> Date? { (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date }
        let before = [node, call.appending(path: installedMark), call.appending(path: "node_modules")].map(stamp)
        let again = Date()
        let ok = await installRuntime(support: setup.support, callFolder: call, bundledCall: bundled, environment: env, node: (URL(filePath: "/nonexistent"), "")) // would fail if it fetched
        check(ok && [node, call.appending(path: installedMark), call.appending(path: "node_modules")].map(stamp) == before, String(format: "Install again changes nothing, fetches nothing (%.1f s)", Date().timeIntervalSince(again)))

        // The local voice.
        let voice = CallSettings.defaultKokoro(home: home)
        me.installVoice()
        let voiceStarted = Date()
        check(await until(1800) { !me.installingVoice }, "the voice download ends")
        print(String(format: "      voice installed in %.1f s", Date().timeIntervalSince(voiceStarted)))
        check(!me.voiceFailed && kokoroReady(voice) && me.kokoro?.path == voice.path, "the voice said ready; the launcher finds the voice (\(voice.path))")
        print("      Kokoro \(megabytes(voice))")

        UITest.app.close()
        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}
