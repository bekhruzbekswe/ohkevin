import AVFoundation
import CallKit
import Ears
import CoreAudio
import Synchronization
@testable import OhKevinKit

/// `AppChecks --engine-check <report>`: the live audio engine, with nothing audible. The devices, every node's formats
/// before and after voice processing, then the engine built a few ways, one change at a time, each started for a
/// moment to count what the microphone delivers. Output muted, nothing scheduled to play, no server, no Claude.
/// The report is written as it goes, so a run stuck on the microphone prompt still says so.
enum EngineCheck {
    static func run(report: URL) async {
        var text = ""
        func say(_ s: String) { text += s + "\n"; try? text.write(to: report, atomically: true, encoding: .utf8); print(s) }
        say("engine check \(Date())")
        say("default input: \(device(kAudioHardwarePropertyDefaultInputDevice)); default output: \(device(kAudioHardwarePropertyDefaultOutputDevice))")
        let before = AVCaptureDevice.authorizationStatus(for: .audio)
        say("microphone permission: \(name(before))")
        if before == .notDetermined {
            say("asking: macOS shows \"\(appName) would like to access the microphone\" now; waiting for the answer")
            say("answer: \(await AVCaptureDevice.requestAccess(for: .audio) ? "allowed" : "not allowed")")
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { say("STOP: no microphone permission"); return }

        for v in Variant.allCases { say(v.run()) }
        say(channels())
        await soundPath(say)
        say("done")
    }

    /// The app's own Sound, as a call uses it: the microphone through voice processing, a Kokoro sentence on the
    /// player (muted), its position while it plays, pauses and resumes, then stop and close.
    static func soundPath(_ say: (String) -> Void) async {
        say("— the app's own Sound, as a call uses it, output muted")
        func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }
        do {
            let s = try Sound(microphone: true, mute: true)
            say("  STARTED: \(s.input); output volume \(s.engine.mainMixerNode.outputVolume)")
            _ = s.ring.take(); await wait(2)
            let got = s.ring.take(), n = Int(s.ring.rate / 50)
            let db = stride(from: 0, to: got.count - n, by: n).map { levelDb(got[$0..<$0 + n]) }.sorted()
            say(db.isEmpty ? "  the microphone delivered nothing in 2 s" : "  the microphone delivered \(got.count) frames in 2 s; level per 20 ms: quietest fifth \(Int(db[db.count / 5])), median \(Int(db[db.count / 2])), loudest tenth \(Int(db[db.count * 9 / 10])) dBFS")
            s.muteInput(true); _ = s.ring.take(); await wait(1)
            let silent = s.ring.take()
            s.muteInput(false); await wait(0.3); _ = s.ring.take(); await wait(1)
            let back = s.ring.take()
            func lvl(_ x: [Float]) -> String { x.isEmpty ? "no frames" : "\(x.count) frames, \(Int(levelDb(x))) dBFS" }
            say("  input muted for 1 s: \(lvl(silent)); unmuted again for 1 s: \(lvl(back))")
            let wav = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../build/wavs/short.wav").standardized
            guard let data = try? Data(contentsOf: wav), let clip = Sound.clip(wav: data, format: s.format) else { say("  no Kokoro clip at \(wav.path)"); s.close(); return }
            var ended = false
            s.play(clip) { ended = true }
            let at = { String(format: "%.2f s", s.played()) }
            await wait(0.6); let a = at(); await wait(0.6); let b = at()
            s.suspend(); let c = at(); await wait(0.5); let d = at()
            s.resume(); await wait(0.5); let e = at()
            say("  a Kokoro sentence of \(String(format: "%.1f", Double(clip.frameLength) / clip.format.sampleRate)) s: played \(a), then \(b); paused \(c), still \(d) after 0.5 s; resumed, \(e) after 0.5 s")
            s.stop(); await wait(0.3)
            say("  stop: the sentence \(ended ? "ended" : "DID NOT end")")
            let t0 = Date(); var heard = false
            s.problem { heard = true }
            for _ in 0..<40 where !heard { await wait(0.1) }
            say(s.problemClip.map { "  the problem sound (\(Sound.problemFile.lastPathComponent)): \(String(format: "%.2f", Double($0.frameLength) / s.format.sampleRate)) s, \(heard ? String(format: "played out in %.2f s", Date().timeIntervalSince(t0)) : "DID NOT finish") on the beep player" } ?? "  NO problem sound at \(Sound.problemFile.path)")
            s.close(); await wait(0.2)
            say("  close: engine \(s.engine.isRunning ? "STILL RUNNING" : "stopped"), voice processing \(s.engine.inputNode.isVoiceProcessingEnabled ? "STILL ON" : "off")")
        } catch { say("  FAILED: \(error)") }
    }

    /// Voice processing hands the app 9 channels and the app hears the first. What is in each, over 2 s of the room
    /// (output muted, so no echo here; the owner's trial log shows the first one with the voice taken out).
    static func channels() -> String {
        let engine = AVAudioEngine(), input = engine.inputNode, player = AVAudioPlayerNode()
        let sums = Mutex((frames: 0, sq: [Double](repeating: 0, count: 16), with0: [Double](repeating: 0, count: 16), layout: ""))
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!)
        engine.mainMixerNode.outputVolume = 0
        var lines = ["— what each voice-processing channel carries (2 s of the room, output muted)"]
        do {
            try input.setVoiceProcessingEnabled(true)
            input.voiceProcessingOtherAudioDuckingConfiguration = NativeTune.ducking
            let fmt = input.outputFormat(forBus: 0)
            let sink = AVAudioSinkNode { _, frames, list in
                let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)), n = Int(frames)
                // every channel as (buffer, step, offset), interleaved or not
                var chans: [(UnsafePointer<Float>, Int)] = []
                for b in abl { guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let k = Int(max(1, b.mNumberChannels)); for c in 0..<k { chans.append((UnsafePointer(p + c), k)) } }
                sums.withLock { s in
                    s.layout = "\(abl.count) buffer(s) of \(abl.first.map { $0.mNumberChannels } ?? 0) channel(s)"
                    s.frames += n
                    for (c, (p, step)) in chans.prefix(16).enumerated() {
                        for i in 0..<n { let x = Double(p[i * step]); s.sq[c] += x * x; s.with0[c] += x * Double(chans[0].0[i * chans[0].1]) }
                    }
                }
                return noErr
            }
            engine.attach(sink); engine.connect(input, to: sink, format: fmt)
            try engine.start()
            Thread.sleep(forTimeInterval: 2)
            let s = sums.withLock { $0 }
            lines.append("  \(f(fmt)), delivered as \(s.layout), \(s.frames) frames")
            for c in 0..<Int(fmt.channelCount) {
                let db = 10 * log10(s.sq[c] / Double(max(1, s.frames)) + 1e-12)
                let corr = s.sq[c] > 0 && s.sq[0] > 0 ? s.with0[c] / (s.sq[c] * s.sq[0]).squareRoot() : 0
                lines.append(String(format: "  channel %d: %.0f dBFS, alike to channel 0: %.2f", c, db, corr))
            }
        } catch { lines.append("  FAILED: \(error)") }
        engine.stop(); try? input.setVoiceProcessingEnabled(false)
        return lines.joined(separator: "\n")
    }

    enum Variant: String, CaseIterable {
        case asBuilt = "the order of 13927a6: VP, sink from the input, players into the mixer at 24 kHz mono"
        case noVP = "the same without voice processing"
        case inputOnly = "VP, the input into the sink, no mixer or players"
        case outputOnly = "VP, players into the mixer, nothing connected from the input"
        case tap = "VP, a tap on the input instead of the sink"
        case vpLast = "players and mixer connected first, voice processing enabled after (the fix)"
        case noDucking = "as built without the ducking setting"

        func run() -> String {
            let engine = AVAudioEngine(), input = engine.inputNode, output = engine.outputNode
            let player = AVAudioPlayerNode(), clip = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
            let heard = Mutex((frames: 0, sum: 0.0))
            var lines = ["— \(rawValue)", "  before VP: in.in \(f(input.inputFormat(forBus: 0))), in.out \(f(input.outputFormat(forBus: 0))), out.in \(f(output.inputFormat(forBus: 0))), out.out \(f(output.outputFormat(forBus: 0)))"]
            func count(_ p: UnsafePointer<Float>, _ n: Int) { var s = 0.0; for i in 0..<n { s += Double(p[i] * p[i]) }; heard.withLock { $0.frames += n; $0.sum += s } }
            func players() { engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: clip); engine.mainMixerNode.outputVolume = 0 }
            do {
                if self == .vpLast { players() }
                if self != .noVP {
                    try input.setVoiceProcessingEnabled(true)
                    if self != .noDucking { input.voiceProcessingOtherAudioDuckingConfiguration = NativeTune.ducking }
                }
                let fmt = input.outputFormat(forBus: 0)
                lines.append("  after VP:  in.in \(f(input.inputFormat(forBus: 0))), in.out \(f(fmt)), out.in \(f(output.inputFormat(forBus: 0))), out.out \(f(output.outputFormat(forBus: 0)))")
                if self == .tap {
                    input.installTap(onBus: 0, bufferSize: 4800, format: fmt) { b, _ in count(b.floatChannelData![0], Int(b.frameLength)) }
                } else if self != .outputOnly {
                    let sink = AVAudioSinkNode { _, frames, list in
                        if let p = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)).first?.mData?.assumingMemoryBound(to: Float.self) { count(p, Int(frames)) }
                        return noErr
                    }
                    engine.attach(sink); engine.connect(input, to: sink, format: fmt)
                }
                if self != .vpLast && self != .inputOnly { players() }
                lines.append("  connected: mixer.out \(f(engine.mainMixerNode.outputFormat(forBus: 0))), out.in \(f(output.inputFormat(forBus: 0))), out.out \(f(output.outputFormat(forBus: 0)))")
                try engine.start()
                Thread.sleep(forTimeInterval: 1.2)
                let h = heard.withLock { $0 }
                lines.append("  STARTED; the microphone delivered \(h.frames) frames in 1.2 s, level \(h.frames > 0 ? String(format: "%.0f dBFS", 10 * log10(h.sum / Double(h.frames) + 1e-12)) : "none")")
            } catch { lines.append("  FAILED: \(error)") }
            engine.stop()
            if input.isVoiceProcessingEnabled { try? input.setVoiceProcessingEnabled(false) }
            return lines.joined(separator: "\n")
        }
    }

    static func f(_ x: AVAudioFormat) -> String { "\(Int(x.sampleRate)) Hz \(x.channelCount) ch\(x.isInterleaved ? " interleaved" : "")" }
    static func name(_ s: AVAuthorizationStatus) -> String { [.notDetermined: "not asked yet", .restricted: "restricted", .denied: "denied", .authorized: "allowed"][s] ?? "\(s.rawValue)" }
    static func device(_ selector: AudioObjectPropertySelector) -> String {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return "none" }
        var label: Unmanaged<CFString>?, rate = Float64(0)
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size); addr.mSelector = kAudioObjectPropertyName
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &label)
        size = UInt32(MemoryLayout<Float64>.size); addr.mSelector = kAudioDevicePropertyNominalSampleRate
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate)
        return "\(label?.takeRetainedValue() as String? ?? "?") at \(Int(rate)) Hz"
    }
}
