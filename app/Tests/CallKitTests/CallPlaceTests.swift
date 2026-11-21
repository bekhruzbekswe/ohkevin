import CryptoKit
import Foundation
import Testing
@testable import VoiceCore
@testable import CallKit

// Where the app's call server runs, and how its copy is installed and refreshed (VoiceCore's syncCall and packagesCurrent, on the
// app's own Call folder). Everything happens in a throwaway folder.
struct CallPlaceTests {
    let home = URL(fileURLWithPath: "/Users/someone")
    let bundled = URL(fileURLWithPath: "/Applications/Oh Kevin.app/Contents/Resources/call")
    let source = URL(fileURLWithPath: "/repo/call")

    @Test func aBuiltAppRunsItsOwnCopy() {
        let p = CallPlace.resolve(override: nil, bundled: bundled, home: home, source: source)
        #expect(p.folder.path == "/Users/someone/Library/Application Support/Oh Kevin/Call")
        #expect(p.bundled == bundled && p.ownCopy)
        #expect(p.node.path.hasPrefix("/Users/someone/Library/Application Support/Oh Kevin/Node/")) // Node's program
    }

    @Test func theDeveloperOverrideWinsAndIsUsedAsItIs() {
        let p = CallPlace.resolve(override: "/work/tree/call", bundled: bundled, home: home, source: source)
        #expect(p.folder.path == "/work/tree/call" && p.bundled == nil && !p.ownCopy)
        #expect(CallPlace.resolve(override: "", bundled: bundled, home: home, source: source).ownCopy) // empty: off
    }

    @Test func withNoBundleTheRepositoryIsUsed() {
        let p = CallPlace.resolve(override: nil, bundled: nil, home: home, source: source)
        #expect(p.folder == source && !p.ownCopy)
    }

    @Test func installThenUpdateRefreshesTheCopyAndKeepsThePackages() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appending(path: "callplace-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let app = root.appending(path: "bundle/call"), copy = root.appending(path: "Call")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        func put(_ name: String, _ text: String, in folder: URL) throws {
            try fm.createDirectory(at: folder.appending(path: name).deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
        }
        func read(_ name: String) -> String? { try? String(contentsOf: copy.appending(path: name), encoding: .utf8) }
        try put("server.mjs", "v1", in: app); try put("old.mjs", "gone next", in: app); try put("package-lock.json", "lock 1", in: app)

        // First run: the copy is made, the packages are not there yet.
        syncCall(from: app, to: copy)
        #expect(read("server.mjs") == "v1" && read("old.mjs") == "gone next")
        #expect(!packagesCurrent(callFolder: copy, locked: true))

        // Installed (what installRuntime leaves): the SDK and the mark of this lock.
        try put(sdk, "{}", in: copy)
        let mark = { (lock: String) in SHA256.hash(data: Data(lock.utf8)).map { String(format: "%02x", $0) }.joined() }
        try put(installedMark, mark("lock 1"), in: copy)
        #expect(packagesCurrent(callFolder: copy, locked: true))

        // An update with the same lock: new server, a file gone, packages and mark untouched, nothing to reinstall.
        try put("server.mjs", "v2", in: app); try fm.removeItem(at: app.appending(path: "old.mjs"))
        syncCall(from: app, to: copy)
        #expect(read("server.mjs") == "v2" && read("old.mjs") == nil)
        #expect(read(sdk) == "{}" && read(installedMark) == mark("lock 1"))
        #expect(packagesCurrent(callFolder: copy, locked: true))

        // An update that changes the lock: the packages are stale, and only then reinstalled by themselves.
        try put("package-lock.json", "lock 2", in: app)
        syncCall(from: app, to: copy)
        #expect(!packagesCurrent(callFolder: copy, locked: true))
        let packages = Missing(id: .packages, title: "", detail: "", fix: .install)
        #expect(installsByItself(missing: [packages])) // the download takes it up by itself (Download, at launch)
    }
}
