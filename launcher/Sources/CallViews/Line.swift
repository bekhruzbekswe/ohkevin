import SwiftUI
import VoiceCore

/// The update line (design/updates.html): a 1 px hairline, then one row of 24: the sentence on the left in ink-2, and at most
/// one word on the right: marigold when it is the person's move, ink when it is an offer; or, while updating, a thin progress line.
/// A word is text only, with a light wash of its own colour under the pointer (a plain view: no system hover shape). Data in, intent out.
public struct LineView: View {
    public enum Layout: Sendable {
        /// Inside the menu-bar panel: the word at the right edge of the card's content.
        case panel
        /// Inside the Mac app's start column: sentence and word together on the left, starting 24 in, where the buttons' labels start.
        case stack
    }

    let line: PanelLine
    let layout: Layout
    let send: (LineAction) -> Void
    @Environment(\.colorScheme) private var scheme

    public init(_ line: PanelLine, layout: Layout = .panel, send: @escaping (LineAction) -> Void) { self.line = line; self.layout = layout; self.send = send }

    /// The row's height; the line adds this, the hairline and 12 above the row to what is above it.
    public static let rowHeight: CGFloat = 24

    public var body: some View {
        let c = Palette(scheme)
        VStack(spacing: 0) {
            Rectangle().fill(c.hair).frame(height: 1)
            HStack(spacing: layout == .stack ? 4 : 0) {
                Text(line.text).font(.system(size: 17)).tracking(-0.17).foregroundStyle(c.ink2).lineLimit(1).fixedSize()
                if layout == .panel { Spacer(minLength: 8) }
                if let word = line.word { LineWord(word: word, send: send).padding(.trailing, layout == .panel ? -8 : 0) }
                if let progress = line.progress { ProgressLine(progress: progress, c: c) }
                if layout == .stack { Spacer(minLength: 0) }
            }
            .padding(.leading, layout == .stack ? 24 : 0)
            .frame(height: Self.rowHeight).padding(.top, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(line.text)
    }
}

private final class LinePointer: ObservableObject { @Published var over = false }

private struct LineWord: View {
    let word: PanelLine.Word
    let send: (LineAction) -> Void
    @Environment(\.colorScheme) private var scheme
    @StateObject private var pointer = LinePointer()

    var body: some View {
        let c = Palette(scheme), color = word.isMove ? c.accentWord : c.ink
        Text(word.title).font(.system(size: 17, weight: .semibold)).tracking(-0.17).foregroundStyle(color).lineLimit(1).fixedSize()
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 12, style: .circular).fill(pointer.over ? color.opacity(0.10) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .circular))
            .onTapGesture { send(word.action) }
            .onHover { pointer.over = $0 }
            .accessibilityElement(children: .ignore).accessibilityLabel(word.title)
            .accessibilityAddTraits(.isButton).accessibilityAction { send(word.action) }
    }
}

/// 2 high, ink-2 on the hairline's own colour; never marigold: it asks nothing. Unknown progress shows a short stretch.
private struct ProgressLine: View {
    let progress: PanelLine.ProgressLine
    let c: Palette
    var body: some View {
        GeometryReader { g in
            let fraction: Double = { if case .known(let p) = progress { return min(1, max(0, p)) } else { return 0.4 } }()
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1).fill(c.hair)
                RoundedRectangle(cornerRadius: 1).fill(c.ink2).frame(width: g.size.width * fraction)
            }
        }
        .frame(height: 2).padding(.leading, 16).accessibilityHidden(true)
    }
}
