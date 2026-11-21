import AVFoundation
import Ears
import Speech

/// Apple's on-device recogniser (SpeechAnalyzer, macOS 26), fed 20 ms at a time, with live partial results, reported in
/// the Web Speech API's shape so the page's rules run on it unchanged: a list of results, finals and at most one partial
/// at the end, and the index of the first one that changed.
final class Recognizer: @unchecked Sendable { // touched on the main queue only; its reader task hops there
    let analyzer: SpeechAnalyzer, format: AVAudioFormat, name: String
    let input: AsyncStream<AnalyzerInput>.Continuation
    var converter: AVAudioConverter?, from: AVAudioFormat?, inb: AVAudioPCMBuffer?, reader: Task<Void, Never>?
    var list: [Heard] = []
    var onFinalize: ([String: Any]) -> Void = { _ in }, onStop: (String) -> Void = { _ in }, closing = false
    var changedAt = 0.0, quietSince: Double? = nil, asked = false, recent: [Double] = []
    static let endpointMs = NativeTune.endpointMs // when an utterance is over, and what "quiet" is: Tune.swift

    /// SpeechTranscriber (the newer model) when its English model is on this Mac, else DictationTranscriber (the
    /// dictation model macOS already has). EARS=speech or EARS=dictation picks one, for measuring both.
    static func make(onResults: @escaping ([Heard], Int) -> Void) async throws -> Recognizer {
        let en = Locale(identifier: "en-US"), want = NativeTune.ears
        let has = { (locales: [Locale]) in locales.contains { $0.identifier(.bcp47) == "en-US" } }
        let module: any SpeechModule, name: String
        if want != "dictation", has(await SpeechTranscriber.installedLocales) {
            module = SpeechTranscriber(locale: en, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
            name = "SpeechTranscriber"
        } else if want != "speech", has(await DictationTranscriber.installedLocales) {
            module = DictationTranscriber(locale: en, contentHints: [], transcriptionOptions: [],
                                          reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: [])
            name = "DictationTranscriber"
        } else { throw NoSpeechModel(want: want) }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw Failure("No audio format for \(name)") }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        let r = Recognizer(analyzer: analyzer, format: format, name: name, input: input)
        func deliver(_ text: String, _ final: Bool) { DispatchQueue.main.async { if !r.closing, let i = r.take(text, final) { onResults(r.list, i) } } } // none after close()
        r.reader = Task {
            do {
                if let m = module as? SpeechTranscriber { for try await x in m.results { deliver(String(x.text.characters), x.isFinal) } }
                if let m = module as? DictationTranscriber { for try await x in m.results { deliver(String(x.text.characters), x.isFinal) } }
                DispatchQueue.main.async { if !r.closing { r.onStop("its results ended") } }
            } catch { DispatchQueue.main.async { if !r.closing { r.onStop("\(error)") } } }
        }
        return r
    }
    init(analyzer: SpeechAnalyzer, format: AVAudioFormat, name: String, input: AsyncStream<AnalyzerInput>.Continuation) {
        self.analyzer = analyzer; self.format = format; self.name = name; self.input = input
    }

    /// A new partial replaces the partial at the end; a final replaces it too, and the next partial starts a new result.
    /// Apple also reports results with no words (a lone "?"); those are dropped, unless one finalises a partial.
    func take(_ text: String, _ final: Bool) -> Int? {
        let open = list.last.map { !$0.isFinal } ?? false
        if !text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) && !(final && open) { return nil }
        if final || !open || list.last?.text != text { changedAt = ProcessInfo.processInfo.systemUptime * 1000; asked = false }
        if open { list[list.count - 1] = Heard(text, final); return list.count - 1 }
        list.append(Heard(text, final)); return list.count - 1
    }

    /// Every 20 ms, the level of what was just heard (ms: the same clock as changedAt).
    func listen(level db: Double, at ms: Double) {
        recent.append(db); if recent.count > NativeTune.roomTicks { recent.removeFirst() }
        let floor = recent.sorted()[recent.count / NativeTune.roomQuantile] // the room's floor
        let bar = max(NativeTune.quietDb, floor + NativeTune.quietAboveRoomDb)
        if db > bar { quietSince = nil } else if quietSince == nil { quietSince = ms }
        guard Self.endpointMs > 0, !asked, list.last.map({ !$0.isFinal }) == true, ms - changedAt >= Self.endpointMs,
              let q = quietSince, ms - q >= Self.endpointMs else { return }
        asked = true
        // which half decided: the one that became true last (the words, or the quiet)
        onFinalize(["wordsMs": Int(ms - changedAt), "quietMs": Int(ms - q), "bar": Int(bar)])
        Task { [analyzer] in try? await analyzer.finalize(through: nil) }
    }

    /// Mono samples at any rate, converted to what the analyser wants. The input buffer is reused (converted at once); the
    /// output goes to the analyser, which reads it later, so each is new.
    func feed(_ samples: [Float], rate: Double) {
        guard !samples.isEmpty else { return }
        if converter == nil { from = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!; converter = AVAudioConverter(from: from!, to: format) }
        if inb == nil || inb!.frameCapacity < samples.count { inb = AVAudioPCMBuffer(pcmFormat: from!, frameCapacity: AVAudioFrameCount(samples.count * 2))! }
        let inb = inb!
        inb.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inb.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(samples.count) * format.sampleRate / rate) + 64)!
        var given = false, error: NSError?
        converter!.convert(to: out, error: &error) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return inb
        }
        if error == nil, out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    /// Main queue: closing is set at once, so a result already on its way is dropped (deliver); the analyser stops in the background.
    func close() { closing = true; input.finish(); Task { [analyzer, reader] in await analyzer.cancelAndFinishNow(); reader?.cancel() } }

    /// The owner's first trial step, if they want the newer model: Apple downloads it (its size is shown as it goes).
    static func installModel() async throws {
        let module = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .progressiveTranscription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { print("Already installed."); return }
        let watch = request.progress.observe(\.fractionCompleted) { p, _ in print(String(format: "%3.0f%%", p.fractionCompleted * 100)) }
        try await request.downloadAndInstall()
        watch.invalidate()
        print("Installed: VoiceApp now uses SpeechTranscriber.")
    }
}

/// Neither English model is on this Mac: the window offers the download (installModel).
struct NoSpeechModel: Error, CustomStringConvertible {
    let want: String?
    var description: String { want == nil ? "Apple's English speech model is not on this Mac yet. Quit Oh Kevin and open it again: it downloads it by itself." : "No English speech model on this Mac for \(want!). Run: VoiceApp --install-model" }
}
struct Failure: Error, CustomStringConvertible { let description: String; init(_ s: String) { description = s } }
