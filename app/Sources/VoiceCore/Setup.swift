import Foundation

// The one setup screen (design/onboarding.html): three rows (Claude, Microphone, Project) and one bottom. Plain data in,
// plain data out: `SetupInput` is what the host knows, `SetupScreen` is what the screen says and which control is gold, and the
// views (CallViews' SetupView) draw it and send `SetupIntent`s back. The launcher and the Mac app both build a `SetupInput`.

public enum SetupIntent: Equatable, Sendable {
    case signIn, updateClaude, allowMicrophone, openMicrophoneSettings, chooseProject, startCall, retryDownload
    /// A recent project, by its path.
    case pick(String)
    /// A page to get something on (Claude Code, Node, Chrome).
    case open(URL)
}

public struct SetupInput: Equatable, Sendable {
    /// `get`: Claude Code is not there (or the update failed and its page is the way); `update`: it is too old to run a call.
    public enum Claude: Equatable, Sendable { case signIn, signingIn, get(URL, old: Bool), update, updating, done }
    public enum Mic: Equatable, Sendable {
        case todo, asking, refused, done
        /// The call listens through Chrome and there is none: its page is the button.
        case get(URL)
    }
    /// One part of the download, as the host knows it. `progress` is 0...1, nil when not known; 1 is done.
    public struct Part: Equatable, Sendable {
        public var name: String
        public var progress: Double?
        /// Its size (any unit, only the ratio matters); a bigger part moves the bar more.
        public var weight: Double
        /// Gave up after quiet retries.
        public var failed: Bool
        public init(_ name: String, progress: Double? = nil, weight: Double = 1, failed: Bool = false) { self.name = name; self.progress = progress; self.weight = weight; self.failed = failed }
        public var done: Bool { (progress ?? 0) >= 1 && !failed }
    }
    /// Something else a call needs that no row covers (Node to get, the app moved, Chrome gone after the microphone was allowed).
    public struct Problem: Equatable, Sendable {
        public var line: String
        public var button: String?
        public var intent: SetupIntent?
        public init(line: String, button: String? = nil, intent: SetupIntent? = nil) { self.line = line; self.button = button; self.intent = intent }
    }

    public var claude = Claude.signIn
    public var mic = Mic.todo
    /// The Microphone row's line while the system asks; the host knows who asks ("Chrome is asking.", "Your Mac is asking.").
    public var micAsking = "Your Mac is asking."
    /// The project's folder name; nil: none chosen.
    public var project: String?
    public var choices: [ProjectPill.Choice] = []
    /// What is still to download, supplied by the host; empty when there is nothing (or it is all there).
    public var download: [Part] = []
    public var problem: Problem?

    public init() {}
}

public struct SetupScreen: Equatable, Sendable {
    public enum ID: Int, CaseIterable, Sendable { case claude, mic, project }
    /// How a button looks: the one gold (your move), an outline you can press, or an outline at rest (nothing to press).
    public enum Look: Equatable, Sendable { case gold, quiet, rest }
    public enum Control: Equatable, Sendable {
        case done
        case button(String, Look, SetupIntent?)
    }
    public struct Row: Equatable, Sendable {
        public var id: ID
        public var name: String
        public var reason: String
        public var control: Control
        /// The project row, once chosen: its name is a word that drops down the recent projects.
        public var pick: Pick?
        public var done: Bool { control == .done }
    }
    public struct Pick: Equatable, Sendable { public var name: String; public var choices: [ProjectPill.Choice] }
    public enum Bottom: Equatable, Sendable {
        /// "Start the first call": gold when everything is done, an outline at rest before.
        case start(ready: Bool)
        /// The parts' combined progress, 0...1; nil when none of them can say.
        case downloading(Double?)
        /// One plain line and, if there is something to press, a gold button under it.
        case note(String, button: String?, intent: SetupIntent?)
    }

    public var rows: [Row]
    public var bottom: Bottom
    /// Rows not done yet.
    public var left: Int { rows.filter { !$0.done }.count }
    /// What the panel says is next: the first row not done, in the order Claude, Microphone, Project.
    public var next: String

    public init(_ i: SetupInput) {
        // Each row is its content and how it stands: done; `action` (a button to press); resting (under way, nothing to press); asking.
        enum State { case done, action, resting, asking }
        var rows: [(Row, State)] = []
        var next = ""
        func row(_ id: ID, _ name: String, _ reason: String, _ state: State, _ title: String = "", _ intent: SetupIntent? = nil, pick: Pick? = nil, then: String = "") {
            let control: Control = state == .done ? .done : .button(title, state == .resting ? .rest : .quiet, state == .resting ? nil : intent)
            rows.append((Row(id: id, name: name, reason: reason, control: control, pick: pick), state))
            if state != .done, next.isEmpty { next = then }
        }
        let why = ["Kevin works through your own Claude Code.", "Kevin listens only while a call is on.", "The folder Kevin will work in."]
        switch i.claude {
        case .done: row(.claude, "Claude", why[0], .done)
        case .signIn: row(.claude, "Claude", why[0], .action, "Sign in", .signIn, then: "Next: sign in to Claude.")
        case .signingIn: row(.claude, "Claude", "Finish in your browser. This moves on by itself.", .resting, "In your browser", then: "Finish in your browser.")
        case .get(let url, let old): row(.claude, "Claude", old ? "Claude Code needs an update." : "Claude Code isn’t installed.", .action, "Get Claude Code", .open(url), then: "Next: get Claude Code.")
        case .update: row(.claude, "Claude", "Claude Code needs an update.", .action, "Update", .updateClaude, then: "Next: update Claude Code.")
        case .updating: row(.claude, "Claude", "Claude Code is updating.", .resting, "Updating", then: "Claude Code is updating.")
        }
        switch i.mic {
        case .done: row(.mic, "Microphone", why[1], .done)
        case .todo: row(.mic, "Microphone", why[1], .action, "Allow", .allowMicrophone, then: "Next: the microphone.")
        case .asking: row(.mic, "Microphone", i.micAsking, .asking, "Allow", .allowMicrophone, then: "Next: the microphone.")
        case .refused: row(.mic, "Microphone", "It is off. Turn it on in System Settings › Privacy & Security.", .action, "Open Settings", .openMicrophoneSettings, then: "Next: the microphone.")
        case .get(let url): row(.mic, "Microphone", "Kevin listens through Chrome.", .action, "Get Chrome", .open(url), then: "Next: get Chrome.")
        }
        if let name = i.project { row(.project, "Project", "Kevin will work in ", .done, pick: Pick(name: name, choices: i.choices)) }
        else { row(.project, "Project", why[2], .action, "Choose", .chooseProject, then: "Next: the project.") }
        // One gold at a time: the first row with a button to press. A row that is asking holds it (the system's question is the next
        // thing); a row at rest does not (the rows after it can be done meanwhile).
        for n in rows.indices {
            if rows[n].1 == .asking { break }
            if rows[n].1 == .action {
                if case .button(let t, _, let intent) = rows[n].0.control { rows[n].0.control = .button(t, .gold, intent) }
                break
            }
        }
        self.rows = rows.map(\.0)
        self.next = next
        let ready = rows.allSatisfy { $0.1 == .done }
        if !ready { bottom = .start(ready: false) }
        else if let p = i.problem { bottom = .note(p.line, button: p.button, intent: p.intent) }
        else {
            let parts = i.download.filter { !$0.done }
            if parts.isEmpty { bottom = .start(ready: true) }
            else if parts.contains(where: \.failed) { bottom = .note("The download didn’t finish.", button: "Try again", intent: .retryDownload) }
            else { bottom = .downloading(Self.combined(i.download)) }
        }
    }
}

extension SetupScreen {
    /// The parts' progress as one: each counts by its weight, a part that cannot say counts as not started; nil when none can say.
    public static func combined(_ parts: [SetupInput.Part]) -> Double? {
        guard parts.contains(where: { $0.progress != nil }) else { return nil }
        let total = parts.reduce(0) { $0 + $1.weight }
        return total > 0 ? parts.reduce(0) { $0 + min(max($1.progress ?? 0, 0), 1) * $1.weight } / total : nil
    }
}

extension PanelInput {
    /// What the setup screen is built from, out of what the panel already knows. A check that has not finished says nothing against anyone.
    public var setup: SetupInput {
        var s = SetupInput()
        let m = missing ?? []
        func fix(_ id: Missing.Item) -> URL? { if case .open(_, let url)? = m.first(where: { $0.id == id })?.fix { url } else { nil } }
        func has(_ id: Missing.Item) -> Bool { m.contains { $0.id == id } }
        s.claude = updatingClaude ? .updating : signingIn ? .signingIn
            : has(.claude) ? (fix(.claude).map { .get($0, old: false) } ?? .signIn)
            : has(.claudeOld) ? (updateFailed ? (fix(.claudeOld).map { .get($0, old: true) } ?? .update) : .update)
            : has(.signIn) ? .signIn : .done
        s.mic = micState
        if micState != .done, let chrome = fix(.chrome) { s.mic = .get(chrome) }
        s.micAsking = micAskingLine
        s.project = project?.lastPathComponent
        s.choices = choices(self)
        if has(.packages) {
            s.download = downloadParts.isEmpty ? [.init("Download")] : downloadParts
            if installFailed { s.download[s.download.count - 1].failed = true }
        }
        if has(.moved) { s.problem = .init(line: "Build the app again from its folder.") }
        else if let node = fix(.node) { s.problem = .init(line: "Node is needed.", button: "Install Node", intent: .open(node)) }
        else if micState == .done, let chrome = fix(.chrome) { s.problem = .init(line: "Chrome is needed.", button: "Get Chrome", intent: .open(chrome)) }
        return s
    }
}
