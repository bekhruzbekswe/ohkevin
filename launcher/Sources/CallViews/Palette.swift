import SwiftUI

/// The design's colours (design/system.css, section 1), light and dark, chosen by the view's own colour scheme
/// so a panel drawn into a picture matches the one on screen. Marigold appears only where it is the person's move.
public struct Palette: Sendable {
    public let ground, sunk, ink, ink2, ink3, onInk, accent, accentWord, accentDown, onAccent, wrong, wrongOnInk, pill, done: Color
    /// The hairline and the pill's well (End call's disc) are the ink at a fixed strength; `dark` only changes the well.
    public let hair, well, shadow1, shadow2: Color

    private static func hex(_ v: UInt32) -> Color { Color(.sRGB, red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255) }

    public static let light = Palette(ground: hex(0xF6F3EC), sunk: hex(0xECE8DF), ink: hex(0x1B1A17), ink2: hex(0x57534B), ink3: hex(0x6B665D),
                               onInk: hex(0xF6F3EC), accent: marigold, accentWord: hex(0xD98E0B), accentDown: hex(0xE2951A), onAccent: hex(0x1B1A17), wrong: hex(0xB82E24),
                               wrongOnInk: hex(0xFF8073), pill: hex(0xFFFFFF), done: hex(0x256B42), hair: hex(0x1B1A17).opacity(0.12), well: hex(0x1B1A17).opacity(0.10),
                               shadow1: hex(0x1B1A17).opacity(0.10), shadow2: hex(0x1B1A17).opacity(0.08))
    public static let dark = Palette(ground: hex(0x181715), sunk: hex(0x262421), ink: hex(0xF6F3EC), ink2: hex(0xB5B0A6), ink3: hex(0x9A958B),
                              onInk: hex(0x1B1A17), accent: marigold, accentWord: marigold, accentDown: hex(0xFFB84A), onAccent: hex(0x1B1A17), wrong: hex(0xFF8073),
                              wrongOnInk: hex(0xB82E24), pill: hex(0x4D4941), done: hex(0x73C795), hair: hex(0xF6F3EC).opacity(0.14), well: Color.black.opacity(0.30),
                              shadow1: Color.black.opacity(0.5), shadow2: Color.black.opacity(0.35))

    /// The one accent, the same in both appearances: "your move".
    public static let marigold = hex(0xF4A62A)

    public init(_ scheme: ColorScheme) { self = scheme == .dark ? .dark : .light }
    private init(ground: Color, sunk: Color, ink: Color, ink2: Color, ink3: Color, onInk: Color, accent: Color, accentWord: Color, accentDown: Color, onAccent: Color,
                 wrong: Color, wrongOnInk: Color, pill: Color, done: Color, hair: Color, well: Color, shadow1: Color, shadow2: Color) {
        self.ground = ground; self.sunk = sunk; self.ink = ink; self.ink2 = ink2; self.ink3 = ink3; self.onInk = onInk
        self.accent = accent; self.accentWord = accentWord; self.accentDown = accentDown; self.onAccent = onAccent; self.wrong = wrong; self.wrongOnInk = wrongOnInk
        self.pill = pill; self.done = done; self.hair = hair; self.well = well; self.shadow1 = shadow1; self.shadow2 = shadow2
    }
}
