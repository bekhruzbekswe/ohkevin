import AVFoundation
import CallKit
import Ears
import VoiceCore

/// The page's turn-taking (Ears.Turns) on real ears, a real mouth and the real server, and a log of all of it, one JSON
/// object per line, in the same shape measure/hook.js records from the page. It also tells the window's model where the
/// call is (starting, live, ending, ended, or failed) and why the ears may be deaf.
final class Call: Ears.Host, @unchecked Sendable { // Ears.: Foundation has a Host too. Main queue only.
    let server: Server, out: FileHandle?
    var sound: Sound?, file: FileMic?, timer: DispatchSourceTimer?, deviceChange: NSObjectProtocol?
    var ears: Recognizer? { didSet { if oldValue !== ears { oldValue?.close() } } } // whatever it is replaced by, a recogniser is never left running
    lazy var turns = Turns(host: self)
    lazy var model: CallModel = { // what the window shows besides the turn-taking: approvals, workers, banners, the end
        let m = CallModel(turns: turns, post: { [unowned self] in post($0, $1) })
        m.stage = .starting
        m.chose = { [unowned self] in record("voice", ["name": $0]) }
        return m
    }()
    var earsEpoch = 0 // the page's `ears`: a recogniser still opening when the mic is muted or the call ends is dropped
    var fileDone: () -> Void = {}, afterEnded: (() -> Void)?
    var ticks = 0, loud = false, connected = false, opening = false, reopening = false, over = false, microphone = true
    var ready: ((Error?) -> Void)?
    var lastProblem = (text: "", at: Date.distantPast)

    init(server: Server, log: URL?) {
        self.server = server
        if let log { FileManager.default.createFile(atPath: log.path, contents: nil); out = try? FileHandle(forWritingTo: log) } else { out = nil }
    }
    func record(_ k: String, _ fields: [String: Any] = [:]) {
        guard let out else { return }
        var o = fields; o["k"] = k; o["t"] = Date().timeIntervalSince1970 * 1000
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes]) { out.write(d + Data("\n".utf8)) }
    }

    /// Waits for the server and its local voice, then opens the ears: the microphone through voice processing, or a
    /// file in real time. ready runs once: when the call is live, or with the reason it never will.
    func start(microphone: Bool, file url: URL?, mute: Bool, ready: @escaping (Error?) -> Void) {
        record("start"); self.ready = ready; self.microphone = microphone
        server.exited = { [weak self] why in guard let self else { return };  fail(.stoppedStarting, why) }
        server.listen({ [self] line, e in
            guard !over else { return }
            connected = true
            receive(line, e)
            if e["type"] as? String == "hangup" { return end() } // the voice hung up
            if !opening && turns.voices.contains(turns.voiceName) { opening = true; open(file: url, mute: mute) }
        }, failed: { [self] why in fail(.stoppedStarting, why) }, dropped: { [self] in dropped(true) }, back: { [self] in dropped(false) })
        DispatchQueue.main.asyncAfter(deadline: .now() + NativeTune.startWaitSeconds) { [weak self] in
            guard let self, !opening, !over else { return }
            fail(connected ? .voiceDidNotLoad : .slowStart, connected ? "Kevin's voice did not load in \(Int(NativeTune.startWaitSeconds / 60)) minutes. Quit Oh Kevin and open it again: it finishes its download by itself."
                           : "The call server did not answer in \(Int(NativeTune.startWaitSeconds / 60)) minutes.")
        }
    }
    /// One line of the server's event stream: to the log, the turn-taking, then the window's model.
    func receive(_ line: String, _ e: [String: Any]) {
        record("sse", ["e": e]); turns.server(e)
        let problems = model.problems.count
        model.apply(line: line, event: e)
        if model.problems.count > problems, let p = model.problems.last { // once, with its red bubble; the same line again soon is the same problem
            let same = p.text == lastProblem.text && Date().timeIntervalSince(lastProblem.at) < NativeTune.sameProblemSeconds
            lastProblem = (p.text, Date())
            record("problem sound", ["on": sound != nil && !same])
            if !same { sound?.problem() } // also while muted: Mute silences the microphone, not the app
        }
    }
    /// Opens the sound and the ears. Without a microphone (not allowed, none, or a recogniser that will not start) the call
    /// is live and deaf: the voice still speaks, typing works, and the window says why.
    func open(file url: URL?, mute: Bool) {
        let mine = earsEpoch // a Listen Again meanwhile starts another open: this one then closes what it made
        Task { @MainActor in
            defer { reopening = false }
            do {
                var why: Deaf?, mic = microphone
                if mic {
                    if AVCaptureDevice.default(for: .audio) == nil { mic = false; why = .noMicrophone }
                    else if !(await AVCaptureDevice.requestAccess(for: .audio)) { mic = false; why = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .device : .microphone }
                }
                let f = try url.map(FileMic.init)
                let s = try Sound(microphone: mic, mute: mute, fileRate: f?.rate ?? 24000)
                var r: Recognizer?
                if mic || f != nil {
                    do { r = try await makeRecogniser() } catch { if f != nil { throw error }; why = deafness(error) }
                }
                if over || mine != earsEpoch { s.close(); r?.close(); return } // ended or superseded while opening: close what opened
                sound = s; ears = r; file = f
                deviceChange = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: s.engine, queue: .main) {
                    [self] _ in lose(.device) // the output too: AirPods in or out ends the voice's audio. Removed at end()
                }
                record("mic", ["recogniser": r?.name ?? "none", "input": s.input, "rate": s.ring.rate, "echoCancelled": mic, "endpointMs": Recognizer.endpointMs])
                turns.start(echoCancelled: true) // a file stands in for the echo-cancelled microphone, as in the page's measurement
                let t = DispatchSource.makeTimerSource(queue: .main)
                t.schedule(deadline: .now(), repeating: .milliseconds(NativeTune.tickMs))
                t.setEventHandler { [self] in tick() }
                t.resume(); timer = t
                model.deaf = why
                if model.stage == .starting { model.stage = .live; model.since = Date() }
                finishStarting(nil)
            } catch { // a live call is not ended by an audio that will not reopen: it stays deaf, with its banner, until Listen Again works
                if model.stage == .starting { fail(.stoppedStarting, "\(error)") } else { record("problem", ["text": "\(error)"]); changed() }
            }
        }
    }
    /// The recogniser, reporting to the turn-taking and the log; its trouble leaves the call deaf.
    func makeRecogniser() async throws -> Recognizer {
        let r = try await Recognizer.make { [self] list, i in
            guard !over else { return }
            record("result", ["i": i, "r": list.map { [$0.text, $0.isFinal] }]); turns.results(list, from: i)
        }
        r.onFinalize = { [self] why in record("finalize", why) }
        r.onStop = { [self] why in record("problem", ["text": "Speech recognition stopped (\(why))."]); lose(.recogniser) }
        return r
    }
    /// Why a recogniser would not open, logged: no model on this Mac to listen with, or it failed otherwise.
    func deafness(_ error: Error) -> Deaf { record("problem", ["text": "\(error)"]); return error is NoSpeechModel ? .speechModel : .recogniser }
    /// The ears stopped (the recogniser ended, or the audio device changed): the call goes on, deaf, until Listen Again.
    func lose(_ why: Deaf) {
        guard !over, model.deaf == nil || (why == .device && model.deaf != .device) else { return } // a device change wins over a recogniser already gone
        ears = nil
        if why == .device { turns.hush(); closeAudio() } // the voice's audio is gone with the device: what it had left was never heard
        turns.recEnded(); model.deaf = why
        if why == .device { listenAgain() } // at once: the banner shows only if that fails
        if !reopening { changed() }
    }
    /// Listen Again: the ears close and open again, the call goes on.
    func listenAgain() {
        guard !over, model.deaf != nil, !reopening else { return } // one at a time: a second click, or coming back to the app, waits
        earsEpoch += 1; reopening = true
        if model.deaf == .recogniser || model.deaf == .speechModel { return renew() } // only the recogniser: the Sound, and the voice playing in it, stay
        turns.hush(); closeAudio(); open(file: nil, mute: false) // else the voice's audio goes: what it had left was never heard
    }
    func renew() {
        let mine = earsEpoch
        Task { @MainActor in
            defer { reopening = false }
            do {
                let r = try await makeRecogniser()
                if over || mine != earsEpoch { r.close() } else { ears = r; model.deaf = nil; changed() }
            } catch { model.deaf = deafness(error); changed() }
        }
    }
    func closeAudio() {
        timer?.cancel(); timer = nil
        if let deviceChange { NotificationCenter.default.removeObserver(deviceChange) }
        deviceChange = nil
        sound?.close(); sound = nil; ears = nil
    }
    /// The mute click: the recogniser stops and voice processing silences the microphone (the audio engine stays on: the
    /// voice plays through it). Unmuting opens a new recogniser; a second click while it opens wins.
    func setMuted(_ on: Bool) {
        guard turns.live, !over, model.deaf == nil, on != turns.muted else { return }
        record("mute", ["on": on]); earsEpoch += 1
        turns.setMuted(on); sound?.muteInput(on)
        if on { ears = nil; return }
        let mine = earsEpoch
        Task { @MainActor in
            do {
                let r = try await makeRecogniser()
                if over || turns.muted || mine != earsEpoch { r.close() } else { ears = r }
            } catch { if mine == earsEpoch { lose(deafness(error)) } }
        }
    }
    /// The typing box.
    func type(_ text: String) { guard !over else { return }; record("type", ["text": text]); turns.type(text) }
    var recogniser: String { ears?.name ?? "" }
    func finishStarting(_ error: Error?) { let r = ready; ready = nil; r?(error); changed() }
    /// The call did not start, or stopped: everything closes at once, and the window says it.
    /// The stream dropped (a sleep, a hiccup) or came back: the page's 'retry' and onopen. The voice stops; typing waits.
    func dropped(_ on: Bool) {
        guard !over, model.reconnecting != on else { return }
        record(on ? "dropped" : "back")
        if on { turns.hush() }
        model.reconnecting = on; receive("", ["type": "gone"])
        if on { model.announce("Reconnecting.") }
    }
    func fail(_ trouble: Trouble, _ why: String) {
        guard !over else { return }
        record("problem", ["text": why]); print(why)
        let starting = model.stage == .starting
        model.stage = .failed(starting ? trouble : .stopped)
        model.reconnecting = false
        teardown(); model.until = Date(); model.update(); model.front(); model.announce(model.word)
        if ready != nil { finishStarting(Failure(why)) }
    }

    /// Every 20 ms: what the microphone delivered goes to the recogniser; while the voice talks, its level goes to the gate.
    func tick() {
        guard let sound else { return }
        let more = file?.pump(into: sound.ring) ?? true
        let new = sound.ring.take() // taken also while muted, so nothing old is heard on unmuting
        if let ears {
            ears.feed(new, rate: sound.ring.rate)
            if !new.isEmpty {
                let db = levelDb(new)
                ears.listen(level: db, at: now())
                if (db > NativeTune.quietDb) != loud { loud.toggle(); record("vad", ["on": loud]) } // for measurement only
            }
        }
        ticks += 1
        if ticks % 10 == 0 { model.update() } // every 200 ms: what the clock changes (a spoken yes's 20 s, a held-back step)
        if ears != nil, turns.listensForLevel {
            let db = levelDb(sound.ring.last(Int(sound.ring.rate * Double(NativeTune.levelSamples) / NativeTune.levelRate)))
            record("level", ["db": db]); turns.level(db)
        }
        if !more { timer?.cancel(); fileDone() }
    }

    /// End Call, ⌘Q, or the voice hanging up: the ears and the mouth close at once, then the work is handed over if it is to be.
    func end() {
        guard !over else { return }
        record("hangup") // the page's End call
        model.stage = .ending; model.until = Date()
        // our own server hands the work over itself, each worker from its own folder; a launcher's server ends the call itself (go=1)
        model.handing = server.own != nil && CallSettings.load().openInClaudeApp && !model.sessions.isEmpty
        if turns.live { turns.end() } // the page's End call: hush, and the talker hears what you heard
        if server.own == nil { post("/hangup", [:]) }
        guard model.handing else { teardown(); model.update(); return ended() }
        over = true; closeAudio(); model.update()
        server.hangUp { [self] ok in model.handedOver = ok; ended() }
    }
    func ended() { model.stage = .ended; model.announce("Call ended"); model.update(); afterEnded?() }
    /// Over: no timer, event or result reaches the turn-taking from here on.
    func teardown() { over = true; closeAudio(); server.end() }
    // ── Host ──
    func now() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
    func after(_ ms: Double, _ fn: @escaping () -> Void) -> Cancel {
        let item = DispatchWorkItem { [self] in if !over { fn() } } // holds the call until it fires; nothing runs once it is over
        DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000, execute: item)
        return Cancel { item.cancel() }
    }
    func post(_ path: String, _ body: [String: Any]) {
        record("post", ["path": path, "body": body])
        server.post(path, body) { [self] in // a Stop or an answer that did not go through says so
            if path == "/stop" { model.stopFailed = true; changed() } else if path == "/permit" { model.answerFailed(body["id"] as? String ?? "") }
            else if path == "/open" { receive("", ["type": "error", "text": "Could not open \(body["name"] as? String ?? "it") in the Claude app."]) } // as the server says it
        }
    }
    final class Sentence: Clip { let buffer: AVAudioPCMBuffer; init(_ b: AVAudioPCMBuffer) { buffer = b }
        var duration: Double { Double(buffer.frameLength) / buffer.format.sampleRate } }
    func fetch(_ text: String, voice: String, _ done: @escaping (Clip?) -> Void) {
        server.tts(text, voice: voice) { [self] data in // no audio open (it is reopening): no clip, and the words show faint, as never heard
            let clip = sound.flatMap { s in data.flatMap { Sound.clip(wav: $0, format: s.format) } }.map(Sentence.init)
            record("tts", ["text": text, "dur": clip?.duration ?? NSNull()])
            done(clip)
        }
    }
    func play(_ clip: Clip, _ ended: @escaping () -> Void) {
        guard let sound, let s = clip as? Sentence else { return ended() }
        record("play", ["dur": clip.duration])
        sound.play(s.buffer) { [self] in record("ended"); ended() }
    }
    func stop() { record("stop"); sound?.stop() }
    func suspend() { record("suspend"); sound?.suspend() }
    func resume() { record("resume"); sound?.resume() }
    func played() -> Double { sound?.played() ?? 0 }
    func tone() { sound?.tone() }
    func log(_ line: String) { record("log", ["text": line]); print(line) }
    func changed() { model.update() }
}
