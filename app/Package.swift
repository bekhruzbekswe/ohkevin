// swift-tools-version:6.0
import Foundation
import PackageDescription

// shortcut: with only the Command Line Tools the compiler often forgets the Swift Testing macro plugin after an edit;
// naming it here (as launcher/Package.swift does) makes `swift test` pass every time. Drop it once that is fixed.
let testingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugin)
    ? [.unsafeFlags(["-load-plugin-library", testingPlugin])] : []

// Ears: the page's turn-taking, ported one for one, with no Apple audio in it (tested, and replayable on any log).
// CallKit: what the call window shows (approvals, workers, the work, hand-over), with no screen in it, on the same Turns.
// VoiceApp: the native app: Apple's recogniser, one audio engine for the microphone and the voice, the call window, and the
// launcher's menu-bar item and panel (CallViews) driving this app's own call.
let package = Package(
    name: "VoiceApp",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "VoiceCore"), // the launcher's shared core, compiled from the same files (Sources/VoiceCore is a link to them)
        .target(name: "CallViews", dependencies: ["VoiceCore"]), // the launcher's panel views, the same files (Sources/CallViews is a link)
        // Sparkle 2.10.1, the launcher's own pin (launcher/Package.swift): the updater. build.sh embeds the framework in the app.
        .binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
                      checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"),
        .target(name: "Ears"),
        .target(name: "CallKit", dependencies: ["Ears", "VoiceCore"]),
        // Updating: the launcher's shared updater and Move to Applications, the same files (Sources/Updating is a link), in Swift 6 as written.
        .target(name: "Updating", dependencies: ["VoiceCore", "Sparkle"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "VoiceApp", dependencies: ["Ears", "CallKit", "VoiceCore", "CallViews", "Updating"]),
        .testTarget(name: "EarsTests", dependencies: ["Ears"], swiftSettings: testSettings),
        .testTarget(name: "CallKitTests", dependencies: ["CallKit", "Ears", "VoiceCore"], swiftSettings: testSettings),
    ],
    swiftLanguageModes: [.v5] // single-threaded by design: everything runs on the main queue; the audio thread only copies samples
)
