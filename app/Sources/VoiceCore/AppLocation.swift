import Foundation

// Where the app is running from, and what moving it to Applications takes. Sparkle cannot update an app that runs from its download
// folder or from a translocated copy (Gatekeeper's randomised read-only path), so the app should live in /Applications. This file is the
// logic only (no UI, off by default in the launcher): the decision from a path, finding the original of a translocated app, the move
// itself, and the command that starts the new copy once this one has quit. All of it is Foundation, so any app can share it.

public enum Applications {
    public static let system = URL(filePath: "/Applications", directoryHint: .isDirectory)
    public static func user(home: URL = .homeDirectory) -> URL { home.appending(path: "Applications", directoryHint: .isDirectory) }
    /// Where an app may be installed, in order of preference.
    public static func folders(home: URL = .homeDirectory) -> [URL] { [system, user(home: home)] }
}

public enum MoveDecision: Equatable, Sendable {
    /// Already in an Applications folder, not translocated.
    case stay
    /// Outside one, or translocated: `source` is where the app really is (never the translocated copy).
    case move(source: URL)
    /// Translocated and its original could not be found: it cannot be copied from anywhere known.
    case unknownOriginal
}

/// A translocated app runs from a path under .../AppTranslocation/<random>/d/.
public func looksTranslocated(_ bundle: URL) -> Bool { bundle.path.contains("/AppTranslocation/") }

/// The pure decision. `original` is what `translocationOriginal` found for a translocated app (nil when it is not translocated, or the
/// original is unknown).
public func moveDecision(bundle: URL, original: URL?, folders: [URL] = Applications.folders()) -> MoveDecision {
    if original != nil || looksTranslocated(bundle) { return original.map { .move(source: $0) } ?? .unknownOriginal }
    let parent = bundle.standardizedFileURL.deletingLastPathComponent().path
    return folders.contains { parent == $0.standardizedFileURL.path || parent.hasPrefix($0.standardizedFileURL.path + "/") } ? .stay : .move(source: bundle)
}

/// Whether macOS runs this bundle translocated, and if so where it really is: Security's SecTranslocate calls, loaded by name (the
/// Command Line Tools' SDK does not declare them). Falls back to the path when the symbols are not there.
public func translocationOriginal(of bundle: URL) -> (translocated: Bool, original: URL?) {
    typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<DarwinBoolean>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
    typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
    guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
          let isSym = dlsym(handle, "SecTranslocateIsTranslocatedURL"), let originalSym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
    else { return (looksTranslocated(bundle), nil) }
    var translocated: DarwinBoolean = false
    guard unsafeBitCast(isSym, to: IsTranslocated.self)(bundle as CFURL, &translocated, nil) else { return (looksTranslocated(bundle), nil) }
    guard translocated.boolValue else { return (false, nil) }
    let original = unsafeBitCast(originalSym, to: Original.self)(bundle as CFURL, nil)?.takeRetainedValue() as URL?
    return (true, original)
}

/// The whole detection for the running app.
public func moveDecisionForRunningApp(_ bundle: URL = Bundle.main.bundleURL, folders: [URL] = Applications.folders()) -> MoveDecision {
    let found = translocationOriginal(of: bundle)
    return moveDecision(bundle: bundle, original: found.translocated ? found.original : nil, folders: folders)
}

public enum InstallOutcome: Equatable, Sendable {
    /// A copy was made at `URL` (none was there).
    case installed(URL)
    /// An older copy was replaced, whole, by this one.
    case replacedOlder(URL)
    /// A copy as new or newer is already there: it is the one to start, nothing was written.
    case keptExisting(URL)
    /// No folder could be written to (or the copy failed): the message says why.
    case failed(String)
}

private func buildNumber(_ app: URL) -> Int? {
    guard let plist = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) else { return nil }
    return (plist["CFBundleVersion"] as? String).flatMap { Int($0) }
}

/// Installs `source` (the app's real place, never a translocated path) into the first of `folders` that can be written, as
/// "<name>.app". An existing copy is replaced only when this one has the higher CFBundleVersion; otherwise it is kept (and is what the
/// caller starts). The copy is made beside its destination under a hidden name and then swapped in whole (`replaceItemAt`, or a
/// rename), so a failure never leaves half an app where the app should be; extended attributes (the quarantine mark macOS set) are
/// copied with it, not stripped. The first folder that cannot be written is skipped: with /Applications first and ~/Applications second,
/// a standard user's app lands in their own Applications. (A privileged copy into /Applications needs the system's authorization
/// dialog, which the Command Line Tools offer no clean way to ask for; this falls back instead.)
public func installApp(from source: URL, into folders: [URL] = Applications.folders()) -> InstallOutcome {
    let fm = FileManager.default
    var last = "no folder to install into"
    for folder in folders {
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        guard fm.isWritableFile(atPath: folder.path) else { last = "\(folder.path) cannot be written"; continue }
        let name = source.lastPathComponent, dest = folder.appending(path: name), staging = folder.appending(path: ".\(name).new")
        let exists = fm.fileExists(atPath: dest.path)
        if exists, let have = buildNumber(dest), let mine = buildNumber(source), mine <= have { return .keptExisting(dest) }
        try? fm.removeItem(at: staging)
        do {
            try fm.copyItem(at: source, to: staging)
            if exists { _ = try fm.replaceItemAt(dest, withItemAt: staging) } else { try fm.moveItem(at: staging, to: dest) }
            return exists ? .replacedOlder(dest) : .installed(dest)
        } catch {
            try? fm.removeItem(at: staging)
            last = "\(name) could not be copied to \(folder.path): \(error.localizedDescription)"
        }
    }
    return .failed(last)
}

/// A shell command that waits for the running app (`pid`) to quit and then starts `app`: the new copy cannot start while this one
/// runs (the app allows one instance), so it is started from a process that outlives it. Run it with /bin/sh -c.
public func relaunchCommand(waitingFor pid: Int32, thenOpen app: URL) -> String {
    let path = app.path.replacingOccurrences(of: "'", with: "'\\''")
    return "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open '\(path)'"
}
