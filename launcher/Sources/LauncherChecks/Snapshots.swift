import AppKit
import CallViews
import SwiftUI
@testable import LauncherKit
import VoiceCore

/// `--snapshots <folder>`: every state of the panel and of the menu-bar item, light and dark, at 2x, drawn offscreen (no
/// window is shown, nothing is launched), plus the design's own size check run on what was drawn: one panel size; head,
/// pill and door in identical places in every state; one menu-bar item width. The panels are built from the same
/// `PanelInput` the app fills, so the mapping from what the launcher knows to what the panel says is drawn too.
@MainActor
enum Snapshots {
    struct State { let name: String; let input: PanelInput }

    static func states() -> [State] {
        let api = URL(filePath: "/Users/me/code/api"), long = URL(filePath: "/Users/me/code/storefront-checkout-redesign-2026")
        let since = Date().addingTimeInterval(-(12 * 60 + 4))
        func idle(_ f: (inout PanelInput) -> Void = { _ in }) -> PanelInput { var i = PanelInput(); i.project = api; i.recents = [api, URL(filePath: "/Users/me/code/web")]; i.missing = []; i.micState = .done; f(&i); return i }
        func call(_ voice: String, _ f: (inout PanelInput) -> Void = { _ in }) -> PanelInput {
            idle { i in
                i.phase = .live; i.liveSince = since; i.status.live = true; i.status.pages = 1; i.status.voice = voice; i.status.canMute = true
                f(&i)
            }
        }
        let ask: (inout PanelInput) -> Void = { $0.status.apply(#"data: {"type":"ask","id":"a","detail":"Bash git push","worker":"api","voice":false,"full":"git push"}"#) }
        /// What a Mac without these would make the health check say.
        func lacking(packages: Bool = false, signIn: Bool = false, chrome: Bool = false) -> [Missing] {
            VoiceCore.missing(Machine(callFolder: URL(filePath: "/x"), node: Node(url: URL(filePath: "/x/node"), version: "24.15.0"), packages: !packages, claude: URL(filePath: "/x/claude"),
                                      claudeVersion: "9.9.9", signedIn: !signIn, chrome: chrome ? nil : URL(filePath: "/Applications/Google Chrome.app")))
        }
        return [
            State(name: "idle", input: idle()),
            State(name: "checking", input: idle { $0.project = nil; $0.recents = []; $0.missing = nil }),
            State(name: "point-first", input: idle { $0.project = nil; $0.recents = []; $0.missing = lacking(packages: true, signIn: true); $0.micState = .todo }),
            State(name: "point-half", input: idle { $0.project = nil; $0.recents = []; $0.micState = .todo }),
            State(name: "setup1", input: idle { $0.missing = lacking(signIn: true) }),
            State(name: "setup-chrome", input: idle { $0.missing = lacking(chrome: true) }),
            State(name: "installing", input: idle { $0.missing = lacking(packages: true); $0.installing = true }),
            State(name: "moved", input: idle { $0.missing = VoiceCore.missing(Machine(callFolder: URL(filePath: "/x"), server: false, node: Node(url: URL(filePath: "/x/node"), version: "24.15.0"), packages: true, claude: URL(filePath: "/x/claude"), claudeVersion: "9.9.9", signedIn: true, chrome: URL(filePath: "/c"))) }),
            State(name: "line-move", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.moveOffered = true; return l }()) }),
            State(name: "line-moving", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.moving = true; return l }()) }),
            State(name: "line-updated", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.state = .installed("0.2"); return l }()) }),
            State(name: "line-failed", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.state = .failed("x"); return l }()) }),
            State(name: "line-checking", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.state = .checking; return l }()) }),
            State(name: "line-current", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.state = .upToDate; return l }()) }),
            State(name: "line-nocheck", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.state = .couldNotCheck("x"); return l }()) }),
            State(name: "line-ready", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.state = .available("0.2"); l.automatic = false; return l }()) }),
            State(name: "line-updating", input: idle { $0.line = updateLine({ var l = UpdateLineInput(); l.state = .downloading(0.62); l.automatic = false; return l }()) }),
            State(name: "line-after-call", input: idle { $0.phase = .ended(Ended(length: 724, line: nil)); $0.line = updateLine({ var l = UpdateLineInput(); l.state = .available("0.2"); l.automatic = false; return l }()) }),
            State(name: "starting", input: idle { $0.phase = .starting }),
            State(name: "listening", input: call("listening")),
            State(name: "speaking", input: call("speaking")),
            State(name: "thinking", input: call("thinking")),
            State(name: "muted", input: call("muted")),
            State(name: "ask1", input: call("listening", ask)),
            State(name: "mutedask", input: call("muted", ask)),
            State(name: "mic", input: call("listening") { $0.status.mic = "mac" }),
            State(name: "micask", input: call("listening") { $0.status.mic = "mac"; ask(&$0) }),
            State(name: "connecting", input: call("")),
            State(name: "window", input: call("listening") { $0.windowClosed = true }),
            State(name: "recon", input: call("listening") { $0.feedLost = true }),
            State(name: "lost", input: idle { $0.phase = .failed(.stopped) }),
            State(name: "didnt-start", input: idle { $0.phase = .failed(.slowStart) }),
            State(name: "ending", input: call("listening") { $0.phase = .ending }),
            State(name: "ended", input: idle { $0.phase = .ended(Ended(length: 724, line: nil)) }),
            State(name: "long", input: idle { $0.project = long; $0.recents = [long] }),
            State(name: "nobreaks", input: idle { $0.project = URL(filePath: "/Users/me/code/supercalifragilisticexpialidocious") }),
            State(name: "wide", input: idle { $0.project = URL(filePath: "/Users/me/code/MMMMMMMMMMMMMMMM") }),
        ]
    }

    /// The six states of design/onboarding.html, from the data a host gives.
    static func setupStates() -> [(Int, String, SetupInput)] {
        func input(_ f: (inout SetupInput) -> Void) -> SetupInput { var i = SetupInput(); f(&i); return i }
        let shop = [ProjectPill.Choice(path: "/Users/me/code/shop", label: "shop", current: true), ProjectPill.Choice(path: "/Users/me/code/web", label: "web", current: false)]
        return [
            (1, "first", input { _ in }),
            (2, "signing-in", input { $0.claude = .signingIn }),
            (3, "mic-asking", input { $0.claude = .done; $0.mic = .asking }),
            (4, "mic-refused", input { $0.claude = .done; $0.mic = .refused }),
            (5, "all-done", input { $0.claude = .done; $0.mic = .done; $0.project = "shop"; $0.choices = shop }),
            (6, "downloading", input { $0.claude = .done; $0.mic = .done; $0.project = "shop"; $0.choices = shop; $0.download = [.init("Packages", progress: 0.86)] }),
        ]
    }

    static func run(folder: URL) -> Int32 {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] { // what an assistive app sets: SwiftUI then builds its accessibility tree
            _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: attribute)
        }
        var problems: [String] = [], seen: [String: String] = [:]
        problems += UpdateChecks.run() // the update driver, by hand: no window, no Sparkle session
        func same(_ key: String, _ value: String, _ name: String) { if let was = seen[key], was != value { problems.append("MOVED \(key) \(value) (was \(was)) in \(name)") } else { seen[key] = value } }
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            for state in states() {
                let data = PanelData(state.input), name = "\(state.name)-\(theme)"
                let view = PanelView(data: data, active: true, still: true, send: { _ in }).environment(\.colorScheme, dark ? .dark : .light)
                guard let image = render(view, dark: dark) else { problems.append("NOT DRAWN \(name)"); continue }
                write(image, folder.appending(path: "\(name)-built.png"))
                if image.size != PanelView.size(for: data) { problems.append("SIZE \(image.size) \(name): a card is 320 × 228, and 320 × 281 with the update line") }
                for (k, v) in layout(view, data: data, dark: dark) { if k.hasPrefix("CLIPPED") || k.hasPrefix("WAVE") { problems.append("\(k) (\(v)) in \(name)") } else { same(k, v, name) } }
                problems += clipped(data).map { "\($0) in \(name)" }
                let bar = menuImage(data.shape, dark: dark)
                write(bar, folder.appending(path: "\(name)-menu-built.png"))
                same("menu item", "\(MenuBarItem.size)", name)
            }
        }
        // The one setup screen: every state of the design, 920 × 660, light and dark.
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            for (n, name, input) in setupStates() {
                let view = SetupView(data: SetupScreen(input), still: true, send: { _ in }).environment(\.colorScheme, dark ? .dark : .light)
                guard let image = render(view, dark: dark) else { problems.append("NOT DRAWN setup-\(name)-\(theme)"); continue }
                write(image, folder.appending(path: "setup-\(n)-\(name)-\(theme)-built.png"))
                if image.size != SetupView.size { problems.append("SIZE \(image.size) setup-\(name)-\(theme): the screen is 920 × 660") }
            }
        }
        // Settings: the window's content, with no voice, with a voice, on a call, and with a chooser's list open.
        let home = FileManager.default.temporaryDirectory.appending(path: "snapshots-home")
        let scratch = Setup(callFolder: home, support: home, chromeProfile: home)
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            for (name, open, tweak) in [("settings-0-no-voice", nil, { (_: Launcher) in }), ("settings-1-list", "Claude Code model", { (_: Launcher) in }),
                                        ("settings-2-spoken-yes-list", "A spoken “yes” approves", { (_: Launcher) in })] as [(String, String?, (Launcher) -> Void)] {
                let launcher = Launcher(settings: CallSettings(), defaults: nil, home: home, setup: scratch)
                tweak(launcher)
                let view = SettingsView(launcher: launcher, openChooser: open).environment(\.colorScheme, dark ? .dark : .light)
                guard let image = render(view, dark: dark) else { problems.append("NOT DRAWN \(name)-\(theme)"); continue }
                write(image, folder.appending(path: "\(name)-\(theme)-built.png"))
                if image.size.width != 400 { problems.append("SIZE \(image.size) \(name)-\(theme): the window is 400 wide") }
            }
        }
        // The brand mark, full and compact, light and dark; and the embedded copies of its SVGs against the owner's files (one source).
        for (name, embedded, file) in [("full", Logo.full, "mark-full-ink.svg"), ("compact", Logo.compact, "mark-compact-ink.svg")] {
            if let svg = try? String(contentsOf: AppIcon.logo.appending(path: file), encoding: .utf8), LogoArt(svg: svg) == embedded {} else { problems.append("BRAND MARK \(name) differs from design/logo/\(file): update CallViews/Brand.swift") }
        }
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            for (name, compact, height) in [("brand-full", false, 120.0), ("brand-compact", true, 120.0), ("brand-compact-32", true, 32.0), ("brand-full-48", false, 48.0)] as [(String, Bool, Double)] {
                let view = BrandMark(compact: compact).frame(height: height).padding(24).background(Palette(dark ? .dark : .light).ground).environment(\.colorScheme, dark ? .dark : .light)
                if let image = render(view, dark: dark) { write(image, folder.appending(path: "\(name)-\(theme)-built.png")) } else { problems.append("NOT DRAWN \(name)-\(theme)") }
            }
        }
        // The shared chooser's other faces: a long grouped list scrolled to the chosen row, an action row, and the keyboard's focus ring.
        let voices: [ChooserOption<Int>] = (0..<24).map { i in
            let g = ["US female", "US male", "British female", "British male"][i / 6]
            return ChooserOption(i, ["Heart", "Bella", "Nicole", "Sarah", "Sky", "Alloy"][i % 6] + (i >= 6 ? " \(i)" : ""), group: g)
        }
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            func sheet<V: View>(_ name: String, rings: Bool = false, open: String? = nil, @ViewBuilder _ body: () -> V) {
                let view = SettingsSheet(openChooser: open) { body(); Color.clear.frame(height: 340) }.environment(\.showFocusRings, rings).environment(\.colorScheme, dark ? .dark : .light)
                if let image = render(view, dark: dark, settle: 0.6) { write(image, folder.appending(path: "\(name)-\(theme)-built.png")) } else { problems.append("NOT DRAWN \(name)-\(theme)") }
            }
            sheet("chooser-grouped-scrolled", open: "Voice") { Chooser("Voice", selection: .constant(21), options: voices) }
            sheet("chooser-action-row", open: "Project folder") {
                Chooser("Project folder", selection: .constant("api"), options: [ChooserOption("api", "api"), ChooserOption("web", "web"), ChooserOption("docs", "docs")], action: ChooserAction("Choose a Folder…") {})
            }
            sheet("chooser-direct", open: nil) { Chooser("Project folder", selection: .constant(""), options: [ChooserOption<String>](), action: ChooserAction("Choose a Folder…") {}) }
            sheet("chooser-direct-named") { Chooser("Project folder", selection: .constant(""), options: [ChooserOption<String>](), action: ChooserAction("Choose a Folder…") {}, selectionTitle: "my-project", showsLabel: false) }
            sheet("focus-rings", rings: true, open: "Model") {
                Chooser("Claude Code model", selection: .constant("Opus"), options: [ChooserOption("Opus", "Opus"), ChooserOption("Sonnet", "Sonnet")])
                SwitchRow("Open the work in Claude afterwards", isOn: .constant(true))
                SwitchRow("Open at login", isOn: .constant(false))
                PillButton("Download", style: .primary) {}
            }
            sheet("focus-rings-list", rings: true, open: "Claude Code model") {
                Chooser("Claude Code model", selection: .constant("Opus"), options: [ChooserOption("Opus", "Opus"), ChooserOption("Sonnet", "Sonnet"), ChooserOption("Haiku", "Haiku")])
            }
        }
        print(problems.isEmpty ? "ok: \(states().count * 2) panels, one size, head, pill and door in identical places, one menu-bar item width" : problems.joined(separator: "\n"))
        return problems.isEmpty ? 0 : 1
    }

    /// The view drawn offscreen at 2x: hosted in a window that is never shown.
    static func render<V: View>(_ view: V, dark: Bool, settle: TimeInterval = 0.1) -> NSImage? {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.setFrameSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(rep)
        window.contentView = nil
        return image
    }

    /// Where the three rows sit, read from the accessibility tree of the drawn panel: head, pill and door boxes, relative to the panel.
    private static func layout<V: View>(_ view: V, data: PanelData, dark: Bool) -> [String: String] {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.setFrameSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }
        func all(_ e: Any) -> [NSObject] {
            let kids: [Any] = (e as? NSView)?.accessibilityChildren() ?? ((e as? NSObject)?.value(forKey: "accessibilityChildren") as? [Any]) ?? []
            return kids.compactMap { $0 as? NSObject }.flatMap { [$0] + all($0) }
        }
        let origin = window.frame.origin, tree = all(host)
        func frame(_ match: (NSObject) -> Bool) -> [CGFloat]? {
            guard let e = tree.first(where: match), let f = e.value(forKey: "accessibilityFrame") as? NSRect else { return nil }
            return [f.minX - origin.x, host.bounds.height - (f.maxY - origin.y), f.width, f.height]
        }
        func box(_ match: (NSObject) -> Bool, width: Bool = true) -> String {
            guard let f = frame(match) else { return "missing" }
            return (width ? f : [f[0], f[1], f[3]]).map { String(Int($0.rounded())) }.joined(separator: " ")
        }
        let label = { (e: NSObject) in e.value(forKey: "accessibilityLabel") as? String ?? "" }
        let role = { (e: NSObject) in e.value(forKey: "accessibilityRole") as? String ?? "" }
        var extra: [String: String] = [:]
        let pill: String
        switch data.pill {
        case .project: pill = box { label($0).hasPrefix("Project, ") || label($0).hasPrefix("Choose a project") }
        case .call:
            if let m = frame({ ["Mute", "Unmute"].contains(label($0)) }), let e = frame({ label($0) == "End call" }) { pill = [m[0] - 8, m[1] - 8, e[0] + e[2] - m[0] + 16, 64].map { String(Int($0.rounded())) }.joined(separator: " ") } else { pill = "missing" }
        }
        if case .call(let p) = data.pill, let w = tree.first(where: { label($0) == p.word && role($0) == "AXStaticText" }), let e = tree.first(where: { label($0) == "End call" }),
           let wf = w.value(forKey: "accessibilityFrame") as? NSRect, let ef = e.value(forKey: "accessibilityFrame") as? NSRect, wf.maxX > ef.minX - 4 { extra = ["CLIPPED word \(p.word)": "meets End call"] }
        if case .call(let p) = data.pill, !p.word.isEmpty, let w = tree.first(where: { label($0) == p.word && role($0) == "AXStaticText" }), let m = tree.first(where: { ["Mute", "Unmute"].contains(label($0)) }),
           let wf = w.value(forKey: "accessibilityFrame") as? NSRect, let mf = m.value(forKey: "accessibilityFrame") as? NSRect, wf.minX < mf.maxX + 8 + WaveArt.minimumWidth - 0.5 { extra["WAVE under three bars before \(p.word)"] = "word at \(wf.minX - mf.maxX)" }
        if let line = data.line { // the design's check: the line sits 16 under the door and 16 above the card's foot, 16 in from each side
            if let l = frame({ label($0) == line.text }), let d = frame({ role($0) == "AXButton" && label($0) == data.door.label }) {
                let bottom = host.bounds.height
                if abs(l[1] - (d[1] + d[3]) - 16) > 1 || abs(bottom - (l[1] + l[3]) - 16) > 1 || abs(l[0] - 16) > 1 || abs(l[2] - 288) > 1 { extra["LINE \(line.text)"] = "\(l.map { Int($0) }) under the door \(d.map { Int($0) })" }
            } else { extra["LINE \(line.text)"] = "not found" }
        }
        return extra.merging(["head": box({ label($0).hasPrefix(data.line1) && role($0) != "AXButton" && label($0) != data.line?.text }, width: false), "pill": pill,
                "door": box { role($0) == "AXButton" && label($0) == data.door.label }]) { $1 }
    }

    /// The design's CLIPPED check: every line fits the width it has.
    private static func clipped(_ data: PanelData) -> [String] {
        func width(_ s: String, _ font: NSFont, tracking: CGFloat = 0) -> CGFloat { NSAttributedString(string: s, attributes: [.font: font, .kern: tracking]).size().width }
        func serif(_ size: CGFloat, italic: Bool) -> NSFont {
            let base = NSFont.systemFont(ofSize: size), d = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            return NSFont(descriptor: italic ? d.withSymbolicTraits(.italic) : d, size: size) ?? base
        }
        var out: [String] = []
        let font1: NSFont = data.style == .ours ? serif(22, italic: false) : data.style == .wrong ? serif(22, italic: true) : .systemFont(ofSize: 22, weight: .semibold)
        if width(data.line1, font1) > 288 - 36 { out.append("CLIPPED line 1: \(data.line1)") }
        if case .text(let t) = data.line2, width(t, .systemFont(ofSize: 17)) > 288 { out.append("CLIPPED line 2: \(t)") }
        if case .project(let p) = data.pill, let n = p.name.map({ fittedName($0) }), width(n, .systemFont(ofSize: 22, weight: .semibold), tracking: -0.44) > chooserNameWidth + 2 { out.append("CLIPPED project: \(n)") }
        return out
    }

    static func menuImage(_ shape: MenuShape, dark: Bool) -> NSImage {
        let pad: CGFloat = 6, size = NSSize(width: MenuBarItem.size.width + 2 * pad, height: MenuBarItem.size.height + 8)
        let ink = dark ? NSColor(srgbRed: 0.965, green: 0.953, blue: 0.925, alpha: 1) : NSColor(srgbRed: 0.106, green: 0.102, blue: 0.09, alpha: 1)
        let bar = NSImage(size: size, flipped: true) { rect in
            (dark ? NSColor(srgbRed: 0.094, green: 0.09, blue: 0.082, alpha: 1) : NSColor(srgbRed: 0.965, green: 0.953, blue: 0.925, alpha: 1)).setFill()
            rect.fill()
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: pad, y: 4)
            MenuBarItem.draw(shape, in: ctx, ink: ink.cgColor)
            if MenuBarItem.asking(shape) {
                NSColor(Palette.marigold).setFill()
                NSBezierPath(ovalIn: MenuBarItem.dot).fill()
            }
            return true
        }
        return bar
    }

    static func write(_ image: NSImage, _ url: URL) {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
