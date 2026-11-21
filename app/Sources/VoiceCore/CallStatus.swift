import Foundation

/// One Claude Code session on the call, as the server's board has it.
public struct Worker: Equatable, Sendable, Identifiable {
    public var name: String
    /// idle, working or waiting
    public var state: String
    public var task: String
    public var step: String
    public var model: String
    public var id: String { name }
}

/// A step Claude Code asks about, kept whole from the `ask` event.
public struct Ask: Equatable, Sendable, Identifiable {
    public let id: String
    /// "Tool argument", without the "worker: " prefix the server adds when there are several workers.
    public let detail: String
    public let worker: String
    /// A spoken yes may approve it.
    public let voice: Bool
    /// The whole command or path.
    public let full: String

    public var question: String { plainWords(detail)?.asking ?? "Allow this step?" }
}

/// Something the app acts on, beyond showing the new state.
public enum Change: Equatable, Sendable {
    case connected
    case asked(Ask)
    case answered(Ask, allow: Bool, byVoice: Bool)
    case hangup
}

/// What the call server says about the call, read from its own event stream (the one the call page reads).
public struct CallStatus: Equatable, Sendable {
    /// The server has answered: it is up and the call is live.
    public var live = false
    public var workers: [Worker] = []
    /// Open requests, oldest first. The server sends them again on every connection, right after `hello`, so they are
    /// cleared there; `seen` keeps every id of the call, so a request is news only once.
    public var asks: [Ask] = []
    public var seen: Set<String> = []
    /// Workers that have a Claude Code session, so there is work to hand to the Claude app.
    public var sessions: Set<String> = []
    /// Call pages open.
    public var pages = 0
    /// The latest problem the server reported, until the conversation moves on.
    public var error: String?
    /// Why the call cannot use the microphone: "mac" (macOS keeps it from the app), or empty.
    public var mic = ""
    /// What the voice is doing, as the server relays it from the call page: listening, speaking, thinking or muted.
    /// Empty until the server has said.
    public var voice = ""
    /// The page reports its mute state, so it acts on a mute request.
    public var canMute = false

    public init() {}

    public var working: Bool { workers.contains { $0.state != "idle" } || !asks.isEmpty }

    /// Takes one line of the event stream; anything that is not an event it knows is ignored.
    @discardableResult
    public mutating func apply(_ line: String) -> Change? {
        guard line.hasPrefix("data:"),
              let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any],
              let type = event["type"] as? String
        else { return nil }
        let text = { (key: String) in event[key] as? String ?? "" }
        switch type {
        case "hello":
            live = true
            asks = [] // the open requests follow, again
            return .connected
        case "board":
            workers = (event["workers"] as? [[String: Any]] ?? []).map { w in
                let s = { (key: String) in w[key] as? String ?? "" }
                return Worker(name: s("name"), state: s("state").isEmpty ? "idle" : s("state"), task: s("task"), step: s("step"), model: s("model"))
            }
        case "ask":
            let worker = text("worker"), detail = text("detail")
            let prefix = "\(worker): "
            let ask = Ask(id: text("id"), detail: detail.hasPrefix(prefix) ? String(detail.dropFirst(prefix.count)) : detail,
                          worker: worker, voice: event["voice"] as? Bool ?? false, full: text("full").isEmpty ? detail : text("full"))
            guard !asks.contains(where: { $0.id == ask.id }) else { return nil }
            asks.append(ask)
            return seen.insert(ask.id).inserted ? .asked(ask) : nil
        case "asked":
            guard let i = asks.firstIndex(where: { $0.id == text("id") }) else { return nil }
            let ask = asks.remove(at: i)
            return .answered(ask, allow: event["allow"] as? Bool ?? false, byVoice: text("by") == "voice")
        case "session": sessions.insert(text("worker"))
        case "pages": pages = event["n"] as? Int ?? 0
        case "mic": mic = text("blocked")
        case "voice": voice = text("state"); canMute = event["canMute"] as? Bool ?? false
        case "error": error = text("text").replacingOccurrences(of: #" \(error \d+\)"#, with: "", options: .regularExpression)
        case "turn_end": error = nil
        case "hangup": return .hangup
        default: break
        }
        return nil
    }
}

/// Where the app is with its call.
public enum Phase: Equatable, Sendable {
    case idle, starting, live, ending
    case ended(Ended)
    case failed(Failure)
}

/// A call that just ended: shown until the panel closes.
public struct Ended: Equatable, Sendable {
    public let length: TimeInterval
    public let line: String?
    public init(length: TimeInterval, line: String?) { self.length = length; self.line = line }
}

/// A failure, said the way the user needs it.
public struct Failure: Equatable, Sendable {
    public let title: String
    public let line: String
    public let button: String
    /// Another client's own failures, in their real words.
    public init(title: String, line: String, button: String) { self.title = title; self.line = line; self.button = button }
    public static let slowStart = Failure(title: "The call didn’t start", line: "Nothing answered for 30 seconds.", button: "Try Again")
    /// Node could not be launched at all; the log has the system's own words.
    public static let couldNotLaunch = Failure(title: "The call didn’t start", line: "Node couldn’t be started on this Mac.", button: "Try Again")
    public static let noPort = Failure(title: "The call didn’t start", line: "Every port from 4747 to 4757 is in use.", button: "Try Again")
    /// It stopped before it answered: no work existed yet.
    public static let stoppedStarting = Failure(title: "The call didn’t start", line: "Something went wrong as it started.", button: "Try Again")
    public static let stopped = Failure(title: "The call stopped", line: "Claude Code’s work so far is saved.", button: "Call Again")
}

/// The one word for where things stand: the menu-bar mark and the panel's header follow it.
public enum Light: Equatable, Sendable {
    case ready, starting, onCall, working, needsAnswer, cantHear, ending, failed

    /// cantHear: the call is live and no call page has been connected for a while.
    public init(phase: Phase, status: CallStatus, cantHear: Bool = false) {
        switch phase {
        case .idle, .ended: self = .ready
        case .starting: self = .starting
        case .ending: self = .ending
        case .failed: self = .failed
        case .live:
            self = !status.asks.isEmpty ? .needsAnswer : cantHear ? .cantHear : status.working ? .working : .onCall
        }
    }
}


/// The header timer: "0:42", "12:04", "1:02:03".
public func timer(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
