import Foundation
import Speech
import CallKit
import VoiceCore

/// The download that starts by itself at launch (design/onboarding.html): everything a call runs on that this Mac does not
/// have yet, behind one bar. Its parts, in order: Node's program and the Agent SDK the server imports (installRuntime), the local voice
/// (installKokoro into Application Support/Claude Voice/Kokoro), Apple's English speech model (AssetInventory). A part this Mac
/// already has is left out, and the bar is over what is left, by size.
@Observable final class Download {
    enum Part: String { case runtime, voice, speech }
    /// What this Mac still needs, in order; empty once all is there. Nil until the first look.
    private(set) var parts: [Part]?
    /// 0…1 over all the parts this run started with, by their size.
    private(set) var fraction = 0.0
    private(set) var running = false
    /// This run's parts, all of them, and how far each is (0…1): the setup screen's parts.
    private(set) var planned: [Part] = []
    private(set) var progress: [Part: Double] = [:]
    /// The part that did not install; a press on the setup's button tries again.
    private(set) var failed: Part?
    var done: Bool { parts?.isEmpty == true }

    @ObservationIgnored private let place: CallPlace
    /// Also ask Spotlight for a voice installed elsewhere (as the call does); off only for a clean-Mac check (--check-call --no-spotlight).
    @ObservationIgnored var spotlight = true
    /// The app's own kokoro-runner (Contents/Helpers): the voice without Python. AppChecks --check-call points it at a built app.
    @ObservationIgnored var runner = bundledRunner()
    @ObservationIgnored private let home = FileManager.default.homeDirectoryForCurrentUser
    init(place: CallPlace) { self.place = place }

    /// What each part adds on disk, measured on this Mac (MB): what the bar is measured against.
    static let size: [Part: Double] = [.runtime: 117, .voice: 380, .speech: 150] // runtime: Node's program and the Agent SDK
    var kokoroFolder: URL { CallSettings.defaultKokoro(home: home) }

    /// Runs what is missing, one part after the other; `done` on the main queue, with whether all of it is there now.
    func start(environment env: [String: String], _ finished: @escaping (Bool) -> Void = { _ in }) {
        guard !running else { return }
        running = true; failed = nil; fraction = 0
        Task.detached { [self] in
            let need = await needed(env)
            await MainActor.run { parts = need; planned = need; progress = [:] }
            let total = need.reduce(0) { $0 + Self.size[$1]! }
            var before = 0.0
            for part in need {
                let weight = Self.size[part]! / max(total, 1), base = before
                let ok = await run(part, env) { f in
                    DispatchQueue.main.async { // never back: an unpack moves files away
                        self.progress[part] = max(self.progress[part] ?? 0, min(f, 1)); self.fraction = max(self.fraction, base + min(f, 1) * weight)
                    }
                }
                guard ok else { await MainActor.run { failed = part; running = false; finished(false) }; return }
                before += weight
                let reached = before
                await MainActor.run { fraction = reached; progress[part] = 1; parts?.removeAll { $0 == part } }
            }
            await MainActor.run { fraction = 1; running = false; finished(true) }
        }
    }

    /// What is not on this Mac yet. A developer's call folder is the developer's to install.
    func needed(_ env: [String: String]) async -> [Part] {
        var out: [Part] = []
        if place.ownCopy {
            if let bundled = place.bundled { syncCall(from: bundled, to: place.folder) }
            if !FileManager.default.isExecutableFile(atPath: place.node.path) || !packagesCurrent(callFolder: place.folder, locked: true) { out.append(.runtime) }
        }
        // where the call looks for it (Server.start): a voice installed anywhere it looks is used, never downloaded again
        if findKokoro(kokoroPlaces(saved: nil, shell: env, home: home, project: nil), spotlight: spotlight ? spotlightKokoro : { [] }) == nil { out.append(.voice) }
        if !(await Self.hasSpeechModel()) { out.append(.speech) }
        return out
    }

    private func run(_ part: Part, _ env: [String: String], progress: @escaping (Double) -> Void) async -> Bool {
        switch part {
        case .runtime:
            let watch = Self.watch([Runtime.folder(support: place.support).deletingLastPathComponent(), place.folder.appending(path: "node_modules")],
                                   megabytes: Self.size[.runtime]!, progress)
            defer { watch.cancel() }
            return await installRuntime(support: place.support, callFolder: place.folder, bundledCall: place.bundled, environment: env)
        case .voice:
            let watch = Self.watch([kokoroFolder], megabytes: Self.size[.voice]!, progress)
            defer { watch.cancel() }
            return await installKokoro(into: kokoroFolder, callFolder: place.folder, environment: env, runner: runner) // no Python when the app carries the runner
        case .speech:
            return await Self.installSpeechModel(progress)
        }
    }

    // MARK: Apple's speech model

    /// Either English model the recogniser can use (Recognizer.make): the newer one or the dictation one macOS often already has.
    static func hasSpeechModel() async -> Bool {
        let en = { (l: [Locale]) in l.contains { $0.identifier(.bcp47) == "en-US" } }
        if en(await SpeechTranscriber.installedLocales) { return true }
        return en(await DictationTranscriber.installedLocales)
    }
    /// Apple downloads the newer English model; its own progress drives the bar.
    static func installSpeechModel(_ progress: @escaping (Double) -> Void) async -> Bool {
        let module = SpeechTranscriber(locale: Locale(identifier: "en-US"), preset: .progressiveTranscription)
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return true }
            let watch = request.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            defer { watch.invalidate() }
            try await request.downloadAndInstall()
            return true
        } catch { return false }
    }

    // MARK: Progress of an install that does not report its own

    /// The folders' growth against what the part adds, every half second, never past 95% until it is done.
    /// shortcut: a size estimate (measured once on this Mac), not the installers' own progress; good enough for one bar.
    static func watch(_ folders: [URL], megabytes: Double, _ progress: @escaping (Double) -> Void) -> Task<Void, Never> {
        let start = folders.reduce(0) { $0 + size(of: $1) }
        return Task.detached {
            while !Task.isCancelled {
                let grown = Double(folders.reduce(0) { $0 + size(of: $1) } - start) / 1_048_576
                progress(min(max(grown / megabytes, 0), 0.95))
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    static func size(of folder: URL) -> Int {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in e { total += (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0 }
        return total
    }
}

extension Download {
    /// The setup screen's parts (SetupInput.Part): this run's, each with its progress and size. Before the first look, one part
    /// that cannot say how far it is (the bar slides); none for a developer's own call folder, which is never downloaded.
    func setupParts(ownCopy: Bool) -> [SetupInput.Part] {
        guard ownCopy else { return [] }
        if parts == nil { return [.init("Download")] }
        let names: [Part: String] = [.runtime: "Node and the call", .voice: "Kevin’s voice", .speech: "Speech recognition"]
        return planned.map { .init(names[$0]!, progress: progress[$0] ?? 0, weight: Self.size[$0]!, failed: failed == $0) }
    }
}
