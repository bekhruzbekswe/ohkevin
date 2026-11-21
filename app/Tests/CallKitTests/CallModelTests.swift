import Foundation
import Testing
import VoiceCore
@testable import CallKit
@testable import Ears

// What the call window shows, run on the real turn-taking with the replay's host (nothing is heard or played).
final class Rig {
    let host = Replay()
    var sent: [(String, [String: Any])] = [], announced: [String] = [], fronted = 0
    var clock = Date(timeIntervalSince1970: 1_000_000)
    lazy var model = CallModel(turns: host.turns, post: { [unowned self] in sent.append(($0, $1)); host.post($0, $1) }, clock: { [unowned self] in clock })
    init(voices: [String] = ["af_heart", "am_michael"]) {
        model.announce = { [unowned self] in announced.append($0) }
        model.front = { [unowned self] in fronted += 1 }
        host.turns.start(echoCancelled: true); model.stage = .live
        send(["type": "hello", "project": "/Users/you/Lab/api", "voices": voices])
    }
    func send(_ e: [String: Any]) {
        host.turns.server(e)
        model.apply(line: "data: " + String(decoding: try! JSONSerialization.data(withJSONObject: e), as: UTF8.self), event: e)
    }
    func board(_ workers: [(String, String, String, String)]) { // name, state, task, step
        send(["type": "board", "state": workers.contains { $0.1 == "waiting" } ? "waiting" : workers.contains { $0.1 == "working" } ? "working" : "idle",
              "workers": workers.map { ["name": $0.0, "state": $0.1, "task": $0.2, "step": $0.3, "model": "opus"] }])
    }
    var paths: [String] { host.posts.map(\.path) }
    /// The voice starts saying this: a 3 s clip, playing (a replay drops what is due after its last event: finish() ends it).
    func voice(_ text: String) {
        host.run([["k": "tts", "t": host.clock, "text": text, "dur": 3.0]])
        send(["type": "say", "text": text])
        host.run([["k": "wait", "t": host.clock + 100]]); model.update()
    }
}

@Suite(.serialized) struct CallModelTests {
    @Test func startingSaysStartingThenConnectingOnceTheServerSaysHello() {
        let r = Rig(); r.model.stage = .starting
        #expect(r.model.headline().word == "Connecting…") // Rig's server has said hello
        r.send(["type": "hello", "project": ""])
        #expect(r.model.headline().word == "Starting the call…")
    }

    @Test func theFirstCallOpensOnSayHelloAndHintsTheFirstFinishedCardOnce() {
        let r = Rig()
        r.model.update()
        #expect(r.model.greeting == CallModel.hi) // any other call
        r.send(["type": "hello", "project": "/Users/you/Lab/shop", "voices": ["af_heart"], "first": true, "hint": true]); r.model.update()
        #expect(r.model.greeting == CallModel.sayHello && r.model.hintFor == nil)
        r.board([("shop", "working", "Read the project", "Read README.md")]); r.model.update()
        #expect(r.model.hintFor == nil) // working: no hint yet
        r.board([("shop", "idle", "Read the project", ""), ("web", "working", "Build", "Bash npm run build")]); r.model.update()
        #expect(r.model.hintFor == "shop" && r.paths.filter { $0 == "/hinted" }.count == 1)
        r.board([("shop", "idle", "Read the project", ""), ("web", "idle", "Build", "")]); r.model.update()
        #expect(r.model.hintFor == "shop" && r.paths.filter { $0 == "/hinted" }.count == 1) // once: the second finished card has none
    }

    @Test func theRailShowsWorkersThatWorkedAndTheOldestRequestIsItsWorkersCard() {
        let r = Rig()
        r.board([("api", "idle", "", "")])
        #expect(r.model.rail.isEmpty) // no work yet: no rail
        r.clock += 1; r.board([("api", "working", "fix the tests", "Bash npm test"), ("web", "working", "shrink it", "Bash npm run build")])
        #expect(r.model.rail.map(\.name) == ["api", "web"] && r.model.rail[0].state == .working && r.model.rail[0].sentence == "Running the tests")
        r.board([("api", "waiting", "fix the tests", ""), ("web", "waiting", "shrink it", "")])
        r.send(["type": "ask", "id": "a1", "detail": "web: Bash git push origin main", "worker": "web", "voice": false, "full": "git push origin main"])
        r.send(["type": "ask", "id": "a2", "detail": "api: Bash rm -rf dist", "worker": "api", "voice": true, "full": "rm -rf dist"])
        #expect(r.model.rail.map(\.state) == [.waiting, .asking]) // web asked first: its card is the request; api's waits
        #expect(r.model.rail[1].approval?.ask.id == "a1" && r.model.rail[1].approval?.byVoice == false)
        r.send(["type": "session", "id": "s1", "worker": "api"])
        r.send(["type": "asked", "id": "a1", "allow": true]); r.send(["type": "asked", "id": "a2", "allow": true])
        r.board([("api", "idle", "fix the tests", ""), ("web", "working", "shrink it", "Bash git push origin main")])
        #expect(r.model.rail[0].state == .done && r.model.rail[0].sentence == "fix the tests" && r.model.rail[0].session == "s1")
        r.model.close("api")
        #expect(r.sent.last?.0 == "/close" && r.sent.last?.1["name"] as? String == "api")
        r.board([("web", "working", "shrink it", "")]) // the server ended it
        #expect(r.model.rail.map(\.name) == ["web"])
        r.board([("web", "working", "shrink it", ""), ("api", "idle", "", "")]) // asked again: a fresh api, no card until it works
        #expect(r.model.rail.map(\.name) == ["web"])
        r.board([("web", "working", "shrink it", ""), ("api", "working", "again", "Bash npm test")])
        #expect(r.model.rail.map(\.name) == ["web", "api"])
    }

    @Test func theBarSaysOneOfItsSevenWords() {
        let r = Rig()
        #expect(r.model.capsule == .listening && r.model.greeting == CallModel.hi) // on the screen from the start, not said
        r.voice("On it.")
        #expect(r.model.capsule == .speaking && r.model.greeting == nil) // the first words: the chat takes over
        r.host.turns.setMuted(true); r.model.update()
        #expect(r.model.capsule == .muted)
        r.model.deaf = .microphone; r.model.update()
        #expect(r.model.capsule == .micBlocked && r.model.micNote?.hasSuffix("then press Allow.") == true)
        r.model.stage = .failed(.stopped); r.model.update()
        #expect(r.model.capsule == .lost)
    }

    @Test func voicesAreGroupedAndNamedAsThePageDoes() {
        let g = voiceGroups(["bm_george", "af_bella", "am_michael", "af_heart", "zz_other", "bf_emma"])
        #expect(g.map(\.title) == ["US female", "US male", "British female", "British male", "Other"])
        #expect(g[0].voices.map(\.title) == ["Bella", "Heart"])
        #expect(g[4].voices.map(\.name) == ["zz_other"])
        #expect(niceName("af_heart") == "Heart")
    }

    @Test func theChosenVoiceIsRememberedAndSaysSoAtOnce() {
        let d = UserDefaults(suiteName: "callkit-test-\(UUID())")!
        let r = Rig(); r.host.turns.voiceName = "af_heart"
        r.model.choose("am_michael", defaults: d)
        #expect(r.host.turns.voiceName == "am_michael" && d.string(forKey: CallModel.voiceKey) == "am_michael")
        #expect(r.paths == ["/hush"]) // cut off whatever was playing, then "This is how I sound now."
        let next = Rig(); next.model.remember(defaults: d)
        #expect(next.host.turns.voiceName == "am_michael")
        let gone = Rig(voices: ["af_heart"]); gone.model.remember(defaults: d) // a remembered voice the server lacks falls back, as setVoices does
        gone.send(["type": "voices", "names": ["af_heart"]])
        #expect(gone.host.turns.voiceName == "af_heart")
    }

    @Test func approvalsStandInLineAndEachSaysHowItCanBeAnswered() {
        let r = Rig()
        r.board([("api", "waiting", "t", ""), ("web", "waiting", "t", "")])
        r.send(["type": "ask", "id": "a1", "detail": "api: Bash git commit -am x", "worker": "api", "voice": true, "full": "git commit -am x"])
        r.send(["type": "ask", "id": "a2", "detail": "web: Bash npm install left-pad", "worker": "web", "voice": false, "full": "npm install left-pad"])
        r.send(["type": "ask", "id": "a1", "detail": "api: Bash git commit -am x", "worker": "api", "voice": true]) // sent again on reconnect
        #expect(r.model.cards.map(\.ask.worker) == ["api", "web"])
        #expect(r.model.cards[0].ask.question == "Commit these changes?" && r.model.cards[0].exact == "git commit -am x")
        #expect(r.model.cards.map(\.armed) == [false, false])
        // the voice asks the oldest; its sentence says a spoken yes will do, and when it ends the yes counts
        r.send(["type": "say", "text": "api wants to run git commit. Should it go ahead?"])
        #expect(!r.model.cards[0].armed)
        r.send(["type": "turn_end", "ask": "a1"]) // the whole question is sent, but still to be played
        #expect(!r.model.cards[0].armed)
        r.host.run([["k": "wait", "t": 1000.0]]); r.model.update() // it has played: now a yes counts
        #expect(r.model.cards[0].armed)
        // click: Approve a1 -> POST /permit once, busy until the server's "asked" (or the post failing)
        r.model.answer("a1", allow: true); r.model.answer("a1", allow: true)
        #expect(r.sent.filter { $0.0 == "/permit" }.count == 1 && r.sent.last!.1["id"] as? String == "a1" && r.sent.last!.1["allow"] as? Bool == true)
        #expect(r.model.cards[0].busy)
        r.model.answerFailed("a1")
        #expect(!r.model.cards[0].busy && r.model.cards[0].failed)
        r.send(["type": "asked", "id": "a1", "allow": true, "by": "voice"])
        #expect(r.model.cards.map(\.ask.id) == ["a2"] && !r.model.cards[0].armed)
        #expect(r.model.confirmation?.allow == true && r.announced.last == "Approved by voice") // for 0.8 s
        r.clock += 1; r.model.update()
        #expect(r.model.confirmation == nil && r.host.turns.armed("a1") == false) // a yes no longer means that step
    }

    @Test func eachCardSaysHowItCanBeAnsweredNowAsThePageDoes() {
        let r = Rig()
        r.send(["type": "ask", "id": "a1", "detail": "Bash git commit -am x", "worker": "api", "voice": true, "full": "git commit -am x", "step": "run git commit"])
        #expect(r.model.cards.map(\.place) == [""] && r.model.cards[0].hint == .again) // one open: no "1 of 1"; a yes now makes it ask once more
        r.send(["type": "ask", "id": "a2", "detail": "Bash git status", "worker": "api", "voice": true, "full": "git status"])
        r.send(["type": "ask", "id": "a3", "detail": "Bash rm -rf x", "worker": "api", "voice": false, "full": "rm -rf x"])
        #expect(r.model.cards.map(\.place) == ["1 of 3", "2 of 3", "3 of 3"])
        #expect(r.model.cards.map(\.hint) == [.again, .next, .next]) // only the oldest is asked aloud: a yes cannot answer the rest
        r.voice("It wants to run git commit. Should it go ahead?")
        #expect(r.model.cards[0].hint == .asking)
        r.send(["type": "turn_end", "ask": "a1"]); r.host.finish(); r.host.run([["k": "wait", "t": r.host.clock + 300]]); r.model.update() // it has played
        #expect(r.model.cards[0].hint == .armed)
        r.model.answer("a1", allow: true); r.model.answerFailed("a1")
        #expect(r.model.cards[0].hint == .failed)
        r.send(["type": "asked", "id": "a1", "allow": true, "by": "voice"]); r.send(["type": "asked", "id": "a2", "allow": true])
        #expect(r.model.cards.map(\.place) == [""] && r.model.cards[0].hint == .click)
    }

    @Test func everyAnsweredApprovalStaysInTalkWhereItHappened() {
        let r = Rig()
        r.send(["type": "ask", "id": "a1", "detail": "Edit /Users/you/Lab/api/src/a.js", "worker": "api", "voice": true, "full": "/Users/you/Lab/api/src/a.js"])
        r.send(["type": "ask", "id": "a2", "detail": "Bash rm -rf x", "worker": "api", "voice": false, "full": "rm -rf x"])
        r.send(["type": "asked", "id": "a1", "allow": true, "by": "voice"])
        r.voice("Approved.")
        r.send(["type": "asked", "id": "a2", "allow": false]) // a click, or Stop
        r.send(["type": "asked", "id": "a2", "allow": false]) // an answer to nothing open is not kept
        #expect(r.model.answered == [Answered(allow: true, byVoice: true, exact: "src/a.js", after: 0),
                                     Answered(allow: false, byVoice: false, exact: "rm -rf x", after: r.model.lines.count)])
        #expect(r.model.lines.count == 1)
    }

    @Test func aRequestThatNeedsAClickBringsTheWindowForwardAndASpokenYesDoesNot() {
        let r = Rig()
        r.send(["type": "ask", "id": "a1", "detail": "Bash ls", "worker": "api", "voice": true])
        #expect(r.fronted == 0 && r.announced.last!.hasPrefix("Claude Code needs your answer"))
        r.send(["type": "ask", "id": "a2", "detail": "Bash rm -rf x", "worker": "api", "voice": false])
        #expect(r.fronted == 1)
    }

    @Test func aSpokenYesCountsOnlyOnceTheQuestionHasFinished() {
        let r = Rig()
        r.board([("api", "waiting", "t", "")])
        r.send(["type": "ask", "id": "a1", "detail": "Bash ls", "worker": "api", "voice": true])
        r.send(["type": "turn_end", "ask": "a1"]) // nothing playing: it counts at once
        #expect(r.host.turns.armed("a1") && r.model.cards[0].armed)
        r.host.clock += r.host.turns.ASK_FOR_MS + 1; r.model.update()
        #expect(!r.host.turns.armed("a1") && !r.model.cards[0].armed) // 20 s on, it no longer does
    }

    @Test func aFilePathIsShownRelativeToItsProject() {
        let r = Rig()
        r.send(["type": "ask", "id": "a1", "detail": "Edit /Users/you/Lab/api/src/a.js", "worker": "api", "voice": true, "full": "/Users/you/Lab/api/src/a.js"])
        r.send(["type": "ask", "id": "a2", "detail": "Edit /Users/you/Lab/web/b.js", "worker": "web", "voice": true, "full": "/Users/you/Lab/web/b.js"])
        #expect(r.model.cards.map(\.exact) == ["src/a.js", "b.js"])
    }

    @Test func theWorkGroupAppearsWithTheFirstWorkAndStepsChangeAtMostEverySixTenthsOfASecond() {
        let r = Rig()
        r.board([("api", "idle", "", "")])
        #expect(!r.model.hasWork && r.model.steps["api"] == "Ready when you are.")
        r.clock += 1; r.board([("api", "working", "fix the tests", "Bash npm test")])
        #expect(r.model.hasWork && r.model.steps["api"] == "Running the tests")
        r.board([("api", "working", "fix the tests", "Edit src/a.js")]) // too soon
        #expect(r.model.steps["api"] == "Running the tests")
        r.clock += 0.7; r.model.update()
        #expect(r.model.steps["api"] == "Editing a.js")
        r.board([("api", "waiting", "fix the tests", "")]); r.clock += 1; r.model.update()
        #expect(r.model.steps["api"] == "" && r.model.status.working)
        r.board([("api", "idle", "", "")]); r.clock += 1; r.model.update()
        #expect(r.model.hasWork && r.model.steps["api"] == "Ready when you are." && !r.model.status.working) // the group stays
    }

    @Test func aServerProblemStaysInTheChatWhereItHappened() {
        let r = Rig()
        r.send(["type": "error", "text": "The voice could not answer (error 529). Say it again in a moment."])
        r.send(["type": "turn_end"])
        #expect(r.model.problems == [Problem(text: "I could not answer just then. Say it again in a moment.", after: 0)] && r.model.greeting == nil)
    }

    @Test func settingsLearnEveryVoiceOnceTheEngineIsReady() {
        let r = Rig(); var saw: [String] = []
        r.model.sawVoices = { saw = $0 }
        r.send(["type": "hello", "project": "/p", "voices": [String]()]) // the server says hello before Kokoro is ready
        #expect(saw.isEmpty)
        r.send(["type": "voices", "names": ["af_heart", "am_michael", "bf_emma", "bm_george"]])
        #expect(saw == ["af_heart", "am_michael", "bf_emma", "bm_george"])
    }

    @Test func openInClaudeHandsThatWorkerOverAndItsCardGoesWithTheBoard() {
        let r = Rig()
        r.board([("api", "working", "fix it", "Bash npm test"), ("web", "working", "shrink it", "")])
        r.model.open("api")
        #expect(r.sent.last?.0 == "/open" && r.sent.last?.1["name"] as? String == "api")
        r.board([("web", "working", "shrink it", "")]) // it left the call for the Claude app
        #expect(r.model.rail.map(\.name) == ["web"])
    }

    @Test func aFreshInstallSpeaksWithFableAndAChosenVoiceStays() {
        let r = Rig(), d = UserDefaults(suiteName: "oh-kevin-test-\(UUID().uuidString)")!
        r.model.remember(defaults: d)
        #expect(r.host.turns.voiceName == "bm_fable")
        d.set("af_bella", forKey: CallModel.voiceKey); r.model.remember(defaults: d)
        #expect(r.host.turns.voiceName == "af_bella")
    }

    @Test func theAppsOwnFailuresKeepTheirWords() {
        #expect(Trouble.voiceDidNotLoad.failure.line == "The voice didn’t load.")
        #expect(Trouble.slowStart.failure.line == "Nothing answered for 2 minutes.")
        #expect(Trouble.stopped.failure == Failure.stopped)
    }

    @Test func cardsAndProblemsSpeakTheVoicesOwnWords() {
        #expect(CallModel.question("data wants to delete the old build files. That needs a click on screen.", worker: "data") == "Delete the old build files?")
        #expect(CallModel.question("web wants to push your commits. Shall it go ahead?", worker: "web") == "Push your commits?")
        #expect(CallModel.question("Something else.", worker: "web") == nil)
        #expect(CallModel.done("docs is done. The setup page is rewritten.")! == ("docs", "The setup page is rewritten."))
        #expect(CallModel.firstPerson("The voice could not answer (error 529). Say it again in a moment.") == "I could not answer just then. Say it again in a moment.")
        #expect(CallModel.firstPerson("Claude Code stopped.") == "Claude Code stopped.")
    }

    @Test func whatsNewOpensTheAppsOwnRelease() {
        let feed = "https://github.com/bekhruzbekswe/ohkevin/releases/latest/download/appcast-app.xml"
        #expect(releaseNotesURL(feed: feed, version: "0.2")?.absoluteString == "https://github.com/bekhruzbekswe/ohkevin/releases/tag/app-v0.2")
    }

    @Test func stopOnACardNamesThatWorkerOnly() {
        let r = Rig()
        r.model.stop("web")
        #expect(r.sent.last!.0 == "/stop" && r.sent.last!.1 as? [String: String] == ["name": "web"])
        r.model.stop()
        #expect(r.sent.last!.1.isEmpty) // no name: every worker
    }

    @Test func stopPostsOnceAndItsBannerGoesWithTheNextStop() {
        let r = Rig()
        r.model.stage = .live; r.board([("api", "working", "t", "")])
        r.model.stop()
        #expect(r.sent.last!.0 == "/stop")
        r.model.stopFailed = true; r.model.update()
        #expect(r.model.notes.map(\.text) == ["Stop didn’t go through. Try again."])
        r.model.stop(); r.model.update()
        #expect(r.model.notes.isEmpty)
    }

    @Test func aUsageLimitTheVoiceSaysIsABannerAndNotAConversationLine() {
        let r = Rig()
        r.model.stage = .live
        let warning = "You've used 75 percent of your weekly limit, and it resets on Wednesday at 9 AM."
        r.send(["type": "say", "text": warning]); r.host.turns.began(warning, 2, limit: true); r.send(["type": "turn_end"])
        #expect(r.host.turns.lines.isEmpty && r.model.notes == [Note(text: warning, icon: .gauge, action: nil)])
        let hit = "You've hit your 5-hour limit; it resets at 3 PM."
        r.send(["type": "say", "text": hit]); r.host.turns.began(hit, 2, limit: true); r.send(["type": "turn_end"]) // a newer one replaces it
        #expect(r.model.notes == [Note(text: hit, icon: .warning, action: nil)])
        r.send(["type": "say", "text": "On it."]); r.host.turns.began("On it.", 2)
        #expect(r.host.turns.lines.map(\.text) == ["On it."])
        r.model.stage = .ended; r.model.update()
        #expect(r.model.notes.isEmpty) // the call is over
    }

    @Test func theServersProblemIsABannerUntilTheTurnEnds() {
        let r = Rig()
        r.model.stage = .live
        r.send(["type": "error", "text": "The voice could not answer. (error 529)"])
        #expect(r.model.notes == [Note(text: "The voice could not answer.", icon: .warning, action: nil)])
        r.send(["type": "turn_end"])
        #expect(r.model.notes.isEmpty)
    }

    @Test func theEarsNotListeningShowOneBannerWithItsFix() {
        let r = Rig()
        r.model.stage = .live
        for (why, text, fix) in [(Deaf.recogniser, "Speech recognition stopped.", "Listen Again"), (.device, "The microphone changed.", "Listen Again"),
                                 (.microphone, "Oh Kevin isn’t allowed to use the microphone.", "Open Settings"),
                                 (.speechModel, "Speech recognition needs a download.", "Download"), (.noMicrophone, "No microphone found.", "Listen Again")] {
            r.model.deaf = why; r.model.update()
            #expect(r.model.notes.map(\.text) == [text] && r.model.notes[0].button == fix && r.model.light == .cantHear && r.model.mic == .dim)
        }
    }

    @Test func theWordForTheTurnFollowsTheSpecsTableFirstMatchWins() {
        let r = Rig(), t = r.host.turns
        func word() -> String { r.model.update(); return "\(r.model.word)|\(r.model.sub)" }
        r.model.stage = .failed(.voiceDidNotLoad); #expect(word() == "The call didn’t start|The voice didn’t load.")
        r.model.stage = .failed(.stopped); #expect(word() == "The call stopped|Claude Code’s work so far is saved.")
        r.model.stage = .ending; #expect(word() == "Ending the call…|Claude Code is saving its work.")
        r.model.handing = true; #expect(word() == "Ending the call…|Then its work opens in the Claude app.")
        r.model.stage = .starting; #expect(word() == "Connecting…|The voice is warming up.")
        r.model.stage = .live; #expect(word() == "Listening|Just talk. It answers when you pause.")
        r.model.deaf = .microphone; #expect(word() == "Can’t hear you|Typing still works.")
        r.model.deaf = .device; #expect(word() == "Can’t hear you|")
        r.model.deaf = nil; t.setMuted(true); #expect(word() == "Mic off|Press M to talk again. Typing works." && r.model.mic == .muted)
        t.setMuted(false)
        t.results([Heard("hello there", false)], from: 0); #expect(word() == "Hearing you|" && r.model.ghost == "hello there")
        t.results([Heard("hello there", true)], from: 0); #expect(word() == "Thinking|" && r.model.ghost.isEmpty)
        r.send(["type": "say", "text": "Hi."]); t.began("Hi.", 2); #expect(word() == "Speaking|")
        r.send(["type": "turn_end"]); t.hush(false) // nothing more said, and it has heard something: no hint
        #expect(word() == "Listening|")
        t.turnState = "waiting"; #expect(word() == "Listening|Waiting for the rest of your thought.")
        r.model.stage = .ended; r.model.opened = nil; r.send(["type": "session", "id": "s1", "worker": "api"])
        #expect(word() == "Call ended|Its work is saved in Claude Code.")
        r.model.opened = true; #expect(word() == "Call ended|Its work is open in the Claude app.")
        r.model.opened = false; #expect(word() == "Call ended|That didn’t open. Try again.")
    }

    @Test func sessionsAreKeptOnceEachForTheHandOver() {
        let r = Rig()
        r.send(["type": "session", "id": "s-api", "worker": "api"]); r.send(["type": "session", "id": "s-web", "worker": "web"])
        r.send(["type": "session", "id": "s-api", "worker": "api"]) // sent at the start of every worker turn
        #expect(r.model.sessions == ["s-api", "s-web"])
    }
}

@Suite(.serialized) struct TurnsAdditions {
    @Test func muteTurnsOnlyTheMicrophoneOff() {
        let r = Rig()
        r.host.turns.setMuted(true)
        #expect(r.host.turns.muted)
        r.host.turns.results([Heard("hello", true)], from: 0) // a late result is not heard
        #expect(r.paths.isEmpty && r.host.turns.lines.isEmpty)
        r.host.turns.setMuted(false)
        r.host.turns.results([Heard("hello", true)], from: 0)
        #expect(r.paths == ["/say"] && r.host.turns.heardAny)
        r.host.turns.setMuted(true); r.host.turns.end()
        #expect(!r.host.turns.muted) // End call unmutes, as the page's click does
        r.host.turns.setMuted(true)
        #expect(!r.host.turns.muted) // no call, no mute
    }

    @Test func typingCutsTheVoiceAndGoesAsAFreshTurn() {
        let r = Rig()
        r.host.turns.type("   ")
        #expect(r.paths.isEmpty)
        r.host.turns.type(" run the tests ")
        #expect(r.paths == ["/hush", "/say"] && r.host.posts.last!.body["text"] as? String == "run the tests")
        #expect(r.host.turns.lines.map(\.text) == ["run the tests"] && r.host.turns.thinking)
    }

    @Test func theVoiceLineGrowsAsEachSentenceStartsAndWhatYouNeverHeardStaysFaint() {
        let r = Rig(), t = r.host.turns
        r.send(["type": "say", "text": "One two three four."])
        #expect(t.lines.isEmpty) // asked for, not playing yet: not said
        t.began("One two three four.", 4); t.began("Five six seven eight.", 4)
        #expect(t.lines.map(\.text) == ["One two three four. Five six seven eight."] && t.lines[0].unsaid.isEmpty)
        // held mid-word, half way through the last sentence: the rest is faint; a noise lets it carry on
        t.hold(-20)
        #expect(!t.lines[0].unsaid.isEmpty && t.lines[0].text.hasSuffix(t.lines[0].unsaid) && t.paused)
        t.release()
        #expect(t.lines[0].unsaid.isEmpty && !t.paused)
        // cut off by your words: the rest stays faint for good, and the voice's next words are a new line
        t.hold(-20); t.hush(true)
        #expect(!t.lines[0].unsaid.isEmpty)
        let kept = t.lines[0]
        t.began("Next.", 1)
        #expect(t.lines.count == 2 && t.lines[0] == kept && t.lines[1].text == "Next.")
    }

    @Test func aRecordedCallKeepsItsHangupMuteAndTypingWhenReplayed() {
        let events: [[String: Any]] = [
            ["k": "mic", "t": 1000.0], ["k": "type", "t": 2000.0, "text": "hello there"], ["k": "mute", "t": 3000.0, "on": true],
            ["k": "result", "t": 3500.0, "i": 0, "r": [["ignored while muted", true]]], ["k": "mute", "t": 4000.0, "on": false], ["k": "hangup", "t": 5000.0],
        ]
        let r = Replay(); r.run(events)
        #expect(r.posts.map(\.path) == ["/hush", "/say", "/hush"])
        #expect(r.posts.first { $0.path == "/say" }?.body["text"] as? String == "hello there")
        #expect(r.turns.live == false && r.posts.last!.path == "/hush") // End call hushed
    }
}
