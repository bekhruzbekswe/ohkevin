import AppKit
import CallKit
import CallViews
import SwiftUI

// The shared visual system (design/system.css) as SwiftUI values: its tokens, the mark, the buttons, the state word,
// the worker card and the bubbles. The names follow the stylesheet's, so one can be checked against the other.

/// A view's own small state. shortcut: @State is a macro the Command Line Tools cannot expand; a published box does the same job.
final class Box<T>: ObservableObject { @Published var value: T; init(_ v: T) { value = v } }

// MARK: - Tokens

enum CV {
    private static func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
        func c(_ v: UInt32, _ a: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
        }
        return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? c(dark, da) : c(light, la) })
    }
    // surfaces
    static let ground = dyn(0xF6F3EC, 0x181715), raised = dyn(0xFFFFFF, 0x38352F), sunk = dyn(0xECE8DF, 0x262421)
    static let hair = dyn(0x1B1A17, 0xF6F3EC, 0.12, 0.14)
    // ink
    static let ink = dyn(0x1B1A17, 0xF6F3EC), ink2 = dyn(0x57534B, 0xB5B0A6), ink3 = dyn(0x6B665D, 0x9A958B), onInk = dyn(0xF6F3EC, 0x1B1A17)
    static let you = dyn(0x36332D, 0xD6D0C3), onYou = dyn(0xF6F3EC, 0x1B1A17) // your bubble: the one solid, strongest shape (not pure black or white)
    static let voiceBubble = dyn(0xE9E4DA, 0x2E2B27) // --cv-voice: the voice's bubble, a quiet grey
    // the one accent: your move
    static let accent = dyn(0xF4A62A, 0xF4A62A), accentDown = dyn(0xE2951A, 0xFFB84A), onAccent = dyn(0x1B1A17, 0x1B1A17)
    static let accentInk = dyn(0x8A5000, 0xF4B551)
    static let accentWord = dyn(0xD98E0B, 0xF4A62A) // marigold as words on the bar: a little deeper in light
    // state words
    static let done = dyn(0x256B42, 0x73C795), wrong = dyn(0xB82E24, 0xFF8073), wrongOnInk = dyn(0xFF8073, 0xB82E24)
    // shadow, one for each theme
    static let shadowNear = dyn(0x1B1A17, 0x000000, 0.06, 0.4), shadowFar = dyn(0x1B1A17, 0x000000, 0.08, 0.35)

    // type: the four sizes. The voice is the serif (New York); you, the workers and every control are SF.
    static let display = DisplaySerif.font(size: 48), title = Font.system(size: 22, weight: .semibold)
    static let body = Font.system(size: 17), bodyBold = Font.system(size: 17, weight: .semibold), small = Font.system(size: 14)
    static let mono = Font.system(size: 14, design: .monospaced)
    static let voice = DisplaySerif.font(size: 17), question = DisplaySerif.font(size: 22) // the shared serif (CallViews), as the panel draws it
    static let stateWord = DisplaySerif.font(size: 22, italic: true)

    // space: one unit of 8, and the half step
    static let s0: CGFloat = 4, s1: CGFloat = 8, sh: CGFloat = 12, s2: CGFloat = 16, s3: CGFloat = 24, s4: CGFloat = 40, s5: CGFloat = 64
    // shape and fixed measures
    static let radius: CGFloat = 20, tail: CGFloat = 6, control: CGFloat = 48, bar: CGFloat = 64
    static let capsule: CGFloat = 200, slot: CGFloat = 120, rail: CGFloat = 400, chatAlone: CGFloat = 720
}

extension View {
    /// The system's one shadow (--cv-shadow).
    func cvShadow() -> some View { shadow(color: CV.shadowNear, radius: 1, y: 1).shadow(color: CV.shadowFar, radius: 12, y: 8) }
    /// Body text's 24-point line.
    func bodyLines() -> some View { lineSpacing(3.5).padding(.vertical, 1.75) } // 24 on 17: between lines, and above and below one
}

// MARK: - The mark: chevron and three bars, the voice itself

struct CVMark: View {
    enum Motion { case still, listening, speaking, thinking, muted, waiting }
    var motion: Motion = .still
    var size: CGFloat
    var color: Color = CV.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = !reduceMotion && [.listening, .speaking, .thinking, .waiting].contains(motion)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { tl in
            Canvas { ctx, sz in draw(ctx, em: sz.height, t: moving ? tl.date.timeIntervalSinceReferenceDate : 0) }
        }
        .frame(width: size * 1.29, height: size)
        .accessibilityHidden(true)
    }

    /// system.css section 8, in units of the mark's height.
    private func draw(_ ctx: GraphicsContext, em: CGFloat, t: Double) {
        var chevron = Path()
        chevron.move(to: CGPoint(x: 0.079 * em, y: 0.249 * em)); chevron.addLine(to: CGPoint(x: 0.33 * em, y: 0.5 * em)); chevron.addLine(to: CGPoint(x: 0.079 * em, y: 0.751 * em))
        ctx.stroke(chevron, with: .color(color), style: StrokeStyle(lineWidth: 0.13 * em, lineCap: .butt, lineJoin: .miter))
        let dots = motion == .muted || motion == .waiting
        for (i, (x, h)) in zip([0.62, 0.89, 1.16], [0.55, 1.0, 0.7]).enumerated() {
            let phase = t + 0.25 * Double(i) // the stylesheet's delays: 0, -.25 s, -.5 s
            func wave(_ period: Double) -> Double { 0.5 - 0.5 * cos(2 * .pi * phase / period) } // 0 → 1 → 0, ease-in-out
            var height = dots ? 0.13 : motion == .thinking ? 0.55 : h, opacity = 1.0
            switch motion {
            case .listening: height *= 1 - 0.2 * wave(2.4)
            case .speaking: height *= 1 - 0.55 * wave(0.7)
            case .thinking, .waiting: if t != 0 { opacity = 1 - 0.65 * wave(1.2) }
            default: break
            }
            let r = CGRect(x: x * em, y: (0.5 - height / 2) * em, width: 0.13 * em, height: height * em)
            ctx.fill(Path(roundedRect: r, cornerRadius: min(0.1 * em, r.height / 2)), with: .color(color.opacity(opacity)))
        }
    }
}

// MARK: - Buttons

/// .cv-btn: quiet (sunk; on a card or a raised surface, ink at 9%), primary (marigold, one per view), danger (red words).
struct CVButton: ButtonStyle {
    enum Kind { case quiet, primary, danger }
    var kind = Kind.quiet
    var onCard = false
    var wide = false
    @Environment(\.isEnabled) private var enabled
    @StateObject private var hovered = Box(false)
    private var hover: Bool { hovered.value }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CV.bodyBold).tracking(-0.17).lineLimit(1)
            .foregroundStyle(kind == .primary ? CV.onAccent : kind == .danger ? CV.wrong : CV.ink)
            .padding(.horizontal, CV.s3)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: CV.control, maxHeight: CV.control)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.35)
            .onHover { hovered.value = $0 }
    }
    private var fill: Color { kind == .primary ? (hover && enabled ? CV.accentDown : CV.accent) : onCard ? CV.ink.opacity(0.09) : CV.sunk }
}

/// .cv-btn--pick: a chooser, its value on the left and up/down arrows on the right.


// MARK: - The state word (Working, Asking, Waiting, Done)

struct StateWord: View {
    let state: Card.State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: CV.s1) {
            Text(state.rawValue).font(state == .working ? CV.body : CV.bodyBold).tracking(-0.17)
            sign.frame(width: 15, height: 14)
        }
        .foregroundStyle(color)
        .fixedSize()
    }
    private var color: Color { switch state { case .working: CV.ink2; case .asking, .waiting: CV.accentInk; case .done: CV.done } }

    @ViewBuilder private var sign: some View {
        switch state {
        case .working: // three bars that pulse
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
                let o = reduceMotion ? 1 : 0.675 + 0.325 * cos(2 * .pi * tl.date.timeIntervalSinceReferenceDate / 1.4)
                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).frame(width: 3, height: 14) } }.opacity(o)
            }
        case .done: Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
        default: Circle().frame(width: 8, height: 8)
        }
    }
}

// MARK: - The worker card

/// .cv-card: a worker at rest (name, state, one sentence; it is a button that opens in place), on one line when the rail is
/// full, or .cv-card--ask: the request itself, with a gold outline and no gold fill.
struct WorkerCard: View {
    let card: Card
    var line = false
    let open: Bool
    /// Stop: a working worker's card.
    let canStop: Bool
    let press: () -> Void
    let openInClaude: () -> Void
    let stop: () -> Void
    let close: () -> Void
    let answer: (Bool) -> Void

    var body: some View {
        if let a = card.approval { ask(a) } else { resting }
    }

    private var head: some View {
        HStack(spacing: CV.s2) {
            Text(card.name).font(card.approval != nil ? CV.bodyBold : CV.title).tracking(card.approval != nil ? -0.17 : -0.44).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            StateWord(state: card.state)
            if card.approval == nil {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(CV.ink3)
                    .rotationEffect(.degrees(open ? 90 : 0)).animation(.easeOut(duration: 0.2), value: open)
            }
        }
        .frame(minHeight: 28)
    }

    private var resting: some View {
        VStack(alignment: .leading, spacing: CV.s0) {
            head
            if !line || open {
                Text(card.sentence).font(CV.body).tracking(-0.17).bodyLines().foregroundStyle(CV.ink2).lineLimit(open ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if open {
                HStack(spacing: CV.s1) {
                    Button("Open in Claude", action: openInClaude).buttonStyle(CVButton(onCard: true, wide: true)).disabled(card.session == nil)
                        .help(card.session == nil ? "Its Claude Code session has not started yet" : "Opens this worker’s session in the Claude app")
                    if card.state == .done { Button("Close", action: close).buttonStyle(CVButton(kind: .danger, onCard: true)) }
                    else if canStop { Button("Stop", action: stop).buttonStyle(CVButton(kind: .danger, onCard: true)) }
                }
                .padding(.top, CV.sh)
            }
        }
        .padding(.vertical, CV.s2).padding(.horizontal, CV.s3)
        .background(CV.sunk, in: RoundedRectangle(cornerRadius: CV.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CV.radius, style: .continuous).strokeBorder(CV.hair, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: CV.radius, style: .continuous))
        .onTapGesture(perform: press)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.name), \(card.state.rawValue). \(card.sentence)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: open ? "Close the card" : "Open the card", press)
    }

    private func ask(_ a: Approval) -> some View {
        VStack(alignment: .leading, spacing: CV.s2) {
            head
            VStack(alignment: .leading, spacing: CV.s1) {
                Text(card.sentence).font(CV.question).tracking(-0.22).foregroundStyle(CV.ink).fixedSize(horizontal: false, vertical: true)
                Text(a.exact).font(CV.mono).foregroundStyle(CV.ink2).lineLimit(4).truncationMode(.middle).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: CV.s1) {
                Button("Deny") { answer(false) }.buttonStyle(CVButton(onCard: true)).help("Deny (⌘⌫)")
                Button { answer(true) } label: {
                    HStack(spacing: CV.s1) {
                        if a.byVoice { CVMark(motion: .listening, size: 16, color: CV.onAccent) } // a spoken yes counts
                        Text(a.byVoice ? "Approve" : "Click to approve")
                    }
                }
                .buttonStyle(CVButton(kind: .primary, wide: true)).help("Approve (⌘↩)")
            }
            .disabled(a.busy)
        }
        .padding(CV.s3)
        .background(CV.sunk, in: RoundedRectangle(cornerRadius: CV.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CV.radius, style: .continuous).strokeBorder(CV.accent, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.name) asks: \(card.sentence) \(a.exact)")
    }
}

// MARK: - Bubbles

/// One speaker's run of bubbles: the voice on the left in the serif on the raised fill, you on the right in SF on ink.
/// The last bubble's corner nearest its speaker is the tail.
/// One thing said: words not yet said (unsaid), still being heard (live), or a problem the server reported (wrong: red words).
struct Said { var text: String; var unsaid = ""; var live = false; var wrong = false }

struct TurnView: View {
    let voice: Bool
    let lines: [Said]
    let width: CGFloat

    var body: some View {
        VStack(alignment: voice ? .leading : .trailing, spacing: CV.s0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                bubble(l, last: i == lines.count - 1)
            }
        }
        .frame(maxWidth: width, alignment: voice ? .leading : .trailing)
        .frame(maxWidth: .infinity, alignment: voice ? .leading : .trailing)
    }

    private func bubble(_ l: Said, last: Bool) -> some View {
        let tail = last ? CV.tail : CV.radius
        let shape = UnevenRoundedRectangle(topLeadingRadius: CV.radius, bottomLeadingRadius: voice ? tail : CV.radius,
                                           bottomTrailingRadius: voice ? CV.radius : tail, topTrailingRadius: CV.radius, style: .continuous)
        return words(l)
            .font(voice ? CV.voice : CV.body).tracking(voice ? 0 : -0.17).bodyLines()
            .padding(.vertical, CV.sh).padding(.horizontal, CV.s3)
            .background(voice ? CV.voiceBubble : CV.you, in: shape)
            .textSelection(.enabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((l.wrong ? "Problem: " : voice ? "Claude: " : "You: ") + l.text)
    }

    /// Words still being heard or said are lighter; the part of a cut-off sentence never said, too.
    private func words(_ l: Said) -> Text {
        let full = l.wrong ? CV.wrong : voice ? CV.ink : CV.onYou, light = voice ? CV.ink3 : CV.onYou.opacity(0.65)
        guard !l.unsaid.isEmpty else { return Text(l.text).foregroundStyle(l.live ? light : full) }
        let said = String(l.text.dropLast(l.unsaid.count)).trimmingCharacters(in: .whitespaces)
        return Text("\(Text(said).foregroundStyle(full)) \(Text(l.unsaid).foregroundStyle(light))")
    }
}

/// The corner's three quiet dots (.cv-more), filled while pointed at or while Settings is open. One press opens or closes Settings. At the trailing edge of the title bar.
struct CornerDots: View {
    let settings: AppSettings
    let press: () -> Void
    @StateObject private var hover = Box(false)
    var body: some View {
        Button(action: press) {
            HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 4, height: 4) } }
                .frame(width: 28, height: 28)
                .background(Circle().fill(CV.ink.opacity(hover.value || settings.shown ? 0.09 : 0)))
                .foregroundStyle(hover.value || settings.shown ? CV.ink : CV.ink2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
        .help("More").accessibilityLabel("More")
    }
}
