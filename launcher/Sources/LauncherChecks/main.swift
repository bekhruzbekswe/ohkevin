import AppKit
import VoiceCore

// Checks that drive the real app, and the icon renderer. Never shipped: the app is the OhKevin product alone.
//   --ui-test <snapshots folder>  the real app against a stub server and a stand-in Claude Code: no model, no sound
//   --self-test <empty folder>     a real call server and a real call window (silent fake microphone), then a crash
//   --hand-over <empty folder>     one real hand-over: one line to Claude Code on Haiku, then End Call (costs a model call)
//   --clean-install <folder>       a Mac with nothing: Install and Download for real, in the folder (README)
//   --snapshots <folder>          every state of the panel and the menu-bar item, light and dark, drawn offscreen (nothing opens)
//   --settings-live <folder>      the real Settings window on screen, real events, photographed: list solid, hover flat, focus ring (opens a window)
//   --first-run <folder>          a Mac from zero: health, Node and packages for real, the voice only offered, a stand-in call; pictures and timings
//   --privacy <file>              the privacy page the app ships, made from the Disclosure strings (build.sh)
//   --icon <folder>                the app icon's PNGs, from the logo set (design/logo), for build.sh
//   --icon-dark <folder>           the same, in the dark appearance
let arguments = CommandLine.arguments
func argument(_ flag: String, _ n: Int = 1) -> URL? {
    guard let i = arguments.firstIndex(of: flag), i + n < arguments.count else { return nil }
    return URL(filePath: arguments[i + n])
}

if let file = argument("--privacy") { // the privacy page the app ships (build.sh)
    do { try Disclosure.page().write(to: file, atomically: true, encoding: .utf8); exit(0) } catch { print(error); exit(1) }
}
if let folder = argument("--icon") {
    do { try AppIcon.write(to: folder); exit(0) } catch { print(error); exit(1) }
}
if let folder = argument("--icon-dark") { // the dark appearance's icon (an .icns holds one look; this is for the shared set)
    do { try AppIcon.write(to: folder, dark: true); exit(0) } catch { print(error); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let folder = argument("--snapshots") { // offscreen: no window is shown, nothing is launched
    MainActor.assumeIsolated { exit(Snapshots.run(folder: folder)) }
}
if let snapshots = argument("--ui-test") {
    Task { @MainActor in exit(await UITest.run(snapshots: snapshots)) }
} else if let folder = argument("--self-test") {
    Task { @MainActor in exit(await SelfTest.run(folder: folder)) }
} else if let folder = argument("--hand-over") { // one real hand-over, by hand: it costs a model call
    Task { @MainActor in exit(await SelfTest.handOver(folder: folder)) }
} else if let folder = argument("--settings-live") {
    Task { @MainActor in exit(await SettingsLive.run(folder: folder)) }
} else if let folder = argument("--first-run") {
    Task { @MainActor in exit(await FirstRun.run(folder: folder)) }
} else if let folder = argument("--clean-install") {
    Task { @MainActor in exit(await CleanInstall.run(folder: folder)) }
} else if let folder = argument("--install-voice") { // installs the voice without Python into <folder>, with the runner of the app named by --runner
    let runner = argument("--runner") ?? bundledRunner()
    Task { exit(await installKokoroRunner(into: folder, runner: runner) ? 0 : 1) }
} else if let folder = argument("--hold-call") { // the self-test's crash helper
    Task { @MainActor in await SelfTest.hold(folder: folder) }
} else {
    print("Use --ui-test <snapshots folder>, --self-test <empty folder>, --clean-install <folder> or --icon <folder>.")
    exit(2)
}
app.run()
