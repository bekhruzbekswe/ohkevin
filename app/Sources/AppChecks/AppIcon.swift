import AppKit
import CallViews

/// The app icon, drawn from the owner's logo set (design/logo): the glyph's SVG (bars and the marigold ball) on an ink squircle
/// (light) or a lifted one with a faint border (dark), on Apple's macOS grid (the 824-point body inside 1024, corners 22.5%). At 32
/// pixels and below the compact mark (five bars) is used, as the set says. build.sh makes AppIcon.icns from these PNGs.
enum AppIcon {
    static let logo = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../design/logo").standardized

    static func write(to folder: URL, dark: Bool = false) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try png(pixels: points * scale, compact: points * scale <= 32, dark: dark).write(to: folder.appending(path: name))
            }
        }
    }

    static func png(pixels: Int, compact: Bool, dark: Bool) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(size: CGFloat(pixels), compact: compact, dark: dark)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return CGColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: alpha)
    }

    static func draw(size: CGFloat, compact: Bool, dark: Bool) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let u = size / 1024
        ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: u, y: -u) // the grid's own space: 1024 units, y down
        let body = CGRect(x: 100, y: 100, width: 824, height: 824), radius = body.width * 0.225
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(color(dark ? "#34312C" : "#1B1A17")); ctx.fillPath()
        // The faint border of the set: 1 of 240 across the body, inside its edge.
        let ring = body.width / 240
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: ring / 2, dy: ring / 2), cornerWidth: radius - ring / 2, cornerHeight: radius - ring / 2, transform: nil))
        ctx.setStrokeColor(dark ? color("#F6F3EC", alpha: 0.14) : color("#1B1A17", alpha: 0.08)); ctx.setLineWidth(ring); ctx.strokePath()
        // The glyph: its SVG's viewBox (-23 -20 144 144) spans the body.
        let file = logo.appending(path: "app-icon\(compact ? "-compact" : "").svg") // one glyph for both looks; the squircle above changes
        guard let svg = try? String(contentsOf: file, encoding: .utf8) else { print("missing \(file.path)"); return }
        ctx.saveGState()
        ctx.translateBy(x: body.minX, y: body.minY); ctx.scaleBy(x: body.width / 144, y: body.height / 144); ctx.translateBy(x: 23, y: 20)
        if let art = LogoArt(svg: svg) { draw(art, in: ctx) }
        ctx.restoreGState()
    }
}

extension AppIcon {
    /// Draws a logo SVG's shapes in its own colours, in the SVG's own units (the caller has set the transform).
    static func draw(_ art: LogoArt, in ctx: CGContext) {
        for shape in art.shapes {
            ctx.setFillColor(color(shape.fill))
            switch shape.kind {
            case .bar(let x, let y, let w, let h, let r):
                ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil))
            case .ball(let cx, let cy, let r):
                ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            }
            ctx.fillPath()
        }
    }
}
