import Foundation

// kokoro-onnx 0.5.0: Kokoro.create and Tokenizer.phonemize (its normalize_text is just strip(), and its phonemes come from
// phonemizer, here Phonemizer), with call/tts.py's one backend per language.

let maxPhonemes = 510

final class Kokoro {
    let ort: Ort?
    let voices: Npz
    private var backends: [String: Phonemizer] = [:]

    /// `source` makes the phoneme source for a language: the library opened in this process, or the espeak-ng program beside it (see main.swift).
    init(ort: Ort?, voices: Npz, source: (String) throws -> PhonemeSource) throws {
        self.ort = ort
        self.voices = voices
        for language in ["en-us", "en-gb"] { backends[language] = Phonemizer(espeak: try source(language)) }
    }

    /// Tokenizer.phonemize: the phonemes kept to the vocabulary, stripped.
    func phonemize(_ text: String, language: String) throws -> Scalars {
        guard let backend = backends[language] else { throw Fail(message: "language \"\(language)\" is not supported") }
        return pyStrip(try backend.phonemize(pyStrip(scalars(text))).filter { kokoroVocab[$0.value] != nil })
    }

    /// Kokoro._split_phonemes: batches of under 510, cut after . , ! ? ; where it can.
    func split(_ phonemes: Scalars) -> [Scalars] {
        var parts: [Scalars] = [[]]
        for c in phonemes {
            if ".,!?;".unicodeScalars.contains(c) { parts.append([c]); parts.append([]) } else { parts[parts.count - 1].append(c) }
        }
        var batches: [Scalars] = [], current = Scalars()
        for raw in parts {
            let part = pyStrip(raw)
            if part.isEmpty { continue }
            if current.count + part.count + 1 >= maxPhonemes {
                batches.append(pyStrip(current))
                current = part
            } else if part.count == 1, ".,!?;".unicodeScalars.contains(part[0]) {
                current += part
            } else {
                if !current.isEmpty { current.append(" ") }
                current += part
            }
        }
        if !current.isEmpty { batches.append(pyStrip(current)) }
        return batches
    }

    /// Kokoro.create(text, voice, speed, lang): trimmed audio of every batch, joined.
    func create(_ text: String, voice: String, speed: Double, language: String) throws -> [Float] {
        guard speed >= 0.5 && speed <= 2.0 else { throw Fail(message: "Speed should be between 0.5 and 2.0") }
        guard voices.has(voice) else { throw Fail(message: "Voice \(voice) not found in available voices") }
        guard let ort else { throw Fail(message: "no model") }
        let batches = split(try phonemize(text, language: language))
        if batches.isEmpty { throw Fail(message: "need at least one array to concatenate") }
        var audio: [Float] = []
        for batch in batches {
            let tokens = batch.prefix(maxPhonemes).compactMap { kokoroVocab[$0.value] } // phonemes[:510], as _create_audio cuts them
            guard tokens.count < Npz.rows else { throw Fail(message: "index \(tokens.count) is out of bounds for axis 0 with size \(Npz.rows)") }
            let style = voices.style(voice, row: tokens.count)
            audio += trim(try ort.run(tokens: [0] + tokens + [0], style: style, speed: Float(speed)))
        }
        return audio
    }
}
