import AppKit
import VoiceCore

/// "Move to Applications": the logic behind the update line's "Move to Applications?" (on by default). Sparkle cannot update an app that
/// runs from its download folder or from a translocated copy, so the line offers the move (VoiceCore's `moveDecisionForRunningApp`,
/// `installApp`, `relaunchCommand`); ignoring it means not now, and it asks again at the next start.
@MainActor
public enum AppMover {
    /// On unless switched off: the UserDefaults key `moveToApplications` set to false, or a build made with `MOVE_TO_APPLICATIONS=0`. Only a
    /// real app bundle is ever offered the move (not a `swift run` binary or a check).
    public static func enabled(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> Bool {
        guard bundle.bundleURL.pathExtension == "app" else { return false }
        if let off = bundle.object(forInfoDictionaryKey: "OKMoveToApplications") as? Bool, !off { return false }
        return defaults.object(forKey: "moveToApplications") as? Bool ?? true
    }

    /// Whether and where from the running app should move; nil while the feature is off.
    public static func decision(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> MoveDecision? {
        enabled(bundle: bundle, defaults: defaults) ? moveDecisionForRunningApp(bundle.bundleURL) : nil
    }

    /// Installs the app from its real place (never a translocated path) into /Applications, or ~/Applications when that cannot be
    /// written, then starts that copy once this one has quit, and quits this one. The original in Downloads is left where it is: this
    /// process still has it open, and a failed move must never have cost the person their only copy; the new copy is the one that
    /// matters. Returns the outcome when the app did not move (nothing to do, off, or failed).
    @discardableResult
    public static func moveAndRelaunch(bundle: Bundle = .main, defaults: UserDefaults = .standard,
                                       terminate: @MainActor () -> Void = { NSApp.terminate(nil) }) -> InstallOutcome? {
        guard case .move(let source)? = decision(bundle: bundle, defaults: defaults) else { return nil }
        let outcome = installApp(from: source)
        switch outcome {
        case .installed(let app), .replacedOlder(let app), .keptExisting(let app):
            let starter = Process()
            starter.executableURL = URL(filePath: "/bin/sh")
            starter.arguments = ["-c", relaunchCommand(waitingFor: ProcessInfo.processInfo.processIdentifier, thenOpen: app)]
            starter.standardInput = FileHandle.nullDevice; starter.standardOutput = FileHandle.nullDevice; starter.standardError = FileHandle.nullDevice
            guard (try? starter.run()) != nil else { return .failed("The new copy could not be started.") }
            terminate()
        case .failed: break
        }
        return outcome
    }
}
