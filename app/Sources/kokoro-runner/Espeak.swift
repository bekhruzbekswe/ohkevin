import Foundation

struct Fail: Error { let message: String }

/// libespeak-ng, opened at run time (never linked): its own copy per instance, as phonemizer's EspeakAPI does, with the voice
/// picked the way phonemizer's EspeakWrapper.set_voice does.
/// What the phonemizer needs from espeak: one chunk of text in, IPA with '_' between phonemes out.
protocol PhonemeSource { func textToPhonemes(_ text: Scalars) -> String }

final class Espeak: PhonemeSource {
    typealias InitFn = @convention(c) (Int32, Int32, UnsafePointer<CChar>?, Int32) -> Int32
    typealias SetVoiceFn = @convention(c) (UnsafePointer<CChar>?) -> Int32
    typealias ListFn = @convention(c) (UnsafeRawPointer?) -> UnsafePointer<UnsafeRawPointer?>?
    typealias ToPhonemesFn = @convention(c) (UnsafeMutablePointer<UnsafeRawPointer?>?, Int32, Int32) -> UnsafePointer<CChar>?

    let toPhonemes: ToPhonemesFn

    init(library: String, data: String, language: String) throws {
        let fm = FileManager.default
        let source = URL(filePath: library).resolvingSymlinksInPath()
        let dir = fm.temporaryDirectory.appending(path: "kokoro-espeak-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) } // the library stays mapped; nothing is left behind
        let copy = dir.appending(path: source.lastPathComponent)
        try fm.copyItem(at: source, to: copy)
        guard let h = dlopen(copy.path, RTLD_NOW | RTLD_LOCAL) else { throw Fail(message: "failed to load espeak library: \(String(cString: dlerror()))") }
        func sym<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let p = dlsym(h, name) else { throw Fail(message: "failed to load espeak library: no \(name)") }
            return unsafeBitCast(p, to: type)
        }
        let initialize = try sym("espeak_Initialize", InitFn.self)
        let setVoice = try sym("espeak_SetVoiceByName", SetVoiceFn.self)
        let list = try sym("espeak_ListVoices", ListFn.self)
        toPhonemes = try sym("espeak_TextToPhonemes", ToPhonemesFn.self)
        let path = URL(filePath: data).resolvingSymlinksInPath().path
        guard initialize(0x02, 0, path, 0) > 0 else { throw Fail(message: "failed to initialize espeak shared library") }
        // the first voice listed whose language is the one asked for (a voice's languages start with a priority byte)
        var identifier: String?
        if let voices = list(nil) {
            var i = 0
            while let v = voices[i] {
                if let langs = v.load(fromByteOffset: 8, as: UnsafePointer<CChar>?.self), String(cString: langs + 1) == language,
                   let id = v.load(fromByteOffset: 16, as: UnsafePointer<CChar>?.self) { identifier = String(cString: id); break }
                i += 1
            }
        }
        guard let identifier else { throw Fail(message: "invalid voice code \"\(language)\"") }
        guard setVoice(identifier) == 0 else { throw Fail(message: "failed to load voice \"\(language)\"") }
    }

    /// EspeakWrapper.text_to_phonemes with no tie: UTF-8 text, IPA with '_' between phonemes, clause by clause, joined by spaces.
    func textToPhonemes(_ text: Scalars) -> String {
        guard let buffer = strdup(string(text)) else { return "" }
        defer { free(buffer) }
        var pointer: UnsafeRawPointer? = UnsafeRawPointer(buffer)
        var clauses: [String] = []
        while pointer != nil {
            if let p = toPhonemes(&pointer, 1, Int32(UInt8(ascii: "_")) << 8 | 0x02) {
                let s = String(cString: p)
                if !s.isEmpty { clauses.append(s) }
            }
        }
        return clauses.joined(separator: " ")
    }
}
