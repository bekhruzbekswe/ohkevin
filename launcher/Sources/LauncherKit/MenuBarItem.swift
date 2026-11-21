import AppKit
import CallViews
import SwiftUI
import VoiceCore

/// The menu-bar item: one box, 52 × 22, in every state, drawn in whole pixels as a template image (the bar tints it), so
/// only shape tells the states apart. The marigold dot of "someone asks" is the one coloured thing, a layer on the button.
enum MenuBarItem {
    static let size = CGSize(width: 52, height: 22)
    /// Where the asking dot sits (centre, y down).
    static let dot = CGRect(x: 34, y: 7, width: 8, height: 8)

    /// Draws the shape in the 52 × 22 box, y down, in `ink` (the dot not included).
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
        case .rest(let setup): // ">_", with a ring while steps remain
            let width: CGFloat = 16.8 + (setup ? 12 : 0), x0 = ((size.width - width) / 2).rounded()
            chevron(left: x0, box: 8.25, border: 1.95, shift: 0.9)
            ctx.addPath(CGPath(roundedRect: CGRect(x: x0 + 9.3, y: cy + 4.05, width: 7.5, height: 1.95), cornerWidth: 0.975, cornerHeight: 0.975, transform: nil)); ctx.fillPath()
            if setup { ctx.setLineWidth(1.5); ctx.strokeEllipse(in: CGRect(x: x0 + 21.8 + 0.75, y: cy - 2.75, width: 5.5, height: 5.5)) }
        case .lost: // ">!"
            let x0 = (((asking(shape) ? dot.minX : size.width) - 12.9) / 2).rounded()
            chevron(left: x0, box: 8.25, border: 1.95, shift: 0.9)
            ctx.fill(CGRect(x: x0 + 10.8, y: cy - 6.9, width: 2.1, height: 8.28)); ctx.fill(CGRect(x: x0 + 10.8, y: cy + 4.416, width: 2.1, height: 2.484))
        case .reconnecting:
            let x0 = (((asking(shape) ? dot.minX : size.width) - 20) / 2).rounded()
            chevron(left: x0, box: 8, border: 2, shift: 1)
            bars(Array(repeating: 2, count: 3), from: x0 + 10)
        case .call(let kind, let muted, let asking):
            ctx.beginTransparencyLayer(auxiliaryInfo: nil) // the knocked-out wave of a muted pill clears only this layer
            defer { ctx.endTransparencyLayer() }
            let pill = CGRect(x: 4, y: 2, width: 44, height: 18)
            let hs = (asking ? WaveArt.asking : WaveArt.small)[kind] ?? WaveArt.small[.dots]!
            if muted { // turned over: solid, the wave knocked out
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

    static func words(_ shape: MenuShape) -> String { base(shape) + (asking(shape) ? ", Claude Code needs you" : "") }

    private static func base(_ shape: MenuShape) -> String {
        switch shape {
        case .rest(let setup): setup ? "\(Product.shortName), setup" : "\(Product.shortName), ready"
        case .lost: "\(Product.shortName), the call needs attention"
        case .reconnecting: "\(Product.shortName), reconnecting"
        case .call(_, let muted, _): "\(Product.shortName), on a call\(muted ? ", muted" : "")"
        }
    }
}
