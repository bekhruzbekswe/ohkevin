import CryptoKit
import Foundation
import Testing
@testable import VoiceCore
@testable import CallKit

// Where the app's call server runs, and how its copy is installed and refreshed (the launcher's syncCall, packagesCurrent and
// refreshesPackagesByItself, used on the app's own Call-App folder). Everything happens in a throwaway folder.
struct CallPlaceTests {
    let home = URL(fileURLWithPath: "/Users/someone")
    let bundled = URL(fileURLWithPath: "/Applications/Oh Kevin.app/Contents/Resources/call")
    let source = URL(fileURLWithPath: "/repo/call")

    @Test func aBuiltAppRunsItsOwnCopyNotTheLaunchers() {
        let p = CallPlace.resolve(override: nil, bundled: bundled, home: home, source: source)
        #expect(p.folder.path == "/Users/someone/Library/Application Support/Claude Voice/Call-App")
        #expect(p.folder.lastPathComponent != "Call") // the launcher's copy: never written by this app
        #expect(p.bundled == bundled && p.ownCopy)
        #expect(p.node.path.hasPrefix("/Users/someone/Library/Application Support/Claude Voice/Node/")) // Node's program, shared with the launcher
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
        let app = root.appending(path: "bundle/call"), copy = root.appending(path: "Call-App")
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

    /// An app that carries its packages (as 0.3 did) and a full Node from an earlier version (Runtime/): nothing is fetched and no
    /// npm runs; an update swaps the copy's npm-installed packages for the app's. Today's apps fetch the Agent SDK instead (installSDK).
    @Test func anAppThatCarriesItsPackagesFetchesNothing() async throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appending(path: "slim-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let support = root.appending(path: "support"), app = root.appending(path: "bundle/call"), copy = support.appending(path: "Call-App")
        func put(_ path: String, _ text: String, in folder: URL, executable: Bool = false) throws {
            let url = folder.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            if executable { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        let mark = { (lock: String) in SHA256.hash(data: Data(lock.utf8)).map { String(format: "%02x", $0) }.joined() }
        // what pack-call.sh puts in the app: the server's files, the SDK's one file, the mark of the lock
        try put("server.mjs", "v1", in: app); try put("package-lock.json", "lock 1", in: app)
        try put(sdk, "{}", in: app); try put("node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs", "export {}", in: app)
        try put(installedMark, mark("lock 1"), in: app)

        // An earlier version's full Node (Runtime/) is used as it is; once Node/ has the program, that one.
        let earlier = support.appending(path: "Runtime/node-\(Runtime.version)-darwin-arm64/bin/node")
        try put(earlier.path.replacingOccurrences(of: support.path + "/", with: ""), "#!/bin/sh", in: support, executable: true)
        #expect(Runtime.node(support: support) == earlier)
        let own = Runtime.folder(support: support).appending(path: "bin/node")
        try put(own.path.replacingOccurrences(of: support.path + "/", with: ""), "#!/bin/sh", in: support, executable: true)
        #expect(Runtime.node(support: support) == own)

        // An earlier copy with its own npm-installed packages: the install takes the app's, fetches nothing (an unreachable Node would
        // fail it) and runs no npm (PATH has none).
        try put("node_modules/zod/index.js", "old", in: copy); try put(sdk, "old", in: copy); try put(installedMark, "stale", in: copy)
        let ok = await installRuntime(support: support, callFolder: copy, bundledCall: app, environment: ["PATH": "/nonexistent"],
                                      node: (URL(fileURLWithPath: "/nonexistent"), ""))
        #expect(ok)
        #expect(!fm.fileExists(atPath: copy.appending(path: "node_modules/zod").path)) // the 61 MB of npm packages: gone
        #expect((try? String(contentsOf: copy.appending(path: "node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs"), encoding: .utf8)) == "export {}")
        #expect(packagesCurrent(callFolder: copy, locked: true))

        // An update with a new lock and SDK: both arrive with the next check, and the packages are current at once.
        try put("package-lock.json", "lock 2", in: app); try put(installedMark, mark("lock 2"), in: app)
        try put("node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs", "export const v2 = 1", in: app)
        syncCall(from: app, to: copy)
        #expect(packagesCurrent(callFolder: copy, locked: true))
        #expect((try? String(contentsOf: copy.appending(path: "node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs"), encoding: .utf8)) == "export const v2 = 1")
    }
}
