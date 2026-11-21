import AppKit
import AVFoundation
import Speech
import CallKit
import VoiceCore

/// What a call needs on this Mac (Node, the call server's packages, Claude Code and its sign-in), checked the way the launcher
/// checks it (VoiceCore's Machine.probe and missing()), and fixed from the app: the pinned Node and `npm ci` (installRuntime),
/// `claude auth login`, `claude update`. Each check first brings the app's own call copy up to the call/ inside it (syncCall), so an
/// update's new server is in place before anything runs; a changed package-lock.json then reinstalls the packages by itself. Chrome is the launcher's own need, never this app's: it listens through Apple's recogniser.
@Observable final class Setup {
    /// Only what is missing, in the order to fix it; nil until the first check has finished.
    private(set) var missing: [Missing]?
    var installing = false
    var installFailed = false
    var signingIn = false
    var updatingClaude = false
    var updateFailed = false
    /// The login shell's environment and the Claude Code found: what the call server runs with.
    @ObservationIgnored private(set) var environment: [String: String]?
    var claude: URL? { machine?.claude }
    @ObservationIgnored private var machine: Machine?
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var downloadStarted = false
    @ObservationIgnored private let place: CallPlace
    /// Everything a call runs on that this Mac lacks (Node and the packages, the local voice, the speech model): started by itself
    /// after the first check, and again by the setup's Install.
    let download: Download

    /// The setup screen's Microphone row: the microphone and speech recognition, asked for together (one Allow, no prompt left
    /// for the first call). Pictures set it directly.
    var mic = SetupInput.Mic.todo

    /// Pictures and tests: a made-up machine instead of this one.
    init(machine: Machine? = nil, place: CallPlace = Server.place) {
        self.place = place; download = Download(place: place)
        if let machine { self.machine = machine; missing = Self.needed(machine); mic = .done } else { lookAtMic() }
    }

    /// Both allowed: done; either refused: off (System Settings); otherwise not asked yet. Never while macOS is asking.
    func lookAtMic() {
        guard mic != .asking else { return }
        let a = AVCaptureDevice.authorizationStatus(for: .audio), s = SFSpeechRecognizer.authorizationStatus()
        mic = a == .authorized && s == .authorized ? .done : a == .denied || a == .restricted || s == .denied || s == .restricted ? .refused : .todo
    }
    /// Allow: macOS asks for the microphone, then for speech recognition, in its own windows.
    func allowMicrophone() {
        guard mic != .asking else { return }
        mic = .asking
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { [self] in mic = .todo; lookAtMic() } }
        }
    }

    static func needed(_ m: Machine) -> [Missing] { VoiceCore.missing(m).filter { $0.id != .chrome } }

    /// Off the main queue: it starts node and claude once each. `done` runs on the main queue once the list is known.
    func check(_ done: @escaping () -> Void = {}) {
        guard !checking else { return }
        checking = true
        DispatchQueue.global().async { [self] in
            let env = Shell.environment() ?? Shell.fallback(home: FileManager.default.homeDirectoryForCurrentUser, base: ProcessInfo.processInfo.environment)
            if let bundled = place.bundled { syncCall(from: bundled, to: place.folder) }
            let m = Machine.probe(environment: env, callFolder: place.folder, chrome: nil, kokoroPlaces: [], spotlight: false,
                                  support: place.ownCopy ? place.support : nil, locked: place.ownCopy)
            DispatchQueue.main.async { [self] in
                environment = env; machine = m; missing = Self.needed(m); checking = false; lookAtMic(); done()
                // The download starts by itself once per launch (onboarding.html): a first run, or an update that changed the packages
                if !downloadStarted { downloadStarted = true; install() }
            }
        }
    }

    /// The fix for a step, as the launcher does it.
    func fix(_ action: DoorAction) {
        switch action {
        case .install: install()
        case .signIn: signIn()
        case .update: update()
        case .open(let url): NSWorkspace.shared.open(url)
        default: break
        }
    }

    private func install() {
        guard !installing, let env = environment else { return }
        installing = true; installFailed = false
        let started = place.ownCopy
        guard started else { // a developer's own call folder: its packages, as a terminal installs them; the voice and model are the developer's
            DispatchQueue.global().async { [self] in
                let ok = installPackages(callFolder: place.folder, environment: env)
                DispatchQueue.main.async { [self] in check { [self] in installing = false; installFailed = !ok } }
            }
            return
        }
        download.start(environment: env) { [self] ok in check { [self] in installing = false; installFailed = !ok } }
    }

    /// `claude auth login` finishes in the browser: looked at every 2 s, for up to 3 minutes, or until the CLI exits.
    private func signIn() {
        guard !signingIn, let env = environment, let claude = machine?.claude else { return }
        let login = signInProcess(claude: claude, environment: env)
        guard (try? login.run()) != nil else { return }
        signingIn = true
        DispatchQueue.global().async { [self] in
            for tick in 1...720 {
                usleep(250_000)
                if !login.isRunning { break }
                if tick % 8 == 0, authStatus(claude: claude, environment: env) == true { break }
            }
            if login.isRunning { login.terminate() }
            DispatchQueue.main.async { [self] in check { [self] in signingIn = false } }
        }
    }

    private func update() {
        guard !updatingClaude, let env = environment, let claude = machine?.claude else { return }
        let run = claudeProcess(claude: claude, ["update"], environment: env)
        guard (try? run.run()) != nil else { return }
        updatingClaude = true; updateFailed = false
        DispatchQueue.global().async { [self] in
            for _ in 1...1200 where run.isRunning { usleep(250_000) }
            if run.isRunning { run.terminate() }
            DispatchQueue.main.async { [self] in
                check { [self] in updatingClaude = false; updateFailed = missing?.contains { $0.id == .claudeOld } ?? false }
            }
        }
    }
}
