// swift-tools-version:6.0
import Foundation
import PackageDescription

// shortcut: with only the Command Line Tools the compiler often forgets the Swift Testing macro plugin after an edit;
// naming it here makes `swift test` pass every time. Drop it once that is fixed.
let testingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugin)
    ? [.unsafeFlags(["-load-plugin-library", testingPlugin])] : []

// Ears: the page's turn-taking, ported one for one, with no Apple audio in it (tested, and replayable on any log).
// CallKit: what the call window shows (approvals, workers, the work, hand-over), with no screen in it, on the same Turns.
// OhKevinKit: the Mac app's code: Apple's recogniser, one audio engine for the microphone and the voice, the call window, and the
// launcher's menu-bar item and panel (CallViews) driving this app's own call. OhKevin: the app, which is all that ships.
// AppChecks: the checks and measurements that drive the app's code (pictures, replays, a WAV for a microphone); never shipped.
let appChecksInfo = Context.packageDirectory + "/Sources/AppChecks/Info.plist" // its microphone and speech reasons: no bundle of its own
let package = Package(
    name: "OhKevin",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "VoiceCore"), // everything testable without a screen: settings, health, installs, the setup model, the server's events
        .target(name: "CallViews", dependencies: ["VoiceCore"]), // the panel, setup screen and Settings pieces, in the design
        // Sparkle 2.10.1: the updater. A pinned release archive (its checksum is SwiftPM's check); build.sh embeds the framework in the app.
        .binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
                      checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"),
        .target(name: "Ears"),
        .target(name: "CallKit", dependencies: ["Ears", "VoiceCore"]),
        // Updating: self-updating (Sparkle, with the quiet-install hook) and Move to Applications, in Swift 6 as written.
        .target(name: "Updating", dependencies: ["VoiceCore", "Sparkle"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "OhKevinKit", dependencies: ["Ears", "CallKit", "VoiceCore", "CallViews", "Updating"]),
        .executableTarget(name: "OhKevin", dependencies: ["OhKevinKit"]),
        .executableTarget(name: "AppChecks", dependencies: ["OhKevinKit", "Ears", "CallKit", "VoiceCore", "CallViews", "Updating"], exclude: ["Info.plist"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", appChecksInfo])]),
        // COnnxRuntime: onnxruntime's C header only (MIT); the library is opened at run time. kokoro-runner: the local voice without Python,
        // the lines in and out the call server speaks, run from Contents/Helpers. Never links espeak-ng (GPL): it opens libespeak-ng at run time.
        .target(name: "COnnxRuntime"),
        .executableTarget(name: "kokoro-runner", dependencies: ["COnnxRuntime"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "VoiceCoreTests", dependencies: ["VoiceCore"], swiftSettings: testSettings),
        .testTarget(name: "CallViewsTests", dependencies: ["CallViews"], swiftSettings: testSettings),
        .testTarget(name: "EarsTests", dependencies: ["Ears"], swiftSettings: testSettings),
        .testTarget(name: "CallKitTests", dependencies: ["CallKit", "Ears", "VoiceCore"], swiftSettings: testSettings),
    ],
    swiftLanguageModes: [.v5] // single-threaded by design: everything runs on the main queue; the audio thread only copies samples
)
