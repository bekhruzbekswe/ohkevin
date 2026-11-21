import SwiftUI

// The design's settings pieces, shared by every Mac app that has a Settings window (design/final.html, the settings
// sheet; system.css): paper ground, small grey labels over full-width choosers, hairlines instead of grey boxes, a switch drawn in
// ink. Marigold only where it is the person's move (a download offered is one; a switch is not). They take bindings and plain
// values: the settings themselves stay with the app.

/// Which chooser's list is open (at most one), which row the keys have reached, and whether the last thing done was a pointer's.
/// `SettingsSheet` owns it; choosers find it in the environment.
public final class ChooserHost: ObservableObject {
    @Published public var open: String?
    @Published var highlight = 0 { didSet { scrollTo = highlight } }
    /// The row the open list is scrolled to (centred): the chosen one when it opens, then the keyboard's.
    @Published var scrollTo: Int?
    /// The last input was a click: the focus ring stays away until a key is pressed (system.css :focus-visible).
    @Published var pointer = false
    /// Where the open list's content top sits in its scroll view (0 at the top, negative once scrolled): the top fade follows it.
    @Published var listOffset: CGFloat = 0
    public init(open: String? = nil) { self.open = open }
}

/// Pictures only: draw the keyboard focus ring on every control as if each had the keyboard.
public struct ShowFocusRingsKey: EnvironmentKey { public static let defaultValue = false }
public extension EnvironmentValues { var showFocusRings: Bool { get { self[ShowFocusRingsKey.self] } set { self[ShowFocusRingsKey.self] = newValue } } }

/// A chooser's open list, handed up to the sheet so it is drawn above everything, however deep the chooser sits.
struct ChooserListRequest { let title: String; let anchor: Anchor<CGRect>; let list: AnyView }
struct ListOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
struct ChooserListKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [ChooserListRequest] = []
    static func reduce(value: inout [ChooserListRequest], nextValue: () -> [ChooserListRequest]) { value += nextValue() }
}

/// The ground of a settings window: paper (or ink at night), 24 round it, 16 between rows. A press on empty ground, or Escape, closes an
/// open chooser list. Put every `Chooser` inside one. `width` nil fills what the host gives; `paintsGround` false leaves the ground to the
/// host (a drop-down with its own rounded surface).
public struct SettingsSheet<Content: View>: View {
    @StateObject private var host: ChooserHost
    @Environment(\.colorScheme) private var scheme
    private let content: Content
    private let width: CGFloat?
    private let paintsGround: Bool
    private let listOpen: Binding<Bool>?

    /// `openChooser`: the title of a chooser whose list starts open (pictures).
    /// `listOpen`: mirrors whether a chooser's list is open, and closes it when the host sets it false (a host that sees Escape first
    /// closes the list with it before it closes anything else).
    public init(openChooser: String? = nil, width: CGFloat? = 400, paintsGround: Bool = true, listOpen: Binding<Bool>? = nil, @ViewBuilder content: () -> Content) {
        _host = StateObject(wrappedValue: ChooserHost(open: openChooser))
        self.width = width; self.paintsGround = paintsGround; self.listOpen = listOpen
        self.content = content()
    }

    public var body: some View {
        let c = Palette(scheme)
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(24)
            .frame(width: width, alignment: .topLeading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .topLeading)
            .background((paintsGround ? c.ground : Color.clear).contentShape(Rectangle()).onTapGesture { host.open = nil })
            .environmentObject(host)
            .onExitCommand { host.open = nil }
            .onChange(of: host.open) { listOpen?.wrappedValue = host.open != nil }
            .onChange(of: listOpen?.wrappedValue ?? false) { if !(listOpen?.wrappedValue ?? false) { host.open = nil } }
            .onAppear { listOpen?.wrappedValue = host.open != nil }
            .overlayPreferenceValue(ChooserListKey.self) { requests in // above every row, whatever sits between the chooser and the top
                GeometryReader { geo in
                    if let r = requests.first(where: { $0.title == host.open }) {
                        let box = geo[r.anchor]
                        r.list.frame(width: box.width).offset(x: box.minX, y: box.maxY + 4)
                    }
                }
            }
    }
}

/// A small grey label over what it names (14, ink-2), on the sheet's one left edge.
public struct SectionLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Palette(scheme).ink2)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}

/// Plain words ending in a link (14, ink-2; the link underlined in ink): a press anywhere on the line follows it.
public struct FineprintLink: View {
    let text: String
    let link: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    public init(_ text: String, link: String, action: @escaping () -> Void) { self.text = text; self.link = link; self.action = action }
    public var body: some View {
        let c = Palette(scheme)
        (Text(text + " ").foregroundStyle(c.ink2) + Text(link).foregroundStyle(c.ink).underline())
            .font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle()).onTapGesture(perform: action)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(text) \(link)").accessibilityAddTraits(.isLink).accessibilityAction { action() }
    }
}

/// A group's name: body size, semibold, ink.
public struct SectionTitle: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette(scheme).ink)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

/// Plain words under a row (14, ink-2); `wrong`: in the system's red.
public struct Fineprint: View {
    let text: String
    let wrong: Bool
    @Environment(\.colorScheme) private var scheme
    public init(_ text: String, wrong: Bool = false) { self.text = text; self.wrong = wrong }
    public var body: some View {
        let c = Palette(scheme)
        Text(text).font(.system(size: 14)).foregroundStyle(wrong ? c.wrong : c.ink2)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}

/// One option of a chooser; `group` puts it under a small grey label in the list (consecutive options with the same group share one).
public struct ChooserOption<Value: Hashable> {
    public let value: Value
    public let title: String
    public let group: String?
    public init(_ value: Value, _ title: String, group: String? = nil) { self.value = value; self.title = title; self.group = group }
}

/// A row after the list's hairline that does something instead of choosing ("Choose a Folder…").
public struct ChooserAction {
    public let title: String
    public let perform: () -> Void
    public init(_ title: String, perform: @escaping () -> Void) { self.title = title; self.perform = perform }
}

private final class MouseFlag: ObservableObject { @Published var down = false }

/// A control that is not a system button: its shape, a press, Space or Return, a marigold focus ring (3 wide, 2 off) only for the
/// keyboard, and no system hover shape.
private struct Activatable<S: InsettableShape>: ViewModifier {
    let shape: S
    let ring: Color
    let action: () -> Void
    @FocusState private var focused: Bool
    @StateObject private var mouse = MouseFlag()
    @Environment(\.showFocusRings) private var forced

    func body(content: Content) -> some View {
        content
            .contentShape(shape)
            .onTapGesture { mouse.down = true; action() }
            .focusable().focused($focused).focusEffectDisabled()
            .onKeyPress(keys: [.space, .return]) { _ in mouse.down = false; action(); return .handled }
            .onChange(of: focused) { if !focused { mouse.down = false } }
            .overlay { if forced || (focused && !mouse.down) { shape.inset(by: -2).stroke(ring, lineWidth: 3) } }
            .accessibilityAddTraits(.isButton).accessibilityAction { action() }
    }
}

/// The design's chooser: a full-width pill (value left, up and down arrows right) that opens the design's own list: one straight column
/// on a raised surface, a tick on the right of the chosen row, small grey labels over groups, scrolling past `maxListHeight`, the chosen row
/// brought into view. A press, or the keys (Space, Return, an arrow, a letter), opens it; up and down move, Return chooses, a letter jumps to
/// the next option that starts with it, Escape closes; focus stays on the pill. `action` is a last row after a hairline; with no options a
/// press goes straight to it. The label above names what it chooses. The list is drawn by the enclosing `SettingsSheet`, above everything.
public struct Chooser<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [ChooserOption<Value>]
    let action: ChooserAction?
    let maxListHeight: CGFloat
    let selectionTitle: String?
    let showsLabel: Bool
    @EnvironmentObject private var host: ChooserHost
    @Environment(\.colorScheme) private var scheme
    @Environment(\.showFocusRings) private var forced
    @FocusState private var focused: Bool

    /// `selectionTitle`: what the pill says for the selection when no option names it (a direct chooser: the project's name); `showsLabel`
    /// false hides the small label above the pill (the title stays its accessibility label).
    public init(_ title: String, selection: Binding<Value>, options: [ChooserOption<Value>], action: ChooserAction? = nil, maxListHeight: CGFloat = 320,
                selectionTitle: String? = nil, showsLabel: Bool = true) {
        self.title = title; _selection = selection; self.options = options; self.action = action; self.maxListHeight = maxListHeight
        self.selectionTitle = selectionTitle; self.showsLabel = showsLabel
    }

    /// The pill's words: the chosen option's title; failing that the host's `selectionTitle`; in a direct chooser with no selection, the action's.
    private var shown: String { options.first { $0.value == selection }?.title ?? selectionTitle ?? (direct ? action?.title ?? "" : "") }

    private var direct: Bool { options.isEmpty && action != nil }
    private var rows: Int { options.count + (action == nil ? 0 : 1) }
    private var chosen: Int { options.firstIndex { $0.value == selection } ?? 0 }

    public var body: some View {
        let c = Palette(scheme), open = host.open == title
        VStack(alignment: .leading, spacing: 4) {
            if showsLabel { SectionLabel(title) }
            HStack(spacing: 0) {
                Text(shown).font(.system(size: 17)).foregroundStyle(c.ink).lineLimit(1)
                Spacer(minLength: 8)
                Arrows(color: c.ink3).frame(width: 10, height: 48)
            }
            .padding(.leading, 24).padding(.trailing, 20).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 24, style: .circular).fill(c.sunk))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .circular))
            .onTapGesture { host.pointer = true; toggle() }
            .focusable().focused($focused).focusEffectDisabled()
            .onKeyPress(phases: .down) { press in key(press) }
            .overlay { if forced || (focused && !host.pointer) { RoundedRectangle(cornerRadius: 24, style: .circular).inset(by: -2).stroke(c.accent, lineWidth: 3) } }
            .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityAction { toggle() }
            .accessibilityLabel(title).accessibilityValue(shown == action?.title && direct ? "" : shown)
            .onAppear { if host.open == title { host.highlight = chosen } } // a list that starts open (pictures) starts at the chosen row too
            .anchorPreference(key: ChooserListKey.self, value: .bounds) { anchor in open ? [ChooserListRequest(title: title, anchor: anchor, list: AnyView(list(c))) ] : [] }
        }
    }

    private func toggle() {
        if direct { action?.perform(); return }
        if host.open == title { host.open = nil } else { host.highlight = chosen; host.scrollTo = chosen; host.open = title }
    }

    private func key(_ press: KeyPress) -> KeyPress.Result {
        host.pointer = false
        let open = host.open == title
        switch press.key {
        case .escape: if open { host.open = nil; return .handled }; return .ignored
        case .space, .return:
            if !open { toggle(); return .handled }
            commit(host.highlight); return .handled
        case .downArrow, .upArrow:
            if direct { return .ignored }
            if !open { toggle(); return .handled }
            host.highlight = min(max(host.highlight + (press.key == .downArrow ? 1 : -1), 0), rows - 1); return .handled
        default:
            guard open, let letter = press.characters.first, letter.isLetter || letter.isNumber else { return .ignored }
            let titles = options.map(\.title) + (action.map { [$0.title] } ?? [])
            let after = (1...titles.count).map { (host.highlight + $0) % titles.count }
            if let hit = after.first(where: { titles[$0].lowercased().hasPrefix(String(letter).lowercased()) }) { host.highlight = hit }
            return .handled
        }
    }

    private func commit(_ index: Int) {
        if index < options.count { selection = options[index].value; host.open = nil } else { host.open = nil; action?.perform() }
    }

    /// Where each row of the list ends (from its top, after the 8 inset): 48 a row, 32 more for a group's label, 9 for the action's hairline.
    private var rowEnds: [CGFloat] {
        var y: CGFloat = 8, ends: [CGFloat] = []
        for i in options.indices {
            if options[i].group != nil, i == 0 || options[i - 1].group != options[i].group { y += 32 }
            y += 48; ends.append(y)
        }
        if action != nil { y += 9 + 48; ends.append(y) }
        return ends
    }

    /// What the list wants (8 inset above and below), or, past the maximum, the most that ends on a row boundary: never a row cut in half.
    private var listHeight: CGFloat {
        let want = (rowEnds.last ?? 8) + 8
        return want <= maxListHeight ? want : (rowEnds.last { $0 + 8 <= maxListHeight } ?? 56) + 8
    }

    private func list(_ c: Palette) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { i in
                    if options[i].group != nil, i == 0 || options[i - 1].group != options[i].group { GroupLabel(options[i].group ?? "") }
                    ChooserListRow(options[i].title, chosen: options[i].value == selection, highlighted: host.highlight == i && (focused || forced) && !host.pointer) { commit(i) }.id(i)
                }
                if let action {
                    Rectangle().fill(c.hair).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 24)
                    ChooserListRow(action.title, chosen: false, highlighted: host.highlight == options.count && (focused || forced) && !host.pointer) { commit(options.count) }.id(options.count)
                }
            }
            .padding(.vertical, 8)
            .scrollTargetLayout()
            .background(GeometryReader { g in Color.clear.preference(key: ListOffsetKey.self, value: g.frame(in: .named("chooserList")).minY) })
        }
        .coordinateSpace(name: "chooserList")
        .onPreferenceChange(ListOffsetKey.self) { host.listOffset = $0 }
        .mask(LinearGradient(stops: [.init(color: .black.opacity(1 - min(1, max(0, -host.listOffset / 32))), location: 0), .init(color: .black, location: min(1, 32 / listHeight))],
                             startPoint: .top, endPoint: .bottom)) // a scrolled group label fades out over 32 at the top, never a hard cut
        .scrollPosition(id: Binding(get: { host.scrollTo }, set: { host.scrollTo = $0 }), anchor: .center)
        .frame(height: listHeight)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(c.sunk)) // the design's surface, opaque: nothing shows through it
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(c.hair, lineWidth: 1))
        .shadow(color: c.shadow1, radius: 1, y: 1).shadow(color: c.shadow2, radius: 8, y: 14) // falls down only: none on the pill above it
    }
}

private struct GroupLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Palette(scheme).ink2).padding(.leading, 24).padding(.top, 8)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

/// A row of a chooser's list: 48 high, the words at 17, a tick on the right when it is the chosen one. Hover is the design's own full-row
/// fill; `highlighted` (the keyboard's row) adds the marigold ring. Not a system button, so no system hover shape can appear.
public struct ChooserListRow: View {
    let title: String
    let chosen: Bool
    let highlighted: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @StateObject private var pointer = ListPointer()

    public init(_ title: String, chosen: Bool, highlighted: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.chosen = chosen; self.highlighted = highlighted; self.action = action
    }

    public var body: some View {
        let c = Palette(scheme)
        HStack {
            Text(title).font(.system(size: 17)).foregroundStyle(c.ink).lineLimit(1)
            Spacer(minLength: 8)
            if chosen { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(c.ink) }
        }
        .padding(.horizontal, 24).frame(height: 48)
        .background(pointer.over || highlighted ? c.ink.opacity(0.06) : .clear)
        .overlay { if highlighted { RoundedRectangle(cornerRadius: 12, style: .continuous).inset(by: 4).stroke(c.accent, lineWidth: 3) } }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { pointer.over = $0 }
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton).accessibilityAction { action() }
    }
}

private final class ListPointer: ObservableObject { @Published var over = false }

/// A switch drawn in ink: an ink track with a paper knob when on, a faint ring with a grey knob when off. 48 × 28. Not a system button.
public struct InkToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { Track(isOn: configuration.$isOn) }

    private struct Track: View {
        @Binding var isOn: Bool
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            let c = Palette(scheme)
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 14, style: .circular).fill(isOn ? c.ink : .clear)
                RoundedRectangle(cornerRadius: 14, style: .circular).inset(by: 0.75).stroke(isOn ? .clear : c.ink3, lineWidth: 1.5)
                Circle().fill(isOn ? c.onInk : c.ink3).frame(width: 20, height: 20).padding(4)
            }
            .frame(width: 48, height: 28)
            .modifier(Activatable(shape: RoundedRectangle(cornerRadius: 14, style: .circular), ring: c.accent) { isOn.toggle() })
            .accessibilityValue(isOn ? "on" : "off")
        }
    }
}

/// A row under a hairline: its words on the left (17, and an optional 14 line under them), what it holds on the right. The hairline sits
/// between rows, so the first row after a heading passes `topRule: false`.
public struct HairlineRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let wrong: Bool
    let topRule: Bool
    let trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    public init(_ title: String, detail: String? = nil, wrong: Bool = false, topRule: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.detail = detail; self.wrong = wrong; self.topRule = topRule; self.trailing = trailing()
    }

    public var body: some View {
        let c = Palette(scheme)
        VStack(spacing: 0) {
            if topRule { Rectangle().fill(c.hair).frame(height: 1) }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17)).foregroundStyle(c.ink).fixedSize(horizontal: false, vertical: true)
                    if let detail { Text(detail).font(.system(size: 14)).foregroundStyle(wrong ? c.wrong : c.ink2).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.vertical, 12).frame(minHeight: 48)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A hairline row with a switch: `title` (and `detail`) on the left, the ink switch on the right.
public struct SwitchRow: View {
    let title: String
    let detail: String?
    let wrong: Bool
    let topRule: Bool
    @Binding var isOn: Bool

    public init(_ title: String, detail: String? = nil, wrong: Bool = false, topRule: Bool = true, isOn: Binding<Bool>) {
        self.title = title; self.detail = detail; self.wrong = wrong; self.topRule = topRule; _isOn = isOn
    }

    public var body: some View {
        HairlineRow(title, detail: detail, wrong: wrong, topRule: topRule) { Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(InkToggleStyle()).accessibilityLabel(title) }
    }
}

/// A 48-high pill button that hugs its words: `.primary` is the one marigold thing (a call to action), `.quiet` an outline. Not a system button.
public struct PillButton: View {
    public enum Style { case primary, quiet }
    let title: String
    let style: Style
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(_ title: String, style: Style = .quiet, action: @escaping () -> Void) { self.title = title; self.style = style; self.action = action }

    public var body: some View {
        let c = Palette(scheme), shape = RoundedRectangle(cornerRadius: 24, style: .circular)
        Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.17).foregroundStyle(style == .primary ? c.onAccent : c.ink)
            .padding(.horizontal, 24).frame(height: 48)
            .background(shape.fill(style == .primary ? c.accent : .clear))
            .overlay(shape.inset(by: 0.75).stroke(style == .quiet ? c.ink3 : .clear, lineWidth: 1.5))
            .modifier(Activatable(shape: shape, ring: c.accent, action: action))
            .fixedSize()
            .accessibilityLabel(title)
    }
}

/// What a hairline row holds when it only says something (17, ink-2).
public struct SettingsValue: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    public init(_ text: String) { self.text = text }
    public var body: some View { Text(text).font(.system(size: 17)).foregroundStyle(Palette(scheme).ink2).fixedSize() }
}
