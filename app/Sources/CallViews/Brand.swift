import SwiftUI

/// The brand mark of the owner's logo set (design/logo): bars arcing to the marigold ball. The two SVGs below are copies of
/// mark-full-ink.svg and mark-compact-ink.svg; a test (CallViewsTests) checks them against the files so there is one source. Shapes are only
/// rectangles (bars) and circles (the ball), read by `LogoArt`.
public struct LogoShape: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bar(x: Double, y: Double, width: Double, height: Double, radius: Double)
        case ball(cx: Double, cy: Double, r: Double)
    }
    public let kind: Kind
    /// The SVG's own fill: the marigold ball is #F4A62A; every other shape is the mark's ink.
    public let fill: String
    public var isBall: Bool { if case .ball = kind { true } else { false } }
}

/// A logo SVG read as shapes: its `viewBox` and its bars and ball.
public struct LogoArt: Equatable, Sendable {
    public let viewBox: CGRect
    public let shapes: [LogoShape]

    public init?(svg: String) {
        func attributes(_ tag: String) -> [String: String] {
            var out: [String: String] = [:]
            for m in try! NSRegularExpression(pattern: #"([A-Za-z]+)="([^"]*)""#).matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                out[String(tag[Range(m.range(at: 1), in: tag)!])] = String(tag[Range(m.range(at: 2), in: tag)!])
            }
            return out
        }
        let box = (attributes(svg.components(separatedBy: ">").first ?? "")["viewBox"] ?? "").split(separator: " ").compactMap { Double($0) }
        guard box.count == 4 else { return nil }
        viewBox = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        var found: [LogoShape] = []
        for m in try! NSRegularExpression(pattern: #"<(rect|circle)\b[^>]*>"#).matches(in: svg, range: NSRange(svg.startIndex..., in: svg)) {
            let tag = String(svg[Range(m.range, in: svg)!]), a = attributes(tag), n = { (k: String) in Double(a[k] ?? "0") ?? 0 }
            let fill = a["fill"] ?? "#000000"
            found.append(tag.hasPrefix("<rect") ? LogoShape(kind: .bar(x: n("x"), y: n("y"), width: n("width"), height: n("height"), radius: n("rx")), fill: fill)
                                                : LogoShape(kind: .ball(cx: n("cx"), cy: n("cy"), r: n("r")), fill: fill))
        }
        shapes = found
    }
}

/// The mark's two forms: the full mark (ten bars), and the compact one (five) for 32 pixels and below.
public enum Logo {
    public static let fullSVG = """
<svg viewBox="4 18 90 68" width="80%" height="80%" xmlns="http://www.w3.org/2000/svg"><rect x="6" y="77" width="4" height="6" rx="2" fill="#1B1A17"></rect><rect x="13.560000000000002" y="59.58000000000001" width="4" height="10" rx="2" fill="#1B1A17"></rect><rect x="21.040000000000003" y="44.92000000000001" width="4" height="14" rx="2" fill="#1B1A17"></rect><rect x="28.44" y="33.019999999999996" width="4" height="18" rx="2" fill="#1B1A17"></rect><rect x="35.76" y="24.879999999999995" width="4" height="20" rx="2" fill="#1B1A17"></rect><rect x="43" y="21.5" width="4" height="18" rx="2" fill="#1B1A17"></rect><rect x="50.16000000000001" y="21.879999999999995" width="4" height="14" rx="2" fill="#1B1A17"></rect><rect x="57.24000000000001" y="25.02" width="4" height="10" rx="2" fill="#1B1A17"></rect><rect x="64.24000000000001" y="29.92000000000001" width="4" height="8" rx="2" fill="#1B1A17"></rect><rect x="71.16000000000001" y="37.58" width="4" height="6" rx="2" fill="#1B1A17"></rect><circle cx="82.2" cy="54.8" r="10" fill="#F4A62A"></circle></svg>
"""
    public static let compactSVG = """
<svg viewBox="4 18 90 68" width="80%" height="80%" xmlns="http://www.w3.org/2000/svg"><rect x="4.25" y="75" width="7.5" height="10" rx="3.75" fill="#1B1A17"></rect><rect x="19.290000000000003" y="42.92000000000001" width="7.5" height="18" rx="3.75" fill="#1B1A17"></rect><rect x="34.01" y="22.879999999999995" width="7.5" height="24" rx="3.75" fill="#1B1A17"></rect><rect x="48.41000000000001" y="18.879999999999995" width="7.5" height="20" rx="3.75" fill="#1B1A17"></rect><rect x="62.49000000000001" y="27.92000000000001" width="7.5" height="12" rx="3.75" fill="#1B1A17"></rect><circle cx="82.5" cy="55.2" r="10.5" fill="#F4A62A"></circle></svg>
"""
    public static let full = LogoArt(svg: fullSVG)!
    public static let compact = LogoArt(svg: compactSVG)!
}

/// The brand mark as a view: ink bars (paper in dark) arcing to the always-marigold ball. It takes its size from its frame (height
/// first, the aspect kept). Use `compact` at small sizes (32 pixels and below), as the logo set says.
public struct BrandMark: View {
    let compact: Bool
    @Environment(\.colorScheme) private var scheme

    public init(compact: Bool = false) { self.compact = compact }

    public var body: some View {
        let art = compact ? Logo.compact : Logo.full, c = Palette(scheme)
        Canvas { ctx, size in
            let k = min(size.width / art.viewBox.width, size.height / art.viewBox.height)
            let dx = (size.width - art.viewBox.width * k) / 2 - art.viewBox.minX * k, dy = (size.height - art.viewBox.height * k) / 2 - art.viewBox.minY * k
            for s in art.shapes {
                let color = s.isBall ? Palette.marigold : c.ink
                switch s.kind {
                case .bar(let x, let y, let w, let h, let r):
                    ctx.fill(Path(roundedRect: CGRect(x: x * k + dx, y: y * k + dy, width: w * k, height: h * k), cornerRadius: min(r, w / 2, h / 2) * k), with: .color(color))
                case .ball(let cx, let cy, let r):
                    ctx.fill(Path(ellipseIn: CGRect(x: (cx - r) * k + dx, y: (cy - r) * k + dy, width: 2 * r * k, height: 2 * r * k)), with: .color(color))
                }
            }
        }
        .aspectRatio(art.viewBox.width / art.viewBox.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
