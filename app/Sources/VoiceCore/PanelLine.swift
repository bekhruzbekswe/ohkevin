import Foundation

// The update line: one row inside the panel card, under the last button, after a hairline. A sentence on the left; on the right at most
// one word (marigold when it is the person's move, ink when it is an offer) or, while updating, a thin progress line. It is there only
// when there is something to say, and never during a call. The words are the approved design's (design/updates.html).

public enum LineAction: Equatable, Sendable {
    /// Install the update that was only reported (automatic updating is off).
    case update
    /// Try an update that failed again.
    case retryUpdate
    /// Open the notes of the version just installed.
    case whatsNew
    /// Move the app to Applications.
    case move
}

public struct PanelLine: Equatable, Sendable {
    public struct Word: Equatable, Sendable {
        public var title: String
        /// Marigold: it is the person's move (Update, Try again, Move). Otherwise ink: an offer (What’s new).
        public var isMove: Bool
        public var action: LineAction
    }
    public var text: String
    public var word: Word?
    /// The thin progress line instead of a word: 0...1, or nil when the length is not known.
    public var progress: ProgressLine?

    public enum ProgressLine: Equatable, Sendable { case known(Double), unknown }

    public init(_ text: String, word: Word? = nil, progress: ProgressLine? = nil) { self.text = text; self.word = word; self.progress = progress }
}

public struct UpdateLineInput: Sendable {
    public var state: UpdateState = .idle
    /// "Update automatically" is on.
    public var automatic = true
    /// The app runs outside Applications and the move is on offer.
    public var moveOffered = false
    public var moving = false
    /// A call is starting, running or ending.
    public var inCall = false
    /// The transient line (checking, up to date, could not check) has had its four seconds.
    public var transientGone = false
    public init() {}
}

/// What the line says now, or nil. With automatic updating on, a new version is downloaded and installed by itself (when quiet), so only
/// its result is said (updated, or could not); with it off, the new version is offered and the update's progress shown.
public func updateLine(_ i: UpdateLineInput, product: String = Product.name) -> PanelLine? {
    guard !i.inCall else { return nil }
    if i.moving { return PanelLine("Moving", progress: .unknown) }
    if i.moveOffered { return PanelLine("Move to Applications?", word: .init(title: "Move", isMove: true, action: .move)) }
    switch i.state {
    case .installed(let v): return PanelLine("Updated to \(v).", word: .init(title: "What’s new", isMove: false, action: .whatsNew))
    case .failed: return PanelLine("Couldn’t update.", word: .init(title: "Try again", isMove: true, action: .retryUpdate))
    case .available(let v): return i.automatic ? nil : PanelLine("\(product) \(v) is out.", word: .init(title: "Update", isMove: true, action: .update))
    case .downloading(let p): return i.automatic ? nil : PanelLine("Updating", progress: p.map { .known($0) } ?? .unknown)
    case .readyToInstall, .installing: return i.automatic ? nil : PanelLine("Updating", progress: .known(1))
    case .checking: return i.transientGone ? nil : PanelLine("Checking…")
    case .upToDate: return i.transientGone ? nil : PanelLine("You’re up to date.")
    case .couldNotCheck: return i.transientGone ? nil : PanelLine("Couldn’t check. Try again later.")
    case .idle: return nil
    }
}

/// The page for "What’s new" of a version: GitHub's release page, found from the feed's own address
/// (https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml). Nil for any other feed.
/// The tag follows the feed's name: appcast.xml is tagged v<version>, appcast-<app>.xml is tagged <app>-v<version> (the Mac app's
/// appcast-app.xml → app-v0.3). tagPrefix overrides it.
public func releaseNotesURL(feed: String?, version: String, tagPrefix: String? = nil) -> URL? {
    guard let feed, let url = URL(string: feed), url.host == "github.com" else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 5, parts[2] == "releases", let file = parts.last, file.hasPrefix("appcast"), file.hasSuffix(".xml") else { return nil }
    let app = file.dropFirst("appcast".count).dropLast(".xml".count)
    guard app.isEmpty || app.hasPrefix("-") else { return nil }
    let prefix = tagPrefix ?? (app.isEmpty ? "v" : "\(app.dropFirst())-v")
    return URL(string: "https://github.com/\(parts[0])/\(parts[1])/releases/tag/\(prefix)\(version)")
}
