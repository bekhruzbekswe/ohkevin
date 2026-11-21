import Foundation

// Self-updating, as plain data. Sparkle's user driver (LauncherKit) turns each of its callbacks into an `UpdateEvent`; this file turns
// events into the `UpdateState` a screen can show, and decides when it is quiet enough to install by relaunching. No Sparkle here, so
// both are tested without it and Track B's app can share them.

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    /// The feed could not be read (offline, a private feed, a damaged one), or no update fits this Mac.
    case couldNotCheck(String)
    /// A newer version exists and has not been downloaded (automatic updating is off).
    case available(String)
    /// Downloading or unpacking: 0...1, or nil while the size is unknown.
    case downloading(Double?)
    /// Downloaded and unpacked: it installs when the app is quiet (or when the app next quits).
    case readyToInstall(String)
    case installing
    case installed(String)
    /// Something went wrong after the person (or a schedule) had started an update: the download, the signature, the install.
    case failed(String)
}

public enum UpdateStage: Equatable, Sendable { case notDownloaded, downloaded, installing }

public enum UpdateEvent: Equatable, Sendable {
    case checkStarted
    case found(version: String, stage: UpdateStage)
    case notFound(onLatest: Bool, reason: String)
    case error(String)
    case downloadStarted
    case expectedLength(UInt64)
    case received(UInt64)
    case extracting(Double?)
    /// `version` nil: the update already announced.
    case readyToInstall(version: String?)
    case installing
    case installed(version: String?)
    /// Sparkle tears its session down.
    case dismissed
}

/// The state a series of events leads to. Terminal results (up to date, could not check, available, ready, installed, failed) survive
/// the teardown that follows them, so a screen can still say them; only work in progress is cleared by it.
public struct UpdateModel: Equatable, Sendable {
    public private(set) var state = UpdateState.idle
    private var version = "", expected: UInt64 = 0, received: UInt64 = 0

    public init() {}

    public mutating func apply(_ event: UpdateEvent) {
        switch event {
        case .checkStarted:
            if state != .installing { state = .checking }
        case .found(let v, let stage):
            version = v
            state = stage == .notDownloaded ? .available(v) : stage == .downloaded ? .readyToInstall(v) : .installing
        case .notFound(let onLatest, let reason):
            state = onLatest ? .upToDate : .couldNotCheck(reason)
        case .error(let message):
            state = state == .checking ? .couldNotCheck(message) : .failed(message) // an error while looking is "could not check"; later it is a failure
        case .downloadStarted:
            expected = 0; received = 0; state = .downloading(0)
        case .expectedLength(let n):
            expected = n
            if case .downloading = state { state = .downloading(progress) }
        case .received(let n):
            received += n; state = .downloading(progress)
        case .extracting(let p):
            state = .downloading(p)
        case .readyToInstall(let v):
            if let v { version = v }
            state = .readyToInstall(version)
        case .installing:
            state = .installing
        case .installed(let v):
            if let v { version = v }
            state = .installed(version)
        case .dismissed:
            if state == .checking { state = .idle } else if case .downloading = state { state = .idle }
        }
    }

    private var progress: Double? { expected > 0 ? min(1, Double(received) / Double(expected)) : nil }
}

/// Whether an update may relaunch the app now: no call running (starting or ending counts), the panel closed, and not in first-run setup.
/// An update never starts mid-call, and one waiting for a quiet moment installs the moment this becomes true.
public func updateIsQuiet(phase: Phase, panelOpen: Bool, inSetup: Bool) -> Bool {
    guard !panelOpen, !inSetup else { return false }
    switch phase {
    case .idle, .ended, .failed: return true
    case .starting, .live, .ending: return false
    }
}
