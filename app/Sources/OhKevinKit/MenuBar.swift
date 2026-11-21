import AppKit
import Carbon.HIToolbox // key codes
import CallKit
import CallViews
import SwiftUI
import Updating
import VoiceCore

/// The launcher the owner approved (design/final.html, "The launcher"), on this app's own call: the fixed-width
/// menu-bar item whose shape is the state, and under it the panel (CallViews' PanelView) that starts, mutes, ends and shows
/// the call this app runs with its own engine and window. The panel is a non-activating NSPanel, as the launcher's is.
final class MenuBar: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: MenuBarItem.size.width) // one width in every state: nothing beside it moves
    let panel: PanelWindow
    let visible = Box(false)
    private let host = FirstClickHostingView(rootView: AnyView(EmptyView()))
    private var outsideClicks: Any?, askingDot: NSView?, shownShape: MenuShape?
    private unowned let app: Window

    init(app: Window) {
        self.app = app
        panel = PanelWindow(content: host)
        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        panel.onKey = { [unowned self] in key($0) }
    }

    /// The panel shows this model's call (Window.setModel calls it with every new call).
    func show(_ model: CallModel) {
        host.rootView = AnyView(PanelHost(model: model, settings: app.settings, visible: visible) { [unowned self] in handle($0) })
        follow()
    }

    // ── the panel ──
    @objc func clicked() { panel.isVisible ? close() : open() }

    func open() {
        guard let screen = item.button?.window?.screen ?? NSScreen.main else { return }
        visible.value = true
        var anchor = NSRect(x: screen.visibleFrame.maxX, y: screen.visibleFrame.maxY + 6, width: 0, height: 0) // no icon to see: the bar's right end
        if let button = item.button, let bar = button.window {
            let icon = bar.convertToScreen(button.convert(button.bounds, to: nil))
            if screen.frame.contains(icon) { anchor = icon }
        }
        var frame = panel.frame
        frame.origin.x = min(max(anchor.midX - frame.width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - frame.width - 8)
        frame.origin.y = anchor.minY - 6 - frame.height
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        item.button?.highlight(true)
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        item.button?.highlight(false)
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        visible.value = false
    }

    /// What the panel asks for, done on this app's call (the old launcher's Launcher.handle was the reference).
    func handle(_ intent: PanelIntent) {
        let model = app.model
        switch intent {
        case .door(let action):
            switch action {
            case .startCall: close(); app.perform(.start)
            case .cancel: app.perform(.end)
            case .chooseProject: close(); app.settings.chooseFolder()
            case .allowMicrophone: app.perform(.openSettings)
            case .showCall: close(); app.show()
            case .open: app.settings.setup.fix(action)
            case .install, .signIn, .update: app.settings.setup.fix(action)
            case .openSetup: close(); app.show() // the window is the setup screen while anything is left (AppView)
            case .none: break
            }
        case .mute(let on): app.call?.setMuted(on)
        case .endCall: app.perform(model.stage == .live || model.stage == .starting ? .end : .close)
        case .pick(let path): app.settings.call.choose(path)
        case .settings: close(); app.openSettings()
        case .showDetails: app.perform(.showLog)
        case .quit: NSApp.terminate(nil)
        case .checkForUpdates: close(); MainActor.assumeIsolated { app.settings.updates?.checkForUpdates() }
        case .line(let action): app.lineAction(action)
        }
    }

    private func key(_ e: NSEvent) -> Bool {
        switch Int(e.keyCode) {
        case kVK_Escape: if app.model.stage == .starting { app.perform(.end) } else { close() }
        case kVK_Return:
            switch app.model.stage {
            case .idle, .ended, .failed: guard app.settings.call.project != nil else { return false }; close(); app.perform(.start)
            default: return false
            }
        default: return false
        }
        return true
    }

    // ── the item: its shape is the state ──
    private func follow() {
        let shape = withObservationTracking { PanelData(app.model.panelInput(app.settings)).shape } onChange: { [weak self] in
            DispatchQueue.main.async { self?.follow() }
        }
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
    }
}

extension CallModel {
    /// What the launcher's panel needs to know, from this app's call. The bar's state word stands in for the page's voice
    /// state, and a blocked microphone for the page's mic report; this app has no separate call window to lose.
    func panelInput(_ settings: AppSettings) -> PanelInput {
        var i = PanelInput()
        i.phase = switch stage {
        case .idle: .idle
        case .starting: .starting
        case .live: .live
        case .ending: .ending
        case .ended: .ended(Ended(length: (until ?? Date()).timeIntervalSince(since ?? until ?? Date()), line: sub.isEmpty ? "Ready for the next one." : sub)) // the window is still open here: not the launcher's "The call window has closed."
        case .failed(let t): .failed(t.failure)
        }
        var s = status
        s.voice = switch capsule {
        case .listening: "listening"; case .speaking: "speaking"; case .thinking: "thinking"; case .muted: "muted"
        default: ""
        }
        s.canMute = mic == .on || mic == .muted
        s.mic = deaf == nil ? "" : "mac"
        i.status = s
        let setup = settings.setup
        i.missing = setup.missing; i.installing = setup.installing; i.installFailed = setup.installFailed
        i.signingIn = setup.signingIn; i.updatingClaude = setup.updatingClaude; i.updateFailed = setup.updateFailed
        i.micState = setup.mic; i.micAskingLine = "Your Mac is asking."
        i.downloadParts = setup.download.setupParts(ownCopy: Server.place.ownCopy)
        i.project = settings.call.project.map { URL(fileURLWithPath: $0) }
        i.recents = settings.call.recents.map { URL(fileURLWithPath: $0) }
        i.liveSince = since
        i.feedLost = reconnecting
        i.handingOver = handing
        return i
    }
}

extension CallModel {
    /// The setup screen's input: the panel's, with all of this app's download (the voice and the speech model too, not only the packages).
    func setupInput(_ settings: AppSettings) -> SetupInput {
        var s = panelInput(settings).setup
        s.download = settings.downloadPicture ?? settings.setup.download.setupParts(ownCopy: Server.place.ownCopy)
        return s
    }
    /// The setup screen while anything is left before a call, and until the first call (the window opens on it); nil: the start.
    func setupScreen(_ settings: AppSettings) -> SetupScreen? {
        let screen = SetupScreen(setupInput(settings))
        return screen.bottom == .start(ready: true) && !settings.firstCall ? nil : screen
    }
}

/// The panel's view on this app: the one place the plain-data panel meets the call.
struct PanelHost: View {
    @Bindable var model: CallModel
    @Bindable var settings: AppSettings
    @ObservedObject var visible: Box<Bool>
    let send: (PanelIntent) -> Void
    var body: some View {
        var data = PanelData(model.panelInput(settings))
        data.canUpdate = MainActor.assumeIsolated { settings.updates?.available ?? false } // "Check for Updates…" in its corner menu
        let inCall = [.starting, .live, .ending].contains(model.stage)
        data.line = inCall ? nil : MainActor.assumeIsolated { settings.updateLine } // the same line as the start window, never mid-call
        return PanelView(data: data, active: visible.value, send: send)
    }
}

/// The panel: borderless, non-activating, a fixed 320 × 228 (as the old launcher's PanelWindow).
final class PanelWindow: NSPanel {
    var onKey: (NSEvent) -> Bool = { _ in false }
    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: PanelView.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true; level = .popUpMenu
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = content
    }
    override var canBecomeKey: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey(event) { return }
        super.sendEvent(event)
    }
}

/// A click on the panel works at once, even when it is not the key window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The menu-bar item: one box, 52 × 22, in every state, a template image (the bar tints it), so only shape tells the states
/// apart; the marigold "someone asks" dot is a layer on the button. Copied from the old launcher's MenuBarItem.swift, as offered.
enum MenuBarItem {
    static let size = CGSize(width: 52, height: 22)
    static let dot = CGRect(x: 34, y: 7, width: 8, height: 8)

    static func draw(_ shape: MenuShape, in ctx: CGContext, ink: CGColor) {
        let cy: CGFloat = 11
        ctx.setFillColor(ink); ctx.setStrokeColor(ink)
        func chevron(left: CGFloat, box: CGFloat, border: CGFloat, shift: CGFloat) {
            ctx.addPath(Chevron.path(left: left, cy: cy, box: box, border: border, shift: shift).cgPath)
            ctx.setLineWidth(border); ctx.setLineCap(.butt); ctx.setLineJoin(.miter); ctx.strokePath()
        }
        func bars(_ heights: [CGFloat], from x: CGFloat) {
            for (i, h) in heights.enumerated() { ctx.addPath(CGPath(roundedRect: CGRect(x: x + CGFloat(i) * 4, y: cy - h / 2, width: 2, height: h), cornerWidth: 1, cornerHeight: min(1, h / 2), transform: nil)) }
            ctx.fillPath()
        }
        switch shape {
        case .rest(let setup):
            let width: CGFloat = 16.8 + (setup ? 12 : 0), x0 = ((size.width - width) / 2).rounded()
            chevron(left: x0, box: 8.25, border: 1.95, shift: 0.9)
            ctx.addPath(CGPath(roundedRect: CGRect(x: x0 + 9.3, y: cy + 4.05, width: 7.5, height: 1.95), cornerWidth: 0.975, cornerHeight: 0.975, transform: nil)); ctx.fillPath()
            if setup { ctx.setLineWidth(1.5); ctx.strokeEllipse(in: CGRect(x: x0 + 21.8 + 0.75, y: cy - 2.75, width: 5.5, height: 5.5)) }
        case .lost:
            let x0 = (((asking(shape) ? dot.minX : size.width) - 12.9) / 2).rounded()
            chevron(left: x0, box: 8.25, border: 1.95, shift: 0.9)
            ctx.fill(CGRect(x: x0 + 10.8, y: cy - 6.9, width: 2.1, height: 8.28)); ctx.fill(CGRect(x: x0 + 10.8, y: cy + 4.416, width: 2.1, height: 2.484))
        case .reconnecting:
            let x0 = (((asking(shape) ? dot.minX : size.width) - 20) / 2).rounded()
            chevron(left: x0, box: 8, border: 2, shift: 1)
            bars(Array(repeating: 2, count: 3), from: x0 + 10)
        case .call(let kind, let muted, let asking):
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { ctx.endTransparencyLayer() }
            let pill = CGRect(x: 4, y: 2, width: 44, height: 18)
            let hs = (asking ? WaveArt.asking : WaveArt.small)[kind] ?? WaveArt.small[.dots]!
            if muted {
                ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.fillPath()
                ctx.setBlendMode(.clear)
            } else {
                ctx.setAlpha(0.55); ctx.setLineWidth(1)
                ctx.addPath(CGPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8.5, cornerHeight: 8.5, transform: nil)); ctx.strokePath()
                ctx.setAlpha(1)
            }
            chevron(left: pill.minX + 6, box: 8, border: 2, shift: 1)
            bars(hs, from: pill.minX + 16)
        }
    }

    static func image(_ shape: MenuShape) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(shape, in: ctx, ink: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func asking(_ shape: MenuShape) -> Bool {
        switch shape {
        case .call(_, _, let a), .lost(let a), .reconnecting(let a): a
        case .rest: false
        }
    }

    static func words(_ shape: MenuShape) -> String {
        let base = switch shape {
        case .rest(let setup): setup ? "\(Product.shortName), setup" : "\(Product.shortName), ready"
        case .lost: "\(Product.shortName), the call needs attention"
        case .reconnecting: "\(Product.shortName), reconnecting"
        case .call(_, let muted, _): "\(Product.shortName), on a call\(muted ? ", muted" : "")"
        }
        return base + (asking(shape) ? ", Claude Code needs you" : "")
    }
}
