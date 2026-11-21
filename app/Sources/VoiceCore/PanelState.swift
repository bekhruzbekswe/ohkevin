import Foundation

// What the menu-bar panel and its item say, as plain data: three rows (head, pill, door) and one small shape.
// Nothing here draws or reaches into the app; the views take a `PanelData` and send `PanelIntent`s back (design/spec.md).
// A state the app cannot truly know is never built here.

/// What the pill's wave does: the voice listening, speaking, thinking; or still dots (muted, blocked); or dots lit in turn.
public enum WaveKind: Equatable, Sendable { case listening, speaking, thinking, dots, waiting }

/// The pill of a live call: Mute, the mark running into a wave, the voice's word, End call.
public struct CallPill: Equatable, Sendable {
    public var word: String
    public var wave: WaveKind
    /// Turned over (ink fill); Mute reads Unmute.
    public var muted: Bool
    /// Nothing is live (mic blocked, reconnecting): sunk, no shadow, Mute disabled.
    public var flat: Bool
    /// The word is red.
    public var wrong: Bool
    public var canMute: Bool
    /// The call is being closed: Mute and End call can do nothing more.
    public var ending = false
}

/// Before a call, the pill is the folder chooser.
public struct ProjectPill: Equatable, Sendable {
    public struct Choice: Equatable, Sendable {
        public var path: String; public var label: String; public var current: Bool
        public init(path: String, label: String, current: Bool) { self.path = path; self.label = label; self.current = current }
    }
    /// The folder's whole name (the view cuts it to the room it has); nil: no project yet.
    public var name: String?
    public var choices: [Choice]
    public var enabled: Bool
}

public enum DoorAction: Equatable, Sendable {
    case startCall, cancel, chooseProject, install, signIn, update, allowMicrophone, showCall
    /// The setup window: "Set up" and "Continue" in the panel.
    case openSetup
    case open(URL)
    /// Nothing to press (busy, or nothing the app can fix).
    case none
}

public enum DoorStyle: Equatable, Sendable {
    /// The one filled marigold button: Start call and the setup step.
    case primary
    /// Outlined, ink: nothing is waiting for you.
    case quiet
    /// Outlined in marigold: it is your move.
    case move
}

public enum PanelIntent: Equatable, Sendable {
    case door(DoorAction)
    case mute(Bool)
    case endCall
    case pick(String)
    case settings, showDetails, quit
    /// "Check for Updates…" in the corner menu (shown only when the app can update itself).
    case checkForUpdates
    /// The word on the update line.
    case line(LineAction)
}

/// Which small shape the menu-bar item takes. Its box is always the same size.
public enum MenuShape: Equatable, Sendable {
    /// The bare mark; `setup`: with a small ring while steps remain.
    case rest(setup: Bool)
    /// It broke, or it cannot hear.
    case lost(asking: Bool)
    case reconnecting(asking: Bool)
    /// A small pill with a little wave; `asking`: a marigold dot at its right end.
    case call(WaveKind, muted: Bool, asking: Bool)
}

public struct PanelData: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case plain
        /// The system's own line, in the serif.
        case ours
        /// Red serif italic.
        case wrong
        /// "We need you", with "you" in marigold.
        case ask
    }
    public enum Sub: Equatable, Sendable {
        case text(String)
        /// Minutes and seconds counting up from `since`.
        case timer(since: Date)
    }
    public enum Pill: Equatable, Sendable { case project(ProjectPill), call(CallPill) }
    public struct Door: Equatable, Sendable {
        public var label: String
        public var style: DoorStyle
        public var action: DoorAction
        /// Nothing to press: busy, or nothing the app can fix.
        public var enabled: Bool { action != .none }
    }

    public var line1: String
    public var style: Style
    public var line2: Sub
    public var pill: Pill
    public var door: Door
    public var shape: MenuShape
    /// The corner menu: "Show Details" only after a failure; Quit says what it does to a call.
    public var failed: Bool
    public var onCall: Bool
    /// The app can update itself: the corner menu offers "Check for Updates…". The host sets it; it is false by default.
    public var canUpdate = false
    /// The update line under the last button; nil when there is nothing to say. The host sets it (see `updateLine`).
    public var line: PanelLine?
}

/// Everything the panel is built from. The app fills it; tests make it up.
public struct PanelInput: Sendable {
    public var phase: Phase = .idle
    public var status = CallStatus()
    /// What a call still needs; nil until the first check has finished.
    public var missing: [Missing]?
    public var project: URL?
    public var recents: [URL] = []
    public var installing = false, installFailed = false, signingIn = false, updatingClaude = false, updateFailed = false
    /// Starting, and the call server has answered: the voice is warming up (the window says so too).
    public var connecting = false
    /// The app lost its feed from the call server while the call is live.
    public var feedLost = false
    public var liveSince: Date?
    public var handingOver = false
    /// The update line, made by the host.
    public var line: PanelLine?
    /// The setup screen's Microphone row, as the host knows it, and the download's parts.
    public var micState = SetupInput.Mic.todo
    public var downloadParts: [SetupInput.Part] = []

    public init() {}
}

extension PanelData {
    public init(_ i: PanelInput) {
        let project = ProjectPill(name: i.project?.lastPathComponent, choices: choices(i), enabled: true)
        func idle(_ l1: String, _ style: Style, _ l2: String, _ door: Door, _ shape: MenuShape = .rest(setup: false), enabled: Bool = true) -> PanelData {
            var p = project; p.enabled = enabled
            return PanelData(line1: l1, style: style, line2: .text(l2), pill: .project(p), door: door, shape: shape, failed: false, onCall: false)
        }
        switch i.phase {
        case .starting:
            self = i.connecting ? idle("Connecting…", .ours, "The voice is warming up.", Door(label: "Cancel", style: .quiet, action: .cancel))
                : idle("Starting the call.", .ours, "This takes a few seconds.", Door(label: "Cancel", style: .quiet, action: .cancel))
        case .ending:
            // The pill stays a call pill, flat and still, until the server is gone; the door says nothing the head did.
            self = PanelData(line1: "Ending the call.", style: .ours, line2: .text(i.handingOver ? "Then its work opens in the Claude app." : "Claude Code is saving its work."),
                             pill: .call(CallPill(word: "", wave: .dots, muted: false, flat: true, wrong: false, canMute: false, ending: true)),
                             door: Door(label: "One moment", style: .quiet, action: .none), shape: .call(.dots, muted: false, asking: false), failed: false, onCall: true)
        case .ended(let e):
            self = idle("Call ended.", .ours, e.line ?? "Ready for the next one.", Door(label: "Start call", style: .primary, action: .startCall))
        case .failed(let f):
            var d = idle(f == .stopped ? "Call lost" : f.title, .wrong, f == .stopped ? "The connection dropped." : f.line, Door(label: f == .stopped ? "Call again" : "Try again", style: .primary, action: .startCall), .lost(asking: false))
            d.failed = true
            self = d
        case .idle where i.missing == nil && i.project == nil: // the very first look: the steps are not known yet, so none is counted
            self = idle("Looking at this Mac.", .ours, "This takes a moment.", Door(label: "One moment", style: .quiet, action: .none), enabled: false)
        case .idle:
            let screen = SetupScreen(i.setup), left = screen.left
            if left > 0 { // the three rows only; the download is never a step
                let none = left == 3
                self = idle(none ? Product.name : "\(left) \(left == 1 ? "thing" : "things") to go", none ? .ours : .plain, none ? "Three things, then a call." : screen.next,
                            Door(label: none ? "Set up" : "Continue", style: .primary, action: .openSetup), .rest(setup: true), enabled: false)
            } else if let first = blockers(i).first {
                self = idle("1 step to go", .plain, first.busyLine ?? "Then you can call.", first.door, .rest(setup: true))
            } else if i.missing?.contains(where: { $0.id == .packages }) == true { // the rows are done and the download is not
                let door = i.installFailed ? Door(label: "Try again", style: .primary, action: .install) : Door(label: "One moment", style: .quiet, action: .none)
                self = idle(Product.name, .ours, i.installFailed ? "The download didn’t finish." : "Downloading, hold on a second…", door, .rest(setup: true))
            } else {
                self = idle("\(Product.name)", .ours, "A voice call with Claude Code.", Door(label: "Start call", style: .primary, action: .startCall))
            }
        case .live:
            self = Self.call(i)
        }
        line = i.line
    }

    private static func call(_ i: PanelInput) -> PanelData {
        let s = i.status, asking = !s.asks.isEmpty
        var line1 = asking ? "We need you" : "On a call", line2 = Sub.timer(since: i.liveSince ?? Date())
        var door = Door(label: "Show the call", style: asking ? .move : .quiet, action: .showCall)
        let pill: CallPill, shape: MenuShape
        if !s.mic.isEmpty { // it cannot hear: the door is the fix; a request still gets its words and its dot
            pill = CallPill(word: "Mic blocked", wave: .dots, muted: false, flat: true, wrong: true, canMute: false)
            line2 = .text("Claude Code can’t hear you.")
            door = Door(label: "Allow microphone", style: .move, action: .allowMicrophone)
            shape = .lost(asking: asking)
        } else if i.feedLost {
            pill = CallPill(word: "Reconnecting", wave: .waiting, muted: false, flat: true, wrong: false, canMute: false)
            line2 = .text("The call dropped. Trying again.")
            shape = .reconnecting(asking: asking)
        } else {
            // Until the page has reported a voice state the pill claims none: still dots, no word.
            let (word, wave): (String, WaveKind) = switch s.voice {
            case "listening": ("Listening", .listening)
            case "speaking": ("Speaking", .speaking)
            case "thinking": ("Thinking", .thinking)
            case "muted": ("Muted", .dots)
            default: ("", .dots)
            }
            let muted = s.voice == "muted"
            pill = CallPill(word: word, wave: wave, muted: muted, flat: false, wrong: false, canMute: s.canMute && !s.voice.isEmpty)
            shape = .call(wave, muted: muted, asking: asking)
            if asking { door.label = "Answer in the call" }
        }
        return PanelData(line1: line1, style: asking ? .ask : .plain, line2: line2, pill: .call(pill), door: door, shape: shape, failed: false, onCall: true)
    }
}

// MARK: - Setup: what no row covers (the rows are SetupScreen's)

private struct Step {
    var door: PanelData.Door
    /// What the second line says while this step is under way.
    var busyLine: String?
}

/// Node to get, for a developer's own call folder (the app's own copy fetches its Node).
private func blockers(_ i: PanelInput) -> [Step] {
    (i.missing ?? []).compactMap { m in
        guard m.id == .node, case .open(_, let url)? = m.fix else { return nil }
        return Step(door: .init(label: "Install Node", style: .primary, action: .open(url)))
    }
}

func choices(_ i: PanelInput) -> [ProjectPill.Choice] {
    i.recents.map { url in
        let twins = i.recents.filter { $0.lastPathComponent == url.lastPathComponent }.count > 1
        return .init(path: url.path, label: twins ? "\(url.lastPathComponent) — \(url.deletingLastPathComponent().lastPathComponent)" : url.lastPathComponent, current: url == i.project)
    }
}

// MARK: - Names: a cut never lands inside a word

/// Cuts a name to `n` characters in the middle, at its separators ("-", "_", ".", "/", space): the start and the last part stay whole,
/// whole parts only: "storefront-checkout-redesign-2026" becomes "storefront…2026". When the last part is too long, or the name has no
/// separator, both ends are kept as they are ("supercalif…cious"): the design's own rule.
public func middleCut(_ s: String, _ n: Int) -> String {
    guard s.count > n else { return s }
    var parts: [String] = [], word = ""
    for c in s { word.append(c); if "-_./ ".contains(c) { parts.append(word); word = "" } }
    if !word.isEmpty { parts.append(word) }
    let tail = parts.last ?? ""
    if parts.count < 2 || tail.count > n - 4 { return String(s.prefix(n - 6)) + "…" + String(s.suffix(5)) }
    let room = n - tail.count - 1
    var head = ""
    for p in parts.dropLast() { if head.count + p.count > room { break }; head += p }
    while let last = head.last, "-_./ ".contains(last) { head.removeLast() }
    return (head.isEmpty ? String(s.prefix(room)) : head) + "…" + tail
}
