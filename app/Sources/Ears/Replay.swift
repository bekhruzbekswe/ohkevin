import Foundation

/// Runs the ported turn-taking on a recorded call (a log written by measure/hook.js or by the app) in virtual time:
/// the recogniser's results, the server's events, the levels the gate read and the voice's clips come in when they came
/// in then, and everything Turns posts is collected. Same stream in, so the posts should be the ones in the log.
public final class Replay: Host {
    public private(set) var posts: [(t: Double, path: String, body: [String: Any])] = []
    public private(set) var logs: [(t: Double, line: String)] = []
    var clock = 0.0, seq = 0, queue: [(t: Double, n: Int, fn: () -> Void)] = []
    var clips: [(t: Double, text: String, dur: Double?, used: Bool)] = []
    struct Sentence: Clip { let duration: Double }

    public init() {}
    public lazy var turns = Turns(host: self)

    /// One log line per JSON object; `t` is epoch milliseconds.
    public func run(_ events: [[String: Any]]) {
        for e in events where e["k"] as? String == "tts" {
            clips.append((e["t"] as! Double, e["text"] as! String, e["dur"] as? Double, false))
        }
        for e in events {
            let t = e["t"] as! Double
            switch e["k"] as? String {
            case "mic": at(t) { self.turns.start(echoCancelled: true) }
            case "result":
                let r = (e["r"] as! [[Any]]).map { Heard($0[0] as! String, $0[1] as! Bool) }
                at(t) { self.turns.results(r, from: e["i"] as! Int) }
            case "end": at(t) { self.turns.recEnded() }
            case "hangup": at(t) { if self.turns.live { self.turns.end() } } // End call
            case "mute": let on = e["on"] as! Bool; at(t) { self.turns.setMuted(on) }
            case "voice": let name = e["name"] as? String; at(t) { self.turns.choose(name ?? self.turns.voiceName) } // the voice menu (a log from before it was recorded: measure.mjs derives the event)
            case "type": let text = e["text"] as! String; at(t) { self.turns.type(text) }
            case "sse": at(t) { self.turns.server(e["e"] as! [String: Any]) }
            case "level": at(t) { self.turns.level(e["db"] as! Double) }
            default: break
            }
        }
        let end = events.compactMap { $0["t"] as? Double }.max() ?? 0 // the recording stops here, and so does the replay
        while !queue.isEmpty {
            let i = queue.indices.min { (queue[$0].t, queue[$0].n) < (queue[$1].t, queue[$1].n) }!
            let next = queue.remove(at: i)
            if next.t > end { break }
            clock = max(clock, next.t); next.fn()
        }
    }
    func at(_ t: Double, _ fn: @escaping () -> Void) { seq += 1; queue.append((t, seq, fn)) }

    // Host
    public func now() -> Double { clock }
    public func after(_ ms: Double, _ fn: @escaping () -> Void) -> Cancel {
        var live = true
        at(clock + ms) { if live { fn() } }
        return Cancel { live = false }
    }
    public func post(_ path: String, _ body: [String: Any]) { posts.append((clock, path, body)) }
    public func fetch(_ text: String, voice: String, _ done: @escaping (Clip?) -> Void) {
        // The clip the recorded call got for this sentence, when it got it; one the recording never asked for fails.
        if let i = clips.firstIndex(where: { !$0.used && $0.text == text }) {
            clips[i].used = true
            let c = clips[i]
            at(max(clock, c.t)) { done(c.dur.map(Sentence.init)) }
        } else { at(clock) { done(nil) } }
    }
    // The voice: a clip ends after its duration, not counting time spent suspended.
    var playingClip: Clip?, ended: (() -> Void)?, startedAt = 0.0, before = 0.0, suspended = false, end: Cancel?
    public func play(_ clip: Clip, _ ended: @escaping () -> Void) {
        playingClip = clip; self.ended = ended; before = 0; startedAt = clock
        if !suspended { schedule() }
    }
    func schedule() { guard let c = playingClip else { return }; end = after((c.duration - before) * 1000) { self.finish() } }
    func finish() { let e = ended; playingClip = nil; ended = nil; end = nil; e?() }
    public func stop() { guard playingClip != nil else { return }; end?.cancel(); before = played(); let e = ended; playingClip = nil; ended = nil; at(clock) { e?() } }
    public func suspend() { guard !suspended else { return }; if playingClip != nil { before = played(); end?.cancel() }; suspended = true }
    public func resume() { guard suspended else { return }; suspended = false; if playingClip != nil { startedAt = clock; schedule() } }
    public func played() -> Double { playingClip == nil ? before : before + (suspended ? 0 : (clock - startedAt) / 1000) }
    public func tone() {}
    public func log(_ line: String) { logs.append((clock, line)) }
    public func changed() {}
}
