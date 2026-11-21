import Foundation

// The call server's local voice, without Python: the same lines in and out as call/tts.py.
//   kokoro-runner <folder with kokoro-v1.0.onnx and voices-v1.0.bin>
// Reads one JSON request per line on stdin ({"id", "text", "voice", "speed"}), answers one JSON line on stdout: {"id", "path"}
// (a WAV) or {"id", "error"}; first {"ready": true, "voices": [...], "threads": n}. libonnxruntime.dylib, libespeak-ng.dylib and
// espeak-ng-data/ are opened from this program's own folder. Hidden: --phonemes <folder> reads {"text", "voice"} lines and
// answers the phonemes and their batches, without the model.

setvbuf(stdout, nil, _IOLBF, 0)

func reply(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
    FileHandle.standardOutput.write(data + Data([10]))
}

func executableFolder() -> String {
    var size: UInt32 = 4096
    var buffer = [CChar](repeating: 0, count: Int(size))
    _ = _NSGetExecutablePath(&buffer, &size)
    return URL(filePath: String(cString: buffer)).resolvingSymlinksInPath().deletingLastPathComponent().path
}

/// VOICE_THREADS (a number, or "all" for every core), else this Mac's performance cores; 0 lets onnxruntime take every core.
func threads() -> Int {
    let want = (ProcessInfo.processInfo.environment["VOICE_THREADS"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    if want == "all" { return 0 }
    if let n = Int(want), n > 0 { return n }
    var cores: Int32 = 0, size = MemoryLayout<Int32>.size
    return sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) == 0 ? Int(cores) : 0
}

let arguments = Array(CommandLine.arguments.dropFirst())
let phonemesOnly = arguments.first == "--phonemes"
guard let folder = arguments.last, arguments.count == (phonemesOnly ? 2 : 1) else {
    FileHandle.standardError.write(Data("usage: kokoro-runner <model folder>\n".utf8))
    exit(2)
}
let here = executableFolder()

do {
    let count = threads()
    let ort = phonemesOnly ? nil : try Ort(library: here + "/libonnxruntime.dylib", model: folder + "/kokoro-v1.0.onnx", threads: count)
    let kokoro = try Kokoro(ort: ort, voices: try Npz(path: folder + "/voices-v1.0.bin")) { (language: String) throws -> PhonemeSource in
        try Espeak(library: here + "/libespeak-ng.dylib", data: here + "/espeak-ng-data", language: language)
    }
    let outputFolder = FileManager.default.temporaryDirectory.appending(path: "claude-voice-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    if !phonemesOnly {
        _ = try kokoro.create("Ready.", voice: "bm_fable", speed: 1.0, language: "en-us") // warm up so the first real sentence is fast
        reply(["ready": true, "voices": kokoro.voices.names.filter { $0.first == "a" || $0.first == "b" }, "threads": count])
    }
    signal(SIGINT, SIG_DFL)
    while let line = readLine(strippingNewline: true) {
        guard let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
        let id: Any = request["id"] ?? NSNull()
        do {
            guard let text = request["text"] as? String else { throw Fail(message: "'text'") }
            let voice = (request["voice"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "bm_fable"
            let language = voice.hasPrefix("b") ? "en-gb" : "en-us" // bf_/bm_ voices are British
            if phonemesOnly {
                let phonemes = try kokoro.phonemize(text, language: language)
                reply(["text": text, "voice": voice, "phonemes": string(phonemes), "batches": kokoro.split(phonemes).map(string)])
                continue
            }
            let speed = (request["speed"] as? NSNumber)?.doubleValue ?? 1.0
            let samples = try kokoro.create(text, voice: voice, speed: speed, language: language)
            let path = outputFolder.appending(path: "\(id).wav")
            try wav(samples).write(to: path)
            reply(["id": id, "path": path.path])
        } catch let failure as Fail {
            reply(["id": id, "error": failure.message]) // one bad sentence must not end the call
        } catch {
            reply(["id": id, "error": "\(error)"])
        }
    }
} catch let failure as Fail {
    FileHandle.standardError.write(Data("kokoro-runner: \(failure.message)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("kokoro-runner: \(error)\n".utf8))
    exit(1)
}
