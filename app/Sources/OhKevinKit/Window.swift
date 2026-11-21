import AppKit
import AVFoundation
import Carbon.HIToolbox // key codes
import CallKit
import Ears
import SwiftUI
import Updating
import VoiceCore

/// The app's one window (design/final.html, "The app"): an AppKit window around the SwiftUI AppView, and the small
/// Settings window. It starts nothing by itself: no server and no microphone until Start call. Closing it hides it and the call goes on.
final class Window: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Drawing pictures (AppChecks --check): nothing is saved, no menu-bar item, no updates, no setup check.
    let drawing: Bool
    /// Runs a second after launch while drawing (AppChecks: Scene).
    var drawn: ((Window) -> Void)?
    var call: Call?, model: CallModel, logURL: URL?, monitor: Any?, click: Any?
    let quiet = Replay() // the turn-taking of the model that shows no call
    lazy var settings = AppSettings(persist: !drawing)
    /// The launcher's menu-bar item and panel, on this app's call (none while drawing figures).
    var menuBar: MenuBar?
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    let content = NSHostingView(rootView: AnyView(EmptyView()))
    /// The three dots (design/system.css "Corner"): at the title bar's trailing edge, in every state; one press opens Settings.
    lazy var corner = NSHostingView(rootView: AnyView(EmptyView()))
    /// The dots' right edge on the content edge (16 narrow, 40 otherwise), as the window's width changes.
    func placeCorner() {
        let inset = OnCall.pad(window.contentLayoutRect.width)
        corner.rootView = AnyView(CornerDots(settings: settings) { [unowned self] in settings.shown.toggle() }.padding(.trailing, inset))
        corner.frame.size = NSSize(width: 28 + inset, height: 28)
    }
    func windowDidResize(_ n: Notification) { placeCorner() }
    /// The voice is chosen through the call when there is one, so it is heard at once.
    func chooseVoice(_ name: String) {
        if model.stage == .live { model.choose(name) } else if settings.persist { UserDefaults.standard.set(name, forKey: CallModel.voiceKey) }
    }

    init(drawing: Bool = false) {
        self.drawing = drawing
        model = CallModel(turns: quiet.turns, post: { _, _ in })
        super.init()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 600)
        window.backgroundColor = NSColor(CV.ground)
        window.delegate = self
        window.contentView = content
        if !drawing { menuBar = MenuBar(app: self) }
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        placeCorner()
        accessory.view = corner
        window.addTitlebarAccessoryViewController(accessory)
        if settings.firstCall && !drawing { // the setup screen (onboarding.html): 920 × 660 in the middle, until the first call
            window.setContentSize(fitted(Self.setupSize)); window.center(); sizedForSetup = true
        } else if !window.setFrameUsingName("Window") { // first time: 1280 × 800, or what fits, in the middle
            window.setContentSize(fitted(Self.callSize)); window.center()
        }
        window.setFrameAutosaveName("Window")
        setModel(model)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] e in key(e) ? nil : e }
        click = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [self] e in release(e); return e }
        if !drawing { show(); settings.setup.check() } // what a call needs, checked at once: the start shows the first step
        if !drawing { startUpdates() }
        if let drawn { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in drawn(self) } }
    }

    static let setupSize = NSSize(width: 920, height: 660), callSize = NSSize(width: 1280, height: 800)
    /// Opened at the setup screen's size: the first call grows it to the call's.
    var sizedForSetup = false
    /// A size, or what fits on this screen with 40 to spare on each side.
    func fitted(_ size: NSSize) -> NSSize {
        guard let area = (window.screen ?? NSScreen.main)?.visibleFrame else { return size }
        return NSSize(width: min(size.width, area.width - 80), height: min(size.height, area.height - 80))
    }
    /// The first call: from the setup screen's size to the call's, around the same middle, once.
    func grow() {
        guard sizedForSetup, !drawing else { return }
        sizedForSetup = false
        let size = fitted(Self.callSize), mid = NSPoint(x: window.frame.midX, y: window.frame.midY)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: mid.x - frame.width / 2, y: mid.y - frame.height / 2)
        if let area = window.screen?.visibleFrame { // kept on screen
            frame.origin.x = min(max(frame.origin.x, area.minX), area.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, area.minY), area.maxY - frame.height)
        }
        window.setFrame(frame, display: true, animate: true)
    }

    /// The window shows this model: its call, or the quiet one before a call.
    func setModel(_ m: CallModel) {
        model = m
        m.perform = { [unowned self] in perform($0) }
        m.front = { [unowned self] in
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless() // in front, without the keyboard
        }
        m.announce = { NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: $0, .priority: NSAccessibilityPriorityLevel.high.rawValue]) }
        m.sawVoices = { [unowned self] in settings.saw($0) }
        m.visible = window.occlusionState.contains(.visible)
        menuBar?.show(m)
        content.rootView = AnyView(AppView(model: m, settings: settings, chooseVoice: { [unowned self] in chooseVoice($0) }, setup: { [unowned self] in setup($0) }))
        m.update()
        follow()
    }
    /// The title is the project's folder name, as the call's server named it.
    func follow() {
        withObservationTracking { _ = model.title } onChange: { [weak self] in DispatchQueue.main.async { self?.follow() } }
        window.title = model.title // the system shows it only in Mission Control and the Window menu
    }
    /// Self-updating, as the launcher does it: only in a build with a feed; installs by relaunching when the app is quiet (no call,
    /// the panel and Settings closed, no setup step, and the window not in use), checked every 15 s and at each call's end.
    func startUpdates() {
        MainActor.assumeIsolated {
            let u = Updates()
            guard u.available else { return }
            settings.updates = u
            u.isQuiet = { [unowned self] in updateQuiet }
            u.onChange = { [unowned self] in // checking, up to date and could not check stay four seconds
                let s = u.state; settings.lineGone = nil
                if [.checking, .upToDate].contains(s) || { if case .couldNotCheck = s { true } else { false } }() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [unowned self] in MainActor.assumeIsolated { if u.state == s { settings.lineGone = s } } }
                }
            }
            Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in MainActor.assumeIsolated { u.tryInstall() } }
            if let app = NSApp.mainMenu?.item(at: 0)?.submenu { // "Check for Updates…" right under About, as Mac apps have it
                let item = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""); item.target = self
                app.insertItem(item, at: 1)
            }
        }
    }
    /// A word on the update line: Update, Try again, What's new, Move.
    func lineAction(_ action: LineAction) {
        MainActor.assumeIsolated {
            guard let u = settings.updates else { return }
            switch action {
            case .update, .retryUpdate: u.install()
            case .whatsNew: // the release page of this version, found from the app's own feed (appcast-app.xml → app-v<version>)
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                if let url = releaseNotesURL(feed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, version: version) { NSWorkspace.shared.open(url) }
                u.acknowledgeInstalled()
            case .move:
                settings.moving = true
                if let outcome = AppMover.moveAndRelaunch(), case .failed = outcome { settings.moving = false }
            }
        }
    }
    @objc func checkForUpdates() { MainActor.assumeIsolated { settings.updates?.checkForUpdates() } }
    var updateQuiet: Bool {
        updateIsQuiet(phase: model.panelInput(settings).phase, panelOpen: (menuBar?.visible.value ?? false) || settings.shown,
                      inSetup: settings.setup.missing?.isEmpty == false) && !(NSApp.isActive && window.isKeyWindow)
    }
    /// About Oh Kevin: the icon, the wordmark and the licence, in a small window of its own.
    lazy var aboutWindow: NSWindow = {
        let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        w.title = ""; w.styleMask = [.titled, .closable, .fullSizeContentView]; w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false; w.backgroundColor = NSColor(CV.ground); w.center()
        return w
    }()
    @objc func showAbout() { aboutWindow.makeKeyAndOrderFront(nil); NSApp.activate() }
    /// ⌘, (the app menu): the same Settings card the three dots open, in the window.
    @objc func openSettings() { show(); settings.shown = true }

    /// In front and key, but the field does not take the keyboard: M and Space work at once.
    func show() {
        window.makeKeyAndOrderFront(nil); NSApp.activate()
        DispatchQueue.main.async { [self] in window.makeFirstResponder(nil); model.typing = false }
    }
    func windowDidChangeOcclusionState(_ n: Notification) { model.visible = window.occlusionState.contains(.visible) }

    /// Close hides the window and the call goes on; once the call is over it is let go.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        switch model.stage { case .starting, .live, .ending: break; default: reset() }
        sender.orderOut(nil)
        return false
    }
    /// Back to the quiet window.
    func reset() { call = nil; settings.lookAtFirstCall(); setModel(CallModel(turns: quiet.turns, post: { _, _ in })) }

    /// The setup screen's buttons (SetupIntent), done here: the host decides what each does.
    func setup(_ intent: SetupIntent) {
        let s = settings.setup
        switch intent {
        case .signIn: s.fix(.signIn)
        case .updateClaude: s.fix(.update)
        case .allowMicrophone: NSApp.activate(); s.allowMicrophone()
        case .openMicrophoneSettings: perform(.openSettings)
        case .chooseProject: settings.chooseFolder()
        case .pick(let path): settings.call.choose(path)
        case .open(let url): NSWorkspace.shared.open(url)
        case .startCall: perform(.start)
        case .retryDownload: s.fix(.install)
        }
    }

    // ── commands ──
    func perform(_ c: Command) {
        switch c {
        case .start, .again: start()
        case .mute: call?.setMuted(!(call?.turns.muted ?? false))
        case .send(let text): call?.type(text)
        case .setup(let action): settings.setup.fix(action)
        case .line(let action): lineAction(action)
        case .end: let cancelled = model.stage == .starting; call?.end(); if cancelled { reset() } // Cancel leaves nothing behind
        case .close: window.orderOut(nil); reset()
        case .listenAgain: call?.listenAgain()
        case .installModel:
            let m = model; m.downloading = true; m.update()
            Task { @MainActor in // Apple downloads it; Listen Again once it is there
                let ok = (try? await Recognizer.installModel()) != nil
                m.downloading = false; m.update()
                if ok { call?.listenAgain() }
            }
        case .openSettings: NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        case .showLog: if let logURL { NSWorkspace.shared.open(logURL) }
        }
    }

    /// Start call: a call server of its own on the chosen project (or --call <link>), the window in front. The call's own log
    /// (every word heard and said) is written only with --log <file>; the server's output goes to ~/Library/Logs/Oh Kevin/.
    func start() {
        let link = arg("--call").flatMap(URL.init(string:))
        guard link != nil || settings.call.project != nil else { return settings.chooseFolder() }
        if link == nil, settings.setup.missing?.isEmpty == false { return show() } // a step to go first: the start shows it
        if link == nil, Server.place.ownCopy, !settings.setup.download.done { return show() } // the voice or the speech model still on its way
        grow()
        reset()
        do {
            let server: Server
            if let link { server = try Server(link: link); logURL = nil }
            else { logURL = try Server.freshLog(); server = try Server.start(log: logURL!, project: URL(fileURLWithPath: settings.call.project!), model: settings.call.workerModel, handOver: settings.call.openInClaudeApp,
                                                                                   shell: settings.setup.environment, claude: settings.setup.claude) }
            let c = Call(server: server, log: arg("--log").map { URL(fileURLWithPath: $0) })
            c.model.remember() // the voice chosen last time
            call = c; setModel(c.model); show()
            c.start(microphone: true, file: nil, mute: false) { _ in }
        } catch {
            print(error)
            model.stage = .failed("\(error)".hasPrefix("No free port") ? .noPort : .couldNotLaunch); model.update(); show()
        }
    }

    // ── keys (spec 13) ──
    /// A click anywhere but the typing field takes the keyboard back from it (SwiftUI leaves a field focused otherwise).
    func release(_ e: NSEvent) {
        guard e.window === window, let editor = window.firstResponder as? NSTextView, let field = editor.delegate as? NSView,
              let hit = window.contentView?.superview?.hitTest(e.locationInWindow), !hit.isDescendant(of: field) else { return }
        window.makeFirstResponder(nil); model.typing = false
    }
    /// Escape in Settings: an open list first, then Settings itself.
    func escape() -> Bool {
        if settings.listOpen { settings.listOpen = false } else { settings.shown = false }
        return true
    }
    func key(_ e: NSEvent) -> Bool {
        guard NSApp.keyWindow === window else { return false }
        if settings.shown { return Int(e.keyCode) == kVK_Escape ? escape() : false } // Settings takes the keys (the choosers' arrows, Return, letters)
        let cmd = e.modifierFlags.contains(.command), card = model.cards.first
        switch (Int(e.keyCode), cmd) {
        case (kVK_Return, true), (kVK_ANSI_KeypadEnter, true): guard let card else { return false }; model.answer(card.ask.id, allow: true)
        case (kVK_Delete, true): guard let card, !(window.firstResponder is NSText) else { return false } // in the field it deletes a word; model.answer(card.ask.id, allow: false)
        case (kVK_ANSI_Period, true): guard model.stage == .live, model.status.working else { return false }; model.stop()
        default:
            guard !e.modifierFlags.contains([.command, .control, .option]), !(window.firstResponder is NSText) else { return false }
            switch Int(e.keyCode) {
            case kVK_Tab: guard model.stage == .live || model.stage == .starting else { return false }; model.typing = true
            case kVK_Space: guard model.turns.speaking else { return false }; model.turns.hush()
            default:
                guard e.charactersIgnoringModifiers == "m", model.mic == .on || model.mic == .muted else { return false }
                perform(.mute)
            }
        }
        return true
    }

    // ── the app ──
    /// ⌘Q ends the call first, and quits once its work is handed over.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let c = call, !c.over else { return .terminateNow }
        c.afterEnded = { c.server.flush(2) { sender.reply(toApplicationShouldTerminate: true) } } // the hang-up leaves first
        c.end()
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool { if !hasVisibleWindows { show() }; return true }
    /// The microphone may have been allowed in System Settings meanwhile.
    func applicationDidBecomeActive(_ note: Notification) {
        if !drawing { settings.setup.lookAtMic() } // allowed in System Settings meanwhile?
        if !drawing, settings.setup.missing?.isEmpty == false { settings.setup.check() } // fixed in the meantime?
        if model.deaf == .microphone, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { call?.listenAgain() }
    }
}
