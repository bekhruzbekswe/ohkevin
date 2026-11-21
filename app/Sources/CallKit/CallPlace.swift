import Foundation
import VoiceCore

/// Where this app's call server runs, and what it runs on. A built app carries call/ in its Resources and runs its own copy of it in
/// Application Support/Claude Voice/Call-App (the launcher's is Call: two apps at different versions never overwrite each other's
/// server); the pinned Node in Runtime and the local voice are shared with the launcher, only read. No repository is needed.
public struct CallPlace: Equatable {
    /// The folder `node server.mjs` runs in.
    public let folder: URL
    /// The app's own call/, copied into `folder` at each check; nil for a developer's folder, which is used as it is.
    public let bundled: URL?
    /// Application Support/Claude Voice: the shared Node (Runtime) and npm cache.
    public let support: URL

    /// The developer override (`OH_KEVIN_CALL_FOLDER` in the environment, or the `DeveloperCallFolder` default; neither is set
    /// by default) wins; then the app's own copy; with neither (`swift run`, no bundle), the repository beside `source`.
    public static func resolve(override: String?, bundled: URL?, home: URL, source: URL) -> CallPlace {
        let support = home.appending(path: "Library/Application Support/\(Product.folder)", directoryHint: .isDirectory)
        if let override, !override.isEmpty { return CallPlace(folder: URL(fileURLWithPath: override, isDirectory: true), bundled: nil, support: support) }
        if let bundled { return CallPlace(folder: support.appending(path: "Call-App", directoryHint: .isDirectory), bundled: bundled, support: support) }
        return CallPlace(folder: source, bundled: nil, support: support)
    }

    /// The app's own copy runs on the shared pinned Node; a developer's folder on the Node a terminal finds.
    public var ownCopy: Bool { bundled != nil }
    public var node: URL { Runtime.node(support: support) }
}
