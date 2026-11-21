import AppKit
import SwiftUI
import VoiceCore

/// The one setup screen (design/onboarding.html): 920 × 660, a 640 column: the mark, the name, one line, three rows, one
/// bottom. Like PanelView it is given plain data (VoiceCore's SetupScreen) and sends intents; it reaches into nothing. The host
/// decides what each intent does.
public struct SetupView: View {
    let data: SetupScreen
    /// Draws the moving bar still (pictures).
    let still: Bool
    let send: (SetupIntent) -> Void
    @Environment(\.colorScheme) private var scheme

    public init(data: SetupScreen, still: Bool = false, send: @escaping (SetupIntent) -> Void) { self.data = data; self.still = still; self.send = send }

    public static let size = CGSize(width: 920, height: 660)

    public var body: some View {
        let c = Palette(scheme)
        VStack(spacing: 0) {
            BrandMark().frame(height: 56).padding(.bottom, 16)
            // The name's tracking is measured against Chrome's drawing: its 48-point name sets 191 wide and light, as at 72 points.
            Text(Product.name).font(DisplaySerif.font(size: 48)).tracking(0.24).foregroundStyle(c.ink).frame(height: 52.8).padding(.bottom, 8)
            Text("Talk to Claude Code out loud. Three things first.").font(.system(size: 22)).tracking(-0.44).foregroundStyle(c.ink2).frame(height: 28).padding(.bottom, 32)
            VStack(spacing: 0) {
                ForEach(data.rows, id: \.id.rawValue) { RowView(row: $0, c: c, send: send) }
                Rectangle().fill(c.hair).frame(height: 1)
            }
            .frame(width: 640).padding(.bottom, 32)
            bottom(c)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(c.ground)
    }

    @ViewBuilder private func bottom(_ c: Palette) -> some View {
        switch data.bottom {
        case .start(let ready):
            SetupButton(title: "Start the first call", look: ready ? .gold : .rest, width: 320, c: c) { send(.startCall) }
        case .downloading(let progress):
            // The bar first, 4 thick with rounded ends, then the words under it.
            VStack(spacing: 8) {
                Bar(progress: progress, still: still, c: c)
                Text("Downloading, hold on a second…").font(.system(size: 17)).tracking(-0.17).foregroundStyle(c.ink2).frame(height: 24)
            }
            .frame(width: 320, height: 48)
        case .note(let line, let button, let intent):
            VStack(spacing: 8) {
                Text(line).font(.system(size: 17)).tracking(-0.17).foregroundStyle(c.ink2).frame(height: 24)
                if let button, let intent { SetupButton(title: button, look: .gold, width: 320, c: c) { send(intent) } }
            }
        }
    }
}

/// The download's bar: the hairline's track, ink-2 fill, 320 × 4. With no length known, a short stretch slides along it.
private struct Bar: View {
    let progress: Double?
    let still: Bool
    let c: Palette
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(c.hair)
            if let p = progress { Capsule().fill(c.ink2).frame(width: 320 * min(max(p, 0), 1)) }
            else { TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { tl in
                let t = still ? 0.3 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                Capsule().fill(c.ink2).frame(width: 96).offset(x: (320 - 96) * t)
            } }
        }
        .frame(width: 320, height: 4).clipShape(Capsule())
    }
}

/// A row: its name over its reason, and its control (88 high, a hairline above).
private struct RowView: View {
    let row: SetupScreen.Row
    let c: Palette
    let send: (SetupIntent) -> Void

    /// The design's 24-point line at 17 points: the font's own line is shorter.
    private static let reasonSpacing = 24 - NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 17))

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name).font(.system(size: 22, weight: .semibold)).tracking(-0.44).foregroundStyle(c.ink).frame(height: 28)
                reason
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch row.control {
            case .done: Done(c: c)
            case .button(let title, let look, let intent): SetupButton(title: title, look: look, width: 168, c: c) { intent.map(send) }
            }
        }
        .padding(.top, 1).frame(height: 88)
        .overlay(alignment: .top) { Rectangle().fill(c.hair).frame(height: 1) }
    }

    @ViewBuilder private var reason: some View {
        if let pick = row.pick {
            HStack(spacing: 0) {
                Text(row.reason).fixedSize()
                PickWord(pick: pick, c: c, send: send)
            }
            .font(.system(size: 17)).tracking(-0.17).foregroundStyle(c.ink2).frame(height: 24, alignment: .leading)
        } else {
            Text(row.reason).font(.system(size: 17)).tracking(-0.17).foregroundStyle(c.ink2).lineSpacing(Self.reasonSpacing).padding(.top, Self.reasonSpacing / 2)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 24, alignment: .topLeading)
        }
    }
}

/// "shop ›": the project's name as a word that drops down the recent projects (4 either side, radius 6, a tint on hover).
private struct PickWord: View {
    let pick: SetupScreen.Pick
    let c: Palette
    let send: (SetupIntent) -> Void
    @StateObject private var pointer = Pointer()

    var body: some View {
        Menu {
            ForEach(pick.choices, id: \.path) { choice in
                Button { send(.pick(choice.path)) } label: { if choice.current { Label(choice.label, systemImage: "checkmark") } else { Text(choice.label) } }
            }
            if !pick.choices.isEmpty { Divider() }
            Button("Choose…") { send(.chooseProject) }
        } label: {
            Text("\(pick.name) ›").font(.system(size: 17, weight: .semibold)).tracking(-0.17).foregroundStyle(c.ink).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 4).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pointer.over ? c.ink.opacity(0.06) : .clear))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusEffectDisabled().fixedSize()
        .padding(.horizontal, -4)
        .onHover { pointer.over = $0 }
        .accessibilityLabel("Project, \(pick.name). Menu.")
    }
}

/// The system's done state: the word and its tick, in the done green.
private struct Done: View {
    let c: Palette
    var body: some View {
        HStack(spacing: 8) {
            Text("Done").font(.system(size: 17, weight: .semibold)).tracking(-0.17)
            Color.clear.frame(width: 13, height: 24).overlay(alignment: .topLeading) { tick }
        }
        .foregroundStyle(c.done).frame(height: 24)
        .accessibilityElement(children: .ignore).accessibilityLabel("Done")
    }

    /// system.css .cv-state--done::after: a 7 × 13 box with its right and bottom borders, rotated 45° about its centre after a move
    /// of (-2, -2); the borders are drawn 2 wide, which is how the drawing's 2.5 comes out in Chrome. Drawn on a canvas wider than its slot: the tick's left end passes the slot's edge, as in the drawing.
    private var tick: some View {
        Canvas { ctx, _ in
            let corners = [(5, 0.0), (7, 0), (7, 13), (0, 13), (0, 11), (5, 11)].map { CGPoint(x: $0.0 - 3.5, y: $0.1 - 6.5) }
            var p = Path()
            p.move(to: corners[0])
            for point in corners.dropFirst() { p.addLine(to: point) }
            p.closeSubpath()
            ctx.translateBy(x: 4 + 2 + 3.5, y: 11)
            ctx.rotate(by: .degrees(45))
            ctx.translateBy(x: -2, y: -2)
            ctx.fill(p, with: .color(c.done))
        }
        .frame(width: 21, height: 24).offset(x: -4)
    }
}

/// A button of the screen: 48 high, a pill, 17 semibold. Gold (the one move), an outline to press, or an outline at rest.
private struct SetupButton: View {
    let title: String
    let look: SetupScreen.Look
    let width: CGFloat
    let c: Palette
    let action: () -> Void
    @StateObject private var pointer = Pointer()

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.17)
                .foregroundStyle(look == .gold ? c.onAccent : look == .rest ? c.ink2 : c.ink)
                .frame(width: width, height: 48)
                .background(Pill(h: 48).fill(look == .gold ? (pointer.over ? c.accentDown : c.accent) : look == .quiet && pointer.over ? c.ink.opacity(0.06) : .clear))
                .overlay { if look != .gold { Pill(h: 48).inset(by: 0.75).stroke(c.ink3, lineWidth: 1.5) } }
                .contentShape(Capsule())
        }
        .buttonStyle(Press(shape: Pill(h: 48), ring: c.accent)).focusEffectDisabled()
        .disabled(look == .rest)
        .onHover { pointer.over = $0 }
    }
}
