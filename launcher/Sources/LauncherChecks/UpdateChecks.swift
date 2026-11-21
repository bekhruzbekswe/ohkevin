import Foundation
import Sparkle
import Updating
import VoiceCore

/// The update driver, worked without Sparkle's own objects (it cannot be given an appcast to find): each callback it can be given by
/// hand becomes the state a screen would show, and the quiet rule gates the install. Run inside `--snapshots` (offscreen, no window).
@MainActor
enum UpdateChecks {
    static func run() -> [String] {
        var problems: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { problems.append("UPDATE \(what)") } }
        let driver = UpdateDriver()
        var states: [UpdateState] = []
        driver.onState = { states.append($0) }
        var quiet = false, automatic = true
        driver.isQuiet = { quiet }; driver.automaticDownloads = { automatic }

        // A check by hand that finds nothing.
        driver.showUserInitiatedUpdateCheck {}
        driver.showUpdateNotFoundWithError(NSError(domain: SUSparkleErrorDomain, code: 1001, userInfo: [SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.onLatestVersion.rawValue)]), acknowledgement: {})
        driver.dismissUpdateInstallation()
        check(states == [.checking, .upToDate], "a check that finds nothing says up to date: \(states)")
        // One that cannot read the feed.
        states = []
        driver.showUserInitiatedUpdateCheck {}
        driver.showUpdaterError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "offline"]), acknowledgement: {})
        driver.dismissUpdateInstallation()
        check(states == [.checking, .couldNotCheck("offline")], "an error while looking is could-not-check: \(states)")
        // Automatic updating on: an update found is downloaded; off: only reported, until a screen asks for it.
        var choices: [SPUUserUpdateChoice] = []
        states = []
        driver.found(version: "0.3", stage: .notDownloaded, informationOnly: false) { choices.append($0) }
        check(choices == [.install] && states == [.available("0.3")], "automatic on: found is downloaded: \(choices) \(states)")
        automatic = false; choices = []
        driver.found(version: "0.3", stage: .notDownloaded, informationOnly: false) { choices.append($0) }
        check(choices == [.dismiss], "automatic off: found is only reported")
        driver.wantsInstall = true; choices = []
        driver.found(version: "0.3", stage: .notDownloaded, informationOnly: false) { choices.append($0) }
        check(choices == [.install] && !driver.wantsInstall, "a screen asked: found is downloaded once")
        choices = []
        driver.found(version: "0.3", stage: .notDownloaded, informationOnly: true) { choices.append($0) }
        check(choices == [.dismiss], "an information-only update is never installed")
        // The download, whole.
        states = []
        driver.showDownloadInitiated {}; driver.showDownloadDidReceiveExpectedContentLength(100); driver.showDownloadDidReceiveData(ofLength: 40)
        driver.showDownloadDidStartExtractingUpdate(); driver.showExtractionReceivedProgress(0.5)
        check(states == [.downloading(0), .downloading(0.4), .downloading(nil), .downloading(0.5)], "download and unpack progress: \(states)")
        // Ready: it waits for a quiet moment, never installs mid-call, installs once the moment comes.
        var installs = 0
        states = []
        driver.showReady(toInstallAndRelaunch: { if $0 == .install { installs += 1 } })
        check(states == [.readyToInstall("0.3")] && installs == 0, "ready, and not installed while the app is busy")
        driver.tryInstall(); check(installs == 0, "still busy: still waiting")
        quiet = true; driver.tryInstall()
        check(installs == 1, "quiet: installed")
        driver.tryInstall(); check(installs == 1, "and only once")
        // (The delegate's willInstallUpdateOnQuit hook takes Sparkle's own appcast item, which cannot be made by hand; it sets the same
        // pending install and calls the same tryInstall, which is checked above.)
        return problems
    }
}
