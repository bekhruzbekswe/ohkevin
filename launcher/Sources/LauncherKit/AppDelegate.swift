import AppKit
import CallViews
import Carbon.HIToolbox // key codes
import SwiftUI
import VoiceCore

/// Starts the app: the menu-bar item and its model. All that the shipped binary's main does.
@MainActor public func runApp() {
    for line in FolderMove.run(home: FileManager.default.homeDirectoryForCurrentUser) { NSLog("%@", line) } // before anything uses the folders
    let app = NSApplication.shared
    let delegate = AppDelegate(launcher: .shared)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

/// The menu-bar item, its panel and the Settings window. The panel is a non-activating NSPanel so it can open from code
/// without taking the keyboard (MenuBarExtra can do neither).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let launcher: Launcher
    private(set) var item: NSStatusItem!
    private(set) var panel: PanelWindow!
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var outsideClicks: Any?
    private var askingDot: NSView?
    private var shownShape: MenuShape?
    /// The marigold dot of the menu-bar item shows.
    var asking: Bool { askingDot?.isHidden == false }

    init(launcher: Launcher) { self.launcher = launcher }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: MenuBarItem.size.width) // one width in every state: nothing beside it ever moves
        item.button?.target = self
        item.button?.action = #selector(clicked)
        panel = PanelWindow(content: PanelHost(launcher: launcher))
        panel.onKey = { [unowned self] in self.key($0) }
        launcher.openPanel = { [unowned self] keyboard, itself in self.open(keyboard: keyboard, itself: itself) }
        launcher.closePanel = { [unowned self] in self.close() }
        launcher.showSettings = { [unowned self] in self.showSettings() }
        launcher.showSetup = { [unowned self] in self.showSetup() }
        launcher.closeSetup = { [unowned self] in self.setupWindow?.close() }
        follow()
        launcher.closeCallWindow() // one a crash left open may still be listening
        launcher.installsAtLaunch = true // the download starts by itself, with no screen
        let health = launcher.checkHealth() // Start Call waits for it
        if !launcher.settings.launchedBefore { // the first launch opens the setup screen once (the panel, if there is nothing left to set up)
            launcher.settings.launchedBefore = true
            Task {
                await health.value
                if launcher.setupScreen.left > 0 { showSetup() } else { open(keyboard: false, itself: false) }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if launcher.missingItems?.isEmpty == false { launcher.checkHealth(rereadShell: true) }
    }

    /// Quitting during a call ends it first, the same way End Call does, and quits once the server is gone.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        launcher.endBeforeQuit { sender.reply(toApplicationShouldTerminate: true) } ? .terminateLater : .terminateNow
    }

    /// Opening the app again (Spotlight, Finder) opens the panel: the way in when macOS shows no icon for it, behind the
    /// notch of a full menu bar or switched off in System Settings › Menu Bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        open(keyboard: true, itself: false)
        return false
    }

    // MARK: The panel

    /// A click on the icon opens the panel, or closes it; a panel that opened by itself is taken into the keyboard first.
    @objc func clicked() {
        if !panel.isVisible { open(keyboard: true, itself: false) }
        else if !panel.isKeyWindow { launcher.panelOpenedItself = false; panel.makeKeyAndOrderFront(nil) }
        else { close() }
    }

    func open(keyboard: Bool, itself: Bool) {
        guard let screen = item.button?.window?.screen ?? NSScreen.main else { return }
        launcher.panelOpenedItself = itself
        launcher.panelVisible = true
        // Under its icon; with no icon to see, at the right end of the menu bar.
        var anchor = NSRect(x: screen.visibleFrame.maxX, y: screen.visibleFrame.maxY + 6, width: 0, height: 0)
        if let button = item.button, let bar = button.window {
            let icon = bar.convertToScreen(button.convert(button.bounds, to: nil))
            if screen.frame.contains(icon) && !behindNotch(icon, on: screen) { anchor = icon }
        }
        var frame = panel.frame
        frame.origin.x = min(max(anchor.midX - frame.width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - frame.width - 8)
        frame.origin.y = anchor.minY - 6 - frame.height
        panel.setFrame(frame, display: true)
        if keyboard { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() } // itself: never takes the keyboard
        item.button?.highlight(true)
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        if launcher.missingItems?.isEmpty == false { launcher.checkHealth(rereadShell: true) } // fixed in the meantime?
    }

    /// Whether an icon sits in the notch's gap, where macOS puts menu-bar icons it has no room for.
    private func behindNotch(_ icon: NSRect, on screen: NSScreen) -> Bool {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        return icon.midX > left.maxX && icon.midX < right.minX
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        item.button?.highlight(false)
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        launcher.panelVisible = false
        launcher.panelOpenedItself = false
        launcher.panelClosed()
    }

    // MARK: Keys

    private func key(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch (e.keyCode, cmd) {
        case (UInt16(kVK_Escape), _):
            if launcher.phase == .starting { launcher.cancelStart() } else { close() }
        case (UInt16(kVK_Return), false):
            switch launcher.phase { // Return never approves and never ends a call; it starts one only when Start Call shows
            case .idle, .ended, .failed: guard launcher.canStart else { return false }; Task { await launcher.startCall() }
            default: return false
            }
        case (UInt16(kVK_ANSI_Comma), true): showSettings()
        case (UInt16(kVK_ANSI_Q), true): NSApp.terminate(nil)
        default: return false
        }
        return true
    }

    // MARK: Settings

    func showSettings() {
        close()
        if settingsWindow == nil { settingsWindow = Self.makeSettingsWindow(for: launcher) }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// The Settings window: the design's ground, a transparent title bar, sized to its content. (The checks open the same one.)
    static func makeSettingsWindow(for launcher: Launcher) -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(launcher: launcher))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = Product.name
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true // the window is the design's ground; only its three buttons are left of the title bar
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(name: nil) { NSColor($0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? Palette.dark.ground : Palette.light.ground) }
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    var settings: NSWindow? { settingsWindow }

    // MARK: Setup

    /// The one setup screen in a window of its own; "Set up" and "Continue" in the panel bring it forward. Closing it is "later".
    func showSetup() {
        close()
        if setupWindow == nil { setupWindow = Self.makeSetupWindow(for: launcher) }
        NSApp.activate()
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    /// 920 × 660, titled "Oh Kevin", centred, not resizable.
    static func makeSetupWindow(for launcher: Launcher) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SetupHost(launcher: launcher)))
        window.title = Product.name
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(SetupView.size)
        window.backgroundColor = NSColor(name: nil) { NSColor($0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? Palette.dark.ground : Palette.light.ground) }
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    var setup: NSWindow? { setupWindow }

    // MARK: The menu-bar item: its shape is the state

    /// Called once at launch: one observation that renews itself, redrawing the item only when its shape changed.
    private func follow() {
        let (shape, size) = withObservationTracking { (launcher.panel.shape, PanelView.size(for: launcher.panel)) } onChange: { [weak self] in Task { @MainActor in self?.follow() } }
        panel.fit(to: size) // the update line makes the card taller by its row, and takes it back
        guard let button = item.button, shape != shownShape else { return }
        shownShape = shape
        button.image = MenuBarItem.image(shape)
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(MenuBarItem.words(shape))
        if askingDot == nil { // the one coloured thing in the item: marigold, at the pill's right end
            let dot = NSView(frame: NSRect(x: MenuBarItem.dot.minX, y: (button.bounds.height - MenuBarItem.dot.height) / 2, width: MenuBarItem.dot.width, height: MenuBarItem.dot.height))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor(Palette.marigold).cgColor
            dot.layer?.cornerRadius = dot.frame.width / 2
            button.addSubview(dot)
            askingDot = dot
        }
        askingDot?.isHidden = !MenuBarItem.asking(shape)
        askingDot?.frame.origin.y = (button.bounds.height - MenuBarItem.dot.height) / 2
    }
}

/// The setup screen's view on the launcher.
struct SetupHost: View {
    let launcher: Launcher
    var body: some View { SetupView(data: launcher.setupScreen, send: launcher.handle) }
}

/// The panel's view on the launcher: the one place the plain-data panel meets the app.
struct PanelHost: View {
    let launcher: Launcher
    var body: some View { PanelView(data: launcher.panel, active: launcher.panelVisible, send: launcher.handle) }
}

/// The panel: borderless, non-activating, painted in the design's ground, a fixed 320 × 228.
final class PanelWindow: NSPanel {
    var onKey: (NSEvent) -> Bool = { _ in false }
    private let host: NSHostingView<AnyView>

    init<Content: View>(content: Content) {
        host = FirstClickHostingView(rootView: AnyView(content))
        super.init(contentRect: NSRect(origin: .zero, size: PanelView.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey(event) { return }
        super.sendEvent(event)
    }

    /// Sets the window's height to the card's, keeping its top edge where it hangs from the menu bar.
    func fit(to size: CGSize) {
        guard abs(frame.height - size.height) > 0.5 else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    var hostingView: NSView { host }
}

/// A click on the panel works at once, even when it opened by itself and is not the key window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
