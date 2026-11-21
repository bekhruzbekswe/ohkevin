import AVFoundation

/// Every number the native app chose itself, with the reason for it. The turn-taking numbers are not here: they are the
/// page's, in Ears.TUNE, and must equal call/ears.mjs (a test reads that file).
enum NativeTune {
    /// The problem sound, as the call page plays it: low (gain 0.3, for the owner's ear), and silent for the same line again within 5 s.
    static let problemGain: Float = 0.3
    static let sameProblemSeconds = 5.0
    /// The app's own clock: what the microphone delivered goes to the recogniser and to the level, this often. The page reads
    /// its analyser every 20 ms; the recogniser and its quiet rule below are fed at the same rate.
    static let tickMs = 20

    // ── ending an utterance (Recognizer.swift) ──
    /// Chrome's recogniser decides itself when you have finished; Apple's dictation model waits 2 to 3.7 s (measured). So the
    /// app finalises once no new words have come AND the microphone has been quiet for this long. Both, because Apple's words
    /// arrive in bursts up to 0.7 s behind the audio, and a quiet room says nothing about a word still being worked out. 0
    /// leaves it to Apple, for measuring that too: ENDPOINT_MS=0.
    static let endpointMs = Double(ProcessInfo.processInfo.environment["ENDPOINT_MS"] ?? "") ?? 700
    /// "Quiet" is under this level (the test files' own floor), or within quietAboveRoomDb of the room's floor when that is
    /// higher: voice processing has gain control, so a room may never read as quiet as the test files.
    static let quietDb = -45.0, quietAboveRoomDb = 10.0
    /// The room's floor is the quieter fifth of the last 3 s of ticks: deaf to a moment's dip, quick to follow a change.
    static let roomSeconds = 3.0, roomQuantile = 5
    static var roomTicks: Int { Int(roomSeconds * 1000) / tickMs }
    /// EARS=speech or EARS=dictation picks one recogniser, for measuring both.
    static let ears = ProcessInfo.processInfo.environment["EARS"]

    // ── the level the gate reads while the voice talks (Call.tick) ──
    /// The page's analyser: 1024 samples at 48 kHz (fftSize 1024), taken from the end of the ring at whatever its real rate is.
    static let levelSamples = 1024, levelRate = 48000.0
    /// Seconds of microphone the ring holds: far more than a tick ever takes, and the 1024-sample window above.
    static let ringSeconds = 2.0

    // ── starting (Call.start, Server.listen) ──
    /// Kokoro warms up slowly on a busy Mac, and slow is not broken: wait this long for the server and its voice.
    static let startWaitSeconds = 120.0
    /// How often the event stream is tried again while the server is still starting.
    static let retryMs = 200
    /// A dropped stream is tried again this long before the call is lost (the page's 15 s).
    static let reconnectSeconds = 15.0
    /// The server's hand-over at hang-up (each worker's session opened in the Claude app) is given this long.
    static let handOverSeconds = 90.0
    static var retries: Int { Int(startWaitSeconds * 1000) / retryMs }

    // ── the audio engine (Sound.swift) ──
    /// Voice processing turns other apps' sound down while it runs. The least ducking (no advanced ducking, level .min) leaves
    /// what else is playing (music, a video) nearly as loud; the call's own voice is not affected. Whether it changes the echo
    /// canceller's work was not measured: it needs speakers and a live call.
    static let ducking = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
}
