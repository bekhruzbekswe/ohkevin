import AppKit
import SwiftUI
import VoiceCore

/// The panel (design/spec.md): 320 × 228 in every state, inset 16, three rows: the head, the pill, the door.
/// It is given plain data and sends intents; it reaches into nothing (so it can move to a shared module unchanged).
public struct PanelView: View {
    let data: PanelData
    /// The panel is on screen: only then do the clock tick and the wave move.
    let active: Bool
    /// Draws the wave still (pictures, tests).
    let still: Bool
    let send: (PanelIntent) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(data: PanelData, active: Bool = true, still: Bool = false, send: @escaping (PanelIntent) -> Void) {
        self.data = data; self.active = active; self.still = still; self.send = send
    }

    /// 320 × 228; with the update line 281: it adds 16 above its hairline, the hairline, 12 and its row of 24 (the card grows by 53).
    public static let size = CGSize(width: 320, height: 228)
    public static func size(for data: PanelData) -> CGSize { data.line == nil ? size : CGSize(width: size.width, height: size.height + 16 + 1 + 12 + LineView.rowHeight) }

    public var body: some View {
        let c = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            Head(data: data, active: active, c: c).frame(height: 52)
            Group {
                switch data.pill {
                case .project(let p): ProjectChooser(pill: p, c: c, send: send)
                case .call(let p): CallBar(pill: p, c: c, animate: active && !still && !reduceMotion && p.wave != .dots, send: send)
                }
            }
            .padding(.top, 16)
            DoorButton(door: data.door, c: c) { send(.door(data.door.action)) }.padding(.top, 16)
            if let line = data.line { LineView(line) { send(.line($0)) }.padding(.top, 16) }
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size(for: data).height, alignment: .topLeading)
        .overlay(alignment: .topTrailing) { Corner(data: data, c: c, send: send).padding(.top, 16).padding(.trailing, 10) }
        .background(c.ground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(c.hair, lineWidth: 1))
    }
}

/// Whether the pointer is over a control (`@State` is a macro the Command Line Tools cannot expand).
final class Pointer: ObservableObject { @Published var over = false }

/// A control's pill shape: fully rounded ends (a rounded rectangle, which draws cleanly into pictures too).
struct Pill: InsettableShape {
    let h: CGFloat
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path { Path(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: h / 2 - inset, style: .circular) }
    func inset(by amount: CGFloat) -> Pill { Pill(h: h, inset: inset + amount) }
}

// MARK: - Head: line 1 at 22, line 2 at 17

private struct Head: View {
    let data: PanelData
    let active: Bool
    let c: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            line1.lineLimit(1).truncationMode(.tail).padding(.trailing, 36).frame(height: 28, alignment: .leading).accessibilityLabel(data.line1)
            line2.font(.system(size: 17)).tracking(-0.17).monospacedDigit().foregroundStyle(c.ink2).lineLimit(1).truncationMode(.tail).frame(height: 24, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var line1: some View {
        switch data.style {
        case .plain: Text(data.line1).font(.system(size: 22, weight: .semibold)).tracking(-0.44).foregroundStyle(c.ink)
        case .ours: Text(data.line1).font(DisplaySerif.font(size: 22)).tracking(-0.22).foregroundStyle(c.ink)
        case .wrong: Text(data.line1).font(DisplaySerif.font(size: 22, italic: true)).foregroundStyle(c.wrong)
        case .ask:
            (Text("We need ").foregroundStyle(c.ink) + Text("you").foregroundStyle(c.accent)).font(.system(size: 22, weight: .semibold)).tracking(-0.44)
        }
    }

    /// Line 2 is its own accessibility element; the clock is read afresh at every tick (a stopped panel draws it once).
    @ViewBuilder private var line2: some View {
        switch data.line2 {
        case .text(let s): Text(s)
        case .timer(let since):
            if active { TimelineView(.periodic(from: since, by: 1)) { tl in clock(tl.date.timeIntervalSince(since)) } }
            else { TimelineView(.explicit([])) { tl in clock(tl.date.timeIntervalSince(since)) } }
        }
    }

    private func clock(_ seconds: TimeInterval) -> some View {
        let s = max(0, Int(seconds))
        return Text(timer(TimeInterval(s))).accessibilityLabel("\(s / 60) minutes \(s % 60) seconds")
    }
}

// MARK: - The corner: Settings and Quit behind three dots

private struct Corner: View {
    let data: PanelData
    let c: Palette
    let send: (PanelIntent) -> Void
    @StateObject private var pointer = Pointer()

    var body: some View {
        Menu {
            Button("Settings…") { send(.settings) }
            if data.canUpdate { Button("Check for Updates…") { send(.checkForUpdates) } }
            if data.failed { Button("Show Details") { send(.showDetails) } }
            Divider()
            Button(data.onCall ? "End Call and Quit" : "Quit \(Product.name)") { send(.quit) }
        } label: {
            ZStack {
                Circle().fill(pointer.over ? c.ink.opacity(0.09) : .clear)
                HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Circle().fill(pointer.over ? c.ink : c.ink2).frame(width: 4, height: 4) } }
            }
            .frame(width: 28, height: 28).contentShape(Circle())
            .modifier(FocusRing(shape: Circle(), ring: c.accent))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusEffectDisabled().fixedSize()
        .frame(width: 28, height: 28)
        .onHover { pointer.over = $0 }
        .accessibilityLabel("More")
    }
}

// MARK: - The pill before a call: the folder chooser, outlined

private struct ProjectChooser: View {
    let pill: ProjectPill
    let c: Palette
    let send: (PanelIntent) -> Void

    /// With no recent projects the list would hold only "Choose a folder…", so a press goes straight to the folder panel.
    var body: some View {
        Group {
            if pill.choices.isEmpty {
                Button { send(.door(.chooseProject)) } label: { label }
                    .buttonStyle(.plain).focusEffectDisabled()
            } else {
                Menu {
                    ForEach(pill.choices, id: \.path) { choice in
                        Button { send(.pick(choice.path)) } label: { if choice.current { Label(choice.label, systemImage: "checkmark") } else { Text(choice.label) } }
                    }
                    Divider()
                    Button("Choose a folder…") { send(.door(.chooseProject)) }
                } label: { label }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusEffectDisabled()
            }
        }
        .allowsHitTesting(pill.enabled).focusable(pill.enabled).opacity(pill.enabled ? 1 : 0.45) // not .disabled: that dims the pill a second time
        .accessibilityLabel(pill.name.map { "Project, \($0). Menu." } ?? (pill.choices.isEmpty ? "Choose a project." : "Choose a project. Menu."))
    }

    private var label: some View {
        HStack(spacing: 0) {
            Folder(color: c.ink2).frame(width: 48, height: 48)
            Text(pill.name.map { fittedName($0) } ?? "No project yet")
                .font(.system(size: 22, weight: pill.name == nil ? .regular : .semibold)).tracking(-0.44)
                .foregroundStyle(pill.name == nil ? c.ink2 : c.ink).lineLimit(1).truncationMode(.middle)
                .padding(.leading, 8).frame(maxWidth: .infinity, alignment: .leading)
            Arrows(color: c.ink3).frame(width: 48, height: 48)
        }
        .padding(.horizontal, 8).frame(height: 64)
        .overlay(Pill(h: 64).inset(by: 0.75).stroke(c.ink3, lineWidth: 1.5))
        .compositingGroup() // the folder's tab and body fade as one, not each on its own
        .contentShape(Capsule())
        .modifier(FocusRing(shape: Pill(h: 64), ring: c.accent))
    }
}

/// The room the project's name has in the chooser, and the name cut to it: `middleCut` at the longest length that measures
/// as fitting, so a name of wide letters is cut at its separators too, never inside a word by the view.
public let chooserNameWidth: CGFloat = 166
public func fittedName(_ name: String, width: CGFloat = chooserNameWidth) -> String {
    let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
    func fits(_ s: String) -> Bool { NSAttributedString(string: s, attributes: [.font: font, .kern: -0.44]).size().width <= width }
    var n = name.count
    while n > 6 {
        let cut = middleCut(name, n)
        if fits(cut) { return cut }
        n -= 1
    }
    return middleCut(name, 6)
}

private struct Folder: View {
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 20, height: 15).offset(y: 3)
            UnevenRoundedRectangle(topLeadingRadius: 2.5, topTrailingRadius: 2.5).fill(color).frame(width: 9, height: 6).offset(x: -5.5, y: -4.5)
        }
        .accessibilityHidden(true)
    }
}

struct Arrows: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            // system.css .cv-arrows: 10 × 16, two chevrons of 2-point strokes (a rotated 8-point square's two borders each)
            let x = (size.width - 10) / 2 + 5, y = (size.height - 16) / 2
            for up in [true, false] {
                var p = Path(); let apex = up ? y + 0.75 : y + 15.25, end = up ? y + 5.7 : y + 10.3
                p.move(to: CGPoint(x: x - 4.95, y: end)); p.addLine(to: CGPoint(x: x, y: apex)); p.addLine(to: CGPoint(x: x + 4.95, y: end))
                ctx.stroke(p, with: .color(color), style: Chevron.style(2))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The pill on a call: Mute · the mark running into a wave · the voice's word · End call

private struct CallBar: View {
    let pill: CallPill
    let c: Palette
    let animate: Bool
    let send: (PanelIntent) -> Void

    var body: some View {
        let fg = pill.muted ? c.onInk : c.ink, bg = pill.muted ? c.ink : pill.flat ? c.sunk : c.pill
        let well = pill.muted ? c.onInk.opacity(0.10) : c.well, end = pill.muted ? c.wrongOnInk : c.wrong
        HStack(spacing: 8) {
            Button { send(.mute(!pill.muted)) } label: {
                Image(systemName: pill.muted ? "mic.slash" : "mic").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(pill.canMute && !pill.flat ? bg : c.ink3)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(pill.canMute && !pill.flat ? fg : .clear))
                    .overlay(Circle().strokeBorder(pill.canMute && !pill.flat ? .clear : c.ink3.opacity(0.45), lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(Press(shape: Circle(), ring: c.accent)).focusEffectDisabled()
            .disabled(!pill.canMute || pill.flat)
            .accessibilityLabel(pill.muted ? "Unmute" : "Mute").help(pill.muted ? "Unmute" : "Mute")
            WaveView(kind: pill.wave, color: fg, animate: animate)
            // The gap before the word is what the pill has to spare after the wave's three bars (the longest word, "Reconnecting", has none).
            Text(pill.word).font(DisplaySerif.font(size: 22, italic: true)).foregroundStyle(pill.wrong ? c.wrong : fg).lineLimit(1).fixedSize()
                .padding(.leading, 0)
            Button { send(.endCall) } label: {
                Handset().fill(pill.ending ? c.ink3 : end).frame(width: 26, height: 26).frame(width: 48, height: 48)
                    .background(Circle().fill(pill.ending ? .clear : well))
                    .overlay(Circle().strokeBorder(pill.ending ? c.ink3.opacity(0.45) : .clear, lineWidth: 1.5)) // disabled, as Mute is
                    .contentShape(Circle())
            }
            .buttonStyle(Press(shape: Circle(), ring: c.accent)).focusEffectDisabled().disabled(pill.ending)
            .accessibilityLabel("End call").help("End call")
        }
        .padding(.horizontal, 8).frame(height: 64)
        .background(Pill(h: 64).fill(bg).shadow(color: pill.flat ? .clear : c.shadow1, radius: 1, y: 1).shadow(color: pill.flat ? .clear : c.shadow2, radius: 5, y: 3))
        .overlay(Pill(h: 64).inset(by: 0.5).stroke(pill.muted ? .clear : c.hair, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pill.word.isEmpty ? (pill.ending ? "Ending the call" : "Connecting") : pill.word)
    }
}

/// The design's keyboard focus: a marigold ring, 3 wide, 2 off the control (system.css :focus-visible). It reads `isFocused`, so it
/// goes on the control's own content; the system's ring is switched off beside it, so there is one, and it is visible.
struct FocusRing<S: InsettableShape>: ViewModifier {
    let shape: S
    let ring: Color
    @Environment(\.isFocused) private var focused
    func body(content: Content) -> some View { content.overlay { if focused { shape.inset(by: -2).stroke(ring, lineWidth: 3) } } }
}

/// A control's press, and its keyboard focus drawn as the design's marigold ring (system.css :focus-visible: 3 wide, 2 off).
/// The system's own ring is switched off where this is used, so there is one, and it is visible.
struct Press<S: InsettableShape>: ButtonStyle {
    let shape: S
    let ring: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(FocusRing(shape: shape, ring: ring)).scaleEffect(configuration.isPressed ? 0.94 : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The mark's chevron running into its bars, as many as fit before the word.
private struct WaveView: View {
    let kind: WaveKind
    let color: Color
    let animate: Bool

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animate)) { tl in
                let t: Double? = animate ? tl.date.timeIntervalSinceReferenceDate : nil
                Canvas { ctx, size in
                    let cy = size.height / 2
                    ctx.stroke(Chevron.path(left: 2, cy: cy, box: 11.76, border: 3.64, shift: 1.68), with: .color(color), style: Chevron.style(3.64))
                    let base = WaveArt.panel[kind] ?? []
                    let n = min(base.count, WaveArt.count(width: size.width, start: 20.24, pitch: 5, bar: 3))
                    for i in 0..<n {
                        let h = WaveArt.height(kind, base[i], i, at: t)
                        let a: Double = kind == .waiting && t != nil ? 0.35 + 0.65 * (0.5 - 0.5 * cos(2 * Double.pi * ((t ?? 0) - 0.15 * Double(i)) / 1.2)) : 1
                        ctx.fill(Path(roundedRect: CGRect(x: 20.24 + CGFloat(i) * 5, y: cy - h / 2, width: 3, height: h), cornerRadius: min(1.5, h / 2)), with: .color(color.opacity(a)))
                    }
                }
            }
        }
        .frame(minWidth: WaveArt.minimumWidth, maxWidth: .infinity).frame(height: 36)
        .accessibilityHidden(true)
    }
}

// MARK: - The door: one button, always here; marigold only when it is your move

private struct DoorButton: View {
    let door: PanelData.Door
    let c: Palette
    let action: () -> Void
    @StateObject private var pointer = Pointer()

    var body: some View {
        Button(action: action) {
            Text(door.label).font(.system(size: 17, weight: .semibold)).tracking(-0.17)
                .foregroundStyle(!door.enabled ? c.ink3 : door.style == .primary ? c.onAccent : c.ink)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Pill(h: 48).fill(door.enabled ? fill : .clear))
                .overlay(Pill(h: 48).inset(by: door.style == .move && door.enabled ? 1 : 0.75).stroke(edge, lineWidth: door.style == .move && door.enabled ? 2 : 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(Press(shape: Pill(h: 48), ring: c.accent)).focusEffectDisabled()
        .disabled(!door.enabled)
        .onHover { pointer.over = $0 }
    }

    /// Disabled is the design's disabled look: no fill, ink-3 words, a faint ring; never a faded marigold.
    private var edge: Color {
        if !door.enabled { return c.ink3.opacity(0.45) }
        return door.style == .move ? c.accent : door.style == .quiet ? c.ink3 : .clear
    }

    private var fill: Color {
        switch door.style {
        case .primary: pointer.over ? c.accentDown : c.accent
        default: pointer.over ? c.ink.opacity(0.06) : .clear
        }
    }
}

/// The design's end-call handset (final.html, ICON.end): its 24-point path, raised 2.
private struct Handset: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + (y - 2) * k) }
        var p = Path()
        p.move(to: pt(2.6, 14.2))
        p.addCurve(to: pt(21.4, 14.2), control1: pt(7.8, 9.2), control2: pt(16.2, 9.2))
        p.addCurve(to: pt(21.4, 15.9), control1: pt(21.9, 14.7), control2: pt(21.9, 15.4))
        p.addLine(to: pt(19.9, 17.4))
        p.addCurve(to: pt(18.4, 17.6), control1: pt(19.5, 17.8), control2: pt(18.9, 17.9))
        p.addLine(to: pt(15.8, 16.2))
        p.addCurve(to: pt(15.1, 15.1), control1: pt(15.4, 16.0), control2: pt(15.1, 15.5))
        p.addLine(to: pt(15.1, 13.6))
        p.addQuadCurve(to: pt(8.9, 13.6), control: pt(12, 12.56)) // the arc of radius 9.5 across 6.2, as a curve
        p.addLine(to: pt(8.9, 15.1))
        p.addCurve(to: pt(8.2, 16.2), control1: pt(8.9, 15.6), control2: pt(8.6, 16.0))
        p.addLine(to: pt(5.6, 17.6))
        p.addCurve(to: pt(4.1, 17.4), control1: pt(5.1, 17.9), control2: pt(4.5, 17.8))
        p.addLine(to: pt(2.6, 15.9))
        p.addCurve(to: pt(2.6, 14.2), control1: pt(2.1, 15.4), control2: pt(2.1, 14.7))
        p.closeSubpath()
        return p
    }
}


/// The design's serif (system.css --cv-font-display: ui-serif, which Chrome draws as New York at its large optical size: lighter and
/// narrower than AppKit's default for the point size). "Listening" is 79.4 wide here and 79.5 in the drawing.
public enum DisplaySerif {
    /// New York, regular, at the 72-point optical size (the font's `opsz` axis), upright or italic.
    public static func nsFont(size: CGFloat, italic: Bool = false, opticalSize: CGFloat = 72) -> NSFont {
        var d = NSFont.systemFont(ofSize: size).fontDescriptor
        d = d.withDesign(.serif) ?? d
        if italic { d = d.withSymbolicTraits(.italic) }
        d = d.addingAttributes([NSFontDescriptor.AttributeName("NSCTFontVariationAttribute"): [NSNumber(value: 0x6f70737a): opticalSize]]) // 'opsz'
        return NSFont(descriptor: d, size: size) ?? .systemFont(ofSize: size)
    }

    public static func font(size: CGFloat, italic: Bool = false, opticalSize: CGFloat = 72) -> Font { Font(nsFont(size: size, italic: italic, opticalSize: opticalSize) as CTFont) }

    /// How wide `text` sets in the 22-point italic.
    public static func width(_ text: String) -> CGFloat { NSAttributedString(string: text, attributes: [.font: nsFont(size: 22, italic: true)]).size().width }
}
