import Foundation

// call/ears.mjs, one for one: the same numbers and the same helpers, in the same order.
// Tests/EarsTests checks the numbers against ears.mjs itself and the helpers against the JavaScript on the same cases.

/// The tunables (ears.mjs TUNE). Times in milliseconds, levels in dBFS.
public enum TUNE {
    public static var barDb = -42.0   // echo-cancelled mic level that counts as someone talking over the voice
    public static var capDb = -30.0   // false alarms raise the bar, never above this
    public static var stepDb = 3.0    // how much each false alarm raises the bar
    public static var riseMs = 120.0  // the level must stay above the bar this long
    public static var guardMs = 300.0 // no pausing in the first moments of each spell of talking
    public static var holdMs = 1200.0 // how long a pause waits for the recogniser to confirm real words
    public static var restMs = 1500.0 // no new pause this soon after a false one
    public static var joinMs = 8000.0 // a pause to think: words added this soon are joined to the last ones; 0 turns it off
    public static var waitMs = 3000.0 // when the voice waits for the rest of a thought and you stay quiet this long, it answers
}

// JavaScript's \s and String.prototype.trim(), exactly: Swift's own whitespace set differs at the edges (U+0085, U+FEFF).
func jsSpace(_ c: Unicode.Scalar) -> Bool {
    switch c.value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
    default: false
    }
}
/// `s.trim()`
public func trim(_ s: String) -> String {
    let u = s.unicodeScalars
    guard let a = u.firstIndex(where: { !jsSpace($0) }), let b = u.lastIndex(where: { !jsSpace($0) }) else { return "" }
    return String(u[a...b])
}
/// `s.split(/\s+/)` without the empty strings JavaScript keeps at the ends (every caller drops them).
public func words(_ s: String) -> [String] {
    s.unicodeScalars.split(whereSeparator: jsSpace).map { String(String.UnicodeScalarView($0)) }
}
/// `/\s/.test(s)`
public func hasSpace(_ s: String) -> Bool { s.unicodeScalars.contains(where: jsSpace) }

// w.toLowerCase().replace(/[^\p{L}\p{N}']/gu, '')
func norm(_ w: String) -> String {
    let letters: Set<Unicode.GeneralCategory> = [.uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                                                 .decimalNumber, .letterNumber, .otherNumber]
    return String(String.UnicodeScalarView(w.lowercased().unicodeScalars.filter { letters.contains($0.properties.generalCategory) || $0 == "'" }))
}
func hasRun(_ words: [String], _ run: [String]) -> Bool {
    words.indices.contains { i in run.indices.allSatisfy { j in i + j < words.count && words[i + j] == run[j] } }
}

/// What the developer said, minus leading words that are the voice's own echo; "" when it is all echo.
public func userPart(_ heard: String, _ aired: String) -> String {
    let tokens = words(trim(heard)).filter { !norm($0).isEmpty }
    let h = tokens.map(norm), a = words(aired).map(norm).filter { !$0.isEmpty }
    var k = h.count
    while k > 0 && !hasRun(a, Array(h[0..<k])) { k -= 1 }
    if k == h.count { return "" }
    return tokens[(k < 2 ? 0 : k)...].joined(separator: " ") // one shared word is chance; two or more in a row is echo
}

/// The start of a sentence, in proportion to how much of its audio has played.
public func cutText(_ text: String, _ fraction: Double) -> String {
    let w = words(trim(text))
    let f = fraction.isNaN ? 0 : min(1, max(0, fraction))
    return w.prefix(Int((Double(w.count) * f).rounded(.down))).joined(separator: " ")
}

/// A whole utterance that only asks the voice to stop: it cuts the voice off and is not sent as a turn.
let CALM: Set = ["stop", "wait", "hold", "pause", "quiet", "enough"]
let FILL: Set = ["on", "it", "please", "now", "ok", "okay", "a", "sec", "second", "moment"]
public func isStopOnly(_ text: String) -> Bool {
    let w = words(text).map(norm).filter { !$0.isEmpty }
    return w.contains(where: CALM.contains) && w.allSatisfy { CALM.contains($0) || FILL.contains($0) }
}

/// Loudness of a block of samples, in dBFS.
public func levelDb<C: Collection>(_ samples: C) -> Double where C.Element == Float {
    var sum = 0.0
    for x in samples { sum += Double(x) * Double(x) }
    return 10 * log10(sum / Double(samples.count) + 1e-12)
}

/// Says when the echo-cancelled microphone has stayed loud long enough to be someone talking over the voice.
public final class Gate {
    public var bar = TUNE.barDb
    var since: Double? = nil // when the level went above the bar
    var until = 0.0          // no firing before this time
    public init() {}
    public func feed(_ db: Double, _ t: Double) -> Bool {
        if t < until || db <= bar { since = nil; return false }
        if since == nil { since = t }
        return t - since! >= TUNE.riseMs
    }
    public func quiet(_ t: Double, _ ms: Double) { until = max(until, t + ms); since = nil }
    public func miss() { bar = min(bar + TUNE.stepDb, TUNE.capDb) } // that was not a person: ask for more next time
}

/// A pause to think: 'sent' (its answer has not started), 'waiting' (the voice waits for the rest), 'answering'.
public func stillOpen(_ state: String, _ ageMs: Double) -> Bool {
    if state == "waiting" { return true }
    if !(TUNE.joinMs > 0) || ageMs >= TUNE.joinMs { return false }
    return state == "sent"
}

/// More words for an open turn: the whole thought, to send in place of the first part. "" means a new turn.
public func joinTurn(_ before: String, _ more: String) -> String { isStopOnly(more) ? "" : "\(before) \(more)" }

/// Words that never end a finished sentence.
let OPEN: Set = ["and", "or", "but", "because", "the", "a", "an", "my", "your", "our", "their", "um", "uh", "er", "erm"]
public func unfinished(_ text: String) -> Bool { OPEN.contains(norm(words(trim(text)).last ?? "")) }
