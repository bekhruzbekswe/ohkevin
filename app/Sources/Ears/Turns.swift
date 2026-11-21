import Foundation

// The page's ears and turn-taking (call/voice.mjs createCall: say, began, ended, heardSoFar, hush, heard, said, aside,
// waitMore, armAsk, watchLevel, hold, release, rec.onresult, rec.onend and server's say, wait, turn_end and asked), ported one
// for one with the same names. The window's side of it (the rows, retract, the usage-limit line) is call/index.html's: its
// call.on('heard') handler, row and on.say. What is left out is only the page's look and its fallbacks: the browser voice,
// the speakers and headphones path for ears without echo cancellation, and the stats panel. Mute, typing, choosing the voice,
// the usage-limit line and what a spoken yes needs from an answered approval are here; the approval cards and the work view
// are CallKit's. Everything runs on one queue.

/// One recognised result, as the Web Speech API gives it: the words so far, and whether they are final.
public struct Heard { public var text: String; public var isFinal: Bool
    public init(_ text: String, _ isFinal: Bool) { self.text = text; self.isFinal = isFinal } }

/// A sentence of the voice, ready to play.
public protocol Clip { var duration: Double { get } }

public final class Cancel { let fn: () -> Void; public init(_ fn: @escaping () -> Void) { self.fn = fn }; public func cancel() { fn() } }

/// What the turn-taking needs from the world: a clock, timers, the server, the voice. The app and the replay give it.
public protocol Host: AnyObject {
    func now() -> Double                                            // ms (performance.now())
    func after(_ ms: Double, _ fn: @escaping () -> Void) -> Cancel  // setTimeout
    func post(_ path: String, _ body: [String: Any])                 // in order: a /say never overtakes a /hush (hushed.then)
    func fetch(_ text: String, voice: String, _ done: @escaping (Clip?) -> Void) // GET /tts
    func play(_ clip: Clip, _ ended: @escaping () -> Void)          // start it now; ended runs once, also after stop()
    func stop()                                                      // current?.stop()
    func suspend()                                                   // audio.suspend(): the voice freezes mid-word
    func resume()
    func played() -> Double                                          // seconds of the playing clip heard so far
    func tone()                                                      // tone(700, 70): your words went
    func log(_ line: String)                                         // console.info
    func changed()                                                   // refresh()
}

public final class Turns {
    unowned let host: Host // the host owns its Turns
    public init(host: Host) { self.host = host }
    var now: Double { host.now() }

    public private(set) var live = false, muted = false, speaking = false, hearing = false, thinking = false
    var track = false
    public private(set) var voices: [String] = []
    public var voiceName = "af_heart"
    var aired: [String] = [], playing: Double? = nil, overVoice: [Bool?] = []
    var askNext = "", askHeard = "", askHeardAt = 0.0, utterAt = 0.0, utterOver = false
    let ASK_GUARD_MS = 300.0, ASK_FOR_MS = 20000.0
    var pending = "", pendingAt = 0.0, turnState = "", joining = false, waitTimer: Cancel? = nil, nudged = false, stray = "", strayAt = 0.0
    var gate: Gate? = nil, held: Cancel? = nil
    var epoch = 0, queued = 0, items: [Item] = [], busy = false
    var told = ["you": false, "voice": false]
    // starts: the first sentence of an answer (no sentence of its turn before it); limit: a usage-limit line said on its own.
    // Both are known when the server says it, as the page knows them in on.say; the row is added when it plays (began).
    final class Item { let text: String, mine: Int, starts: Bool, limit: Bool; var clip: Clip?, fetched = false
        init(_ text: String, _ mine: Int, starts: Bool, limit: Bool) { self.text = text; self.mine = mine; self.starts = starts; self.limit = limit } }

    // What the window shows. unsaid: the end of a voice line that was never heard (cut off, or held mid-word).
    public struct Line: Equatable { public let who: String; public var text: String; public var unsaid = ""
        public init(who: String, text: String, unsaid: String = "") { self.who = who; self.text = text; self.unsaid = unsaid } }
    public private(set) var lines: [Line] = []
    public private(set) var ghost = "", limit = "" // limit: the voice's own usage-limit sentence, kept out of the lines
    public private(set) var heardAny = false       // you have said something on this call
    public var paused: Bool { held != nil }        // the voice is held mid-word
    public var waiting: Bool { turnState == "waiting" }
    var voiceOpen = false // the last line is the voice's, open to its next sentence (the page's voiceBubble)
    var limitOpen = false // this turn began with a usage-limit line: the server's next lines (it may send two) belong to it, as to the page's limit bubble
    var turnOpen = false  // the server has said something this turn and not yet turn_end (what voiceBubble is when the event arrives)
    func refresh() { host.changed() }
    func row(_ who: String, _ text: String, newBubble: Bool = false, unsaid: String = "") {
        if who == "voice" && voiceOpen && !newBubble, let last = lines.indices.last { lines[last].text += " " + text; return }
        lines.append(Line(who: who, text: text, unsaid: unsaid)); voiceOpen = who == "voice" && unsaid.isEmpty
    }
    /// The end of the sentence playing that has not been heard yet, by the player's clock ("" when none is playing).
    func unheard() -> String {
        guard let dur = playing, let s = aired.last else { return "" }
        return words(trim(s)).dropFirst(words(cutText(s, host.played() / dur)).count).joined(separator: " ")
    }
    func markUnsaid(_ on: Bool) {
        guard let i = lines.indices.last, lines[i].who == "voice" else { return }
        let rest = on ? unheard() : ""
        lines[i].unsaid = lines[i].text.hasSuffix(rest) ? rest : ""
    }

    // The call button. The recogniser itself is the app's: these are only the page's own steps around it.
    public func start(echoCancelled: Bool) { live = true; muted = false; track = echoCancelled; gate = Gate(); overVoice = []; refresh() }
    public func end() {
        live = false; muted = false; hush()
        if let h = held { h.cancel(); held = nil; host.resume(); mark("you", false) } // stopEars()
        gate = nil; hearing = false; thinking = false; refresh() // thinking: nothing is thought about once it is over
    }
    /// The mute click and setMuted: only the microphone goes off (recognition stops, the ears are released); the voice and the
    /// work carry on. Unmuting opens the ears again, with a fresh gate. The app stops and restarts its recogniser itself.
    public func setMuted(_ on: Bool) {
        guard live, on != muted else { return }
        muted = on
        if on { // rec.abort(); stopEars()
            if let h = held { h.cancel(); held = nil; host.resume(); mark("you", false) }
            gate = nil; hearing = false; mark("you", false); ghost = ""
        } else { gate = Gate() } // listen()
        overVoice = []
        refresh()
    }
    /// The typing box: what you type goes as your turn, after cutting off the voice.
    public func type(_ words: String) { let t = trim(words); if !t.isEmpty { hush(); turnState = ""; heard(t) } }
    /// The voice menu: the chosen voice says so at once. (Remembering it is the app's: the page keeps it in localStorage.)
    public func choose(_ name: String) { voiceName = name; hush(); say("This is how I sound now.") }
    /// Whether a spoken yes would answer this approval now (the page's "armed").
    public func armed(_ id: String) -> Bool { askHeard == id && !speaking && now - askHeardAt < ASK_FOR_MS }

    func mark(_ lane: String, _ on: Bool) { if told[lane] != on { told[lane] = on; host.post("/live", [lane: on]) } }

    // ── mouth ────────────────────────────────────────────────────────────────
    func began(_ text: String, _ dur: Double, starts: Bool = false, limit: Bool = false) {
        askHeard = ""
        if turnState == "sent" || turnState == "waiting" { turnState = "answering"; pendingAt = now }
        if !speaking { aired = []; gate?.quiet(now, TUNE.guardMs) } // a new spell of talking
        aired.append(text); playing = dur
        speaking = true; thinking = false; mark("voice", true); refresh()
        if !limit { row("voice", text, newBubble: starts) } // each sentence joins its answer's line as it starts to play
    }
    func ended() {
        _ = host.after(250) { [self] in
            if queued > 0 { return }
            speaking = false; mark("voice", false); refresh()
            if !askNext.isEmpty { askHeard = askNext; askHeardAt = now; askNext = "" }
        }
    }
    public func say(_ text: String, starts: Bool = false, limit: Bool = false) {
        guard voices.contains(voiceName) else { host.log("[mouth] no local voice: not said"); return } // the page would use the browser voice
        let item = Item(text, epoch, starts: starts, limit: limit) // asked for now, so it is ready by the time the sentence before it has played
        host.fetch(text, voice: voiceName) { [self] clip in item.clip = clip; item.fetched = true; pump() }
        queued += 1; items.append(item); pump()
    }
    func pump() { // the page's chain: one sentence after another, each once its audio is in
        guard !busy, let it = items.first, it.fetched else { return }
        busy = true
        let t = now // the answer to your last words does not start while you are still adding to them
        func go() {
            if hearing && joining && turnState == "sent" && it.mine == epoch && now - t < TUNE.joinMs { _ = host.after(50, go); return }
            if now - t > 100 { host.log("[turn] answer held \(String(format: "%.1f", (now - t) / 1000)) s while you were still talking") }
            func done() { items.removeFirst(); busy = false; queued -= 1; ended(); pump() }
            if it.mine == epoch, let clip = it.clip { began(it.text, clip.duration, starts: it.starts, limit: it.limit); host.play(clip) { [self] in playing = nil; done() } }
            else {
                if it.mine == epoch { // no audio (the page would use the browser voice): the words show, faint, as never heard
                    host.log("[mouth] no audio for a sentence")
                    if !it.limit { row("voice", it.text, newBubble: true, unsaid: it.text); refresh() }
                }
                done()
            }
        }
        go()
    }
    /// What the developer has heard of the current spell of talking: whole sentences, plus the played share of the last.
    func heardSoFar() -> String {
        guard let dur = playing else { return aired.joined(separator: " ") }
        let part = cutText(aired.last ?? "", host.played() / dur)
        return (aired.dropLast() + [part]).filter { !$0.isEmpty }.joined(separator: " ")
    }
    public func hush(_ cutOff: Bool? = nil) { // cut: something was still to be said, so tell the talker what was heard
        let cut = cutOff ?? (speaking || queued > 0)
        askNext = ""
        let heard = speaking ? heardSoFar() : ""
        if cut && speaking { markUnsaid(true); voiceOpen = false } // what you never heard stays faint; its next words are a new line
        epoch += 1
        host.stop()
        if let h = held { h.cancel(); held = nil; host.resume(); mark("you", false) }
        host.post("/hush", cut ? ["heard": heard] : [:])
        speaking = false; mark("voice", false); refresh()
    }

    // ── ears ─────────────────────────────────────────────────────────────────
    func heard(_ text: String, ask: String = "") {
        ghost = ""; row("you", text); heardAny = true; host.tone()
        thinking = true; refresh()
        host.post("/say", ask.isEmpty ? ["text": text] : ["text": text, "ask": ask])
    }
    let JOINED = ["sent": "before its answer started", "waiting": "while the voice waited"]
    func said(_ words: String) {
        var text = words
        let echo = !stray.isEmpty && now - strayAt < TUNE.joinMs // a lone word heard over the voice goes in front of these
        if echo { text = "\(stray) \(text)" }
        stray = ""
        let both = joining ? joinTurn(pending, text) : ""
        if !both.isEmpty && turnState == "sent" { hush(true) } // its answer has not played: drop it
        if !both.isEmpty && turnState != "answering" { retract() } // one thought, one bubble
        host.log("[turn] \(both.isEmpty ? "usual" : "joined \(JOINED[turnState] ?? "undefined")")")
        let since = utterAt - askHeardAt
        let fresh = !echo && both.isEmpty && !utterOver && since >= ASK_GUARD_MS && since < ASK_FOR_MS
        heard(both.isEmpty ? text : both, ask: fresh ? askHeard : "")
        pending = both.isEmpty ? text : both; pendingAt = now; turnState = "sent"; joining = false; nudged = false
    }
    func aside(_ word: String) { stray = word; strayAt = now }
    func retract() {
        guard let mine = lines.lastIndex(where: { $0.who == "you" }) else { return }
        lines.removeSubrange(mine...); voiceOpen = false
    }
    func waitMore() {
        waitTimer?.cancel()
        waitTimer = host.after(TUNE.waitMs) { [self] in
            if turnState != "waiting" { return }
            if hearing { return waitMore() } // you are still talking: your words will come
            host.log("[turn] nothing more came: it answers what it has")
            turnState = "sent"; pendingAt = now; thinking = true; nudged = true; refresh()
            host.post("/say", ["text": pending, "done": true])
        }
    }
    func armAsk(_ id: String) { if speaking || queued > 0 { askNext = id } else { askHeard = id; askHeardAt = now } }

    /// watchLevel(): the echo-cancelled microphone's level, every 20 ms. A sustained level pauses the voice at once.
    public func level(_ db: Double) {
        guard speaking, held == nil, voices.contains(voiceName), let gate else { return }
        if gate.feed(db, now) { hold(db) }
    }
    /// Whether level() would look at the level now (the page reads its analyser only then).
    public var listensForLevel: Bool { speaking && held == nil && voices.contains(voiceName) && gate != nil }
    func hold(_ db: Double) { // maybe someone is talking: freeze the voice mid-word until the recogniser confirms
        host.suspend(); markUnsaid(true); mark("you", true); held = host.after(TUNE.holdMs) { [self] in release() }
        host.log("[ears] paused at \(String(format: "%.1f", db)) dB")
    }
    func release() { // no words came, so it was a noise: carry on from the same word
        held = nil; markUnsaid(false); gate?.miss(); gate?.quiet(now, TUNE.restMs); host.resume(); mark("you", false)
        host.log("[ears] no words, carrying on; bar now \(js(gate?.bar ?? 0)) dB")
    }

    /// rec.onresult: every result from the changed one on, as the Web Speech API reports them.
    public func results(_ list: [Heard], from index: Int) {
        guard live, !muted else { return }
        if TUNE.joinMs > 0 && overVoice.count > list.count { overVoice.removeLast(overVoice.count - list.count) }
        if overVoice.count < list.count { overVoice += Array(repeating: nil, count: list.count - overVoice.count) }
        for i in index..<list.count {
            let r = list[i], over = speaking
            var text = trim(r.text)
            if track && voices.contains(voiceName) {
                // Echo-cancelled ears: words heard over the voice are the developer's, once any leaked echo of it is removed.
                if overVoice[i] == nil { overVoice[i] = speaking }
                if overVoice[i]! { text = userPart(text, aired.joined(separator: " ")) }
                if text.isEmpty {
                    if r.isFinal { if !hasSpace(trim(r.text)) { aside(trim(r.text)) }; hearing = false; mark("you", false); ghost = ""; refresh() }
                    continue
                }
                if speaking {
                    if held == nil && !isStopOnly(text) && words(text).count < 2 { if r.isFinal { aside(text) }; continue } // one stray word
                    host.log("[ears] cut off by \(quoted(text))")
                    hush()
                }
                if r.isFinal && overVoice[i]! && isStopOnly(text) { hearing = false; mark("you", false); ghost = ""; refresh(); continue } // "stop" only cuts it
            } // the page's fallback for ears without echo cancellation is not ported: the app always has them
            if !hearing { joining = stillOpen(turnState, now - pendingAt); utterAt = now; utterOver = over || overVoice[i] == true }
            if !r.isFinal { hearing = true; mark("you", true); ghost = text; refresh(); continue }
            hearing = false; mark("you", false); refresh()
            if !text.isEmpty { said(text) }
        }
    }
    /// rec.onend: the recogniser stopped (the page starts it again at once).
    public func recEnded() { hearing = false; mark("you", false); overVoice = [] }

    /// The server's event stream.
    public func server(_ e: [String: Any]) {
        switch e["type"] as? String {
        case "hello": setVoices(e["voices"] as? [String] ?? [])
        case "voices": setVoices(e["names"] as? [String] ?? [])
        case "say":
            let text = e["text"] as? String ?? ""
            let own = turnOpen ? limitOpen : limitSentence(text) // said on its own, not mid-answer: `!voiceBubble && LIMIT.exec(e.text)` (index.html on.say); a second line joins the limit bubble (index.html row)
            if own && !limitOpen { limit = text }
            limitOpen = own
            say(text, starts: !turnOpen, limit: own); turnOpen = true; refresh()
        case "turn_end": turnOpen = false; limitOpen = false; thinking = false; refresh(); if let ask = e["ask"] as? String { armAsk(ask) }
        case "wait":
            if turnState != "sent" || nudged { return } // it has already said something, or was already told to answer
            turnState = "waiting"; pendingAt = now; thinking = false; refresh()
            host.log("[turn] held: the voice waits for the rest")
            waitMore()
        case "asked": // answered by a click or by voice: a yes can no longer mean this step
            let id = e["id"] as? String ?? ""
            if askHeard == id { askHeard = "" }
            if askNext == id { askNext = "" }
            refresh()
        case "gone": thinking = false // the page lost the server, or found it again (voice.mjs)
        default: break
        }
    }
    func setVoices(_ names: [String]) {
        voices = names
        if !names.contains(voiceName) { voiceName = names.contains("af_heart") ? "af_heart" : names.first ?? voiceName }
    }
}

/// A number as JavaScript prints it (-39, not -39.0).
func js(_ x: Double) -> String { x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : String(x) }
/// JSON.stringify(text)
func quoted(_ text: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes]), encoding: .utf8)!.dropFirst().dropLast().description
}

/// A usage-limit line the voice says on its own (the server's limits.mjs writes these three sentences; the page's LIMIT).
func limitSentence(_ text: String) -> Bool {
    text.range(of: #"^You(?:'ve (hit)|'re close to|'ve used (\d+) percent of) your ([\w -]*limit)"#, options: .regularExpression) != nil
}
