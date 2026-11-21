import AppKit
import CallViews
import SwiftUI
@testable import LauncherKit
import VoiceCore

/// `--settings-live <folder>`: the real Settings window, on screen, worked with real events (needs Accessibility permission to post
/// them) and photographed as it is on screen (needs nothing for its own window). It checks, light and dark, what the offscreen pictures
/// cannot: (1) an open list is solid over the rows below it; (2) a hovered list row, pill or switch shows only the design's flat tint,
/// never a system shape; (3) a click on a chooser shows no marigold focus ring, and a key then shows it. Pictures go to <folder>; the
/// window is closed and the pointer put back afterwards. Nothing is spoken and no call is started.
@MainActor
enum SettingsLive {
    private static var failures = 0
    private static var out: URL!
    private static var window: NSWindow!

    private static func check(_ ok: Bool, _ what: String) { print(ok ? "ok    \(what)" : "FAIL  \(what)"); fflush(stdout); if !ok { failures += 1 } }
    private static func sleep(_ s: Double = 0.35) async { try? await Task.sleep(for: .seconds(s)) }

    // MARK: Events (real ones, through the system)

    private static var primaryHeight: CGFloat { NSScreen.screens[0].frame.height }
    private static func cg(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }

    private static func move(_ p: NSPoint) async {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cg(p), mouseButton: .left)?.post(tap: .cghidEventTap)
        await sleep()
    }

    private static func click(_ p: NSPoint) async {
        await move(p)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cg(p), mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(60))
        }
        await sleep()
    }

    private static func key(_ code: CGKeyCode) async {
        for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap); try? await Task.sleep(for: .milliseconds(40)) }
        await sleep()
    }

    // MARK: The window's controls, by what they say

    private static func tree(_ e: Any) -> [NSObject] {
        let kids: [Any] = (e as? NSView)?.accessibilityChildren() ?? ((e as? NSObject)?.value(forKey: "accessibilityChildren") as? [Any]) ?? []
        return kids.compactMap { $0 as? NSObject }.flatMap { [$0] + tree($0) }
    }

    /// Screen rectangle (AppKit coordinates) of the control that says `label`.
    private static func frame(_ label: String) -> NSRect? {
        // The control, not the small label over it: both say the same words, but only the control is not static text.
        guard let e = tree(window.contentView!).first(where: { ($0.value(forKey: "accessibilityLabel") as? String) == label && ($0.value(forKey: "accessibilityRole") as? String) != "AXStaticText" }) else { return nil }
        return e.value(forKey: "accessibilityFrame") as? NSRect
    }

    private static func centre(_ r: NSRect) -> NSPoint { NSPoint(x: r.midX, y: r.midY) }

    // MARK: The window as it is on screen

    private struct Shot {
        let rep: NSBitmapImageRep, origin: NSRect, scale: CGFloat
        /// sRGB 0...255 at a screen point (AppKit coordinates).
        func rgb(_ p: NSPoint) -> [Double] {
            let x = Int((p.x - origin.minX) * scale), y = Int((origin.maxY - p.y) * scale)
            guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return [-1, -1, -1] }
            return [c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255]
        }
        func near(_ a: [Double], _ b: [Double], _ tol: Double) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) <= tol } }
        /// How many pixels of `r` are marigold (the focus ring's colour), judged by hue: the capture is colour-managed, so exact values move.
        func marigold(in r: NSRect) -> Int {
            var n = 0
            for x in stride(from: r.minX, to: r.maxX, by: 0.5) {
                for y in stride(from: r.minY, to: r.maxY, by: 0.5) {
                    let c = rgb(NSPoint(x: x, y: y))
                    if c[0] > 200, c[1] > 120, c[1] < 205, c[2] < 120, c[0] - c[2] > 110 { n += 1 }
                }
            }
            return n
        }
        /// How many pixels of `r` differ from the same place in `other`.
        func differences(in r: NSRect, from other: Shot) -> Int {
            var n = 0
            for x in stride(from: r.minX, to: r.maxX, by: 1) { for y in stride(from: r.minY, to: r.maxY, by: 1) { if !near(rgb(NSPoint(x: x, y: y)), other.rgb(NSPoint(x: x, y: y)), 3) { n += 1 } } }
            return n
        }
    }

    /// The window photographed by the window server (the system's own compositing: what the person sees), through the symbol the
    /// Swift SDK hides; if that is not there, the window's own view drawn.
    private static func shoot(_ name: String) -> Shot? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        var cgImage: CGImage?
        if let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") {
            cgImage = unsafeBitCast(sym, to: Capture.self)(.null, 1 << 3, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() // this window alone, without its shadow, at full resolution
        }
        let rep: NSBitmapImageRep
        var origin = window.frame
        if let cgImage { rep = NSBitmapImageRep(cgImage: cgImage) } else {
            guard let view = window.contentView, let r = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: r); rep = r
            origin = window.convertToScreen(view.convert(view.bounds, to: nil))
            print("      (no window-server capture: the window's own view is drawn instead)")
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appending(path: "\(name).png"))
        let scale = CGFloat(rep.pixelsWide) / origin.width
        return Shot(rep: rep, origin: origin, scale: scale)
    }

    // MARK: The walk

    static func run(folder: URL) async -> Int32 {
        out = folder
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard AXIsProcessTrusted() else { print("Posting real events needs Accessibility permission for the app that runs this (System Settings › Privacy & Security › Accessibility)."); return 2 }
        let home = FileManager.default.temporaryDirectory.appending(path: "settings-live-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let me = Launcher(settings: CallSettings(), defaults: nil, home: home, setup: Setup(callFolder: home, support: home, chromeProfile: home))
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            _ = NSApp.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: attribute)
        }
        window = AppDelegate.makeSettingsWindow(for: me)
        let screen = NSScreen.main!.visibleFrame
        window.setFrameTopLeftPoint(NSPoint(x: screen.minX + 80, y: screen.maxY - 40))
        let pointer = CGEvent(source: nil)?.location
        defer { window.close(); if let pointer { CGWarpMouseCursorPosition(pointer) } }

        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            print("— \(theme)")
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            await sleep(0.8)
            let away = NSPoint(x: window.frame.maxX + 60, y: window.frame.midY)
            await move(away)
            guard let rest = shoot("\(theme)-0-rest"), let pill = frame("A spoken “yes” approves"), let modelPill = frame("Claude Code model"),
                  let sw = frame("Open the work in Claude afterwards"), let login = frame("Open at login") else { check(false, "the Settings window and its controls are there (\(theme)); the window says: \(tree(window.contentView!).compactMap { ($0.value(forKey: "accessibilityLabel") as? String) }.filter { !$0.isEmpty })"); continue }
            print("      ground at the left edge: \(rest.rgb(NSPoint(x: window.frame.minX + 6, y: window.frame.midY)).map { Int($0) }); the model pill: \(rest.rgb(NSPoint(x: modelPill.maxX - 40, y: modelPill.midY)).map { Int($0) })")
            check(true, "the real Settings window is on screen, \(Int(window.frame.width)) × \(Int(window.frame.height)) (\(theme))")

            // (3) first, from rest: a click on a pill shows no ring; a key then does.
            let ringBox = pill.insetBy(dx: -7, dy: -7)
            await click(centre(pill))
            guard let opened = shoot("\(theme)-1-list-open") else { continue }
            check(frame("Any step") != nil, "a click on the spoken-yes pill opens its list (\(theme))")
            check(opened.marigold(in: ringBox) < 20,
                  "a mouse click shows no marigold ring on the pill (\(theme))")

            // (1) the open list is solid over the switch beneath it: every probe there is the list's own colour (read from a plain row;
            // the window server's colour management shifts absolute values, so the list is compared with itself).
            guard let plainRow = frame("Nothing") else { check(false, "the list's rows are there (\(theme))"); continue }
            let want = opened.rgb(NSPoint(x: plainRow.minX + 3, y: plainRow.midY))
            let probes = [centre(sw), NSPoint(x: sw.minX + 5, y: sw.minY + 5), NSPoint(x: sw.maxX - 5, y: sw.maxY - 5), NSPoint(x: sw.minX + 5, y: sw.maxY - 5), NSPoint(x: sw.midX + 10, y: sw.midY)]
            let seen: [[Int]] = probes.map { p in opened.rgb(p).map { Int($0) } }
            check(sw.intersects(plainRow.insetBy(dx: -200, dy: -200)) && probes.allSatisfy { opened.near(opened.rgb($0), want, 3) },
                  "the open list is solid over the switch beneath it: \(seen) against the list's own \(want.map { Int($0) }) (\(theme))")

            // (2) hover a list row: a flat full-row tint, corners included.
            if let row = frame("Any step"), let other = frame("Nothing") {
                await move(centre(row))
                if let hover = shoot("\(theme)-2-hover-row") {
                    let edge = hover.rgb(NSPoint(x: row.minX + 3, y: row.midY)), corner = hover.rgb(NSPoint(x: row.minX + 3, y: row.maxY - 3)), middle = hover.rgb(NSPoint(x: row.midX + 40, y: row.midY))
                    let plain = hover.rgb(NSPoint(x: other.minX + 3, y: other.midY))
                    let ints = { (c: [Double]) -> [Int] in c.map { Int($0) } }
                    check(!hover.near(edge, plain, 4) && hover.near(edge, corner, 3) && hover.near(edge, middle, 3),
                          "a hovered list row is one flat tint from edge to corner: edge \(ints(edge)) corner \(ints(corner)) middle \(ints(middle)) against the plain row \(ints(plain)) (\(theme))")
                }
            } else { check(false, "the list rows are there to hover (\(theme))") }
            await key(53) // Escape closes the list
            check(frame("Any step") == nil, "Escape closes the list (\(theme))")

            // Hover the pill and a switch: nothing may appear that is not the design's.
            await move(away)
            guard let still = shoot("\(theme)-3-rest-again") else { continue }
            await move(centre(modelPill))
            if let hover = shoot("\(theme)-4-hover-pill") { check(hover.differences(in: modelPill.insetBy(dx: -6, dy: -6), from: still) == 0, "hovering the pill draws nothing new, no system shape (\(theme))") }
            await move(centre(login))
            if let hover = shoot("\(theme)-5-hover-switch") { check(hover.differences(in: login.insetBy(dx: -6, dy: -6), from: still) == 0, "hovering a switch draws nothing new, no system shape (\(theme))") }
            await move(away)
            _ = rest

            // (3) a mouse click, list closed again by a second click: still no ring; then a key.
            await click(centre(modelPill)); await click(centre(modelPill))
            let clicked = shoot("\(theme)-6-after-clicks")
            let ring = modelPill.insetBy(dx: -7, dy: -7)
            check((clicked?.marigold(in: ring) ?? 99) < 20, "after clicks the pill has no marigold ring (\(theme))")
            await key(125) // Down arrow
            let arrow = shoot("\(theme)-7-after-arrow")
            let afterArrow = arrow?.marigold(in: ring) ?? 0
            await key(53)
            await key(48) // Tab
            let tab = shoot("\(theme)-8-after-tab")
            let afterTab = [modelPill, pill, sw, login].map { tab?.marigold(in: $0.insetBy(dx: -7, dy: -7)) ?? 0 }
            check(afterArrow > 40 || afterTab.contains { $0 > 40 }, "a key brings the marigold ring: \(afterArrow) marigold pixels on the pill after the arrow; after Tab on [model pill, yes pill, first switch, login switch]: \(afterTab) (\(theme))")
            await key(53)
        }
        print(failures == 0 ? "All live Settings checks passed." : "\(failures) live Settings check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}
