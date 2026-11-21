import Ears
import Foundation
import Observation
import VoiceCore

// What the call window shows, with no screen in it. The turn-taking (mute, typing, the voice, the spoken yes) is Ears' Turns;
// the status of the call server (workers, open asks) is VoiceCore's CallStatus; the words for Claude Code's steps are
// VoiceCore's plainWords. This joins them for the window (design/spec.md): the word for the turn, the approvals, the banners,
// the work group, and the end of the call. Everything the window reads is a stored property that update() assigns only when
// it changed (Turns and Call are plain classes: they call update() whenever anything may have), as the spec's section 17 says.

/// The product's name: VoiceCore's Product, the one place it lives (build.sh reads it there too).
public let appName = Product.name

/// One open approval.
public struct Approval: Equatable {
    /// The card's one line on how to answer it now, as the page's showAsks() picks its hint (first match wins).
    public enum Hint: Equatable { case failed, next, click, armed, asking, again }
    public let ask: Ask
    /// A spoken yes may approve it; false until the server said.
    public let byVoice: Bool
    /// What exactly it is: a command whole; a file relative to its project.
    public let exact: String
    /// The question has finished and a spoken yes counts now (the oldest one only).
    public let busy: Bool, failed: Bool, expanded: Bool, armed: Bool
    /// "1 of 2" while more than one is open, else empty: the page's position chip.
    public let place: String
    public let hint: Hint
}

/// An approval answered on this call, kept in Talk where it happened: the page moves the answered card into its work log.
public struct Answered: Equatable {
    public let allow: Bool, byVoice: Bool
    public let exact: String
    /// It sits before Talk's line of this index (after the last when there is none).
    public let after: Int
}

/// A problem the call server reported, kept in the chat where it happened as the voice's bubble in red (system.css "Problems").
public struct Problem: Equatable {
    public let text: String
    /// It sits before Talk's line of this index (after the last when there is none).
    public let after: Int
}

/// Where the call is. Idle is only the stand-in for the menu-bar panel's Start Call, until this app has one.
public enum Stage: Equatable { case idle, starting, live, ending, ended, failed(Trouble) }

/// A call that did not start or stopped: the launcher's Failure values, plus the voice that did not load.
public struct Trouble: Equatable {
    public let title: String, line: String, button: String
    public init(_ f: Failure) { title = f.title; line = f.line; button = f.button }
    init(_ line: String) { title = "The call didn’t start"; self.line = line; button = "Try Again" }
    public static let voiceDidNotLoad = Trouble("The voice didn’t load.")
    public static let slowStart = Trouble("Nothing answered for 2 minutes.")
    public static let noPort = Trouble(.noPort), couldNotLaunch = Trouble(.couldNotLaunch), stoppedStarting = Trouble(.stoppedStarting)
    public static let stopped = Trouble(.stopped)
    /// As the launcher's panel says it: in this app's own words.
    public var failure: Failure { Failure(title: title, line: line, button: button) }
}

/// Why the ears are not listening on a live call.
public enum Deaf: Equatable { case recogniser, speechModel, device, microphone, noMicrophone }

public enum Mic: Equatable { case on, muted, dim, hidden }

/// The voice's state word in the call bar: exactly these (design/system.css, "Capsule words").
public enum Capsule: String, Equatable { case listening = "Listening", speaking = "Speaking", thinking = "Thinking", muted = "Muted",
    micBlocked = "Mic blocked", reconnecting = "Reconnecting", lost = "Call lost" }

/// One worker in the rail. The asking worker's card is the request itself; later requests wait as one line.
public struct Card: Equatable, Identifiable {
    public enum State: String, Equatable { case working = "Working", asking = "Asking", waiting = "Waiting", done = "Done" }
    public let name: String, state: State, sentence: String
    /// The request this card is, when it is asking.
    public let approval: Approval?
    /// Its Claude Code session, for Open in Claude; nil until the server has named one.
    public let session: String?
    public var id: String { name }
}

/// Everything the window can ask of the app beyond the model.
public enum Command: Equatable {
    case start, mute, end, close, again, listenAgain, installModel, openSettings, showLog
    case send(String)
    /// A setup step's fix (the panel's door before a call): a site, the packages, the sign-in, an update.
    case setup(DoorAction)
    /// A word on the start window's update line (Update, Try again, What's new, Move).
    case line(LineAction)
    var title: String { self == .openSettings ? "Open Settings" : self == .installModel ? "Download" : "Listen Again" }
}

/// A banner in the pinned zone.
public struct Note: Equatable {
    public enum Icon { case warning, gauge }
    public let text: String, icon: Icon?, action: Command?
    public var button: String? { action?.title }
}

@Observable public final class CallModel {
    public let turns: Turns
    public private(set) var status = CallStatus()
    public private(set) var project = ""
    public private(set) var projectPath = ""
    // what update() assigns
    public private(set) var word = ""
    public private(set) var sub = ""
    public private(set) var light = Light.ready
    public private(set) var mic = Mic.hidden
    public private(set) var ghost = ""
    public private(set) var lines: [Turns.Line] = []
    public private(set) var cards: [Approval] = []
    public private(set) var answered: [Answered] = []
    public private(set) var problems: [Problem] = []
    public private(set) var notes: [Note] = []
    public private(set) var confirmation: (id: String, allow: Bool)?
    public private(set) var steps: [String: String] = [:]
    public private(set) var voices: [VoiceGroup] = []
    public private(set) var voice = ""
    public private(set) var rail: [Card] = []
    public private(set) var capsule = Capsule.listening
    /// The voice's lines before you have said anything: the call's first line, drawn large until answered. nil once answered.
    public private(set) var greeting: String?
    /// The first call on this Mac, as the server remembers it (first-call.json, told in hello): it opens on "Say hello." instead of
    /// the usual line, and the first finished card carries a one-time hint, which the server is told was shown (POST /hinted).
    public private(set) var firstCall = false
    public private(set) var hintFor: String?
    @ObservationIgnored var hintable = false
    public static let sayHello = "Say hello.", hint = "Press a card to open its work in Claude."
    /// The line on the screen at the start of a call, until the first words. Shown only: the voice does not say it.
    public static let hi = "Hi. What shall we do?"
    /// Each worker's Claude Code session, from the server's "session" event.
    public private(set) var sessionOf: [String: String] = [:]
    // what the call sets
    public var stage = Stage.idle
    public var deaf: Deaf?
    public var since: Date?
    public var until: Date?
    /// End Call will hand the work to the Claude app; handedOver: it did. opened: the Open in Claude button's result.
    public var handing = false
    public var handedOver = false
    public var opened: Bool?
    public var stopFailed = false
    /// The stream to the call server dropped and is being tried again (the bar says Reconnecting).
    public var reconnecting = false
    /// The speech model is downloading (the Download button was pressed).
    public var downloading = false
    // view state
    public var text = ""
    public var typing = false
    public var visible = true
    public var expanded: Set<String> = []
    /// The one worker card pressed open; finished cards closed with Close.
    public var openCard: String?
    @ObservationIgnored var worked: Set<String> = []
    /// The voice's own words for a request ("Delete the old build files?"), by its id, from "<worker> wants to delete the old build files."
    @ObservationIgnored var spokenQuestion: [String: String] = [:]
    /// A finished worker's line as the voice said it ("The setup page is rewritten."), from "<worker> is done. …".
    @ObservationIgnored var doneLine: [String: String] = [:]
    /// The pinned zone has more than it shows: its bottom edge fades.
    public var pinnedFull = false
    public private(set) var hasWork = false
    @ObservationIgnored public var perform: (Command) -> Void = { _ in }
    /// The window comes forward without the keyboard; announce: VoiceOver says it.
    @ObservationIgnored public var front: () -> Void = {}
    @ObservationIgnored public var chose: (String) -> Void = { _ in } // the app's log: a voice picked from the menu
    @ObservationIgnored public var announce: (String) -> Void = { _ in }
    /// The voices the server offers, for Settings to list between calls.
    @ObservationIgnored public var sawVoices: ([String]) -> Void = { _ in }
    @ObservationIgnored let post: (String, [String: Any]) -> Void
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored var override: [String: Bool] = [:]
    @ObservationIgnored var answering: Set<String> = []
    @ObservationIgnored var answerFailed: Set<String> = []
    @ObservationIgnored var shown: [String: Date] = [:]
    @ObservationIgnored var confirmedAt = Date.distantPast
    @ObservationIgnored public private(set) var sessions: [String] = []

    public init(turns: Turns, post: @escaping (String, [String: Any]) -> Void, clock: @escaping () -> Date = Date.init) {
        self.turns = turns; self.post = post; self.clock = clock
    }

    // ── what the server says ──
    /// One line of the server's event stream, and the event it holds.
    public func apply(line: String, event e: [String: Any]) {
        let change = status.apply(line)
        switch e["type"] as? String {
        case "hello":
            projectPath = e["project"] as? String ?? ""; project = String(projectPath.split(separator: "/").last ?? "")
            firstCall = e["first"] as? Bool == true; hintable = e["hint"] as? Bool == true
            if let v = e["voices"] as? [String], !v.isEmpty { sawVoices(v) }
        case "voices": // Kokoro is ready: every voice it has (hello came before, usually with none)
            if let v = e["names"] as? [String], !v.isEmpty { sawVoices(v) }
        case "ask":
            if case .asked(let ask) = change {
                announce("Claude Code needs your answer. \(ask.question)")
                if !ask.voice { front() } // a click is needed: the window comes forward, a spoken yes never moves it
            }
        case "asked":
            if case .answered(let ask, let allow, let byVoice) = change {
                answered.append(Answered(allow: allow, byVoice: byVoice, exact: exact(ask), after: turns.lines.count))
                if byVoice {
                    confirmation = (ask.id, allow); confirmedAt = clock()
                    announce(allow ? "Approved by voice" : "Denied by voice")
                }
            }
            if let id = e["id"] as? String { override[id] = nil; answering.remove(id); answerFailed.remove(id) }
        case "say": // the voice asks the oldest open approval; its sentence says whether a spoken yes will do
            if let a = status.asks.first, let t = e["text"] as? String {
                if t.contains("needs a click on screen") { override[a.id] = false }
                else if t.contains("Should it go ahead?") { override[a.id] = true }
                if let q = Self.question(t, worker: a.worker) { spokenQuestion[a.id] = q }
            }
            if let t = e["text"] as? String, let (name, line) = Self.done(t) { doneLine[name] = line }
        case "error":
            if let t = status.error { problems.append(Problem(text: Self.firstPerson(t), after: turns.lines.count)) }
        case "board":
            if status.workers.contains(where: { $0.state != "idle" }) { hasWork = true } // the work group stays from here on
            worked.formIntersection(status.workers.map(\.name)) // closed (gone from the board): a fresh worker of that name starts with no card
            for w in status.workers where w.state != "idle" { worked.insert(w.name); doneLine[w.name] = nil }
            if let o = openCard, !status.workers.contains(where: { $0.name == o }) { openCard = nil }
        case "session": // sent at the start of every worker turn
            if let id = e["id"] as? String, !sessions.contains(id) { sessions.append(id) }
            if let id = e["id"] as? String, let w = e["worker"] as? String { sessionOf[w] = id }
        default: break
        }
        update()
    }

    // ── approvals ──
    func makeCards() -> [Approval] {
        let n = status.asks.count
        return status.asks.enumerated().map { i, ask in
            let byVoice = override[ask.id] ?? ask.voice, armed = i == 0 && byVoice && turns.armed(ask.id), failed = answerFailed.contains(ask.id)
            // only the oldest is asked aloud; override is set once the voice has said its sentence about it
            let hint: Approval.Hint = failed ? .failed : i > 0 ? .next : !byVoice ? .click : armed ? .armed
                : override[ask.id] != nil && turns.speaking ? .asking : .again
            return Approval(ask: ask, byVoice: byVoice, exact: exact(ask), busy: answering.contains(ask.id), failed: failed,
                            expanded: expanded.contains(ask.id), armed: armed, place: n > 1 ? "\(i + 1) of \(n)" : "", hint: hint)
        }
    }
    /// A command whole; a file relative to the folder of the project that asks.
    func exact(_ ask: Ask) -> String {
        guard !ask.detail.hasPrefix("Bash "), !projectPath.isEmpty else { return ask.full }
        let folder = ask.worker.replacingOccurrences(of: #" (two|three|four|five|six|seven|eight|nine|ten)$"#, with: "", options: .regularExpression)
        let parent = URL(fileURLWithPath: projectPath).deletingLastPathComponent().appending(path: folder).path
        return [projectPath, parent].map { $0 + "/" }.first(where: ask.full.hasPrefix).map { String(ask.full.dropFirst($0.count)) } ?? ask.full
    }
    /// POST /permit: the click on Approve or Deny. The answer comes back as the server's "asked"; a failed post is answerFailed.
    public func answer(_ id: String, allow: Bool) {
        guard !answering.contains(id) else { return }
        answering.insert(id); answerFailed.remove(id)
        post("/permit", ["id": id, "allow": allow]); update()
    }
    /// "web wants to push your commits. Shall it go ahead?" is asked as "Push your commits?" (the design's question).
    static func question(_ said: String, worker: String) -> String? {
        guard let r = said.range(of: "\(worker) wants to ") else { return nil }
        let rest = said[r.upperBound...].prefix { $0 != "." && $0 != "?" }
        guard let first = rest.first else { return nil }
        return first.uppercased() + rest.dropFirst() + "?"
    }
    /// "docs is done. The setup page is rewritten." gives docs its done line, which agrees with the word Done.
    static func done(_ said: String) -> (String, String)? {
        guard let r = said.range(of: #"^(\S+) is done\. "#, options: .regularExpression) else { return nil }
        let name = String(said[r].dropLast(" is done. ".count)), line = said[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : (name, line)
    }
    /// The server's "The voice could not answer …" is the voice's own bubble, in the first person (the design's words).
    static func firstPerson(_ problem: String) -> String {
        problem.hasPrefix("The voice could not answer") ? "I could not answer just then. Say it again in a moment." : problem
    }
    public func answerFailed(_ id: String) { answering.remove(id); answerFailed.insert(id); update() }
    public func expand(_ id: String) { expanded.insert(id); update() }

    // ── the rail ──
    /// Every worker that has worked on this call, in the board's order (a finished one until it is closed); the oldest open
    /// request is its worker's card, any later one a waiting line. A request from a worker the board has not named still shows.
    func makeRail(_ cards: [Approval]) -> [Card] {
        func card(_ name: String, _ w: Worker?) -> Card {
            let session = sessionOf[name]
            func question(_ a: Approval) -> String { spokenQuestion[a.ask.id] ?? a.ask.question }
            if let a = cards.first, a.ask.worker == name { return Card(name: name, state: .asking, sentence: question(a), approval: a, session: session) }
            if let a = cards.first(where: { $0.ask.worker == name }) { return Card(name: name, state: .waiting, sentence: question(a), approval: nil, session: session) }
            switch w?.state {
            case "idle"?: return Card(name: name, state: .done, sentence: doneLine[name] ?? w?.task ?? "", approval: nil, session: session)
            case "waiting"?: return Card(name: name, state: .waiting, sentence: "Waiting for an answer", approval: nil, session: session)
            default: return Card(name: name, state: .working, sentence: steps[name].flatMap { $0.isEmpty ? nil : $0 } ?? "Thinking", approval: nil, session: session)
            }
        }
        let names = status.workers.map(\.name)
        return status.workers.filter { w in worked.contains(w.name) || cards.contains { $0.ask.worker == w.name } }.map { card($0.name, $0) }
            + Array(Set(cards.map(\.ask.worker)).subtracting(names)).sorted().map { card($0, nil) }
    }
    /// Close on a finished card: it leaves the rail until its worker works again.
    /// Close on a finished card: the server ends that worker and its session; the card goes when the board no longer has it.
    public func close(_ name: String) { post("/close", ["name": name]) }

    /// The word in the call bar, first match wins.
    func capsuleWord() -> Capsule {
        if case .failed = stage { return .lost }
        if reconnecting { return .reconnecting }
        if deaf != nil { return .micBlocked }
        if turns.muted { return .muted }
        if turns.speaking { return .speaking }
        if stage == .starting || turns.thinking { return .thinking }
        return .listening
    }

    // ── the work ──
    /// Each worker's step in plain words, changed at most once every 0.6 s so fast steps do not flicker (the launcher's rule).
    func refreshSteps() {
        let now = clock()
        for w in status.workers {
            let words = w.state == "idle" ? "Ready when you are." : w.state == "waiting" ? "" : plainWords(w.step)?.doing ?? "Thinking"
            guard steps[w.name] != words else { continue }
            if steps[w.name] == nil || now.timeIntervalSince(shown[w.name] ?? .distantPast) >= 0.6 { steps[w.name] = words; shown[w.name] = now }
        }
    }
    /// POST /stop: every worker stops. A failed post shows the banner until the next Stop.
    public func stop() { stopFailed = false; post("/stop", [:]) }
    /// Stop on a worker's card: that worker only.
    public func stop(_ name: String) { stopFailed = false; post("/stop", ["name": name]) }
    /// Open in Claude on a worker's card: the server resumes its session in the Claude app, from its own folder, titled;
    /// a failure comes back as an error event (a red line in the chat).
    public func open(_ name: String) { post("/open", ["name": name]) }

    // ── the voice menu ──
    public static let voiceKey = "voice"
    /// The chosen voice is remembered, as the page keeps it in localStorage.
    public func choose(_ name: String, defaults: UserDefaults = .standard) { defaults.set(name, forKey: Self.voiceKey); chose(name); turns.choose(name); update() }
    /// The remembered voice, if any, for the start of a call.
    /// The voice before any is chosen: Fable, British male (the page's default too). A voice once chosen stays chosen.
    public static let defaultVoice = "bm_fable"
    public func remember(defaults: UserDefaults = .standard) { turns.voiceName = defaults.string(forKey: Self.voiceKey) ?? Self.defaultVoice }

    // ── the window ──
    /// The window's title: the project's folder name.
    public var title: String { project.isEmpty ? appName : project }
    /// The typing field's Return or its arrow: the words go in as yours (the page's typed.onsubmit).
    public func send() { let t = trim(text); text = ""; if !t.isEmpty { perform(.send(t)) } }

    /// The spec's table of the turn (section 5), first match wins.
    func headline() -> (word: String, sub: String) {
        switch stage {
        case .idle: return ("Ready", "")
        case .failed(let t): return (t.title, t.line)
        case .ended: return ("Call ended", sessions.isEmpty ? "" : opened == false ? "That didn’t open. Try again."
                             : handedOver || opened == true ? "Its work is open in the Claude app." : "Its work is saved in Claude Code.")
        case .ending: return ("Ending the call…", handing ? "Then its work opens in the Claude app." : "Claude Code is saving its work.")
        case .starting: return ("Connecting…", "The voice is warming up.")
        case .live: break
        }
        if deaf != nil { return ("Can’t hear you", deaf == .microphone ? "Typing still works." : "") }
        if turns.muted { return ("Mic off", "Press M to talk again. Typing works.") }
        if turns.paused { return ("Paused", "It stopped mid-word to hear you.") }
        if turns.speaking { return ("Speaking", "") }
        if turns.hearing { return ("Hearing you", "") }
        if turns.thinking { return ("Thinking", "") }
        if turns.waiting { return ("Listening", "Waiting for the rest of your thought.") }
        return ("Listening", turns.heardAny ? "" : "Just talk. It answers when you pause.")
    }

    /// The how-to line above the bar while the microphone is blocked: exactly what to do for this fault, Allow being the bar's button.
    public var micNote: String? {
        switch deaf {
        case .microphone?: "Turn the microphone on in System Settings › Privacy & Security, then press Allow."
        case .noMicrophone?: "No microphone found. Connect one, or choose one in System Settings › Sound › Input, then press Allow."
        case .device?: "The microphone changed. Press Allow to listen on the one in use now."
        case .recogniser?: "Speech recognition stopped. Press Allow to start it again."
        case .speechModel?: downloading ? "Downloading the speech model. Listening starts when it is done." : "Speech recognition needs a one-time download from Apple. Press Allow to get it."
        case nil: nil
        }
    }

    func makeNotes() -> [Note] {
        var out: [Note] = []
        if let e = status.error { out.append(Note(text: e, icon: .warning, action: nil)) }
        if !turns.limit.isEmpty { out.append(Note(text: turns.limit, icon: turns.limit.hasPrefix("You've hit") ? .warning : .gauge, action: nil)) }
        if stopFailed { out.append(Note(text: "Stop didn’t go through. Try again.", icon: .warning, action: nil)) }
        switch deaf {
        case .recogniser?: out.append(Note(text: "Speech recognition stopped.", icon: nil, action: .listenAgain))
        case .speechModel?: out.append(Note(text: downloading ? "Downloading the speech model…" : "Speech recognition needs a download.", icon: nil, action: downloading ? nil : .installModel))
        case .device?: out.append(Note(text: "The microphone changed.", icon: nil, action: .listenAgain))
        case .noMicrophone?: out.append(Note(text: "No microphone found.", icon: nil, action: .listenAgain))
        case .microphone?: out.append(Note(text: "\(appName) isn’t allowed to use the microphone.", icon: nil, action: .openSettings))
        case nil: break
        }
        return out
    }

    /// Copies what the window shows from Turns, the status and the call, assigning only what changed: this runs on every
    /// 20 ms tick and every recogniser result, and an Observation write re-renders even when the value is equal.
    public func update() {
        refreshSteps()
        func put<T: Equatable>(_ kp: ReferenceWritableKeyPath<CallModel, T>, _ v: T) { if self[keyPath: kp] != v { self[keyPath: kp] = v } }
        let live = stage == .live, (w, s) = headline()
        let lost = { if case .failed = stage { true } else { false } }()
        let notes = makeNotes()
        if live { for n in notes where !self.notes.contains(n) { announce(n.text) } }
        put(\.word, w); put(\.sub, s); put(\.ghost, live && turns.hearing ? turns.ghost : ""); put(\.lines, turns.lines)
        let cards = live ? makeCards() : []
        put(\.cards, cards); put(\.notes, live ? notes : [])
        put(\.rail, live || lost ? makeRail(cards) : []); put(\.capsule, capsuleWord())
        if hintable, hintFor == nil, let done = rail.first(where: { $0.state == .done }) { hintable = false; hintFor = done.name; post("/hinted", [:]) }
        put(\.greeting, (live || stage == .starting) && problems.isEmpty && turns.lines.isEmpty && !turns.hearing && turns.ghost.isEmpty ? (firstCall ? CallModel.sayHello : CallModel.hi) : nil)
        put(\.voices, voiceGroups(turns.voices)); put(\.voice, turns.voiceName)
        let phase: Phase = switch stage {
        case .idle, .ended: .idle
        case .starting: .starting
        case .live: .live
        case .ending: .ending
        case .failed: .failed(.stopped)
        }
        put(\.light, Light(phase: phase, status: status, cantHear: deaf != nil))
        put(\.mic, stage == .starting ? .dim : !live ? .hidden : deaf != nil ? .dim : turns.muted ? .muted : .on)
        let confirm = clock().timeIntervalSince(confirmedAt) < 0.8 ? confirmation : nil
        if confirm?.id != confirmation?.id { confirmation = confirm }
    }
}

public struct VoiceGroup: Equatable { public let title: String; public let voices: [(name: String, title: String)]
    public static func == (a: VoiceGroup, b: VoiceGroup) -> Bool { a.title == b.title && a.voices.map(\.name) == b.voices.map(\.name) } }

/// "af_heart" is Heart, in "US female": the page's VOICE_GROUPS.
public func voiceGroups(_ names: [String]) -> [VoiceGroup] {
    let groups = [("af_", "US female"), ("am_", "US male"), ("bf_", "British female"), ("bm_", "British male")]
    func group(_ n: String) -> String { groups.first { n.hasPrefix($0.0) }?.1 ?? "Other" }
    return (groups.map(\.1) + ["Other"]).compactMap { g in
        let mine = names.filter { group($0) == g }
        return mine.isEmpty ? nil : VoiceGroup(title: g, voices: mine.map { ($0, niceName($0)) })
    }
}
public func niceName(_ n: String) -> String { n.count > 3 ? n.dropFirst(3).prefix(1).uppercased() + n.dropFirst(4) : n }
