import Foundation
import Testing
@testable import Ears

// call/ears.test.mjs, one for one (same names, same cases), then two checks against the JavaScript itself.
let callFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../call").standardized
let AIRED = "Sure. I will run the login tests now, then report back."

@Suite(.serialized) struct Ears {
    @Test func userPartDropsTheVoicesOwnEchoAndKeepsTheDevelopersWords() {
        #expect(userPart("run the login tests", AIRED) == "")
        #expect(userPart("Run the login tests.", AIRED) == "") // case and punctuation do not matter
        #expect(userPart("tests", AIRED) == "")
        #expect(userPart("the login tests no wait use the other file", AIRED) == "no wait use the other file")
        #expect(userPart("the plan is wrong", AIRED) == "the plan is wrong") // one shared word is chance
        #expect(userPart("actually tell me a joke", AIRED) == "actually tell me a joke")
        #expect(userPart("stop", AIRED) == "stop")
        #expect(userPart("hello there", "") == "hello there")
        #expect(userPart("", AIRED) == "")
    }

    @Test func cutTextKeepsThePlayedShareOfTheWords() {
        let s = "one two three four"
        #expect(cutText(s, 0.5) == "one two")
        #expect(cutText(s, 0.74) == "one two")
        #expect(cutText(s, 1) == s)
        #expect(cutText(s, 0) == "")
        #expect(cutText(s, .nan) == "")
        #expect(cutText(s, 3) == s)
        #expect(cutText(s, -1) == "")
    }

    @Test func isStopOnlyTest() {
        for t in ["stop", "Stop.", "stop stop", "hold on", "Wait a second.", "okay stop", "quiet please", "stop it"] { #expect(isStopOnly(t), "\(t)") }
        for t in ["stop the tests", "wait, use the other file", "okay", "please", "", "that is enough for today"] { #expect(!isStopOnly(t), "\(t)") }
    }

    @Test func levelDbTest() {
        #expect(levelDb([Float](repeating: 0, count: 1024)) <= -100)
        let sine = { (a: Float) in (0..<4800).map { a * sin(2 * .pi * 440 * Float($0) / 48000) } }
        #expect(abs(levelDb(sine(1)) - -3.01) < 0.1)
        #expect(abs(levelDb(sine(0.1)) - -23.01) < 0.1)
    }

    @Test func gateFiresOnASustainedLevelOnlyHonoursQuietWindowsAndLearnsFromMisses() {
        var g = Gate()
        for t in stride(from: 0.0, through: 2000, by: 20) { #expect(g.feed(-60, t) == false) } // a quiet room never fires
        g = Gate()
        #expect(g.feed(-20, 0) == false); #expect(g.feed(-20, 100) == false); #expect(g.feed(-20, 120) == true)
        g = Gate() // a dip starts the count again
        _ = g.feed(-20, 0); _ = g.feed(-20, 60); _ = g.feed(-60, 80); _ = g.feed(-20, 100)
        #expect(g.feed(-20, 200) == false); #expect(g.feed(-20, 220) == true)
        g = Gate()
        g.quiet(0, 300)
        for t in stride(from: 0.0, to: 300, by: 20) { #expect(g.feed(-20, t) == false) }
        #expect(g.feed(-20, 300) == false); #expect(g.feed(-20, 420) == true)
        g = Gate()
        g.miss(); #expect(g.bar == TUNE.barDb + TUNE.stepDb)
        _ = g.feed(-40, 0); #expect(g.feed(-40, 500) == false)
        for _ in 0..<10 { g.miss() }
        #expect(g.bar == TUNE.capDb)
    }

    @Test func stillOpenATurnTakesMoreWordsUntilItsAnswerStartsPlaying() {
        #expect(stillOpen("", 0) == false) // nothing said yet, or a typed turn
        #expect(stillOpen("sent", 0) == true) // its answer has not started
        #expect(stillOpen("sent", TUNE.joinMs - 1) == true)
        #expect(stillOpen("sent", TUNE.joinMs) == false) // too long ago: a new turn, as before
        #expect(stillOpen("answering", 1000) == false) // talking over its answer starts a new turn
        #expect(stillOpen("waiting", 60000) == true) // the voice is waiting for the rest
    }

    @Test func joinTurnKeepsEveryWordInOrderExceptABareStop() {
        #expect(joinTurn("check", "the files in this project") == "check the files in this project")
        #expect(joinTurn("tell me about closures and", "how they use memory") == "tell me about closures and how they use memory")
        #expect(joinTurn("what is a closure", "stop") == "")
        #expect(joinTurn("what is a closure", "stop using var") == "what is a closure stop using var")
    }

    @Test func unfinishedOnlyWordsThatNeverEndAFinishedSentence() {
        for t in ["tell me about closures and", "check the", "um", "I want my", "use this or"] { #expect(unfinished(t), "\(t)") }
        for t in ["check", "what are you up to", "I think so", "what is that", "tell me about closures", ""] { #expect(!unfinished(t), "\(t)") }
    }

    @Test func joinMs0SwitchesJoiningOffButAWaitingVoiceIsStillAnswered() {
        let was = TUNE.joinMs
        TUNE.joinMs = 0
        defer { TUNE.joinMs = was }
        #expect(stillOpen("sent", 0) == false)
        #expect(stillOpen("waiting", 0) == true)
    }

    // ── beyond the JavaScript tests ──────────────────────────────────────────

    @Test func theNumbersAreEarsMjsOwn() throws {
        let source = try String(contentsOf: callFolder.appending(path: "ears.mjs"), encoding: .utf8)
        let block = source.components(separatedBy: "export const TUNE = {")[1].components(separatedBy: "}")[0]
        var js: [String: Double] = [:]
        for m in block.matches(of: #/(\w+):\s*(-?[\d.]+)/#) { js[String(m.1)] = Double(m.2) }
        let swift = ["barDb": TUNE.barDb, "capDb": TUNE.capDb, "stepDb": TUNE.stepDb, "riseMs": TUNE.riseMs, "guardMs": TUNE.guardMs,
                     "holdMs": TUNE.holdMs, "restMs": TUNE.restMs, "joinMs": TUNE.joinMs, "waitMs": TUNE.waitMs]
        #expect(js == swift)
    }

    /// The same helpers in JavaScript and in Swift, on many more inputs than the tests above: punctuation, case, odd
    /// whitespace, non-English letters. Every answer must be equal.
    @Test func everyHelperAnswersAsTheJavaScriptDoes() throws {
        let vocab = ["run", "the", "login", "tests", "Stop.", "stop", "wait,", "hold", "on", "okay", "it's", "and", "um",
                     "Tests!", "über", "ÉTÉ", "日本語", "x2", "4.5", "—", "'", "the\u{00A0}plan", "now", "please", "A", "or"]
        var rng = SystemRandomNumberGenerator()
        let seps = [" ", "  ", "\t", "\n", " \u{3000}", "\u{2009}"]
        func sentence() -> String {
            (0..<Int.random(in: 0...6, using: &rng)).map { _ in vocab.randomElement(using: &rng)! }
                .map { $0 + seps.randomElement(using: &rng)! }.joined()
        }
        let aired = [AIRED, "", "The login tests now.", "  run the  login\ttests  "]
        let heard = (0..<300).map { _ in sentence() } + ["", " ", "stop", "Stop.", "the login tests no wait"]
        let fractions = [0, 0.1, 0.25, 0.5, 0.74, 0.999, 1, 1.5, -2]
        let cases: [String: Any] = ["heard": heard, "aired": aired, "fractions": fractions]
        let input = try JSONSerialization.data(withJSONObject: cases)
        let script = """
        import { userPart, cutText, isStopOnly, unfinished, joinTurn } from '\(callFolder.appending(path: "ears.mjs").path)'
        let s = ''; process.stdin.on('data', d => s += d).on('end', () => {
          const c = JSON.parse(s)
          console.log(JSON.stringify(c.heard.map(h => ({ user: c.aired.map(a => userPart(h, a)), cut: c.fractions.map(f => cutText(h, f)),
            stop: isStopOnly(h), open: unfinished(h), join: joinTurn('before', h) }))))
        })
        """
        let node = Process(), pin = Pipe(), pout = Pipe()
        node.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        node.arguments = ["node", "--input-type=module", "-e", script]
        node.standardInput = pin; node.standardOutput = pout
        try node.run()
        pin.fileHandleForWriting.write(input); try pin.fileHandleForWriting.close()
        let out = pout.fileHandleForReading.readDataToEndOfFile()
        node.waitUntilExit()
        let js = try #require(try JSONSerialization.jsonObject(with: out) as? [[String: Any]])
        #expect(js.count == heard.count)
        for (h, j) in zip(heard, js) {
            #expect(aired.map { userPart(h, $0) } == j["user"] as? [String], "userPart \(h.debugDescription)")
            #expect(fractions.map { cutText(h, $0) } == j["cut"] as? [String], "cutText \(h.debugDescription)")
            #expect(isStopOnly(h) == j["stop"] as? Bool, "isStopOnly \(h.debugDescription)")
            #expect(unfinished(h) == j["open"] as? Bool, "unfinished \(h.debugDescription)")
            #expect(joinTurn("before", h) == j["join"] as? String, "joinTurn \(h.debugDescription)")
        }
    }
}

/// What the window shows of the voice's words: one answer is one bubble, whenever its sentences play.
@Suite(.serialized) struct Bubbles {
    /// A call at 0 s: the voice speaks `say` (offset in ms from 2 s, text, clip seconds or nil for no audio), turn_end at `end`.
    func run(_ say: [(Double, String, Double?)], end: Double?) -> Replay {
        let r = Replay()
        var ev: [[String: Any]] = [["k": "mic", "t": 1000.0], ["k": "sse", "t": 1500.0, "e": ["type": "hello", "voices": ["af_heart"]]]]
        for (at, text, dur) in say {
            ev.append(["k": "sse", "t": 2000 + at, "e": ["type": "say", "text": text]])
            ev.append(["k": "tts", "t": 2000 + at, "text": text, "dur": dur as Any? ?? NSNull()])
        }
        if let end { ev.append(["k": "sse", "t": 2000 + end, "e": ["type": "turn_end"]]) }
        ev.append(["k": "stop", "t": 30000.0])
        r.run(ev)
        return r
    }

    @Test func aTurnEndBeforeItsSentencesPlayDoesNotSplitTheAnswer() {
        // the server's turn_end comes at 50 ms, while the first sentence is still playing and the other two wait
        let r = run([(0, "Sure.", 1), (10, "Why did the car get a ticket?", 2), (20, "It was parked illegally.", 2)], end: 50)
        #expect(r.turns.lines == [Turns.Line(who: "voice", text: "Sure. Why did the car get a ticket? It was parked illegally.")])
    }

    @Test func theNextAnswerIsANewBubbleEvenWhenItQueuedBehindTheLastSentenceOfTheOneBefore() {
        let s = Replay()
        s.run([["k": "mic", "t": 1000.0], ["k": "sse", "t": 1500.0, "e": ["type": "hello", "voices": ["af_heart"]]],
               ["k": "sse", "t": 2000.0, "e": ["type": "say", "text": "Sure."]], ["k": "tts", "t": 2000.0, "text": "Sure.", "dur": 1.0],
               ["k": "sse", "t": 2010.0, "e": ["type": "turn_end"]],
               ["k": "sse", "t": 2020.0, "e": ["type": "say", "text": "Fair enough."]], ["k": "tts", "t": 2020.0, "text": "Fair enough.", "dur": 1.0],
               ["k": "sse", "t": 2030.0, "e": ["type": "turn_end"]], ["k": "stop", "t": 30000.0]])
        #expect(s.turns.lines.map(\.text) == ["Sure.", "Fair enough."])
    }

    @Test func aUsageLimitLineIsOneOnlyWhenSaidOnItsOwn() {
        let line = "You've hit your five-hour limit; it resets at 3:40 PM."
        let mid = run([(0, "Sure.", 1), (10, line, 1)], end: 50)
        #expect(mid.turns.limit.isEmpty && mid.turns.lines.map(\.text) == ["Sure. \(line)"])
        let alone = run([(0, line, 1)], end: 50)
        #expect(alone.turns.limit == line && alone.turns.lines.isEmpty)
    }

    @Test func twoUsageLimitLinesInOneTurnAreNotGluedToTheAnswerBefore() {
        let a = "You're close to your five-hour limit.", b = "You've hit your weekly limit; it resets on Friday."
        let s = Replay()
        s.run([["k": "mic", "t": 1000.0], ["k": "sse", "t": 1500.0, "e": ["type": "hello", "voices": ["af_heart"]]],
               ["k": "sse", "t": 2000.0, "e": ["type": "say", "text": "Sure."]], ["k": "tts", "t": 2000.0, "text": "Sure.", "dur": 1.0],
               ["k": "sse", "t": 2010.0, "e": ["type": "turn_end"]],
               ["k": "sse", "t": 5000.0, "e": ["type": "say", "text": a]], ["k": "tts", "t": 5000.0, "text": a, "dur": 1.0],
               ["k": "sse", "t": 5001.0, "e": ["type": "say", "text": b]], ["k": "tts", "t": 5001.0, "text": b, "dur": 1.0],
               ["k": "sse", "t": 5010.0, "e": ["type": "turn_end"]], ["k": "stop", "t": 30000.0]])
        #expect(s.turns.lines.map(\.text) == ["Sure."] && s.turns.limit == a)
    }

    @Test func aSentenceWithNoAudioShowsFaintAndIsLogged() {
        let r = run([(0, "Sure.", 1), (10, "No sound for this.", nil), (20, "Again.", 1)], end: 50)
        #expect(r.turns.lines == [Turns.Line(who: "voice", text: "Sure."), Turns.Line(who: "voice", text: "No sound for this.", unsaid: "No sound for this."),
                                  Turns.Line(who: "voice", text: "Again.")])
        #expect(r.logs.contains { $0.line == "[mouth] no audio for a sentence" })
    }

    @Test func aRecordedCallShowsEachAnswerOnce() throws {
        let text = try String(contentsOf: callFolder.appending(path: "../app/Tests/recordings/recorded-call-1.jsonl"), encoding: .utf8)
        let r = Replay()
        r.run(text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
        let voice = r.turns.lines.filter { $0.who == "voice" }.map(\.text)
        // the turn_end came while their sentences were still to play: each answer is one bubble, though it was cut off by the hush
        #expect(voice.contains("Sure. Why did the car get a ticket? It was parked illegally."))
        #expect(voice.contains("Sure. Why don't elephants use computers? They're afraid of the mouse. What do you call a bear with no teeth? A gummy bear."))
        #expect(!voice.contains("Sure."))
    }
}
