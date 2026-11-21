// swift-tools-version:6.0
import Foundation
import PackageDescription

// shortcut: with only the Command Line Tools, the compiler often forgets the Swift Testing macro plugin after an edit
// ("plugin for module 'TestingMacros' not found"); naming it here makes `swift test` pass every time. Drop it once a
// Command Line Tools update fixes that.
let testingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugin)
    ? [.unsafeFlags(["-load-plugin-library", testingPlugin])] : []

// VoiceCore: everything testable without a screen. CallViews: the panel's SwiftUI views. Updating: Sparkle updates and Move to Applications. LauncherKit: the app's windows and its model. OhKevin: the app,
// which is all that ships. LauncherChecks: the checks that drive the real app, and the icon renderer; never shipped.
let package = Package(
    name: "Launcher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VoiceCore"),
        // CallViews: the panel's views, colours and wave art. Plain data in (VoiceCore's PanelData), intents out; no app, no process.
        .target(name: "CallViews", dependencies: ["VoiceCore"]),
        // Sparkle 2.10.1: the updater. A pinned release archive (its checksum is SwiftPM's check); build.sh embeds the framework in the app.
        .binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
                      checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"),
        // Updating: self-updating (Sparkle driver with the quiet-install hook, its observable state) and Move to Applications. The host
        // passes its bundle, defaults and quiet rule; nothing here knows the launcher.
        .target(name: "Updating", dependencies: ["VoiceCore", "Sparkle"]),
        .target(name: "LauncherKit", dependencies: ["VoiceCore", "CallViews", "Updating"]),
        .executableTarget(name: "OhKevin", dependencies: ["LauncherKit"]),
        .executableTarget(name: "LauncherChecks", dependencies: ["LauncherKit", "Updating", "CallViews", "VoiceCore"]),
        // COnnxRuntime: onnxruntime's C header only (MIT); the library is opened at run time. kokoro-runner: the local voice without Python,
        // the lines in and out the call server speaks; one binary for both apps. Never links espeak-ng (GPL): it opens libespeak-ng at run time.
        .target(name: "COnnxRuntime"),
        .executableTarget(name: "kokoro-runner", dependencies: ["COnnxRuntime"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "VoiceCoreTests", dependencies: ["VoiceCore"], swiftSettings: testSettings),
    ]
)
