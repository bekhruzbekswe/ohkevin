import AVFoundation
import Synchronization

/// One audio engine for both ears and mouth: the microphone through Apple's voice processing (its echo canceller), and
/// the voice played through the same engine, so the canceller knows exactly what to take out of the microphone.
final class Sound {
    let engine = AVAudioEngine()
    let voice = AVAudioPlayerNode(), beep = AVAudioPlayerNode()
    let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)! // Kokoro's
    let ring: Ring, microphone: Bool, input: String // input: what the ears get, for the log
    var clipStart: AVAudioFramePosition = 0, pausedAt: AVAudioFramePosition? = nil

    /// microphone: false for a measurement, where a file stands in for it (see FileMic). mute: nothing reaches the speakers.
    init(microphone: Bool, mute: Bool, fileRate: Double = 24000) throws {
        self.microphone = microphone
        // The mixer meets the speakers first, in their own format (48 kHz here). Created after voice processing is on,
        // it is joined to the output at 44.1 kHz, the output then reports 0 Hz, 0 channels and will not initialise
        // (-10875): results/engine-check-1.txt.
        for node in [voice, beep] { engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format) }
        if microphone {
            let input = engine.inputNode
            try input.setVoiceProcessingEnabled(true) // also puts the output through it: that is the canceller's reference
            input.voiceProcessingOtherAudioDuckingConfiguration = NativeTune.ducking
            let fmt = input.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw Failure("No microphone found.") }
            self.input = "microphone through voice processing: \(Int(fmt.sampleRate)) Hz, \(fmt.channelCount) channel(s), the first one heard"
            ring = Ring(rate: fmt.sampleRate)
            let sink = AVAudioSinkNode { [ring] _, frames, list in ring.write(list, Int(frames)); return noErr }
            engine.attach(sink)
            engine.connect(input, to: sink, format: fmt)
        } else { input = "file, \(Int(fileRate)) Hz, mono"; ring = Ring(rate: fileRate) }
        if mute { engine.mainMixerNode.outputVolume = 0 }
        try engine.start()
        voice.play(); beep.play()
    }
    /// The mute click: voice processing sends silence for the microphone. The engine stays on: the voice plays through it.
    func muteInput(_ on: Bool) { if microphone { engine.inputNode.isVoiceProcessingInputMuted = on } }
    func close() { engine.stop(); if microphone { try? engine.inputNode.setVoiceProcessingEnabled(false) } }

    // ── the mouth ──
    func sampleTime() -> AVAudioFramePosition { voice.lastRenderTime.flatMap { voice.playerTime(forNodeTime: $0) }?.sampleTime ?? clipStart }
    func play(_ clip: AVAudioPCMBuffer, ended: @escaping () -> Void) {
        clipStart = pausedAt ?? sampleTime()
        voice.scheduleBuffer(clip, at: nil, options: [], completionCallbackType: .dataRendered) { _ in DispatchQueue.main.async(execute: ended) } // as Web Audio's onended: the render clock, not the speaker's
    }
    /// Seconds of the current clip played: the player's own sample clock, frozen while paused.
    func played() -> Double { max(0, Double((pausedAt ?? sampleTime()) - clipStart) / format.sampleRate) }
    func stop() { voice.stop(); pausedAt = nil; clipStart = 0; voice.play() } // stop() ends the clip (its completion runs)
    func suspend() { guard pausedAt == nil else { return }; pausedAt = sampleTime(); voice.pause() } // mid-word, keeps its place
    func resume() { guard pausedAt != nil else { return }; pausedAt = nil; voice.play() }

    /// The page's tone(freq, ms, gain, delay): a short blip that fades out. Your words went: tone(700, 70).
    func tone(_ freq: Double = 700, _ ms: Double = 70, _ gain: Double = 0.05, _ delay: Double = 0) {
        let lead = Int(format.sampleRate * delay), len = Int(format.sampleRate * ms / 1000)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(lead + len))!
        b.frameLength = AVAudioFrameCount(lead + len)
        for i in 0..<lead + len {
            let t = Double(max(0, i - lead)) / format.sampleRate
            b.floatChannelData![0][i] = i < lead ? 0 : Float(gain * exp(log(0.0001 / gain) * t * 1000 / ms) * sin(2 * .pi * freq * t))
        }
        beep.scheduleBuffer(b)
    }

    /// The problem sound: once per server problem, on the beep player, so it goes through the same echo canceller as the voice
    /// and the ears do not take it for you. completed: when it has left the engine (for the engine check).
    lazy var problemClip = Sound.load(Sound.problemFile, format: format, gain: NativeTune.problemGain)
    func problem(completed: (() -> Void)? = nil) {
        guard let b = problemClip else { completed?(); return }
        beep.scheduleBuffer(b, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in completed.map { DispatchQueue.main.async(execute: $0) } }
    }
    /// call/problem.mp3: inside the app (build.sh copies it), else in the call folder this was built from (`swift run`).
    static var problemFile: URL {
        Bundle.main.url(forResource: "problem", withExtension: "mp3") ?? Server.callFolder.appending(path: "problem.mp3")
    }
    /// A sound file decoded and converted to the given format, whole, at the given gain.
    static func load(_ url: URL, format: AVAudioFormat, gain: Float = 1) -> AVAudioPCMBuffer? {
        guard let f = try? AVAudioFile(forReading: url),
              let src = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: src)) != nil,
              let conv = AVAudioConverter(from: f.processingFormat, to: format),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(src.frameLength) * format.sampleRate / f.processingFormat.sampleRate) + 4096)
        else { return nil }
        var fed = false
        let status = conv.convert(to: out, error: nil) { _, s in
            if fed { s.pointee = .endOfStream; return nil }
            fed = true; s.pointee = .haveData; return src
        }
        guard status != .error, out.frameLength > 0 else { return nil }
        for i in 0..<Int(out.frameLength) { out.floatChannelData![0][i] *= gain }
        return out
    }

    /// The server's /tts answer (a 16-bit WAV) as a buffer the voice can play.
    static func clip(wav d: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        func u32(_ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 | Int(d[i + 2]) << 16 | Int(d[i + 3]) << 24 }
        guard d.count > 12, String(decoding: d[0..<4], as: UTF8.self) == "RIFF" else { return nil }
        var p = 12, rate = 0, bits = 0, channels = 1
        while p + 8 <= d.count {
            let id = String(decoding: d[p..<p + 4], as: UTF8.self), n = u32(p + 4)
            if id == "fmt " { channels = Int(d[p + 10]); rate = u32(p + 12); bits = Int(d[p + 22]) }
            if id == "data", rate == Int(format.sampleRate), bits == 16, channels == 1 {
                let frames = min(n, d.count - p - 8) / 2
                let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
                b.frameLength = AVAudioFrameCount(frames)
                for i in 0..<frames { b.floatChannelData![0][i] = Float(Int16(bitPattern: UInt16(d[p + 8 + 2 * i]) | UInt16(d[p + 9 + 2 * i]) << 8)) / 32768 }
                return b
            }
            p += 8 + n + (n & 1)
        }
        return nil
    }
}

/// The microphone's last two seconds. The audio thread only copies samples in (no locks, no allocation); the main
/// queue takes what is new every 20 ms, for the recogniser and for the level, as the page reads its analyser.
final class Ring: @unchecked Sendable {
    let rate: Double, size: Int
    let data: UnsafeMutablePointer<Float>
    let written = Atomic<Int>(0) // frames written in all
    var read = 0                 // frames taken (main queue only)
    init(rate: Double) { self.rate = rate; size = Int(rate * NativeTune.ringSeconds); data = .allocate(capacity: size); data.initialize(repeating: 0, count: size) }
    deinit { data.deallocate() }

    /// Audio thread: the first channel of what the input delivered.
    func write(_ list: UnsafePointer<AudioBufferList>, _ frames: Int) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let buf = abl.first, let src = buf.mData?.assumingMemoryBound(to: Float.self) else { return }
        write(src, frames, step: Int(max(1, buf.mNumberChannels)))
    }
    func write(_ src: UnsafePointer<Float>, _ frames: Int, step: Int = 1) {
        let w = written.load(ordering: .relaxed)
        for i in 0..<frames { data[(w + i) % size] = src[i * step] }
        written.store(w + frames, ordering: .releasing)
    }
    /// Everything written since the last take (at most the ring).
    func take() -> [Float] {
        let w = written.load(ordering: .acquiring), from = max(read, w - size)
        read = w
        return (from..<w).map { data[$0 % size] }
    }
    /// The last n frames, like the page's analyser (fftSize 1024).
    func last(_ n: Int) -> [Float] { let w = written.load(ordering: .acquiring); return (max(0, w - n)..<w).map { data[$0 % size] } }
}

/// A WAV file played into the ring in real time, standing in for the microphone in a measurement.
final class FileMic {
    let samples: [Float], rate: Double
    var fed = 0, started: Date? = nil
    init(_ url: URL) throws {
        let f = try AVAudioFile(forReading: url)
        let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: b)
        samples = Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength))); rate = f.processingFormat.sampleRate
    }
    var duration: Double { Double(samples.count) / rate }
    /// Writes what a microphone would have delivered by now; false once the file is over.
    func pump(into ring: Ring) -> Bool {
        let due = min(samples.count, Int(Date().timeIntervalSince(started ?? { started = Date(); return started! }()) * rate))
        if due > fed { samples.withUnsafeBufferPointer { ring.write($0.baseAddress! + fed, due - fed) }; fed = due }
        return fed < samples.count
    }
}
