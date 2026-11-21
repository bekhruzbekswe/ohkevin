import AppKit
import CallKit
import CallViews
import Ears
import SwiftUI
import VoiceCore

/// The window (design/final.html, "The app"): before a call the start in the middle; on a call the chat, with the
/// workers' rail on the right from the first worker and one call bar under the chat. Narrow, the rail goes on top.
struct AppView: View {
    @Bindable var model: CallModel
    @Bindable var settings: AppSettings
    let chooseVoice: (String) -> Void
    let setup: (SetupIntent) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack {
                switch model.stage {
                case .idle where model.setupScreen(settings) != nil: // the one setup screen (onboarding.html), in the middle of the window
                    SetupView(data: model.setupScreen(settings)!, still: settings.openForPicture != nil, send: setup)
                case .idle, .ending, .ended: Start(model: model, settings: settings)
                default: OnCall(model: model, size: g.size)
                }
                if settings.shown { // Settings drops from the three dots; a click anywhere else, the dots again, or Escape close it
                    Color.clear.contentShape(Rectangle()).onTapGesture { settings.shown = false }
                    let card = SettingsView(settings: settings, chooseVoice: chooseVoice, onCall: [.starting, .live, .ending].contains(model.stage))
                        .frame(width: min(CV.rail, g.size.width - 2 * OnCall.pad(g.size.width)))
                    ViewThatFits(in: .vertical) { card; ScrollView { card.padding(.bottom, CV.s2) }.scrollIndicators(.never) } // a short window scrolls it
                        .frame(maxHeight: g.size.height - 40 - CV.s2, alignment: .top)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 40).padding(.trailing, OnCall.pad(g.size.width)) // on the content edge: over the rail exactly
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeOut(duration: 0.15), value: settings.shown)
        }
        .background(CV.ground)
        .foregroundStyle(CV.ink)
        .ignoresSafeArea()
    }
}

// MARK: - Before a call, and after

struct Start: View {
    @Bindable var model: CallModel
    @Bindable var settings: AppSettings

    var body: some View {
            VStack(spacing: 0) {
                BrandMark().frame(width: 100 * 90 / 68, height: 100).accessibilityHidden(true) // the owner's mark, as the page's .cv-brand: 100 high, 90:68
                Text(model.stage == .idle ? Self.ready.line1 : "Call ended.").font(CV.display).tracking(-0.96)
                    .multilineTextAlignment(.center).padding(.top, 56) // 56 from the mark, as the page
                    .accessibilityAddTraits(.isHeader)
                Text(model.stage == .idle ? Self.readyLine : " ").font(CV.body).tracking(-0.17).foregroundStyle(CV.ink2) // the start only; the same height after a call
                    .padding(.top, CV.s1).padding(.bottom, CV.s4).accessibilityHidden(model.stage != .idle)
                VStack(spacing: CV.s1) { // the setup screen holds every step, the project and the download; the start is ready
                    Button("Start call") { model.perform(.start) }
                        .buttonStyle(CVButton(kind: .primary, wide: true))
                        .disabled(settings.call.project == nil || model.stage == .ending)
                        .keyboardShortcut(.defaultAction)
                    // the update line (design/updates.html, frames 17–20): the shared LineView, under Start call in the 320 column,
                    // one run on the left from the buttons' label inset; 8 here and the stack's 8: 16 in all
                    if let line = MainActor.assumeIsolated({ settings.updateLine }) {
                        LineView(line, layout: .stack) { model.perform(.line($0)) }.padding(.top, CV.s1)
                    }
                }
                .frame(width: 320)
            }
            .padding(.horizontal, CV.s2) // Settings: the three dots at the top right, and the app menu
    }
    /// The launcher's own words when ready (VoiceCore's PanelState): one wording for both apps.
    static let ready: PanelData = { var i = PanelInput(); i.project = URL(fileURLWithPath: "/"); i.missing = []; return PanelData(i) }()
    static var readyLine: String { if case .text(let t) = ready.line2 { t } else { "" } }
}

/// The project chooser: recent folders, and any other.
struct ProjectPick: View {
    @Bindable var settings: AppSettings
    var body: some View { // the shared chooser in a sheet of its own, its 24 folded away; the start shows the pill alone
        SettingsSheet(width: nil, paintsGround: false) {
            Chooser("Project folder", selection: settings.projectBinding, options: settings.projectOptions, action: settings.projectAction,
                    selectionTitle: settings.projectName ?? "Choose a project", showsLabel: false)
        }
        .padding(-24)
    }
}

// MARK: - On a call

struct OnCall: View {
    @Bindable var model: CallModel
    let size: CGSize
    /// The content's edge from the window's: 16 narrow, 40 otherwise (the rail, the Settings sheet and the three dots line up on it).
    static func pad(_ width: CGFloat) -> CGFloat { width < 640 ? CV.s2 : CV.s4 }

    var body: some View {
        let compact = size.width < 640, onTop = !model.rail.isEmpty && size.width < 920
        let pad = Self.pad(size.width), top = max(pad, 32) // 32: room for the window's own buttons
        Group {
            if onTop {
                VStack(spacing: CV.s2) {
                    AtMost(height: max(0, size.height - top - pad - CV.s2 - 272)) { Rail(model: model, whole: true) }.clipped()
                    Talk(model: model, compact: compact, width: size.width - 2 * pad)
                }
            } else {
                HStack(alignment: .top, spacing: CV.s4) {
                    let alone = model.rail.isEmpty
                    let talk = alone ? min(CV.chatAlone, size.width - 2 * pad) : size.width - 2 * pad - CV.s4 - CV.rail
                    Talk(model: model, compact: compact, width: talk).frame(width: talk)
                    if !alone { Rail(model: model).frame(width: CV.rail, alignment: .top).frame(maxHeight: .infinity, alignment: .top) }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, pad).padding(.top, top).padding(.bottom, pad)
        .animation(.easeOut(duration: 0.25), value: model.rail.map(\.id))
    }
}

/// The chat (or, until you answer, the voice's first line at display size) and the call bar under it.
struct Talk: View {
    @Bindable var model: CallModel
    let compact: Bool
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let g = model.greeting {
                    Text(g).font(CV.display).tracking(-0.96).multilineTextAlignment(.center).lineLimit(nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Claude: \(g)")
                } else {
                    Chat(model: model, width: width * (compact ? 0.86 : 0.76))
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, compact ? CV.s2 : CV.s3)
            if let note = model.micNote { // .cv-note: grey, left aligned, 12 above the bar
                Text(note).font(CV.small).lineSpacing(3).foregroundStyle(CV.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, CV.s3).padding(.bottom, CV.sh)
            }
            CallBar(model: model, two: compact)
        }
    }
}

/// What was said, in bubbles; full, it scrolls with the newest at the bottom and its top 32 fades.
struct Chat: View {
    @Bindable var model: CallModel
    let width: CGFloat
    @StateObject private var full = Box(false)
    @StateObject private var pos = Box(ScrollPosition(edge: .bottom))

    private struct Run { let voice: Bool; var lines: [Said] }
    private var runs: [Run] {
        var all: [(Bool, Said)] = [] // the greeting is the app's own line, never a bubble: once the talk begins it is gone
        let n = model.lines.count
        for (i, l) in model.lines.enumerated() {
            all += model.problems.filter { min($0.after, n) == i }.map { (true, Said(text: $0.text, wrong: true)) }
            all.append((l.who == "voice", Said(text: l.text, unsaid: l.unsaid)))
        }
        all += model.problems.filter { $0.after >= n }.map { (true, Said(text: $0.text, wrong: true)) }
        if !model.ghost.isEmpty { all.append((false, Said(text: model.ghost, live: true))) }
        var out: [Run] = []
        for (voice, said) in all {
            if out.last?.voice == voice { out[out.count - 1].lines.append(said) } else { out.append(Run(voice: voice, lines: [said])) }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CV.s3) {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, r in TurnView(voice: r.voice, lines: r.lines, width: width) }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.top, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollPosition($pos.value)
        .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height > $0.containerSize.height + 1 } action: { _, f in full.value = f }
        // more or less room (the rail above changed, a card opened, a note came): the newest line stays in view
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { was, now in if now != was { pos.value.scrollTo(edge: .bottom) } }
        .mask(VStack(spacing: 0) {
            // the top 56: the first 28 clear, so no sliver of a scrolled-away bubble shows; then the fade
            LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom).frame(height: full.value ? 56 : 0)
            Color.black
        })
    }
}

/// The workers. Too many for the room: resting cards drop their sentence, then the rail scrolls and its cut edge fades.
struct Rail: View {
    @Bindable var model: CallModel
    /// Narrow, on top of the talk: only whole cards, an asking one always among them, and no fade where the chat's fade begins.
    var whole = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            cards(line: false)
            if whole { WholeCards(keep: model.rail.firstIndex { $0.approval != nil }) { cardViews(line: true) } } else {
            ScrollView { cards(line: true) }.scrollIndicators(.never)
                .mask(VStack(spacing: 0) { Color.black; LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.75)], startPoint: .top, endPoint: .bottom).frame(height: 32) })
            }
        }
    }

    private func cards(line: Bool) -> some View { VStack(spacing: CV.s2) { cardViews(line: line) } }

    @ViewBuilder private func cardViews(line: Bool) -> some View {
            ForEach(model.rail) { c in
                WorkerCard(card: c, line: line && c.approval == nil, open: model.openCard == c.name, canStop: c.state == .working,
                           press: { model.openCard = model.openCard == c.name ? nil : c.name },
                           openInClaude: { if c.session != nil { model.open(c.name) } },
                           stop: { model.stop(c.name) },
                           close: { model.close(c.name) },
                           answer: { if let a = c.approval { model.answer(a.ask.id, allow: $0) } })
                if c.name == model.hintFor { // the first call's one-time line under the first finished card (onboarding.html)
                    Text(CallModel.hint).font(CV.small).foregroundStyle(CV.ink2).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, CV.s3).padding(.top, -CV.s1)
                }
            }
    }
}

// MARK: - The call bar

/// One board divided by hairlines: the voice's state, Type instead, Mute, End. Pointing at Mute or End fills its whole
/// segment and its lines fade; muted, the whole bar turns over. Narrow, the field goes under the state row.
struct CallBar: View {
    @Bindable var model: CallModel
    let two: Bool
    @StateObject private var hovered = Box<Int?>(nil) // 1 the slot, 2 End
    private var hover: Int? { hovered.value }
    @FocusState private var focused: Bool

    private var muted: Bool { model.capsule == .muted }
    private var fg: Color { muted ? CV.onInk : CV.ink }
    private var line: Color { muted ? CV.onInk.opacity(0.25) : CV.hair }

    /// The slot after the field: Mute, Unmute, or the one thing that fixes the call (Allow, Call again) in marigold words.
    private var slot: (label: String, gold: Bool, command: Command?) {
        switch model.capsule {
        case .muted: ("Unmute", false, .mute)
        case .lost: ("Call again", true, .again)
        case .micBlocked:
            ("Allow", true, model.deaf == .microphone ? .openSettings : model.deaf == .speechModel ? (model.downloading ? nil : .installModel) : .listenAgain)
        case .reconnecting: ("Mute", false, nil)
        default: ("Mute", false, model.stage == .live ? .mute : nil)
        }
    }
    private var motion: CVMark.Motion {
        switch model.capsule {
        case .listening: .listening; case .speaking: .speaking; case .thinking: .thinking; case .reconnecting: .waiting
        case .muted, .micBlocked, .lost: .muted
        }
    }

    var body: some View {
        Group {
            if two {
                VStack(spacing: 0) {
                    HStack(spacing: 0) { capsule.padding(.leading, CV.s3); Spacer(minLength: 0); slotButton; endButton }.frame(height: 56)
                    field.padding(.horizontal, CV.s3).frame(height: 52).overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
                }
                .background(muted ? CV.ink : CV.raised, in: RoundedRectangle(cornerRadius: CV.radius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: CV.radius, style: .continuous))
            } else {
                HStack(spacing: 0) {
                    capsule.padding(.leading, CV.s1 + CV.s2).frame(width: CV.capsule + CV.s1, alignment: .leading)
                    field.padding(.horizontal, CV.s3).frame(height: 32).overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
                    slotButton; endButton
                }
                .frame(height: CV.bar)
                .background(muted ? CV.ink : CV.raised, in: Capsule())
                .clipShape(Capsule())
            }
        }
        .foregroundStyle(fg)
        .cvShadow()
        .overlay {
            (two ? AnyShape(RoundedRectangle(cornerRadius: CV.radius, style: .continuous)) : AnyShape(Capsule()))
                .stroke(CV.accent, lineWidth: 3).padding(-1.5).opacity(focused ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.2), value: muted)
    }

    private var capsule: some View {
        let red = model.capsule == .micBlocked || model.capsule == .lost
        return HStack(spacing: CV.sh) {
            CVMark(motion: motion, size: 28, color: red ? CV.wrong : fg)
            Text(model.capsule.rawValue).font(CV.stateWord).foregroundStyle(red ? CV.wrong : fg).lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(model.capsule.rawValue)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var field: some View {
        TextField("", text: $model.text).accessibilityLabel("Type instead")
            .textFieldStyle(.plain).font(CV.body).foregroundStyle(fg)
            .background(alignment: .leading) { // the system's placeholder keeps its own grey: on the turned-over bar it would vanish
                if model.text.isEmpty { Text("Type instead").font(CV.body).foregroundStyle(muted ? CV.onInk.opacity(0.65) : CV.ink3).allowsHitTesting(false) }
            }
            .focused($focused)
            .onSubmit { model.send(); focused = false } // sent: the keyboard goes back to M and Space
            .onKeyPress(.escape) { focused = false; return .handled } // the words stay for later
            .disabled(model.stage != .live || model.reconnecting)
            .onChange(of: model.typing) { _, on in focused = on }
            .onChange(of: focused) { _, on in model.typing = on }
    }

    private var slotButton: some View {
        let s = slot
        return segment(1, s.label, color: s.gold ? CV.accentWord : s.command == nil ? fg.opacity(0.4) : fg, width: CV.slot, lead: true, enabled: s.command != nil) { if let c = s.command { model.perform(c) } }
            .accessibilityLabel(s.label == "Mute" ? "Mute microphone" : s.label == "Unmute" ? "Unmute microphone" : s.label)
    }

    private var endButton: some View {
        let lost = model.capsule == .lost
        return segment(2, "End", color: muted ? CV.wrongOnInk : CV.wrong, width: nil, lead: hover != 1) { model.perform(lost ? .close : .end) }
            .help("End call").accessibilityLabel("End call")
    }

    /// A part of the bar between two hairlines: no shape of its own; pointed at, it fills top to bottom and its lines fade.
    /// Not a Button: on macOS 26 a button draws the system's own rounded hover under any style; a segment draws only its square fill.
    private func segment(_ i: Int, _ label: String, color: Color, width: CGFloat?, lead: Bool, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        let lit = hover == i && enabled
        return Text(label).font(CV.bodyBold).tracking(-0.17).foregroundStyle(color).lineLimit(1).fixedSize()
            .frame(width: width).padding(.leading, width == nil ? CV.s3 : 0).padding(.trailing, width == nil ? (two ? CV.s3 : 28) : 0)
            .frame(maxHeight: .infinity)
            .background(Rectangle().fill(color.opacity(lit ? 0.10 : 0)))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1).padding(.vertical, two ? 12 : 16).opacity(lit || !lead ? 0 : 1) }
            .onHover { on in hovered.value = on ? i : (hover == i ? nil : hover) }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Its content at its own height, but never taller than this (a frame with maxHeight would take all of it, leaving a gap under a short rail).
struct AtMost: Layout {
    let height: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: min(proposal.height ?? height, height))) ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// A press with the label as it is, nothing the system adds (the plain style draws its own rounded hover on macOS 26).
struct Bare: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.7 : 1) }
}

/// The narrow rail's cards: as many whole ones as fit, from the top, moved down only as far as needed to show the asking card
/// (`keep`) whole. The rest are not drawn here; a wider window, or the voice, shows them.
struct WholeCards: Layout {
    let keep: Int?
    func window(_ heights: [CGFloat], _ room: CGFloat) -> Range<Int> {
        func fits(_ r: Range<Int>) -> Bool { r.map { heights[$0] }.reduce(0, +) + CGFloat(max(0, r.count - 1)) * CV.s2 <= room }
        var start = 0, end = 0
        while end < heights.count, fits(start..<(end + 1)) { end += 1 }
        if let k = keep, k >= end { while start <= k, !fits(start..<(k + 1)) { start += 1 }; end = k + 1; while end < heights.count, fits(start..<(end + 1)) { end += 1 } }
        return start..<max(end, min(start + 1, heights.count)) // at least one card
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400, hs = subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }
        let r = window(hs, proposal.height ?? .infinity)
        return CGSize(width: w, height: r.map { hs[$0] }.reduce(0, +) + CGFloat(max(0, r.count - 1)) * CV.s2)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let hs = subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height }, r = window(hs, bounds.height + 0.5)
        var y = bounds.minY
        for (i, s) in subviews.enumerated() {
            guard r.contains(i) else { s.place(at: CGPoint(x: bounds.minX, y: bounds.minY - 10_000), proposal: ProposedViewSize(width: bounds.width, height: hs[i])); continue }
            s.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: hs[i])); y += hs[i] + CV.s2
        }
    }
}
