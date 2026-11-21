/// What leaves the Mac and what runs unasked: at the foot of Settings (the launcher's panel no longer carries it).
/// What a spoken yes approves is said beside its setting.
public enum Disclosure {
    public static let leaves = "Chrome sends your speech to Google to become text. Your words, and the files Claude Code reads, go to Anthropic."
    // Auto mode does not ask: Claude Code's own checks let a step run or refuse it (probed: 17 steps, no question).
    static let runs = "Claude Code edits files, runs commands and uses the network without asking", checks = "own safety checks refuse what they judge dangerous"
    public static let unasked = "\(runs). Its \(checks)."
    /// What Claude Code may do on a call, as one sentence.
    public static let mayDo = "\(runs); its \(checks)."
    /// The Settings line that points at the page below.
    public static let pointer = "What leaves this Mac, and what Claude Code may do."

    /// The logo's mark (design/logo/lockup-mark-light.svg), its bars in the page's ink: inlined so the page needs nothing else.
    static let markSVG = """
    <svg viewBox="4 18 90 68" width="76" height="57" aria-hidden="true"><rect x="6" y="77" width="4" height="6" rx="2" fill="currentColor"/><rect x="13.56" y="59.58" width="4" height="10" rx="2" fill="currentColor"/><rect x="21.04" y="44.92" width="4" height="14" rx="2" fill="currentColor"/><rect x="28.44" y="33.01" width="4" height="18" rx="2" fill="currentColor"/><rect x="35.76" y="24.87" width="4" height="20" rx="2" fill="currentColor"/><rect x="43" y="21.5" width="4" height="18" rx="2" fill="currentColor"/><rect x="50.16" y="21.87" width="4" height="14" rx="2" fill="currentColor"/><rect x="57.24" y="25.02" width="4" height="10" rx="2" fill="currentColor"/><rect x="64.24" y="29.92" width="4" height="8" rx="2" fill="currentColor"/><rect x="71.16" y="37.58" width="4" height="6" rx="2" fill="currentColor"/><circle cx="82.2" cy="54.8" r="10" fill="#F4A62A"/></svg>
    """

    /// The short privacy page the app ships: self-contained HTML in the design's look (paper and ink, a serif title, light and dark by
    /// the browser's own setting). It is made from the strings above, so the words never drift from Settings. `current` marks the
    /// choice the person has made for a spoken yes.
    public static func page(product: String = Product.name, current: SpokenYes? = nil) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let choices: [(SpokenYes, String)] = [(.safeSteps, "Safe steps"), (.anyStep, "Any step"), (.nothing, "Nothing")]
        let list = choices.map { c in "<li><b>\(esc(c.1))</b>\(c.0 == current ? " <span>(your setting)</span>" : "")<br>\(esc(yes(c.0)))</li>" }.joined(separator: "\n    ")
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>What leaves this Mac · \(esc(product))</title>
        <style>
        :root { --ground:#F6F3EC; --ink:#1B1A17; --ink2:#57534B; --hair:rgba(27,26,23,.12); color-scheme: light dark; }
        @media (prefers-color-scheme: dark) { :root { --ground:#181715; --ink:#F6F3EC; --ink2:#B5B0A6; --hair:rgba(246,243,236,.14); } }
        body { margin:0; background:var(--ground); color:var(--ink); font:17px/1.55 -apple-system, BlinkMacSystemFont, system-ui, "Helvetica Neue", sans-serif; }
        main { max-width:34rem; margin:0 auto; padding:64px 24px 96px; }
        header { display:flex; align-items:center; gap:16px; margin:0 0 64px; }
        header span { font:400 28px/1 ui-serif, "New York", "Iowan Old Style", Georgia, serif; letter-spacing:-0.02em; }
        h1 { font:400 44px/1.1 ui-serif, "New York", "Iowan Old Style", Georgia, serif; letter-spacing:-0.01em; margin:0 0 40px; }
        h2 { font-size:17px; font-weight:600; margin:40px 0 8px; padding-top:16px; border-top:1px solid var(--hair); }
        p, li { margin:0 0 8px; } ul { padding:0; margin:0; list-style:none; } li { padding:8px 0; }
        li span { color:var(--ink2); font-size:14px; }
        </style></head><body><main>
        <header>\(markSVG)<span>\(esc(product))</span></header>
        <h1>What leaves this Mac</h1>
        <p>\(esc(leaves))</p>
        <h2>What Claude Code may do</h2>
        <p>\(esc(mayDo))</p>
        <h2>A spoken “yes”</h2>
        <p>What a spoken “yes” may approve is your choice in Settings:</p>
        <ul>
            \(list)
        </ul>
        </main></body></html>
        """
    }

    /// One paragraph for Settings, joined by a semicolon after "asking".
    public static let settings = "\(leaves) \(runs); its \(checks)."

    /// The second line of "A spoken “yes” approves", by choice.
    public static func yes(_ s: SpokenYes) -> String {
        switch s {
        case .safeSteps: "Edits, new files, commits and new branches in the project. Anything else needs a click."
        case .anyStep: "Any step Claude Code asks about."
        case .nothing: "Nothing. Every step needs a click."
        }
    }
}
