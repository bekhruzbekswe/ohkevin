import AppKit
import Observation
import ServiceManagement
import Updating
import VoiceCore

let chromeID = "com.google.Chrome"
/// In development, the call server lives in the repository this app was built from; the app built for others carries its own copy.
let repoCallFolder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../call").standardized

/// Where the launcher works: the app's support folder (its Node, its copy of the call server and its voice), the call
/// server's folder, the ports a call may use, the call window's Chrome profile and the arguments it adds to Chrome. The
/// app uses the standard ones; the checks point them at a stub and a scratch folder.
struct Setup {
    var callFolder = repoCallFolder
    /// The call server's files inside the app, copied to callFolder at every check; nil in development.
    var bundledCall: URL?
    var support: URL
    var ports = CallSettings.ports
    var chromeProfile: URL
    var chromeArguments: [String] = []
    /// Whether Spotlight may be asked where a local voice is.
    var spotlight = true

    static func standard(home: URL) -> Setup {
        let support = home.appending(path: "Library/Application Support/\(Product.folder)", directoryHint: .isDirectory)
        let bundled = Bundle.main.url(forResource: "call", withExtension: nil)
        return Setup(callFolder: bundled == nil ? repoCallFolder : support.appending(path: "Call"), bundledCall: bundled, support: support,
                     chromeProfile: support.appending(path: "Chrome"))
    }
}

/// The app's one model: settings, the call server process, what its event stream says, the call window and what is
/// missing. The views and the menu-bar icon only read it.
@MainActor @Observable
final class Launcher {
    static let shared = Launcher(settings: .load(), defaults: .standard)

    var settings: CallSettings { didSet { defaults.map(settings.save) } }
    private(set) var phase = Phase.idle { didSet { updates.tryInstall() } }
    private(set) var status = CallStatus()
    /// What a call still needs; empty when nothing is missing. Nil until the first check has finished.
    private(set) var missingItems: [Missing]? { didSet { updates.tryInstall() } }
    private(set) var installing = false
    private(set) var installFailed = false
    /// The quiet retries are used up: the setup screen says so.
    private(set) var installGaveUp = false
    private(set) var downloadParts: [SetupInput.Part] = []
    private var installAttempts = 0
    /// The download starts by itself as soon as the first look finds it missing (the app sets it; the checks start theirs by hand).
    var installsAtLaunch = false
    /// The Microphone row: Chrome is being asked (its own window is open), or said no ("chrome": its settings, "mac": the system's).
    private(set) var micAsking = false
    private(set) var micRefused: MicAsk.Answer?
    private var micAsk: MicAsk?
    private(set) var signingIn = false
    private(set) var updatingClaude = false
    private(set) var updateFailed = false
    private(set) var installingVoice = false
    private(set) var voiceFailed = false
    private(set) var kokoro: URL?
    /// The call's start, for the timer.
    private(set) var liveSince: Date?
    /// The call is live and no call page is connected: its window never opened or was closed.
    private(set) var cantHear = false
    /// The launcher's feed from the call server dropped while the call is live: it cannot see the call until it is back.
    private(set) var feedLost = false
    private var launch: Launch?
    private var lostWatch: Task<Void, Never>?
    /// The call broke and its window is the way back (a restart can still use it).
    private var lost: Bool { if case .failed(let f) = phase { f == .stopped } else { false } }
    private var canRecall: Bool { launch != nil && (callWindow.map { !$0.isTerminated } ?? false) }
    /// The server has been started again for this call: the call page reconnects to it.
    private var restarted = false
    /// How many times the broken server has been started again by itself in this call: once, never a loop.
    private var restarts = 0
    private(set) var loginItem = SMAppService.mainApp.status
    private(set) var loginError: String?

    // The panel, as the app delegate shows it.
    var panelVisible = false { didSet { updates.tryInstall() } }
    var panelOpenedItself = false
    var openPanel: (_ keyboard: Bool, _ itself: Bool) -> Void = { _, _ in }
    var closePanel: () -> Void = {}
    var showSettings: () -> Void = {}
    var showSetup: () -> Void = {}
    var closeSetup: () -> Void = {}

    let defaults: UserDefaults?
    /// Self-updating (nothing unless the build was given a feed and a key).
    let updates = Updates()
    private var refreshedPackages = false
    /// The move to Applications is on offer (decided once, at launch), and under way.
    private let moveDecision = AppMover.decision()
    private(set) var moving = false
    /// The update state whose four seconds of being said are over (checking, up to date, could not check).
    private var transientGone: UpdateState?
    let home: URL
    let setup: Setup

    private var environment: [String: String]?
    private var machine: Machine?
    private var probing: Task<Void, Never>?
    private var server: CallServer?
    private(set) var key = ""
    private(set) var port = 0
    private var watcher: Task<Void, Never>?
    private var startLimit: Task<Void, Never>?
    private var pageCheck: Task<Void, Never>?
    private var whenEnded: [() -> Void] = []
    private(set) var callWindow: NSRunningApplication?
    /// The hand-over setting as it was when the call started, and whether this call's end hands its work over.
    private var callOpensApp = false
    private(set) var handingOver = false
    /// Each start attempt's number: only the latest may go on after the health check.
    private var attempt = 0

    init(settings: CallSettings, defaults: UserDefaults?, home: URL = .homeDirectory, setup: Setup? = nil) {
        self.settings = settings
        self.defaults = defaults
        self.home = home
        self.setup = setup ?? .standard(home: home)
        updates.isQuiet = { [unowned self] in self.isQuiet }
        updates.onChange = { [unowned self] in self.updateStateChanged() }
    }

    /// What the panel and the menu-bar item say now, as plain data.
    var panelInput: PanelInput {
        var i = PanelInput()
        i.phase = phase; i.status = status; i.missing = missingItems; i.project = project; i.recents = recentProjects
        i.installing = installing; i.installFailed = installGaveUp; i.signingIn = signingIn; i.updatingClaude = updatingClaude; i.updateFailed = updateFailed
        i.windowClosed = cantHear; i.feedLost = feedLost; i.liveSince = liveSince; i.handingOver = handingOver
        i.micState = settings.micAllowed || settings.hasCalled ? .done : micAsking ? .asking : micRefused != nil ? .refused : .todo
        i.micAskingLine = "Chrome is asking."
        i.downloadParts = downloadParts
        return i
    }
    /// The one setup screen, as it stands.
    var setupScreen: SetupScreen { SetupScreen(panelInput.setup) }

    var panel: PanelData {
        var d = PanelData(panelInput)
        d.canUpdate = updates.available
        var l = UpdateLineInput()
        l.state = updates.state; l.automatic = updates.automatic; l.moving = moving
        if case .move? = moveDecision { l.moveOffered = true }
        l.inCall = [.starting, .live, .ending].contains { $0 == phase }
        l.transientGone = transientGone == updates.state
        d.line = updateLine(l)
        return d
    }
    var project: URL? { settings.project.flatMap { exists($0) ? URL(filePath: $0) : nil } }
    var recentProjects: [URL] { settings.recents.filter(exists).map { URL(filePath: $0) } }
    var onCall: Bool { server != nil || phase == .live || phase == .ending }
    var serverPID: Int32? { server?.pid }
    var logURL: URL { CallLog.current(home: home) }
    var failure: Failure? { if case .failed(let f) = phase { f } else { nil } }
    /// Start Call is ready unless something is truly missing; a call started during the check waits for it.
    var canStart: Bool { missingItems?.isEmpty != false }

    // MARK: What a call needs

    /// Checks Node, the server's packages, Claude Code and its sign-in, Chrome, and looks for the local voice. The login
    /// shell's environment (about a second) is read the first time and again on rereadShell.
    @discardableResult
    func checkHealth(rereadShell: Bool = false) -> Task<Void, Never> {
        if let probing { return probing }
        let task = Task {
            let known = rereadShell ? nil : environment
            let env = await Task.detached {
                known ?? Shell.environment() ?? Shell.fallback(home: .homeDirectory, base: ProcessInfo.processInfo.environment)
            }.value
            let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID)
            let places = kokoroPlaces(saved: settings.kokoroFolder, shell: env, home: home, project: project)
            let setup = setup
            let m = await Task.detached {
                if let bundled = setup.bundledCall { syncCall(from: bundled, to: setup.callFolder) } // an app update brings its new files by itself
                return Machine.probe(environment: env, callFolder: setup.callFolder, chrome: chrome, kokoroPlaces: places, spotlight: setup.spotlight,
                                     support: setup.support, locked: setup.bundledCall != nil)
            }.value
            environment = env; machine = m; missingItems = missing(m); kokoro = m.kokoro
            if let found = m.kokoro?.path, found != settings.kokoroFolder { settings.kokoroFolder = found }
            probing = nil
            // The download (first run, or an update that changed the packages) starts by itself, once; it has no screen and waits for no press.
            if installsAtLaunch, !refreshedPackages, let items = missingItems, installsByItself(missing: items) {
                refreshedPackages = true
                runInstall()
            }
        }
        probing = task
        return task
    }

    /// "Try again": the quiet retries start over.
    func installMissingPackages() {
        installAttempts = 0; installGaveUp = false
        runInstall()
    }

    /// Node (when the app has none yet) and the packages. A failure is tried again quietly, three times in all, a little later each
    /// time; only then does the setup screen say so.
    private func runInstall() {
        guard !installing, let env = environment else { return }
        installing = true; installFailed = false
        let setup = setup
        let node = Runtime.node(support: setup.support)
        let needsNode = !FileManager.default.isExecutableFile(atPath: node.path)
        func parts() -> [SetupInput.Part] {
            (needsNode ? [SetupInput.Part("Node", progress: FileManager.default.isExecutableFile(atPath: node.path) ? 1 : nil, weight: 30)] : []) + [SetupInput.Part("Packages", weight: 40)]
        }
        downloadParts = parts()
        Task {
            let watch = Task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); downloadParts = parts() } }
            let ok = await Task.detached { await installRuntime(support: setup.support, callFolder: setup.callFolder, bundledCall: setup.bundledCall, environment: env) }.value
            watch.cancel()
            installFailed = !ok
            if !ok { installAttempts += 1; installGaveUp = installAttempts >= 3 }
            await recheck()
            installing = false // after the look, so the row never offers Install again for what has just been installed
            if !ok, !installGaveUp {
                try? await Task.sleep(for: .seconds(5 * installAttempts))
                runInstall()
            }
        }
    }

    /// Downloads the local voice (Settings); the folder is the one the call looks in first.
    func installVoice() {
        guard !installingVoice, let env = environment else { return }
        installingVoice = true; voiceFailed = false
        let folder = CallSettings.defaultKokoro(home: home), call = setup.callFolder
        Task {
            let ok = await Task.detached { await installKokoro(into: folder, callFolder: call, environment: env, runner: bundledRunner()) }.value
            voiceFailed = !ok
            await recheck()
            installingVoice = false // after the look, so the row never shows "Download" for a voice that is already there
        }
    }

    /// Looks again after work that changed the Mac: a look already under way may have started before it, so it is waited
    /// for and another follows.
    private func recheck() async {
        await probing?.value
        await checkHealth().value
    }

    /// Runs `claude update`, which gives up after 5 minutes, then looks again.
    func updateClaude() {
        guard !updatingClaude, let env = environment, let claude = machine?.claude else { return }
        let update = claudeProcess(claude: claude, ["update"], environment: env)
        guard (try? update.run()) != nil else { return }
        updatingClaude = true; updateFailed = false
        Task {
            for _ in 1...1200 where update.isRunning { try? await Task.sleep(for: .milliseconds(250)) }
            if update.isRunning { update.terminate() }
            await recheck()
            updateFailed = missingItems?.contains { $0.id == .claudeOld } ?? false
            updatingClaude = false
        }
    }

    /// Runs `claude auth login`, which finishes in the browser, and looks every 2 s, for up to 3 minutes, whether it did;
    /// once the CLI has exited (signed in, or the browser tab closed) it stops at once and checks one last time.
    func signIn() {
        guard !signingIn, let env = environment, let claude = machine?.claude else { return }
        let login = signInProcess(claude: claude, environment: env)
        guard (try? login.run()) != nil else { return }
        signingIn = true
        Task {
            for tick in 1...720 {
                try? await Task.sleep(for: .milliseconds(250))
                if !login.isRunning { break }
                if tick % 8 == 0, await Task.detached(operation: { authStatus(claude: claude, environment: env) }).value == true { break }
            }
            if login.isRunning { login.terminate() }
            signingIn = false
            await checkHealth().value
        }
    }

    // MARK: The call

    func startCall() async {
        switch phase { case .idle, .ended, .failed: break; default: return }
        // "Call again" on a call that broke, with its window still open: the same server address and key again, so that window
        // reconnects and the call carries on in it: no new window, no page in between.
        // It rests on the facts, not on what the panel last showed: a launch of this call exists, its window is alive, and the call was
        // lost (the person did not end it).
        if lost, canRecall, let l = launch {
            restarts = 0
            if relaunch(l) { return }
        }
        launch = nil; restarted = false; lostWatch?.cancel(); lostWatch = nil
        guard let project else { return chooseProject(thenStart: true) }
        phase = .starting
        attempt += 1
        let mine = attempt
        status = CallStatus(); cantHear = false; feedLost = false
        if let old = callWindow, !old.isTerminated { // a window a broken call left: it goes before a new call opens its own
            closeCallWindow()
            for _ in 0..<50 where !old.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
        }
        guard attempt == mine, phase == .starting else { return }
        await checkHealth().value
        guard attempt == mine, phase == .starting else { return } // cancelled while checking, or started again
        guard canStart, let node = machine?.node, let environment else { phase = .idle; return }
        guard let port = freePort(in: setup.ports) else { phase = .failed(.noPort); return }
        key = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        self.port = port
        callOpensApp = settings.openInClaudeApp
        handingOver = false
        let voice = kokoro ?? CallSettings.defaultKokoro(home: home) // a folder without Kokoro: Chrome's voice speaks
        do {
            let l = Launch(node: node.url, project: project, port: port, key: key,
                           environment: settings.environment(base: environment, project: project, key: key, port: port, kokoro: voice, claude: machine?.claude))
            try spawn(l, log: CallLog.fresh(home: home))
            launch = l; restarts = 0
        } catch {
            phase = .failed(.couldNotLaunch)
            return
        }
        settings.choose(project.path)
        let key = key
        watcher = Task { await watch(port: port, key: key) }
        startLimit = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, phase == .starting else { return }
            phase = .failed(.slowStart)
            server?.forceQuit() // a server that never answered may not answer a polite signal either
        }
    }

    /// What a call server was started with: enough to start the same one again, on the same address with the same key.
    private struct Launch { let node: URL, project: URL, port: Int, key: String, environment: [String: String] }

    private func spawn(_ l: Launch, log: URL) throws {
        let server = try CallServer(node: l.node, server: setup.callFolder.appending(path: "server.mjs"), project: l.project, environment: l.environment, log: log)
        try server.start { code in Task { @MainActor in self.exited(server, code) } }
        self.server = server
    }

    /// Starts the call server again on its old address with its old key. The call window is the old one: its page reconnects by
    /// itself and carries on. The new server is a new call: it knows nothing of the old conversation or its workers. False when it
    /// could not be started.
    private func relaunch(_ l: Launch) -> Bool {
        guard (try? spawn(l, log: logURL)) != nil else { return false }
        phase = .live
        status = CallStatus(); feedLost = true; restarted = true; cantHear = false
        pageCheck?.cancel(); pageCheck = nil
        watcher?.cancel()
        watcher = Task { await watch(port: l.port, key: l.key) }
        startLimit?.cancel()
        startLimit = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, phase == .live, !status.live else { return }
            server?.forceQuit() // it never answered: the restart failed, and exited() says so
        }
        watchPages(after: 10)
        announce("The call dropped. Starting it again.")
        return true
    }

    /// While a call is lost: when its window goes (the person closed it) there is nothing to come back to, and Ready is what is left.
    private func watchLost() {
        lostWatch?.cancel()
        lostWatch = Task {
            while !Task.isCancelled, lost {
                try? await Task.sleep(for: .seconds(2))
                if lost, !canRecall { launch = nil; if !panelVisible { phase = .idle }; return }
            }
        }
    }

    /// Stops a call that has not answered yet: nothing ran, so nothing ends; back to Ready.
    func cancelStart() {
        guard phase == .starting else { return }
        attempt += 1
        watcher?.cancel(); watcher = nil
        startLimit?.cancel(); startLimit = nil
        let server = server
        self.server = nil
        server?.forceQuit()
        phase = .idle
    }

    /// Follows the server's event stream for as long as it runs, reconnecting if it drops.
    private func watch(port: Int, key: String) async {
        while !Task.isCancelled, server != nil {
            try? await EventFeed.read(port: port, key: key) { line in await self.heard(line) }
            if phase == .live && server != nil { feedLost = true } // the server is still there: the call is out of sight, not over
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func heard(_ line: String) {
        if feedLost { feedLost = false }
        let blocked = status.mic
        if restarted, line.contains("\"type\":\"hello\"") { restarted = false; liveSince = Date() } // a new call: its clock starts again
        let change = status.apply(line)
        if phase == .live, !status.mic.isEmpty, status.mic != blocked { // the page's microphone is blocked: the call is deaf until it is fixed
            announce("The call can’t hear you")
            if !panelVisible { openPanel(false, true) }
        }
        switch change {
        case .connected? where phase == .starting:
            phase = .live
            liveSince = Date()
            settings.hasCalled = true
            startLimit?.cancel(); startLimit = nil
            openCallWindow()
            announce("Call started")
        case .asked(let ask)?:
            announce("Claude Code needs your answer. \(ask.question)")
            if !ask.voice && !panelVisible { openPanel(false, true) }
        case .answered?:
            if panelOpenedItself && !status.asks.contains(where: { !$0.voice }) {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if panelOpenedItself && !status.asks.contains(where: { !$0.voice }) { closePanel() }
                }
            }
        case .hangup?: // the page's End call: the server ends the call itself, by the same rule as End Call
            guard phase == .live else { break }
            beginEnding(handOver: callOpensApp && !status.sessions.isEmpty)
        default: break
        }
        watchPages()
    }

    /// With no call page connected for a while the call cannot hear: 10 s after its window opens, 3 s after one closes.
    private func watchPages(after seconds: Double = 3) {
        guard phase == .live else { return }
        if status.pages > 0 { cantHear = false; pageCheck?.cancel(); pageCheck = nil; return }
        guard pageCheck == nil, !cantHear else { return }
        pageCheck = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, status.pages == 0, phase == .live { cantHear = true }
            pageCheck = nil
        }
    }

    private func exited(_ ended: CallServer, _ code: Int32) {
        guard server === ended else { return }
        if let log = try? FileHandle(forWritingTo: logURL) { // for Show Details: how the call server ended
            log.seekToEndOfFile()
            log.write(Data("[\(Product.name)] The call server exited with code \(code).\n".utf8))
            try? log.close()
        }
        // A server that broke in the middle of a call whose window is open is started again, once, with the same address and key:
        // the page reconnects by itself and the call goes on in the same window. A second break, or no window, is a lost call.
        let crashed = phase == .live && code != 0 && code != 3
        if crashed, restarts < 1, status.pages > 0, callWindow.map({ !$0.isTerminated }) ?? false, let l = launch {
            restarts += 1
            if relaunch(l) { return }
        }
        restarted = false // a restart that did not take is over
        watcher?.cancel(); watcher = nil
        startLimit?.cancel(); startLimit = nil
        pageCheck?.cancel(); pageCheck = nil
        server = nil
        if !crashed { closeCallWindow() } // a lost call leaves its window: "Call again" brings it back to life
        let length = Date().timeIntervalSince(liveSince ?? Date())
        // 0: ended (and, if handed over, opened in the Claude app); 3: ended, the work did not open there.
        let endedItself = phase == .live && (code == 0 || code == 3) // the page ended it, and the event was missed
        if endedItself { handingOver = callOpensApp && !status.sessions.isEmpty }
        if case .failed = phase {
        } else if phase == .starting {
            phase = .failed(.stoppedStarting)
        } else if phase == .ending || endedItself {
            let line: String? = status.sessions.isEmpty ? nil
                : handingOver && code == 0 ? "Its work is open in the Claude app." : "Its work is saved in Claude Code."
            phase = .ended(Ended(length: length, line: line))
            launch = nil
            announce("Call ended")
        } else {
            phase = .failed(.stopped)
            watchLost()
            if !panelVisible { openPanel(false, true) } // a call that broke comes to you
        }
        if let f = failure { announce(f.title) }
        status = CallStatus(); cantHear = false; feedLost = false
        liveSince = nil
        whenEnded.forEach { $0() }
        whenEnded = []
    }

    /// Ends the call the way Ctrl-C does in a terminal: with the hand-over to the Claude app when that was on at the
    /// start of the call and Claude Code was given work.
    func endCall() {
        guard let server, phase == .live else { return }
        beginEnding(handOver: callOpensApp && !status.sessions.isEmpty)
        server.end(handingOver ? .handOver : .plain)
    }

    /// The call's window closes at once, so its microphone goes with the call, not 9 s later. However the ending began
    /// (End Call, the page, Quit), a server still there after 30 s is stuck and is ended: nothing waits for ever.
    private func beginEnding(handOver: Bool) {
        handingOver = handOver
        phase = .ending
        closeCallWindow()
        let server = server
        Task { // the hand-over waits up to 9 s for Claude Code to close
            try? await Task.sleep(for: .seconds(30))
            if let server, self.server === server { server.forceQuit() }
        }
    }

    /// Quitting during a call ends it first. Returns true when the app must wait for that.
    func endBeforeQuit(then done: @escaping () -> Void) -> Bool {
        if phase == .starting { cancelStart() }
        guard server != nil else { closeCallWindow(); return false }
        whenEnded.append(done)
        endCall()
        return true
    }

    /// A lost call stays "Call lost / Call again" for as long as its window is there to come back to; any other call that ended or
    /// failed is shown until the panel closes, and then the panel is Ready again.
    func panelClosed() {
        updates.acknowledgeInstalled() // "Updated to …" is said once
        switch phase {
        case .ended: phase = .idle
        case .failed: if !(lost && canRecall) { launch = nil; phase = .idle }
        default: break
        }
    }

    /// Asks the call page to mute or unmute; the voice's state comes back through the feed, so the panel never claims what it did not see.
    func mute(_ on: Bool) {
        let (port, key) = (port, key)
        Task { try? await EventFeed.post("/mute", ["on": on], port: port, key: key) }
    }

    /// What the panel's controls ask for.
    func handle(_ intent: PanelIntent) {
        switch intent {
        case .door(let action):
            switch action {
            case .startCall: Task { await startCall() }
            case .cancel: cancelStart()
            case .chooseProject: chooseProject()
            case .install: installMissingPackages()
            case .openSetup: showSetup()
            case .signIn: signIn()
            case .update: updateClaude()
            case .allowMicrophone: openMicSettings()
            case .showCall: showCallWindow()
            case .open(let url): NSWorkspace.shared.open(url)
            case .none: break
            }
        case .mute(let on): mute(on)
        case .endCall: endCall()
        case .pick(let path): settings.choose(path)
        case .settings: showSettings()
        case .showDetails: openLog()
        case .quit: NSApp.terminate(nil)
        case .checkForUpdates: updates.checkForUpdates()
        case .line(let action): handleLine(action)
        }
    }

    // MARK: The call window: the launcher's own Chrome, one window, closed with the call

    func openCallWindow() {
        guard phase == .live, let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID) else { cantHear = true; return }
        if callWindow?.isTerminated ?? true { callWindow = runningInstance(profile: setup.chromeProfile) } // left by a launcher that crashed
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--user-data-dir=\(setup.chromeProfile.path)", "--app=\(EventFeed.pageURL(port: port, key: key))",
                            "--window-size=480,760", "--no-first-run", "--no-default-browser-check",
                            "--autoplay-policy=no-user-gesture-required"] + setup.chromeArguments
        cantHear = false
        pageCheck?.cancel(); pageCheck = nil
        // Opened while the instance runs, Chrome hands the window to it and the new process leaves: keep the first.
        NSWorkspace.shared.openApplication(at: chrome, configuration: config) { app, error in
            Task { @MainActor in
                guard error == nil, let app else { self.cantHear = true; return }
                if self.callWindow?.isTerminated ?? true { self.callWindow = app }
            }
        }
        watchPages(after: 10)
    }

    /// Where the page's microphone is allowed again: macOS's Microphone privacy list, or Chrome's own settings for the
    /// call page's site, opened in the call window's Chrome (it has no address bar).
    func openMicSettings() {
        if status.mic == "mac" || micRefused == .mac { NSWorkspace.shared.open(Self.macMicrophone); return }
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--user-data-dir=\(setup.chromeProfile.path)", Self.chromeMicrophone(port: port == 0 ? setup.ports.lowerBound : port).absoluteString] + setup.chromeArguments
        NSWorkspace.shared.openApplication(at: chrome, configuration: config)
    }

    /// What the setup screen's controls ask for.
    func handle(_ intent: SetupIntent) {
        switch intent {
        case .signIn: signIn()
        case .updateClaude: updateClaude()
        case .allowMicrophone: askMicrophone()
        case .openMicrophoneSettings: openMicSettings()
        case .chooseProject: chooseProject()
        case .startCall: closeSetup(); Task { await startCall() }
        case .retryDownload: installMissingPackages()
        case .pick(let path): settings.choose(path)
        case .open(let url): NSWorkspace.shared.open(url)
        }
    }

    // MARK: The microphone, before any call

    /// Opens the call's own Chrome (its profile, its address) on a page that asks for the microphone and says what Chrome answered. Not
    /// while a call has the address.
    func askMicrophone() {
        guard !micAsking, !onCall, let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID) else { return }
        let port = setup.ports.lowerBound
        guard portIsFree(port), let ask = MicAsk(port: port, answered: { answer in Task { @MainActor in self.micAnswered(answer) } }) else { return }
        ask.start()
        micAsk = ask; micAsking = true; micRefused = nil
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--user-data-dir=\(setup.chromeProfile.path)", "--app=\(ask.url.absoluteString)", "--window-size=420,160", "--no-first-run",
                            "--no-default-browser-check"] + setup.chromeArguments
        NSWorkspace.shared.openApplication(at: chrome, configuration: config) { app, error in
            Task { @MainActor in
                guard error == nil, let app else { return self.micEnded() }
                if self.callWindow?.isTerminated ?? true { self.callWindow = app }
                // Closed without an answer (or none in two minutes): back to the button.
                for _ in 0..<120 where self.micAsking && !app.isTerminated { try? await Task.sleep(for: .seconds(1)) }
                if self.micAsking { self.micEnded() }
            }
        }
    }

    private func micAnswered(_ answer: MicAsk.Answer) {
        guard micAsking else { return }
        if answer == .ok { settings.micAllowed = true; micRefused = nil } else { micRefused = answer }
        micEnded()
    }

    private func micEnded() {
        micAsk?.stop(); micAsk = nil; micAsking = false
        closeCallWindow()
    }

    static let macMicrophone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static func chromeMicrophone(port: Int) -> URL { URL(string: "chrome://settings/content/siteDetails?site=http%3A%2F%2F127.0.0.1%3A\(port)")! }

    /// Brings exactly the call's window forward; opens it again if it is not open.
    func showCallWindow() {
        guard let window = callWindow, !window.isTerminated, status.pages > 0 else { return openCallWindow() }
        NSApp.activate() // macOS lets an app hand over the front only while it is active itself
        if !window.activate(from: .current, options: []) { _ = window.activate() }
    }

    /// Closes the call window, or one a launcher that crashed left open (still listening, perhaps).
    func closeCallWindow() {
        let window = callWindow ?? runningInstance(profile: setup.chromeProfile)
        callWindow = nil
        guard let window else { return }
        window.terminate()
        Task {
            try? await Task.sleep(for: .seconds(3))
            if !window.isTerminated { window.forceTerminate() }
        }
    }

    // MARK: Choosing folders

    func chooseProject(thenStart: Bool = false) {
        guard let folder = chooseFolder("Choose the project Claude Code will work in.") else { return }
        settings.choose(folder.path)
        if thenStart { // back where the call happens
            openPanel(false, false)
            Task { await startCall() }
        }
    }

    private func chooseFolder(_ message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = message
        closePanel()
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: Settings that act at once

    var opensAtLogin: Bool {
        get { loginItem == .enabled || loginItem == .requiresApproval }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
            }
            loginItem = SMAppService.mainApp.status
        }
    }

    func refreshLoginItem() { loginItem = SMAppService.mainApp.status }

    /// Whether an update may relaunch the app now (see VoiceCore's `updateIsQuiet`).
    var isQuiet: Bool {
        var setup = false
        if case .rest(setup: true) = panel.shape { setup = true }
        return updateIsQuiet(phase: phase, panelOpen: panelVisible, inSetup: setup)
    }

    /// The update line says checking, up to date or could not check for four seconds.
    private func updateStateChanged() {
        let s = updates.state
        transientGone = nil
        switch s {
        case .checking, .upToDate, .couldNotCheck:
            Task { try? await Task.sleep(for: .seconds(4)); if updates.state == s { transientGone = s } }
        default: break
        }
    }

    private func handleLine(_ action: LineAction) {
        switch action {
        case .update, .retryUpdate: updates.install()
        case .whatsNew:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            if let url = releaseNotesURL(feed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, version: version) { NSWorkspace.shared.open(url) }
        case .move:
            moving = true
            if let outcome = AppMover.moveAndRelaunch(), case .failed = outcome { moving = false }
        }
    }

    func openLog() { NSWorkspace.shared.open(logURL) }

    /// For the "Move to Applications" screen to come: where the app should move from (nil while the feature is off or the app is in place).
    var appMove: MoveDecision? { AppMover.decision().flatMap { $0 == .stay ? nil : $0 } }

    /// Moves the app to Applications and starts the copy there (see AppMover). Nothing calls this yet: there is no UI.
    func moveToApplications() { AppMover.moveAndRelaunch() }

    /// Opens the privacy page in the browser, in a window of its own where that can be had. The page is made now from the Disclosure
    /// strings (marking the person's spoken-yes choice); if it cannot be written, the copy shipped in the app is used. Chrome is asked
    /// for a new window (`open -n … --new-window`); another browser opens its usual way, which may be a tab.
    func openPrivacy() {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(Product.folder) privacy.html")
        let fresh = (try? Disclosure.page(current: settings.spokenYes).write(to: file, atomically: true, encoding: .utf8)) != nil
        guard let page = fresh ? file : Bundle.main.url(forResource: "privacy", withExtension: "html") else { return }
        if let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!), Bundle(url: browser)?.bundleIdentifier == chromeID {
            _ = run(URL(filePath: "/usr/bin/open"), ["-na", browser.path, "--args", "--new-window", page.absoluteString])
        } else {
            NSWorkspace.shared.open(page)
        }
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// The Chrome that holds a profile, if one is running: its SingletonLock names its process ("host-pid"). A lock can
/// outlive its Chrome (a power loss), and its number can come back as the user's own browser, so the process must
/// also carry this profile on its command line before it is touched.
func runningInstance(profile: URL) -> NSRunningApplication? {
    guard let lock = try? FileManager.default.destinationOfSymbolicLink(atPath: profile.appending(path: "SingletonLock").path),
          let pid = lock.split(separator: "-").last.flatMap({ Int32($0) }),
          let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == chromeID, !app.isTerminated,
          let ps = run(URL(filePath: "/bin/ps"), ["-ww", "-o", "command=", "-p", String(pid)]),
          (String(decoding: ps.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) + " ")
            .contains("--user-data-dir=\(profile.path) ") // the whole path: not one that only begins with it
    else { return nil }
    return app
}

private func exists(_ path: String) -> Bool {
    var folder: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
}
