import Observation
import Sparkle
import VoiceCore

/// Sparkle's user driver, and the updater's delegate, in one: no Sparkle window ever appears. Every callback becomes an `UpdateEvent`
/// (VoiceCore turns events into the `UpdateState` a screen shows), and the choices Sparkle asks for are made here by rule:
/// - an update found while automatic updating is on is downloaded; with it off it is only reported (`available`) and not downloaded
///   until `Updates.install()` is called (the screen to come);
/// - an update that is ready (downloaded and unpacked) is installed by relaunching only when `isQuiet` says so: never mid-call, never
///   with the panel open or in first-run setup. Until then it waits, and installs the moment the app is quiet (`tryInstall`); Sparkle
///   also installs it when the app quits. The app comes back as it was.
@MainActor
public final class UpdateDriver: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    public private(set) var model = UpdateModel()
    public override init() { super.init() }

    /// Called with every new state.
    public var onState: (UpdateState) -> Void = { _ in }
    public var isQuiet: () -> Bool = { false }
    public var automaticDownloads: () -> Bool = { true }
    /// A screen asked for the reported update to be installed: the next update found is downloaded whatever the setting.
    public var wantsInstall = false
    /// What installs the ready update, once.
    private var installNow: (() -> Void)?

    private func apply(_ event: UpdateEvent) {
        let before = model.state
        model.apply(event)
        if model.state != before { onState(model.state) }
    }

    /// Installs the waiting update if the app is quiet now.
    public func tryInstall() {
        guard installNow != nil, isQuiet() else { return }
        let go = installNow
        installNow = nil
        go?()
    }

    // MARK: Found

    /// What Sparkle's "update found" means here (split out of the Sparkle-typed callback so it can be checked without Sparkle's objects).
    public func found(version: String, stage: UpdateStage, informationOnly: Bool, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        apply(.found(version: version, stage: stage))
        if informationOnly { return reply(.dismiss) } // nothing to download or install: only a page to point at
        switch stage {
        case .notDownloaded:
            if automaticDownloads() || wantsInstall { wantsInstall = false; reply(.install) } else { reply(.dismiss) }
        case .downloaded, .installing:
            installNow = { reply(.install) }
            tryInstall()
        }
    }

    // MARK: SPUUserDriver

    public func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, automaticUpdateDownloading: true, sendSystemProfile: false)) // the defaults; nothing about this Mac is sent
    }

    public func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { apply(.checkStarted) }

    public func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let stage: UpdateStage = state.stage == .downloaded ? .downloaded : state.stage == .installing ? .installing : .notDownloaded
        found(version: appcastItem.displayVersionString, stage: stage, informationOnly: appcastItem.isInformationOnlyUpdate, reply: reply)
    }

    public func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    public func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    public func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber).map { Int32(truncating: $0) }
        let onLatest = reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue || reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue
        apply(.notFound(onLatest: onLatest, reason: error.localizedDescription))
        acknowledgement()
    }

    public func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        apply(.error(error.localizedDescription))
        acknowledgement()
    }

    public func showDownloadInitiated(cancellation: @escaping () -> Void) { apply(.downloadStarted) }
    public func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { apply(.expectedLength(expectedContentLength)) }
    public func showDownloadDidReceiveData(ofLength length: UInt64) { apply(.received(length)) }
    public func showDownloadDidStartExtractingUpdate() { apply(.extracting(nil)) }
    public func showExtractionReceivedProgress(_ progress: Double) { apply(.extracting(progress)) }

    public func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        apply(.readyToInstall(version: nil))
        installNow = { reply(.install) }
        tryInstall()
    }

    public func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { apply(.installing) }

    public func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        apply(.installed(version: nil))
        acknowledgement()
    }

    public func dismissUpdateInstallation() {
        installNow = nil
        apply(.dismissed)
    }

    public func showUpdateInFocus() {}

    // MARK: SPUUpdaterDelegate

    /// An update was downloaded in the background and is set to install when the app quits. The app takes charge: it installs (and
    /// relaunches, invisibly) the moment it is quiet, instead of waiting for a quit that a menu-bar app rarely has.
    public nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        struct Handler: @unchecked Sendable { let install: () -> Void } // Sparkle calls this on the main thread, and the block is used there only
        let version = item.displayVersionString, handler = Handler(install: immediateInstallHandler)
        MainActor.assumeIsolated {
            apply(.readyToInstall(version: version))
            installNow = handler.install
            tryInstall()
        }
        return true
    }
}

/// Self-updating (Sparkle 2): checks once a day, downloads and installs by itself unless the person turned that off, and offers
/// "Check for Updates…" in the corner menu. It exists only when the host bundle has a feed and a public key (build.sh: FEED_URL,
/// SPARKLE_PUBLIC_KEY, which land in Info.plist as SUFeedURL and SUPublicEDKey); without them there is no updater, no menu item and
/// no error. Updates are verified by their EdDSA signature against that key; the app keeps its own code-signing identity, so macOS keeps
/// its permissions across an update. Sparkle shows no window of its own: `state` is what a screen can show.
///
/// What the host supplies: its `bundle` (feed, key, version are read from it), the `defaults` that remember the last run's version, and
/// `isQuiet`, the host's "nothing is going on" rule, which gates installing; the host calls `tryInstall()` whenever that may have changed.
@MainActor @Observable
public final class Updates {
    public private(set) var state = UpdateState.idle
    /// Called after `state` changes (the host times the transient lines by it).
    @ObservationIgnored public var onChange: () -> Void = {}
    /// "Update automatically": Sparkle's own setting (kept in the user's defaults; on unless the person switches it off).
    public var automatic: Bool { didSet { updater?.automaticallyDownloadsUpdates = automatic } }
    /// The host's quiet rule: an update that is ready installs (and relaunches) only when this is true.
    @ObservationIgnored public var isQuiet: () -> Bool {
        get { driver.isQuiet }
        set { driver.isQuiet = newValue }
    }

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored public let driver: UpdateDriver

    /// Whether this bundle can update itself (has a feed and a public key).
    public static func configured(_ bundle: Bundle = .main) -> Bool {
        (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String).map { !$0.isEmpty } == true
            && (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).map { !$0.isEmpty } == true
    }

    /// `enabled` defaults to whether `bundle` is configured; false makes an inert `Updates` (no updater, state stays idle).
    public init(bundle: Bundle = .main, defaults: UserDefaults = .standard, enabled: Bool? = nil) {
        driver = UpdateDriver()
        automatic = true
        guard enabled ?? Updates.configured(bundle) else { return }
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: driver)
        guard (try? updater.start()) != nil else { return } // a build with a damaged feed or key setting: no updater rather than a broken one
        self.updater = updater
        automatic = updater.automaticallyDownloadsUpdates
        driver.automaticDownloads = { [weak updater] in updater?.automaticallyDownloadsUpdates ?? true }
        driver.onState = { [weak self] in self?.state = $0; self?.onChange() }
        // The first start after an update: it was updated, once (until the panel has been seen and closed).
        let current = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        if let last = defaults.string(forKey: "lastRunVersion"), last != current { state = .installed(current) }
        defaults.set(current, forKey: "lastRunVersion")
    }

    public var available: Bool { updater != nil }

    /// "Updated to …" is said once: the panel was shown and closed.
    public func acknowledgeInstalled() { if case .installed = state { state = .idle; onChange() } }

    public func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    /// Installs an update that was only reported (automatic updating off).
    public func install() {
        driver.wantsInstall = true
        checkForUpdates()
    }

    /// The app became quiet (or something else changed): an update waiting for a quiet moment installs now.
    public func tryInstall() { driver.tryInstall() }
}
