import SwiftUI
import VoiceCore

/// The mark's one geometry: a chevron (">") drawn as the design's rotated square with two borders, then bars. Used by the
/// panel's wave and by the menu-bar item, at their own sizes (system.css, sections 8, 12 and 13).
public enum Chevron {
    /// The centreline of the ">" for a box `box` wide whose left edge is at `left`, stroked `border` thick, centred at `cy`;
    /// `shift` is the design's translate(-shift, shift) before the 45° turn. Butt caps, mitred: stroke it with `lineWidth: border`.
    public static func path(left: CGFloat, cy: CGFloat, box: CGFloat, border: CGFloat, shift: CGFloat) -> Path {
        let r2 = CGFloat(2).squareRoot()
        let tip = left + box / 2 + box * r2 / 2 - r2 * shift
        let vertex = tip - border * r2 / 2, dx = (box - border / 2) * r2 / 2
        var p = Path()
        p.move(to: CGPoint(x: vertex - dx, y: cy - dx)); p.addLine(to: CGPoint(x: vertex, y: cy)); p.addLine(to: CGPoint(x: vertex - dx, y: cy + dx))
        return p
    }
    public static func style(_ w: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .miter, miterLimit: 10) }
}

/// The wave's bar heights in the panel and in the menu-bar item, and how they move: the design's own loops, a mark of the state,
/// never a measurement of the sound.
public enum WaveArt {
    public static let panel: [WaveKind: [CGFloat]] = [
        .listening: [6, 10, 14, 20, 24, 20, 14, 10, 8, 6, 4, 4, 4, 4, 4, 4],
        .speaking: [12, 24, 16, 34, 20, 36, 14, 28, 18, 32, 10, 22, 8, 14, 6, 10],
        .thinking: [3, 3, 3, 10, 18, 10, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
        .dots: Array(repeating: 3, count: 40), .waiting: Array(repeating: 3, count: 40), // as many as fit
    ]
    public static let small: [WaveKind: [CGFloat]] = [
        .listening: [4, 6, 8, 8, 6, 4], .speaking: [6, 12, 8, 12, 5, 10], .thinking: [2, 2, 10, 2, 2, 2],
        .dots: Array(repeating: 2, count: 6),
    ]
    /// With an asking dot beside it, the menu-bar wave keeps three bars.
    public static let asking: [WaveKind: [CGFloat]] = [.listening: [5, 8, 5], .speaking: [8, 12, 6], .thinking: [2, 10, 2], .dots: [2, 2, 2]]

    /// Bar `i` at time `t` (nil: still).
    public static func height(_ kind: WaveKind, _ base: CGFloat, _ i: Int, at t: Double?) -> CGFloat {
        guard let t else { return base }
        let wave = { (period: Double, delay: Double) in 0.5 - 0.5 * cos(2 * Double.pi * (t + delay) / period) } // 0 at rest, 1 at the far swing
        switch kind {
        case .listening: return base * (1 - 0.45 * wave(1.7, 0.06 * Double(i)))
        case .speaking: return base * (1 - 0.7 * wave(0.62, 0.23 * Double(i)))
        case .thinking: // three bars' bump (10, 18, 10) walks left to right, one bar every 120 ms
            let p = ((t - 0.12 * Double(i) + 2.16) / 1.08).truncatingRemainder(dividingBy: 1)
            let q = p < 0 ? p + 1 : p
            let h: Double = q < 0.12 ? 3 + 7 * q / 0.12 : q < 0.18 ? 10 + 8 * (q - 0.12) / 0.06 : q < 0.24 ? 18 - 8 * (q - 0.18) / 0.06 : q < 0.36 ? 10 - 7 * (q - 0.24) / 0.12 : 3
            return CGFloat(h)
        case .dots, .waiting: return base
        }
    }

    public static let minimumWidth: CGFloat = 34

    /// How many bars fit in `width` points (the design shows as many as fit before the word), never fewer than three. `minimumWidth` is what three bars need.
    public static func count(width: CGFloat, start: CGFloat, pitch: CGFloat, bar: CGFloat) -> Int { max(3, Int((width - start - bar) / pitch) + 1) }
}
