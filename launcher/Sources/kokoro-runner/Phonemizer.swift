import Foundation

// phonemizer-fork 3.3.2: EspeakBackend(language, preserve_punctuation=True, with_stress=True), the default separator
// (phone "", word " "), strip=False, language_switch='keep-flags', words_mismatch='ignore', njobs=1; and Punctuation.

private let punctuationMarks = Set(scalars(";:,.!?¡¿—…\"«»“”(){}[]"))
private let space = Unicode.Scalar(UInt8(32))

private enum Position { case begin, inside, end, alone }
private struct Mark { var index: Int; var text: Scalars; var position: Position }

/// Punctuation.preserve: the text split at its runs of marks (and the white space round them), the marks kept for restore.
private func preserve(_ lines: [Scalars]) -> (text: [Scalars], marks: [Mark]) {
    var text: [Scalars] = [], marks: [Mark] = []
    for (num, line) in lines.enumerated() {
        // re.finditer(r"(\s*[marks]+\s*)+"): a maximal run of white space and marks that holds a mark
        var runs: [Range<Int>] = []
        var i = 0
        while i < line.count {
            guard isPySpace(line[i]) || punctuationMarks.contains(line[i]) else { i += 1; continue }
            var j = i, hasMark = false
            while j < line.count, isPySpace(line[j]) || punctuationMarks.contains(line[j]) { if punctuationMarks.contains(line[j]) { hasMark = true }; j += 1 }
            if hasMark { runs.append(i..<j) }
            i = j
        }
        if runs.isEmpty { text.append(line); continue }
        if runs.count == 1, runs[0] == 0..<line.count { marks.append(Mark(index: num, text: line, position: .alone)); continue }
        var rest = 0
        for (k, run) in runs.enumerated() {
            var position = Position.inside
            if k == 0 && run.lowerBound == 0 { position = .begin } else if k == runs.count - 1 && run.upperBound == line.count { position = .end }
            marks.append(Mark(index: num, text: Array(line[run]), position: position))
            text.append(Array(line[rest..<run.lowerBound]))
            rest = run.upperBound
        }
        text.append(Array(line[rest...]))
    }
    return (text.filter { !$0.isEmpty }, marks)
}

/// Punctuation.restore with the default separator and strip=False.
private func restore(_ phonemized: [Scalars], _ marksIn: [Mark]) -> [Scalars] {
    var text = phonemized, marks = marksIn, out: [Scalars] = [], pos = 0
    while !text.isEmpty || !marks.isEmpty {
        if marks.isEmpty {
            for var line in text { if !hasSuffix(line, [space]) { line.append(space) }; out.append(line) }
            text = []
        } else if text.isEmpty {
            out.append(marks.flatMap { $0.text })
            marks = []
        } else {
            let current = marks[0]
            if current.index == pos {
                marks.removeFirst()
                if hasSuffix(text[0], [space]) { text[0].removeLast() }
                switch current.position {
                case .begin: text[0] = current.text + text[0]
                case .end:
                    out.append(text[0] + current.text + (hasSuffix(current.text, [space]) ? [] : [space]))
                    text.removeFirst(); pos += 1
                case .alone:
                    out.append(current.text + (hasSuffix(current.text, [space]) ? [] : [space]))
                    pos += 1
                case .inside:
                    if text.count == 1 { text[0] += current.text } else { let first = text.removeFirst(); text[0] = first + current.text + text[0] }
                }
            } else {
                out.append(text[0]); text.removeFirst(); pos += 1
            }
        }
    }
    return out
}

final class Phonemizer {
    let espeak: PhonemeSource
    init(espeak: PhonemeSource) { self.espeak = espeak }

    /// EspeakBackend._postprocess_line
    private func postprocess(_ raw: String) -> Scalars {
        var line = pyStrip(scalars(raw))
        line = pyReplace(line, [Unicode.Scalar(UInt8(10))], [space])
        line = pyReplace(line, [space, space], [space])
        // re.sub('_+', '_'), then re.sub('_ ', ' ')
        var squeezed = Scalars()
        for c in line { if c == "_", squeezed.last == "_" { continue }; squeezed.append(c) }
        line = pyReplace(squeezed, ["_", space], [space])
        if line.isEmpty { return [] }
        var out = Scalars()
        for word in pySplit(line, space) { out += pyReplace(pyStrip(word), ["_"], []); out.append(space) }
        return out
    }

    /// backend.phonemize([text])[0]
    func phonemize(_ text: Scalars) throws -> Scalars {
        let (chunks, marks) = preserve([text])
        let phonemized = chunks.map { postprocess(espeak.textToPhonemes($0)) }
        guard let first = restore(phonemized, marks).first else { throw Fail(message: "list index out of range") }
        return first
    }
}
