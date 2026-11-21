import Foundation
import Testing
@testable import VoiceCore

let home = URL(filePath: "/Users/someone")
let project = URL(filePath: "/Users/someone/code/api")

// MARK: Plain words: every row of spec section 7, top to bottom

@Test(arguments: [
    ("Read /Users/x/api/src/login.ts", "Reading login.ts", "Read login.ts?"),
    ("Edit /p/src/login.test.ts", "Editing login.test.ts", "Edit login.test.ts?"),
    ("NotebookEdit /p/analysis.ipynb", "Editing analysis.ipynb", "Edit analysis.ipynb?"),
    ("Write /p/notes.md", "Writing notes.md", "Create notes.md?"),
    ("Grep TODO", "Searching the project", "Search the project?"),
    ("Glob **/*.ts", "Looking for files", "Look for files?"),
    ("WebFetch https://docs.github.com/en/rest", "Reading docs.github.com", "Open docs.github.com?"),
    ("WebSearch swift testing macros", "Searching the web", "Search the web?"),
    ("Task find the flaky test", "Handing part of it to a helper", "Hand part of it to a helper?"),
    ("Agent review the diff", "Handing part of it to a helper", "Hand part of it to a helper?"),
    ("TodoWrite", "Planning the steps", "Plan the steps?"),
    ("mcp__github__create_issue", "Using github", "Use github: create issue?"),
    ("Bash git status", "Checking what changed", "Check what changed?"),
    ("Bash git diff --stat", "Checking what changed", "Check what changed?"),
    ("Bash git log -3", "Checking what changed", "Check what changed?"),
    ("Bash git show HEAD", "Checking what changed", "Check what changed?"),
    ("Bash git branch", "Checking what changed", "Check what changed?"),
    ("Bash git add -A", "Staging the changes", "Stage the changes?"),
    ("Bash git commit -m \"Fix login redirect\"", "Committing", "Commit these changes?"),
    ("Bash git push origin main", "Pushing your commits", "Push your commits?"),
    ("Bash git pull", "Getting the latest changes", "Get the latest changes?"),
    ("Bash git fetch origin", "Getting the latest changes", "Get the latest changes?"),
    ("Bash git switch -c fix-login", "Starting the branch fix-login", "Start the branch fix-login?"),
    ("Bash git checkout -b fix-login", "Starting the branch fix-login", "Start the branch fix-login?"),
    ("Bash git stash", "Running git stash", "Run git stash?"),
    ("Bash npm test -- login", "Running the tests", "Run the tests?"),
    ("Bash pnpm run test:unit", "Running the tests", "Run the tests?"),
    ("Bash bun test", "Running the tests", "Run the tests?"),
    ("Bash pytest -q", "Running the tests", "Run the tests?"),
    ("Bash jest", "Running the tests", "Run the tests?"),
    ("Bash npx vitest run", "Running the tests", "Run the tests?"),
    ("Bash cargo test", "Running the tests", "Run the tests?"),
    ("Bash go test ./...", "Running the tests", "Run the tests?"),
    ("Bash swift test", "Running the tests", "Run the tests?"),
    ("Bash npm ci", "Installing packages", "Install packages?"),
    ("Bash yarn add zod", "Installing packages", "Install packages?"),
    ("Bash pip install requests", "Installing packages", "Install packages?"),
    ("Bash brew install jq", "Installing packages", "Install packages?"),
    ("Bash cargo add serde", "Installing packages", "Install packages?"),
    ("Bash npm run build", "Building the project", "Build the project?"),
    ("Bash tsc --noEmit", "Building the project", "Build the project?"),
    ("Bash make", "Building the project", "Build the project?"),
    ("Bash cargo build --release", "Building the project", "Build the project?"),
    ("Bash swift build", "Building the project", "Build the project?"),
    ("Bash go build ./cmd/api", "Building the project", "Build the project?"),
    ("Bash npm run lint", "Running lint", "Run lint?"),
    ("Bash npm start", "Running start", "Run start?"),
    ("Bash pnpm dev", "Running dev", "Run dev?"),
    ("Bash rm -rf dist coverage", "Deleting files", "Delete files?"),
    ("Bash rmdir old", "Deleting files", "Delete files?"),
    ("Bash mkdir -p src/new", "Making a folder", "Make a folder?"),
    ("Bash touch src/new/index.ts", "Creating index.ts", "Create index.ts?"),
    ("Bash mv a.ts b.ts", "Moving files", "Move files?"),
    ("Bash cp a.ts b.ts", "Copying files", "Copy files?"),
    ("Bash curl -s https://example.com", "Fetching from the web", "Fetch from the web?"),
    ("Bash wget https://example.com/x.zip", "Fetching from the web", "Fetch from the web?"),
    ("Bash ls -la", "Looking through the project", "Look through the project?"),
    ("Bash rg login src", "Looking through the project", "Look through the project?"),
    ("Bash which node", "Looking through the project", "Look through the project?"),
    ("Bash docker compose up", "Running docker compose", "Run docker compose?"),
    ("Bash python3 scripts/seed.py", "Running python3", "Run python3?"),
    ("Bash /usr/bin/env", "Running env", "Run env?"),
    ("Bash npm test | tee out.txt", "Running a command", "Run this command?"),
    ("Bash echo $HOME", "Running a command", "Run this command?"),
    ("ExitPlanMode", "Using Exit Plan Mode", "Use Exit Plan Mode?"),
    ("some_new_tool x", "Using some new tool", "Use some new tool?"),
])
func plainWordsRow(step: String, doing: String, asking: String) {
    let words = plainWords(step)
    #expect(words?.doing == doing && words?.asking == asking, "\(step) gave \(String(describing: words))")
}

@Test func plainWordsCutLongNamesAndSkipEmptySteps() {
    #expect(plainWords("Read /p/a-really-long-file-name-for-the-test.ts")?.doing == "Reading a-really-long-file-name-for…") // 28 characters with the ellipsis
    #expect(plainWords("") == nil && plainWords("   ") == nil)
    #expect(shellWords("git commit -m 'a b'") == ["git", "commit", "-m", "a b"])
    #expect(shellWords("a && b") == nil && shellWords("echo \"$x\"") == nil && shellWords("") == nil)
}

// MARK: The call's state, from the event stream

@Test func requestsKeepAllTheyCarryAndAnswersSayWhoAnswered() {
    var s = CallStatus()
    #expect(s.apply(#"data: {"type":"hello","project":"/p","voices":[]}"#) == .connected)
    let first = s.apply(#"data: {"type":"ask","id":"a1","detail":"api: Bash git push origin main","worker":"api","voice":false,"full":"git push origin main --force-with-lease"}"#)
    let ask = Ask(id: "a1", detail: "Bash git push origin main", worker: "api", voice: false, full: "git push origin main --force-with-lease")
    #expect(first == .asked(ask) && ask.question == "Push your commits?")
    s.apply(#"data: {"type":"ask","id":"a2","detail":"Edit /p/package.json","worker":"web","voice":true,"full":"/p/package.json"}"#)
    #expect(s.apply(#"data: {"type":"ask","id":"a1","detail":"api: Bash git push origin main","worker":"api","voice":false}"#) == nil) // sent again on reconnect
    #expect(s.asks.map(\.id) == ["a1", "a2"]) // oldest first
    let edit = Ask(id: "a2", detail: "Edit /p/package.json", worker: "web", voice: true, full: "/p/package.json")
    #expect(edit.question == "Edit package.json?")
    #expect(s.apply(#"data: {"type":"asked","id":"a2","allow":true,"by":"voice"}"#) == .answered(edit, allow: true, byVoice: true))
    #expect(s.apply(#"data: {"type":"asked","id":"a1","allow":false}"#) == .answered(ask, allow: false, byVoice: false))
    #expect(s.asks.isEmpty && s.apply(#"data: {"type":"asked","id":"a1","allow":false}"#) == nil)
}

@Test func aReconnectIsNotNewsForRequestsAlreadyShown() {
    var s = CallStatus()
    let line = #"data: {"type":"ask","id":"r1","detail":"Bash git push","worker":"api","voice":false,"full":"git push"}"#
    #expect(s.apply(line) != nil)
    s.apply(#"data: {"type":"hello"}"#) // a new connection: the open requests follow again
    #expect(s.asks.isEmpty)
    #expect(s.apply(line) == nil && s.asks.map(\.id) == ["r1"]) // shown again, but no second announcement or opening
}

@Test func eachWorkerHasItsOwnState() {
    var s = CallStatus()
    s.apply(#"data: {"type":"board","state":"working","model":"api opus · web sonnet","workers":[{"name":"api","state":"working","task":"Fix the login test","step":"Bash npm test","model":"opus"},{"name":"web","state":"idle","task":"","step":"","model":"sonnet"}]}"#)
    #expect(s.workers == [Worker(name: "api", state: "working", task: "Fix the login test", step: "Bash npm test", model: "opus"),
                          Worker(name: "web", state: "idle", task: "", step: "", model: "sonnet")])
    #expect(s.working && Light(phase: .live, status: s) == .working)
    s.apply(#"data: {"type":"board","state":"idle","workers":[{"name":"api","state":"idle","model":"opus"}]}"#)
    #expect(!s.working && Light(phase: .live, status: s) == .onCall)
    #expect(Light(phase: .live, status: s, cantHear: true) == .cantHear)
    s.apply(#"data: {"type":"ask","id":"x","detail":"Bash rm -rf dist","worker":"api","voice":false}"#)
    #expect(Light(phase: .live, status: s, cantHear: true) == .needsAnswer) // a question comes first
}

@Test func errorsLoseTheirCodeAndGoWhenTheConversationMovesOn() {
    var s = CallStatus()
    s.apply(#"data: {"type":"error","text":"The voice could not answer (error 529). Say it again in a moment."}"#)
    #expect(s.error == "The voice could not answer. Say it again in a moment.")
    s.apply(#"data: {"type":"turn_end"}"#)
    #expect(s.error == nil)
    #expect(s.apply(#"data: {"type":"hangup"}"#) == .hangup)
    s.apply(#"data: {"type":"pages","n":1}"#); s.apply(#"data: {"type":"session","id":"z","worker":"api"}"#)
    #expect(s.pages == 1 && s.sessions == ["api"])
    s.apply(": keep-alive"); s.apply("data: not json"); s.apply(#"data: {"type":"something new"}"#)
}

@Test func aBlockedMicrophoneSaysWhoBlocksItUntilItHears() {
    var s = CallStatus()
    #expect(s.mic == "")
    s.apply(#"data: {"type":"mic","blocked":"mac"}"#)
    #expect(s.mic == "mac")
    s.apply(#"data: {"type":"mic","blocked":"chrome"}"#)
    #expect(s.mic == "chrome")
    s.apply(#"data: {"type":"mic","blocked":""}"#)
    #expect(s.mic == "")
}

@Test func theVoiceSaysWhatItIsDoingAndWhetherTheMicCanBeMuted() {
    var s = CallStatus()
    #expect(s.voice == "" && !s.canMute)
    s.apply(#"data: {"type":"voice","state":"speaking","canMute":false}"#)
    #expect(s.voice == "speaking" && !s.canMute)
    s.apply(#"data: {"type":"voice","state":"muted","canMute":true}"#)
    #expect(s.voice == "muted" && s.canMute)
    s.apply(#"data: {"type":"voice"}"#) // an event without its words says nothing
    #expect(s.voice == "" && !s.canMute)
}

@Test func everyPhaseHasItsLight() {
    let s = CallStatus()
    #expect(Light(phase: .idle, status: s) == .ready && Light(phase: .ended(Ended(length: 60, line: nil)), status: s) == .ready)
    #expect(Light(phase: .starting, status: s) == .starting && Light(phase: .ending, status: s) == .ending)
    #expect(Light(phase: .failed(.slowStart), status: s) == .failed)
}

@Test func callLengthsAndTheTimerReadNaturally() {
    #expect(callLength(42) == "under a minute" && callLength(12 * 60 + 5) == "12 min" && callLength(65 * 60) == "1 h 5 min")
    #expect(timer(42) == "0:42" && timer(12 * 60 + 4) == "12:04" && timer(3723) == "1:02:03")
}

// MARK: Port, local voice, settings

@Test func thePortIs4747UnlessItIsTaken() {
    #expect(freePort(in: CallSettings.ports) { _ in true } == 4747)
    #expect(freePort(in: CallSettings.ports) { $0 > 4749 } == 4750)
    #expect(freePort(in: CallSettings.ports) { _ in false } == nil)
}

@Test func theLocalVoiceIsFoundWithoutAsking() throws {
    let tmp = FileManager.default.temporaryDirectory.appending(path: "kokoro-search-\(UUID())")
    defer { try? FileManager.default.removeItem(at: tmp) }
    func kokoro(_ path: String) throws -> URL {
        let dir = tmp.appending(path: path)
        try FileManager.default.createDirectory(at: dir.appending(path: "espeak-ng-data"), withIntermediateDirectories: true)
        for file in ["kokoro-runner", "libonnxruntime.dylib", "libespeak-ng.dylib", "espeak-ng-data/phontab", "kokoro-v1.0.onnx", "voices-v1.0.bin"] {
            FileManager.default.createFile(atPath: dir.appending(path: file).path, contents: Data(), attributes: [.posixPermissions: 0o755])
        }
        return dir
    }
    let beside = try kokoro("projects/kokoro"), spotted = try kokoro("elsewhere/voice")
    let half = tmp.appending(path: "half")
    try FileManager.default.createDirectory(at: half, withIntermediateDirectories: true)
    let places = kokoroPlaces(saved: half.path, shell: [:], home: tmp, project: tmp.appending(path: "projects/api"))
    #expect(places.map(\.path) == [half.path, CallSettings.defaultKokoro(home: tmp).path, beside.path])
    #expect(findKokoro(places) { [spotted] } == beside) // a folder without the models is passed over
    #expect(kokoroPlaces(saved: nil, shell: ["KOKORO_DIR": "/k"], home: tmp, project: nil).first?.path == "/k")
    #expect(findKokoro([half]) { [half, spotted] } == spotted) // then Spotlight
    #expect(findKokoro([half]) { [] } == nil)
}

@Test func onlyWhatIsMissingIsListedEachWithItsFix() {
    let call = URL(filePath: "/p/call")
    let node = Node(url: URL(filePath: "/n"), version: "24.15.0")
    let fine = Machine(callFolder: call, node: node, packages: true, claude: URL(filePath: "/c"), signedIn: true, chrome: URL(filePath: "/C"))
    #expect(missing(fine).isEmpty)
    var m = fine; m.signedIn = nil // an older Claude Code that cannot say
    #expect(missing(m).isEmpty)
    m = Machine(callFolder: call)
    #expect(missing(m).map(\.id) == [.node, .claude, .chrome]) // a launcher without a Runtime of its own: the old rows
    #expect(missing(m).map(\.title) == ["Node is needed", "Claude Code isn’t installed", "Chrome isn’t installed"])
    m.runtime = true // the app's own Runtime: no Node and no packages is one download, not two
    #expect(missing(m).map(\.id) == [.packages, .claude, .chrome] && missing(m)[0].fix == .install)
    m.locked = true; m.server = false
    #expect(missing(m).map(\.id) == [.packages, .claude, .chrome]) // the app's copy of the server is brought back by it
    m.locked = false
    #expect(missing(m).map(\.id) == [.moved, .packages, .claude, .chrome]) // a repository that moved is not
    m = fine; m.packages = false; m.signedIn = false
    #expect(missing(m).map(\.id) == [.packages, .signIn])
    #expect(missing(m)[0].fix == .install && missing(m)[0].title == "One more download")
    #expect(missing(m)[1].fix == .signIn && missing(m)[1].detail == "Calls use your Claude Code account.")
    m.node = Node(url: URL(filePath: "/n"), version: "16.0.0")
    #expect(missing(m).map(\.id) == [.node, .signIn]) // a Node too old to run them is first
    m.runtime = true
    #expect(missing(m).map(\.id) == [.packages, .signIn]) // …or, with a Runtime of the app's own, the same download
    m = fine; m.claudeVersion = "2.1.322"; m.signedIn = false
    #expect(missing(m).map(\.id) == [.claudeOld]) // an old Claude Code is updated before it is asked to sign in
    m.claudeVersion = Runtime.minimumClaudeCode
    #expect(missing(m).map(\.id) == [.signIn])
    #expect(isAtLeast("2.1.323", "2.1.323") && isAtLeast("2.2", "2.1.323") && isAtLeast("10.0.0", "9.9.9") && !isAtLeast("2.1.99", "2.1.323"))
    m = fine; m.server = false
    #expect(missing(m).map(\.title) == ["\(Product.name) was moved"])
}

@Test func environmentSetsEveryCallVariableOverTheShell() {
    var s = CallSettings()
    s.workerModel = .haiku; s.spokenYes = .nothing; s.openInClaudeApp = false
    let shell = ["PATH": "/bin", "PORT": "3000", "VOICE_APPROVE": "all", "VOICE_THREADS": "4", "HOME": "/Users/someone"]
    let env = s.environment(base: shell, project: project, key: "abc", port: 4810, kokoro: URL(filePath: "/opt/kokoro"))
    #expect(env["PATH"] == "/bin" && env["HOME"] == "/Users/someone") // the shell's own variables stay
    #expect(env["PORT"] == "4810" && env["CALL_KEY"] == "abc" && env["NO_OPEN"] == "1" && env["CALL_LAUNCHER"] == "1")
    #expect(env["WORKER_MODEL"] == "haiku" && env["TALKER_MODEL"] == "haiku")
    #expect(env["VOICE_APPROVE"] == "0" && env["SPEAK_FIRST"] == "1" && env["OPEN_IN_APP"] == "0") // limit warnings are always on
    #expect(env["KOKORO_DIR"] == "/opt/kokoro" && env["VOICE_THREADS"] == nil)
    #expect(env["PROJECTS_DIR"] == "/Users/someone/code") // "open a worker on …" looks next to the project
    #expect(CallSettings().environment(base: [:], project: project, key: "k", port: 4747, kokoro: home)["OPEN_IN_APP"] == "1")
    #expect(env["CLAUDE_PATH"] == nil) // not given: the server's SDK uses its own
    let own = s.environment(base: ["CLAUDE_PATH": "/stray"], project: project, key: "k", port: 1, kokoro: home, claude: URL(filePath: "/u/claude"))
    #expect(own["CLAUDE_PATH"] == "/u/claude")
}

@Test func choosingAProjectKeepsSixRecentOnesNewestFirst() {
    var s = CallSettings()
    for n in 1...8 { s.choose("/p/\(n)") }
    s.choose("/p/5")
    #expect(s.project == "/p/5")
    #expect(s.recents == ["/p/5", "/p/8", "/p/7", "/p/6", "/p/4", "/p/3"])
}

@Test func settingsSurviveASaveAndOldFieldsAreIgnored() {
    var s = CallSettings()
    s.choose("/p/a"); s.spokenYes = .anyStep; s.hasCalled = true; s.launchedBefore = true
    #expect(CallSettings.decode(s.encoded) == s)
    let old = CallSettings.decode(Data(#"{"port": 4999, "allCores": true, "shortcut": true, "talkerModel": "sonnet", "limitWarnings": false, "workerModel": "sonnet"}"#.utf8)) // as older versions saved it
    #expect(old.workerModel == .sonnet && old.openInClaudeApp && !old.launchedBefore)
    #expect(CallSettings.decode(Data("not json".utf8)) == CallSettings() && CallSettings.decode(nil) == CallSettings())
    #expect(Disclosure.settings.contains("without asking; its own safety checks refuse") && !Disclosure.settings.contains("asks you"))
}

// MARK: Shell

@Test func shellEnvironmentIsReadBetweenTheMarks() {
    let raw = Data("Last login: today\n\(Shell.mark)PATH=/a:/b\u{0}HOME=/h\u{0}EQ=x=y\u{0}\(Shell.mark)bye".utf8)
    #expect(Shell.parse(raw) == ["PATH": "/a:/b", "HOME": "/h", "EQ": "x=y"])
    #expect(Shell.parse(Data("no marks".utf8)) == nil)
}

@Test func aRealLoginShellGivesItsPath() throws {
    let env = try #require(Shell.environment(shell: "/bin/sh"))
    #expect(env["PATH"]?.contains("/usr/bin") == true)
    #expect(Shell.which("ls", path: env["PATH"])?.path == "/bin/ls")
    #expect(Shell.which("no-such-program-here", path: env["PATH"]) == nil)
}

@Test func runGivesUpOnAProgramThatHangs() {
    let started = Date()
    #expect(run(URL(filePath: "/bin/sleep"), ["5"], timeout: 0.3) == nil)
    #expect(Date().timeIntervalSince(started) < 2)
    #expect(run(URL(filePath: "/bin/echo"), ["hi"])?.output == Data("hi\n".utf8))
    #expect(run(URL(filePath: "/no/such/program"), []) == nil)
}

@Test func nodeVersionsBelow18_14AreTooOld() {
    let n = { Node(url: URL(filePath: "/n"), version: $0).supported }
    #expect(n("18.14.0") && n("24.15.0") && n("20.0.1"))
    #expect(!n("18.13.9") && !n("16.20.0") && !n("garbage"))
}

@Test func aBusyPortIsSeenAndAFreeOneIsNot() throws {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET); addr.sin_addr.s_addr = inet_addr("127.0.0.1"); addr.sin_port = 0
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
    _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
    listen(fd, 1)
    let port = Int(UInt16(bigEndian: addr.sin_port))
    #expect(!portIsFree(port))
    close(fd) // that the port is free again is not asserted: a test running beside this one may take it first
}

@Test func aServerIsEndedWithItsWholeTreeAndTheLogIsPrivate() async throws {
    let tmp = FileManager.default.temporaryDirectory.appending(path: "launcher-\(UUID())")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let log = try CallLog.fresh(home: tmp)
    #expect((try FileManager.default.attributesOfItem(atPath: log.path)[.posixPermissions] as? Int) == 0o600)
    // A stand-in server: /bin/sh with a child of its own, ending on SIGTERM.
    let script = tmp.appending(path: "server.sh")
    try "trap 'echo bye; exit 0' TERM; sleep 30 & wait; wait".write(to: script, atomically: true, encoding: .utf8)
    let server = try CallServer(node: URL(filePath: "/bin/sh"), server: script, project: tmp, environment: [:], log: log)
    let exited = Locked<Int32?>(nil)
    try server.start { status in exited.with { $0 = status } }
    try await Task.sleep(for: .milliseconds(300))
    let tree = [server.pid] + descendants(of: server.pid)
    #expect(tree.count == 2 && tree.allSatisfy(alive))
    server.forceQuit()
    for _ in 0..<50 where tree.contains(where: alive) { try await Task.sleep(for: .milliseconds(100)) }
    #expect(!tree.contains(where: alive))
}

// MARK: What a call runs on: the lock, the checksum, the app's copy

private func scratch() throws -> URL {
    let tmp = FileManager.default.temporaryDirectory.appending(path: "install-\(UUID())")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return tmp
}

@Test func packagesAreStaleWhenTheLockChangedSinceTheyWereInstalled() throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    #expect(!packagesCurrent(callFolder: tmp, locked: true))
    try fm.createDirectory(at: tmp.appending(path: "node_modules/@anthropic-ai/claude-agent-sdk"), withIntermediateDirectories: true)
    fm.createFile(atPath: tmp.appending(path: sdk).path, contents: Data())
    try "lock one".write(to: tmp.appending(path: "package-lock.json"), atomically: true, encoding: .utf8)
    #expect(packagesCurrent(callFolder: tmp, locked: false)) // a repository's own node_modules
    #expect(!packagesCurrent(callFolder: tmp, locked: true)) // installed by no one we know of
    try sha256(of: tmp.appending(path: "package-lock.json"))?.write(to: tmp.appending(path: installedMark), atomically: true, encoding: .utf8)
    #expect(packagesCurrent(callFolder: tmp, locked: true))
    try "lock two".write(to: tmp.appending(path: "package-lock.json"), atomically: true, encoding: .utf8) // an app update
    #expect(!packagesCurrent(callFolder: tmp, locked: true))
    #expect(packagesCurrent(callFolder: tmp, locked: false))
}

@Test func anUpdateRefreshesTheCopyAndOnlyTheStalePackagesAreDone() throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    let v1 = tmp.appending(path: "v1"), v2 = tmp.appending(path: "v2"), copy = tmp.appending(path: "Call")
    for dir in [v1, v2] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    for (dir, version) in [(v1, "1"), (v2, "2")] {
        try "server \(version)".write(to: dir.appending(path: "server.mjs"), atomically: true, encoding: .utf8)
        try "lock \(version)".write(to: dir.appending(path: "package-lock.json"), atomically: true, encoding: .utf8)
    }
    // Version 1 installed: its files, its packages, and the mark that says they were installed from its lock.
    syncCall(from: v1, to: copy)
    try fm.createDirectory(at: copy.appending(path: sdk).deletingLastPathComponent(), withIntermediateDirectories: true)
    try "sdk".write(to: copy.appending(path: sdk), atomically: true, encoding: .utf8)
    try (sha256(of: copy.appending(path: "package-lock.json")) ?? "").write(to: copy.appending(path: installedMark), atomically: true, encoding: .utf8)
    #expect(packagesCurrent(callFolder: copy, locked: true))
    // The user's own things beside the copy are not in it, and an update does not reach them.
    let support = tmp, mine = ["Runtime/node", "Kokoro/model", "Chrome/profile", "settings.json"]
    for file in mine { try fm.createDirectory(at: support.appending(path: file).deletingLastPathComponent(), withIntermediateDirectories: true); try file.write(to: support.appending(path: file), atomically: true, encoding: .utf8) }
    // Version 2 arrives (Sparkle replaced the app): the next check copies its call/ over; the lock changed, so the packages are stale.
    syncCall(from: v2, to: copy)
    #expect(try String(contentsOf: copy.appending(path: "server.mjs"), encoding: .utf8) == "server 2")
    #expect(!packagesCurrent(callFolder: copy, locked: true)) // npm ci is due
    #expect(installsByItself(missing: [Missing(id: .packages, title: "", detail: "", fix: .install)]))
    #expect(installsByItself(missing: [Missing(id: .packages, title: "", detail: "", fix: .install), Missing(id: .signIn, title: "", detail: "", fix: .signIn)]), "a first run too")
    #expect(!installsByItself(missing: []))
    for file in mine { #expect(fm.fileExists(atPath: support.appending(path: file).path), "\(file) is the user's and stays") }
    #expect(fm.fileExists(atPath: copy.appending(path: sdk).path), "the installed packages stay until npm ci replaces them")
    // The same lock again (an update that did not change it): nothing to install.
    try (sha256(of: copy.appending(path: "package-lock.json")) ?? "").write(to: copy.appending(path: installedMark), atomically: true, encoding: .utf8)
    syncCall(from: v2, to: copy)
    #expect(packagesCurrent(callFolder: copy, locked: true))
}

@Test func theAppsFilesReplaceTheCopyButKeepItsPackages() throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    let app = tmp.appending(path: "app"), copy = tmp.appending(path: "Call")
    for dir in [app, copy.appending(path: "node_modules")] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    try "new".write(to: app.appending(path: "server.mjs"), atomically: true, encoding: .utf8)
    try "old".write(to: copy.appending(path: "server.mjs"), atomically: true, encoding: .utf8)
    try "mark".write(to: copy.appending(path: installedMark), atomically: true, encoding: .utf8)
    try "dropped".write(to: copy.appending(path: "gone.mjs"), atomically: true, encoding: .utf8) // a file a newer app no longer has
    try "same".write(to: app.appending(path: "same.mjs"), atomically: true, encoding: .utf8)
    try "same".write(to: copy.appending(path: "same.mjs"), atomically: true, encoding: .utf8)
    let stamp = try #require(fm.attributesOfItem(atPath: copy.appending(path: "same.mjs").path)[.creationDate] as? Date)
    syncCall(from: app, to: copy)
    #expect(try String(contentsOf: copy.appending(path: "server.mjs"), encoding: .utf8) == "new")
    #expect(!fm.fileExists(atPath: copy.appending(path: "gone.mjs").path))
    #expect(try fm.attributesOfItem(atPath: copy.appending(path: "same.mjs").path)[.creationDate] as? Date == stamp) // an equal file is not touched
    #expect(try fm.contentsOfDirectory(atPath: copy.path).sorted() == [".installed", "node_modules", "same.mjs", "server.mjs"])
    #expect(fm.fileExists(atPath: copy.appending(path: "node_modules").path) && fm.fileExists(atPath: copy.appending(path: installedMark).path))
}

/// A tiny archive shaped like nodejs.org's: one top folder holding bin/node.
private func archive(in tmp: URL) throws -> (file: URL, sha: String) {
    let top = tmp.appending(path: "top/\(Runtime.name)/bin")
    try FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
    try "#!/bin/sh\n".write(to: top.appending(path: "node"), atomically: true, encoding: .utf8)
    let file = tmp.appending(path: "node.tar.xz")
    #expect(run(URL(filePath: "/usr/bin/tar"), ["-cJf", file.path, "-C", tmp.appending(path: "top").path, Runtime.name])?.status == 0)
    return (file, try #require(sha256(of: file)))
}

@Test func anArchiveWhoseChecksumIsWrongIsNeverUnpacked() async throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    let (file, sha) = try archive(in: tmp)
    let into = tmp.appending(path: "Runtime/.new")
    #expect(await unpack(file, sha256: String(repeating: "0", count: 64), flags: "-xJf", into: into) == false)
    #expect(!fm.fileExists(atPath: into.path))
    #expect(await unpack(file, sha256: sha, flags: "-xJf", into: into))
    #expect(fm.fileExists(atPath: into.appending(path: "bin/node").path)) // the top folder is dropped
    // the whole install refuses it too, and leaves no Runtime behind
    let support = tmp.appending(path: "support")
    let ok = await installRuntime(support: support, callFolder: support.appending(path: "Call"), bundledCall: nil, environment: [:], node: (file, String(repeating: "0", count: 64)))
    #expect(!ok && !fm.fileExists(atPath: support.appending(path: "Runtime").path))
}

@Test func theRunnerLayoutCountsAsAVoiceAndAHalfOneDoesNot() throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    func put(_ path: String, executable: Bool = false) throws {
        let url = tmp.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data(), attributes: executable ? [.posixPermissions: 0o755] : nil)
    }
    try put("kokoro-runner", executable: true); try put("libonnxruntime.dylib"); try put("libespeak-ng.dylib"); try put("espeak-ng-data/phontab")
    try put("kokoro-v1.0.onnx")
    #expect(!runnerReady(tmp) && !kokoroReady(tmp)) // no voices file yet
    try put("voices-v1.0.bin")
    #expect(runnerReady(tmp) && kokoroReady(tmp))
    try fm.removeItem(at: tmp.appending(path: "libonnxruntime.dylib"))
    #expect(!kokoroReady(tmp))
}

@Test func theRunnerInstallLeavesNothingBehindWhenAPartFails() async throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    let (file, sha) = try archive(in: tmp)
    let runner = tmp.appending(path: "kokoro-runner")
    fm.createFile(atPath: runner.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
    let folder = tmp.appending(path: "Kokoro")
    let wrong = (url: file, sha256: String(repeating: "0", count: 64), member: "x")
    #expect(await installKokoroRunner(into: folder, runner: runner, onnx: wrong) == false)
    #expect(!fm.fileExists(atPath: folder.path))
    let notAWheel = (url: file, sha256: sha, member: "onnxruntime/capi/libonnxruntime.1.23.2.dylib") // right bytes, no such member
    #expect(await installKokoroRunner(into: folder, runner: runner, onnx: notAWheel) == false)
    #expect(!fm.fileExists(atPath: folder.path))
    // without a runner there is nothing to install with
    #expect(await installKokoro(into: folder, callFolder: tmp, environment: [:]) == false)
    #expect(!fm.fileExists(atPath: folder.path))
}

// MARK: Signing in, with a stand-in for the Claude Code CLI (never the real one: someone is signed in)

@Test func signingInLendsTheCliATerminalAndItsStatusIsRead() throws {
    let tmp = FileManager.default.temporaryDirectory.appending(path: "signin-\(UUID())")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let cli = tmp.appending(path: "claude"), done = tmp.appending(path: "signed-in")
    try """
    #!/bin/sh
    if [ "$1 $2" = "auth status" ]; then [ -e '\(done.path)' ] && echo '{"loggedIn": true}' || echo '{"loggedIn": false}'; exit 0; fi
    if [ "$1 $2" = "auth login" ] && [ -t 0 ] && [ -t 1 ]; then touch '\(done.path)'; exit 0; fi
    exit 1
    """.write(to: cli, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
    let env = ["PATH": "/usr/bin:/bin"]
    #expect(authStatus(claude: cli, environment: env) == false)
    let login = signInProcess(claude: cli, environment: env)
    try login.run()
    login.waitUntilExit()
    #expect(login.terminationStatus == 0 && FileManager.default.fileExists(atPath: done.path)) // it had a terminal, with no input
    #expect(authStatus(claude: cli, environment: env) == true)
    #expect(authStatus(claude: URL(filePath: "/usr/bin/true"), environment: env) == nil) // a CLI that cannot say
}

// MARK: - The panel's data

private func input(_ f: (inout PanelInput) -> Void = { _ in }) -> PanelInput {
    var i = PanelInput(); i.project = URL(filePath: "/x/api"); i.missing = []; i.micState = .done; f(&i); return i
}
private func live(_ voice: String = "listening", _ f: (inout PanelInput) -> Void = { _ in }) -> PanelData {
    PanelData(input { $0.phase = .live; $0.liveSince = Date(); $0.status.voice = voice; $0.status.canMute = true; $0.status.pages = 1; f(&$0) })
}

@Test func namesAreCutInTheMiddleNeverInsideAWord() {
    #expect(middleCut("api", 16) == "api")
    #expect(middleCut("storefront-checkout-redesign-2026", 16) == "storefront…2026")
    #expect(middleCut("supercalifragilisticexpialidocious", 16) == "supercalif…cious")
}

@Test func theIdlePanelIsOneChooserAndOneDoor() {
    let d = PanelData(input())
    #expect(d.line1 == "Oh Kevin" && d.line2 == .text("A voice call with Claude Code.") && d.door.label == "Start call" && d.door.style == .primary && d.shape == .rest(setup: false))
    guard case .project(let p) = d.pill else { Issue.record("a chooser"); return }
    #expect(p.name == "api")
}

@Test func setupCountsOnlyTheThreeRows() {
    let signedOut = missing(Machine(callFolder: URL(filePath: "/x"), node: Node(url: URL(filePath: "/n"), version: "24.0.0"), packages: true, claude: URL(filePath: "/c"), claudeVersion: "9.9.9", signedIn: false, chrome: URL(filePath: "/ch")))
    var i = PanelInput(); i.missing = signedOut
    var d = PanelData(i)
    #expect(d.line1 == "Oh Kevin" && d.style == .ours && d.line2 == .text("Three things, then a call.") && d.door.label == "Set up" && d.door.style == .primary && d.door.action == .openSetup)
    i.micState = .done
    d = PanelData(i)
    #expect(d.line1 == "2 things to go" && d.line2 == .text("Next: sign in to Claude.") && d.door.label == "Continue" && d.door.action == .openSetup && d.shape == .rest(setup: true))
    i.project = URL(filePath: "/x/api"); i.missing = missing(Machine(callFolder: URL(filePath: "/x"), node: Node(url: URL(filePath: "/n"), version: "24.0.0"), packages: false, claude: URL(filePath: "/c"),
                                                                  claudeVersion: "9.9.9", signedIn: false, chrome: URL(filePath: "/ch")))
    d = PanelData(i)
    #expect(d.line1 == "1 thing to go" && d.line2 == .text("Next: sign in to Claude."), "the download is not a thing to go")
    i.micState = .todo
    #expect(PanelData(i).line1 == "2 things to go" && PanelData(i).line2 == .text("Next: sign in to Claude."))
}

@Test func theGoldIsTheFirstRowNotDoneAndTheBottomWaitsForAllThree() {
    func look(_ s: SetupScreen) -> [SetupScreen.Look?] { s.rows.map { if case .button(_, let l, _) = $0.control { l } else { nil } } }
    var i = SetupInput()
    #expect(look(SetupScreen(i)) == [.gold, .quiet, .quiet] && SetupScreen(i).bottom == .start(ready: false))
    i.claude = .signingIn // at rest: the gold moves on, the others can be done meanwhile
    #expect(look(SetupScreen(i)) == [.rest, .gold, .quiet] && SetupScreen(i).rows[0].reason == "Finish in your browser. This moves on by itself.")
    i.claude = .done; i.mic = .asking // asking holds the gold: the system's question is the next thing
    #expect(look(SetupScreen(i)) == [nil, .quiet, .quiet] && SetupScreen(i).rows[1].reason == "Your Mac is asking.")
    i.mic = .refused
    #expect(look(SetupScreen(i)) == [nil, .gold, .quiet])
    guard case .button(let title, _, let intent) = SetupScreen(i).rows[1].control else { Issue.record("a button"); return }
    #expect(title == "Open Settings" && intent == .openMicrophoneSettings)
    i.mic = .done; i.project = "shop"
    #expect(SetupScreen(i).left == 0 && SetupScreen(i).bottom == .start(ready: true) && SetupScreen(i).rows[2].pick?.name == "shop")
    i.download = [.init("Node", progress: 1, weight: 40), .init("Packages", progress: 0.5, weight: 60)]
    #expect(SetupScreen(i).bottom == .downloading(0.7))
    i.download = [.init("Packages")]
    #expect(SetupScreen(i).bottom == .downloading(nil))
    i.download[0].failed = true
    guard case .note(_, let button, let retry) = SetupScreen(i).bottom else { Issue.record("a note"); return }
    #expect(button == "Try again" && retry == .retryDownload)
    i.mic = .todo; i.claude = .signIn
    #expect(SetupScreen(i).bottom == .start(ready: false), "the download is said only when the three rows are done")
}

@Test func claudeCodeMissingOrOldIsTheClaudeRows() {
    let site = URL(string: "https://x.test")!
    func row(_ c: SetupInput.Claude) -> (String, String) {
        var i = SetupInput(); i.claude = c
        guard case .button(let t, _, _) = SetupScreen(i).rows[0].control else { return ("", "") }
        return (SetupScreen(i).rows[0].reason, t)
    }
    #expect(row(.get(site, old: false)) == ("Claude Code isn’t installed.", "Get Claude Code"))
    #expect(row(.update) == ("Claude Code needs an update.", "Update"))
    #expect(row(.signIn).1 == "Sign in")
}

@Test func aCallShowsTheVoicesRealStateAndNothingElse() {
    guard case .call(let listening) = live().pill, case .call(let muted) = live("muted").pill, case .call(let speaking) = live("speaking").pill else { Issue.record("a call"); return }
    #expect(listening.word == "Listening" && speaking.word == "Speaking" && muted.word == "Muted" && muted.muted && !listening.muted)
    #expect(live().line1 == "On a call" && live().door.label == "Show the call" && live().door.style == .quiet)
    #expect(live("thinking").shape == .call(.thinking, muted: false, asking: false))
}

@Test func someoneAsksShowsOnlyTheSignal() {
    let d = live("listening") { $0.status.apply(#"data: {"type":"ask","id":"a","detail":"Bash ls","worker":"api","voice":true,"full":"ls"}"#) }
    #expect(d.line1 == "We need you" && d.style == .ask && d.door.label == "Answer in the call" && d.door.style == .move)
    #expect(d.shape == .call(.listening, muted: false, asking: true))
}

@Test func aBlockedMicOrAClosedWindowFlattensThePill() {
    let d = live { $0.status.mic = "mac" }
    guard case .call(let p) = d.pill else { Issue.record("a call"); return }
    #expect(p.flat && p.wrong && p.word == "Mic blocked" && !p.canMute && d.door.action == .allowMicrophone && d.shape == .lost(asking: false))
    let w = live { $0.windowClosed = true }
    #expect(w.door.action == .showCall && w.door.style == .move)
    #expect(live { $0.feedLost = true }.shape == .reconnecting(asking: false))
}

@Test func failuresAndEndingsSayWhatHappened() {
    #expect(PanelData(input { $0.phase = .failed(.stopped) }).line2 == .text("The connection dropped."))
    #expect(PanelData(input { $0.phase = .failed(.stopped) }).line1 == "Call lost" && PanelData(input { $0.phase = .failed(.stopped) }).door.label == "Call again")
    #expect(PanelData(input { $0.phase = .failed(.slowStart) }).line1 == "The call didn’t start")
    #expect(PanelData(input { $0.phase = .ended(Ended(length: 5, line: nil)) }).line2 == .text("The call window has closed."))
}

@Test func whatNoRowCoversKeepsItsOldWordsOnceTheRowsAreDone() {
    func panel(_ f: (inout Machine) -> Void) -> PanelData {
        var m = Machine(callFolder: URL(filePath: "/x"), node: Node(url: URL(filePath: "/n"), version: "24.0.0"), packages: true, claude: URL(filePath: "/c"), claudeVersion: "9.9.9", signedIn: true, chrome: URL(filePath: "/ch"))
        f(&m)
        var i = input(); i.missing = missing(m)
        return PanelData(i)
    }
    #expect(panel { $0.chrome = nil }.door.label == "Get Chrome")
    #expect(panel { $0.node = nil }.door.label == "Install Node")
    #expect(panel { $0.node = nil; $0.chrome = nil }.line1 == "1 step to go")
}

@Test func theCallNeverClaimsAStateItHasNotBeenTold() {
    guard case .call(let p) = live("") .pill else { Issue.record("a call"); return }
    #expect(p.word == "" && p.wave == .dots && !p.canMute && !p.muted)
}

@Test func aRequestIsNeverHiddenByATroubledCall() {
    let ask = { (i: inout PanelInput) in i.status.apply(#"data: {"type":"ask","id":"a","detail":"Bash ls","worker":"api","voice":false,"full":"ls"}"#); i.status.mic = "chrome" }
    let d = live("listening", ask)
    #expect(d.line1 == "We need you" && d.style == .ask && d.door.action == .allowMicrophone && d.door.style == .move && d.shape == .lost(asking: true))
    #expect(live("listening") { $0.windowClosed = true; ask(&$0); $0.status.mic = "" }.shape == .lost(asking: true))
    #expect(live("listening") { $0.feedLost = true; ask(&$0); $0.status.mic = "" }.shape == .reconnecting(asking: true))
}

@Test func endingKeepsAFlatCallPillAndANewWordOnTheDoor() {
    let d = PanelData(input { $0.phase = .ending; $0.liveSince = Date() })
    guard case .call(let p) = d.pill else { Issue.record("a call pill"); return }
    #expect(p.flat && p.ending && !p.canMute && d.door.label != "Ending…" && !d.door.enabled && d.shape == .call(.dots, muted: false, asking: false) && d.onCall)
}

@Test func nameCutsAtTheDesignsLimits() {
    #expect(middleCut("exactly-sixteen-c", 16) != "exactly-sixteen-c") // 17 characters: cut
    #expect(middleCut("exactly-16-chars!", 17) == "exactly-16-chars!") // as long as the room: whole
    #expect(middleCut("sixteen-chars-xyz", 17) == "sixteen-chars-xyz") // exactly the room: kept
    #expect(middleCut("1234567890123456", 16) == "1234567890123456")
    #expect(middleCut("a-short-start-then-a-very-long-last-part", 16) == "a-short…part") // whole parts, then the last part whole
    #expect(middleCut("short-averyverylonglastpartname", 16) == "short-aver…tname") // a last part too long: both ends as they are
    #expect(middleCut("storefront-checkout-redesign-2026", 16).hasPrefix("storefront"))
}

@Test func theDownloadIsNeverAStepAndNeverComesBeforeTheProject() {
    var i = input { $0.project = nil }
    i.missing = missing(Machine(callFolder: URL(filePath: "/x"), node: Node(url: URL(filePath: "/n"), version: "24.0.0"), packages: false, claude: URL(filePath: "/c"), claudeVersion: "9.9.9", signedIn: true, chrome: URL(filePath: "/ch")))
    #expect(PanelData(i).line2 == .text("Next: the project.") && PanelData(i).door.action == .openSetup)
    i.project = URL(filePath: "/x/api") // the rows are done: only now is the download said
    let wait = PanelData(i)
    #expect(wait.line2 == .text("Downloading, hold on a second…") && wait.door.style == .quiet && !wait.door.enabled)
    i.installFailed = true
    #expect(PanelData(i).door.label == "Try again" && PanelData(i).door.action == .install)
    var moved = i; moved.installFailed = false
    moved.missing = missing(Machine(callFolder: URL(filePath: "/x"), server: false, node: Node(url: URL(filePath: "/n"), version: "24.0.0"), packages: true, claude: URL(filePath: "/c"), claudeVersion: "9.9.9", signedIn: true, chrome: URL(filePath: "/ch")))
    let m = PanelData(moved)
    #expect(m.line2 == .text("Build the app again from its folder.") && m.door.style == .quiet && !m.door.enabled)
}

@Test func theFirstLookCountsNoStepsItDoesNotKnowYet() {
    var i = PanelInput(); i.missing = nil; i.project = nil
    let d = PanelData(i)
    #expect(d.line1 == "Looking at this Mac." && d.door.label == "One moment" && !d.door.enabled)
    i.missing = []; i.micState = .done
    #expect(PanelData(i).line1 == "1 thing to go") // the check is done: only the project is left
    i.missing = nil; i.project = URL(filePath: "/x/api")
    #expect(PanelData(i).line1 == "Oh Kevin") // a project already chosen: ready, the call itself waits for the check
}

@Test func theDesignsWordForNode() {
    var i = input()
    i.missing = missing(Machine(callFolder: URL(filePath: "/x"), node: nil, packages: true, claude: URL(filePath: "/c"), claudeVersion: "9.9.9", signedIn: true, chrome: URL(filePath: "/ch")))
    #expect(PanelData(i).door.label == "Install Node")
}

@Test func thePrivacyPageIsMadeFromTheDisclosureStrings() {
    let page = Disclosure.page(current: .anyStep)
    #expect(page.contains(Disclosure.leaves) && page.contains(Disclosure.mayDo))
    for choice in [SpokenYes.safeSteps, .anyStep, .nothing] { #expect(page.contains(Disclosure.yes(choice))) }
    #expect(page.contains("(your setting)") && page.contains("prefers-color-scheme: dark") && !page.contains("http"), "self-contained: no link out, light and dark")
    #expect(Disclosure.settings == "\(Disclosure.leaves) \(Disclosure.mayDo)")
}

// MARK: - Moving the app to Applications

private func fakeApp(_ folder: URL, version: String, name: String = "Oh Kevin.app") throws -> URL {
    let app = folder.appending(path: name), contents = app.appending(path: "Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try "version \(version)".write(to: contents.appending(path: "payload.txt"), atomically: true, encoding: .utf8)
    try (["CFBundleVersion": version] as NSDictionary).write(to: contents.appending(path: "Info.plist"))
    return app
}
private func payload(_ app: URL) -> String? { try? String(contentsOf: app.appending(path: "Contents/payload.txt"), encoding: .utf8) }

@Test func theDecisionFromWhereTheAppRuns() {
    let folders = [URL(filePath: "/Applications"), URL(filePath: "/Users/me/Applications")]
    #expect(moveDecision(bundle: URL(filePath: "/Applications/Oh Kevin.app"), original: nil, folders: folders) == .stay)
    #expect(moveDecision(bundle: URL(filePath: "/Users/me/Applications/Oh Kevin.app"), original: nil, folders: folders) == .stay)
    #expect(moveDecision(bundle: URL(filePath: "/Applications/Utilities/Oh Kevin.app"), original: nil, folders: folders) == .stay)
    let downloads = URL(filePath: "/Users/me/Downloads/Oh Kevin.app")
    #expect(moveDecision(bundle: downloads, original: nil, folders: folders) == .move(source: downloads))
    #expect(moveDecision(bundle: URL(filePath: "/Applications Old/Oh Kevin.app"), original: nil, folders: folders) == .move(source: URL(filePath: "/Applications Old/Oh Kevin.app")), "a name that only starts like Applications")
    // Translocated: the copy is never the source; its original is.
    let translocated = URL(filePath: "/private/var/folders/xx/T/AppTranslocation/ABC-123/d/Oh Kevin.app")
    #expect(looksTranslocated(translocated) && !looksTranslocated(downloads))
    #expect(moveDecision(bundle: translocated, original: downloads, folders: folders) == .move(source: downloads))
    #expect(moveDecision(bundle: translocated, original: nil, folders: folders) == .unknownOriginal)
    #expect(translocationOriginal(of: URL(filePath: "/Applications/Safari.app")) == (false, nil)) // the real system call, on an app that is not translocated
}

@Test func aFreshAppIsCopiedWholeWithItsQuarantineMark() throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    let downloads = tmp.appending(path: "Downloads"), apps = tmp.appending(path: "Applications")
    try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
    let source = try fakeApp(downloads, version: "3")
    let mark = "0081;5f5e1000;Safari;"
    #expect(setxattr(source.path, "com.apple.quarantine", mark, mark.utf8.count, 0, 0) == 0)
    let outcome = installApp(from: source, into: [apps])
    #expect(outcome == .installed(apps.appending(path: "Oh Kevin.app")))
    #expect(payload(apps.appending(path: "Oh Kevin.app")) == "version 3")
    var buffer = [CChar](repeating: 0, count: 100)
    let n = getxattr(apps.appending(path: "Oh Kevin.app").path, "com.apple.quarantine", &buffer, 100, 0, 0)
    // macOS itself rewrites the value of a quarantine mark when anything copies the file (cp and ditto do the same: 0081;… becomes 0281;…), so
    // what matters is that the mark is still there: it is kept, not stripped.
    #expect(n > 0 && String(cString: buffer).hasPrefix("0"), "the quarantine mark is kept, not stripped")
    #expect(try fm.contentsOfDirectory(atPath: apps.path) == ["Oh Kevin.app"], "no half-written staging copy is left")
    #expect(payload(source) == "version 3", "the original is not touched")
}

@Test func anOlderCopyIsReplacedAndANewerOrEqualOneIsKept() throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    let downloads = tmp.appending(path: "Downloads"), apps = tmp.appending(path: "Applications")
    for dir in [downloads, apps] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    let source = try fakeApp(downloads, version: "5"), dest = apps.appending(path: "Oh Kevin.app")
    _ = try fakeApp(apps, version: "4")
    #expect(installApp(from: source, into: [apps]) == .replacedOlder(dest))
    #expect(payload(dest) == "version 5")
    #expect(installApp(from: source, into: [apps]) == .keptExisting(dest), "the same version is kept: nothing to write")
    try fm.removeItem(at: dest); _ = try fakeApp(apps, version: "9")
    #expect(installApp(from: source, into: [apps]) == .keptExisting(dest), "a newer copy is the one to start")
    #expect(payload(dest) == "version 9")
    #expect(try fm.contentsOfDirectory(atPath: apps.path) == ["Oh Kevin.app"])
}

@Test func anUnwritableFolderIsSkippedAndNothingWritableIsAFailureNotAHalfApp() throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { for dir in ["locked", "second"] { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.appending(path: dir).path) }; try? fm.removeItem(at: tmp) }
    let downloads = tmp.appending(path: "Downloads"), locked = tmp.appending(path: "locked"), second = tmp.appending(path: "second")
    for dir in [downloads, locked, second] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    let source = try fakeApp(downloads, version: "1")
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    #expect(installApp(from: source, into: [locked, second]) == .installed(second.appending(path: "Oh Kevin.app")), "falls back to the next folder, as ~/Applications follows /Applications")
    #expect(try fm.contentsOfDirectory(atPath: locked.path).isEmpty)
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: second.path)
    guard case .failed(let why) = installApp(from: source, into: [locked, second].map { $0 }) else { Issue.record("it should fail"); return }
    #expect(why.contains("cannot be written"))
    #expect(installApp(from: source, into: []) == .failed("no folder to install into"))
}

@Test func theRelaunchWaitsForThisAppAndQuotesThePath() {
    let command = relaunchCommand(waitingFor: 123, thenOpen: URL(filePath: "/Applications/Oh Kevin's.app"))
    #expect(command == "while kill -0 123 2>/dev/null; do sleep 0.2; done; /usr/bin/open '/Applications/Oh Kevin'\\''s.app'")
}

// MARK: - Updates

@Test func theUpdateLineSaysOnlyWhatThereIsToSay() {
    func line(_ f: (inout UpdateLineInput) -> Void) -> PanelLine? { var i = UpdateLineInput(); f(&i); return updateLine(i, product: "Oh Kevin") }
    #expect(line { _ in } == nil)
    #expect(line { $0.state = .installed("0.2") } == PanelLine("Updated to 0.2.", word: .init(title: "What’s new", isMove: false, action: .whatsNew)), "an offer is ink")
    #expect(line { $0.state = .failed("x") } == PanelLine("Couldn’t update.", word: .init(title: "Try again", isMove: true, action: .retryUpdate)), "your move is marigold")
    #expect(line { $0.state = .checking }?.text == "Checking…" && line { $0.state = .upToDate }?.text == "You’re up to date." && line { $0.state = .couldNotCheck("x") }?.text == "Couldn’t check. Try again later.")
    #expect(line { $0.state = .upToDate; $0.transientGone = true } == nil && line { $0.state = .checking; $0.transientGone = true } == nil, "gone after four seconds")
    // A new version is offered, and its progress shown, only with automatic updating off.
    #expect(line { $0.state = .available("0.2"); $0.automatic = false } == PanelLine("Oh Kevin 0.2 is out.", word: .init(title: "Update", isMove: true, action: .update)))
    #expect(line { $0.state = .available("0.2") } == nil && line { $0.state = .downloading(0.5) } == nil && line { $0.state = .readyToInstall("0.2") } == nil)
    #expect(line { $0.state = .downloading(0.62); $0.automatic = false } == PanelLine("Updating", progress: .known(0.62)))
    #expect(line { $0.state = .downloading(nil); $0.automatic = false }?.progress == .unknown)
    // The move: one line, one word; moving shows its progress.
    #expect(line { $0.moveOffered = true } == PanelLine("Move to Applications?", word: .init(title: "Move", isMove: true, action: .move)))
    #expect(line { $0.moving = true; $0.moveOffered = true } == PanelLine("Moving", progress: .unknown))
    // Never during a call (starting, running or ending).
    for state in [UpdateState.installed("0.2"), .failed("x"), .available("0.2"), .checking] {
        #expect(line { $0.state = state; $0.automatic = false; $0.inCall = true } == nil)
    }
    #expect(line { $0.moveOffered = true; $0.inCall = true } == nil)
    #expect(PanelData({ var i = PanelInput(); i.project = URL(filePath: "/x/api"); i.missing = []; i.line = PanelLine("Checking…"); return i }()).line == PanelLine("Checking…"))
}

@Test func whatsNewOpensTheReleasePageOfAGitHubFeed() {
    #expect(releaseNotesURL(feed: "https://github.com/bekhruzbekswe/ohkevin/releases/latest/download/appcast.xml", version: "0.2")?.absoluteString == "https://github.com/bekhruzbekswe/ohkevin/releases/tag/v0.2")
    #expect(releaseNotesURL(feed: "http://127.0.0.1:8765/appcast.xml", version: "0.2") == nil)
    #expect(releaseNotesURL(feed: nil, version: "0.2") == nil)
    // The Mac app's own feed and tags; an explicit prefix; names that are not a feed
    #expect(releaseNotesURL(feed: "https://github.com/bekhruzbekswe/ohkevin/releases/latest/download/appcast-app.xml", version: "0.3")?.absoluteString == "https://github.com/bekhruzbekswe/ohkevin/releases/tag/app-v0.3")
    #expect(releaseNotesURL(feed: "https://github.com/bekhruzbekswe/ohkevin/releases/latest/download/appcast.xml", version: "0.3", tagPrefix: "launcher-v")?.absoluteString == "https://github.com/bekhruzbekswe/ohkevin/releases/tag/launcher-v0.3")
    #expect(releaseNotesURL(feed: "https://github.com/bekhruzbekswe/ohkevin/releases/latest/download/appcastx.xml", version: "0.3") == nil)
    #expect(releaseNotesURL(feed: "https://github.com/bekhruzbekswe/ohkevin/releases/latest/download/notes.xml", version: "0.3") == nil)
}

@Test func anUpdateInstallsOnlyWhenTheAppIsQuiet() {
    let phases: [(Phase, Bool)] = [(.idle, true), (.ended(Ended(length: 5, line: nil)), true), (.failed(.stopped), true), (.starting, false), (.live, false), (.ending, false)]
    for (phase, quietPhase) in phases {
        #expect(updateIsQuiet(phase: phase, panelOpen: false, inSetup: false) == quietPhase, "\(phase)")
        #expect(!updateIsQuiet(phase: phase, panelOpen: true, inSetup: false), "an open panel is never quiet: \(phase)")
        #expect(!updateIsQuiet(phase: phase, panelOpen: false, inSetup: true), "first-run setup is never quiet: \(phase)")
    }
}

private func run(_ events: [UpdateEvent]) -> [UpdateState] {
    var model = UpdateModel(), states: [UpdateState] = []
    for e in events { model.apply(e); states.append(model.state) }
    return states
}

@Test func theEventsOfASessionBecomeTheStatesAScreenShows() {
    #expect(run([.checkStarted, .notFound(onLatest: true, reason: ""), .dismissed]) == [.checking, .upToDate, .upToDate])
    #expect(run([.checkStarted, .notFound(onLatest: false, reason: "needs a newer macOS"), .dismissed]) == [.checking, .couldNotCheck("needs a newer macOS"), .couldNotCheck("needs a newer macOS")])
    #expect(run([.checkStarted, .error("offline"), .dismissed]) == [.checking, .couldNotCheck("offline"), .couldNotCheck("offline")], "an error while looking is could-not-check")
    #expect(run([.checkStarted, .dismissed]) == [.checking, .idle], "a cancelled check leaves nothing behind")
    // Reported only (automatic updating off), then installed by a person who chose to.
    #expect(run([.checkStarted, .found(version: "0.3", stage: .notDownloaded), .dismissed]) == [.checking, .available("0.3"), .available("0.3")])
    // The whole way: download with progress, unpack, ready, install, done.
    #expect(run([.checkStarted, .found(version: "0.3", stage: .notDownloaded), .downloadStarted, .expectedLength(200), .received(50), .received(100), .extracting(nil), .extracting(0.5),
                 .readyToInstall(version: nil), .installing, .installed(version: nil), .dismissed])
            == [.checking, .available("0.3"), .downloading(0), .downloading(0), .downloading(0.25), .downloading(0.75), .downloading(nil), .downloading(0.5),
                .readyToInstall("0.3"), .installing, .installed("0.3"), .installed("0.3")])
    #expect(run([.downloadStarted, .received(10)]) == [.downloading(0), .downloading(nil)], "no length known: no fraction")
    #expect(run([.downloadStarted, .expectedLength(10), .received(30)]).last == .downloading(1), "more than announced never passes 1")
    // Already downloaded in the background: ready at once. A failure after work began is a failure, not could-not-check.
    #expect(run([.found(version: "0.4", stage: .downloaded)]) == [.readyToInstall("0.4")])
    #expect(run([.found(version: "0.4", stage: .installing)]) == [.installing])
    #expect(run([.downloadStarted, .error("the download failed"), .dismissed]) == [.downloading(0), .failed("the download failed"), .failed("the download failed")])
    #expect(run([.downloadStarted, .dismissed]) == [.downloading(0), .idle], "an update torn down half-way is not a state to keep")
}

@Test func updatesAreOnByDefaultInABuildWithAFeed() throws {
    let script = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../build.sh"), encoding: .utf8)
    for key in ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate"] { #expect(script.contains("<key>\(key)</key><true/>"), "\(key) is on") }
    #expect(script.contains("<key>SUScheduledCheckInterval</key><integer>86400</integer>"))
    #expect(script.contains(#"-n "${FEED_URL:-}" && -n "${SPARKLE_PUBLIC_KEY:-}""#), "and only when there is a feed and a key")
}

// MARK: The Agent SDK, fetched from npm at first run

@Test func theAgentSDKPinIsPackageLocksOwn() throws {
    let lock = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../call/package-lock.json"))) as? [String: Any]
    let entry = try #require((lock?["packages"] as? [String: Any])?["node_modules/@anthropic-ai/claude-agent-sdk"] as? [String: Any])
    #expect(entry["version"] as? String == AgentSDK.version && entry["integrity"] as? String == AgentSDK.integrity)
    #expect(entry["resolved"] as? String == AgentSDK.url.absoluteString)
}

@Test func theAgentSDKIsTakenOnlyWhenItsIntegrityIsThePinnedOne() async throws {
    let tmp = try scratch(), fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }
    let package = tmp.appending(path: "src/package")
    try fm.createDirectory(at: package, withIntermediateDirectories: true)
    for (name, text) in [("sdk.mjs", "export const query = 1"), ("package.json", "{}"), ("LICENSE.md", "terms"), ("README.md", "readme"), ("cli.js", "not taken")] {
        try text.write(to: package.appending(path: name), atomically: true, encoding: .utf8)
    }
    let tgz = tmp.appending(path: "sdk.tgz")
    #expect(run(URL(filePath: "/usr/bin/tar"), ["-czf", tgz.path, "-C", tmp.appending(path: "src").path, "package"])?.status == 0)
    let call = tmp.appending(path: "call"), sdkFolder = call.appending(path: "node_modules/@anthropic-ai/claude-agent-sdk")
    #expect(await installSDK(into: call, url: tgz, integrity: "sha512-wrong") == false)
    #expect(!fm.fileExists(atPath: sdkFolder.path))
    #expect(await installSDK(into: call, url: tgz, integrity: try #require(integrity(of: tgz))))
    #expect(try String(contentsOf: sdkFolder.appending(path: "sdk.mjs"), encoding: .utf8) == "export const query = 1")
    #expect(fm.fileExists(atPath: call.appending(path: sdk).path) && !fm.fileExists(atPath: sdkFolder.appending(path: "cli.js").path))
}

// MARK: The folders' old name

@Test func theOldFoldersMoveOnceAndTheSavedVoiceFollows() throws {
    let fm = FileManager.default, home = try scratch()
    defer { try? fm.removeItem(at: home) }
    let suite = "folder-move-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let oldSupport = home.appending(path: "Library/Application Support/\(Product.oldFolder)")
    try fm.createDirectory(at: oldSupport.appending(path: "Kokoro"), withIntermediateDirectories: true)
    try fm.createDirectory(at: home.appending(path: "Library/Logs/\(Product.oldFolder)"), withIntermediateDirectories: true)
    var s = CallSettings(); s.kokoroFolder = oldSupport.appending(path: "Kokoro").path; s.save(to: defaults)

    #expect(FolderMove.run(home: home, defaults: defaults).count == 2)
    let newSupport = home.appending(path: "Library/Application Support/\(Product.folder)")
    #expect(fm.fileExists(atPath: newSupport.appending(path: "Kokoro").path) && !fm.fileExists(atPath: oldSupport.path))
    #expect(fm.fileExists(atPath: home.appending(path: "Library/Logs/\(Product.folder)").path))
    #expect(CallSettings.load(from: defaults).kokoroFolder == newSupport.appending(path: "Kokoro").path)
    #expect(FolderMove.run(home: home, defaults: defaults).isEmpty) // once

    try fm.createDirectory(at: oldSupport, withIntermediateDirectories: true) // both there: the old one stays
    #expect(FolderMove.run(home: home, defaults: defaults).first?.hasPrefix("Both") == true)
    #expect(fm.fileExists(atPath: oldSupport.path))
}
