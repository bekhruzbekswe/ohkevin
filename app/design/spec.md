# Oh Kevin call window: build specification (first design)

Status: frozen. The first native-window design; the Mac app now follows `design/final.html`. Kept for its reasoning.

Build from this file with `mockups.html` open beside it. The mockups are drawn at true size (1 CSS px = 1 pt); where
this file and the mockups disagree, this file wins. Every string in section 14 is final.

This window extends the old launcher's design ("the launcher spec" below; its pictures are in `docs/design/launcher/`). Everything not said
here is as the launcher spec says: tokens, the mark, the approval card, plain words, motion rules, Increase Contrast.

Units are points. Colours are AppKit/SwiftUI semantic colours unless a value is given.

---

## 1. The idea in one paragraph

The window is the call, the way a phone's screen is the call. At the top, one word says whose turn it is. In the
middle, whatever needs you (a question, a problem), then what Claude Code is doing, then what was said, with your
words appearing as you speak them. At the bottom, how you act: type, stop the work, end the call. The launcher's
rules hold: green live, orange needs you, red broke; motion means Claude Code is working; nothing else is on screen.

## 2. Structure

One window, 400 × 600 by default. Four zones, top to bottom, full width, no sidebars, no tabs:

| Zone | Height | Content |
|---|---|---|
| **Title bar** | 32 | Traffic lights · the project's name, centred (the window title) · timer · ⋯ |
| **Now** | 6 top, 40 content, 14 bottom; 0.5 hairline below | Mark 28×28 · 12 gap · state word over the sub line · flexible space · microphone button 32×32 |
| **Body** | the rest | *Pinned* (12 top, 16 sides, 10 between items): banners, then approval cards, then the work group. Below it, *Talk* (12 top and bottom, 16 sides, 10 between lines), scrolling. |
| **Act** | 4 top, 16 sides and bottom | The text field (32), 8 gap, the call row (36): Stop and End Call |

- The Now zone keeps its height when the sub line is empty (the line keeps 16 pt), so nothing jumps between states.
- Pinned items appear only when they have something to say; with none, Talk starts 12 below the hairline.
- Pinned takes at most 62% of the body's height, then scrolls inside itself (the launcher's `HuggingScroll`); Talk
  keeps the rest. Talk is anchored to the bottom (`defaultScrollAnchor(.bottom)`), its top edge fades out over 22 pt.
- In ended and failed states the text field is gone and the call row holds that state's buttons (section 9).

## 3. Tokens

Reuse `Style.swift` as it is (`Tint`, `CallButtonStyle`, `CallRowButtonStyle`, `AnswerButtonStyle`,
`SmallButtonStyle`, `PlainEdge`). The window adds only these:

| Use | Token |
|---|---|
| Window background | `windowBackgroundColor`; title bar transparent over it (`titlebarAppearsTransparent`, `fullSizeContentView`) |
| Your line | fill `tertiarySystemFill`, radius 12 continuous, padding 6 × 10 |
| Your line while you are still speaking | no fill, 1 pt `tertiaryLabelColor` stroke, text `secondaryLabelColor` |
| What the voice did not get to say | `tertiaryLabelColor` |
| Work group | fill `quaternarySystemFill`, radius 10, padding 0 × 12 (the launcher's row fill) |
| Microphone button | the launcher's plain button face, circle 32, SF `mic.fill` 15; muted: fill `labelColor`, `mic.slash.fill` in `windowBackgroundColor`; at 40% and disabled while the ears are not listening (connecting, can’t hear you) |
| Text field | `textBackgroundColor`, radius 8, the plain button's 0.5 edge; focus: the system focus ring |

### Type (SF Pro; SF Mono for commands)

| Element | Size | Weight | Colour |
|---|---|---|---|
| Window title (project) | 13 | semibold (system title) | label |
| Timer | 12 | regular, monospaced digits | secondary |
| State word | 20 | semibold, −0.2 tracking | label |
| Sub line | 12 | regular | secondary |
| Talk lines (yours and the voice's) | 14 | regular, line height 1.42 | label |
| Text field | 13 | regular | label; placeholder tertiary |
| Banners, worker rows, cards | as the launcher spec | | |

Talk is 14 rather than the launcher's 12–13 because it is read from a little further away, mid-conversation.

## 4. The mark in the window

The Now zone's mark is the menu-bar icon's form, at 28 × 28, coloured as the launcher's header mark, following the
same `Light` (`app/Sources/VoiceCore/CallStatus.swift`). Use `HeaderMark` at 28.

| Light | Form | Colour |
|---|---|---|
| starting | live, pulsing | green |
| onCall | live | green |
| working | working (moving) | green |
| needsAnswer, cantHear | live | orange |
| ending | live, pulsing | secondary |
| ready (call ended) | quiet (dots) | secondary |
| failed | SF `exclamationmark.triangle.fill` 21 pt | red |

The mark says the call's state; the word beside it says the turn. They are independent: "Speaking" with moving
bars means the voice talks while Claude Code works.

## 5. The turn: state word and sub line

The state word is the window's heart and comes from `Turns` (`app/Sources/Ears/Turns.swift`). First match wins:

| # | When | Word | Sub line |
|---|---|---|---|
| 1 | Failed (section 10) | the failure title | the failure line |
| 2 | Ended | Call ended | the launcher's ended line (section 9) |
| 3 | Ending | Ending the call… | the launcher's ending line |
| 4 | Starting | Connecting… | The voice is warming up. |
| 5 | Ears not listening (mic denied, recogniser stopped) | Can’t hear you | Typing still works. (mic denied only; the banner says the rest) |
| 6 | Muted | Mic off | Press M to talk again. Typing works. |
| 7 | The voice is held mid-word (`held != nil`) | Paused | It stopped mid-word to hear you. |
| 8 | `speaking` | Speaking | |
| 9 | `hearing` | Hearing you | |
| 10 | `thinking` | Thinking | |
| 11 | live, and the server said `wait` (turn state "waiting") | Listening | Waiting for the rest of your thought. |
| 12 | live, nothing heard yet this call | Listening | Just talk. It answers when you pause. |
| 13 | live | Listening | |

The word changes at once (no cross-fade: it must keep up with talk). The page's "Reply started 0.9 s after you
finished." is not shown: it is a measurement, and it is in the call's log.

## 6. Talk

What was said, oldest at the top. No names, no times, no avatars: the side and the shape say who.

- **The voice**: plain text, left, up to 94% of the width. Each sentence is added when it starts playing (`began`),
  to the voice's current line, as the page does.
- **You**: a bubble, right, up to 80% of the width. Typed words are yours too and look the same.
- **You, still speaking** (`Turns.ghost`, non-empty): the same bubble as an outline, text secondary, at the bottom.
  It updates in place as words come. When the words are final it becomes a filled bubble in the same place: the user
  sees exactly what was heard.
- **Joining a pause**: when your new words join your last ones (`joinTurn`), the last bubble (and any voice line
  after it that was never heard) is replaced by the joined words, as the page's `heard()` does. Nothing animates but
  the text.
- **What the voice did not get to say**: while the voice is held, the unplayed rest of the current sentence turns
  tertiary (cut at the player's sample clock, `cutText`). If the hold ends as noise, it turns back and plays on. If
  the voice is cut off (`hush` with a cut), the rest stays tertiary for good: that is what you never heard, and what
  the talker was told you never heard.
- **Usage-limit lines** (the voice's own sentences matching the page's `LIMIT` pattern) are not added to Talk; they
  become the limit banner (section 8).
- Scrolling: anchored to the bottom; if you have scrolled up, new lines do not pull you down. Text is selectable.
  The talk is kept for the window's life only (it is in the call's log).

## 7. Work and approvals (the launcher's parts)

**Work group.** The launcher's `WorkerRow`s, one per worker, in a group (section 3). It appears the first time any
worker leaves `idle` on this call and stays until the call ends, so a finished worker reads "Ready when you are."
Step text follows the launcher's rules (plain words from `plainWords`, at most one change per 0.6 s).

**Stop.** The launcher's rule: in the call row, left of End Call, equal widths, only while any worker is working or
waiting; "Stop All" with two or more workers. `POST /stop`.

**Approval cards.** The launcher's `AskCard`, `Confirmation` and their behaviour (launcher spec 6), first in Pinned
after banners, oldest first, with the worker tag when there are several workers. Added to match the call page
(`index.html` `showAsks`), whose approvals the owner's side-by-side trial preferred:

- **Place.** While two or more are open, the tag line reads "API · 1 OF 2" (just "1 OF 2" with one worker): the voice
  asks them one at a time, oldest first, and the pinned zone may hide the rest under its fade.
- **Armed.** While a spoken yes counts (the voice has finished asking it, the 20 s window is open), the card gets a
  2 pt accent outline, the page's armed card, and its hint turns label colour, semibold.
- **Next in line.** Only the oldest is asked aloud, so a later card's Approve is never accent, even if a spoken yes
  could answer it once its turn comes.
- **The hint**, first match wins (`Approval.Hint`, made in `CallModel.makeCards`):

| Card | Symbol + hint |
|---|---|
| its answer did not go through | `exclamationmark.circle` "That didn’t go through. Try again." |
| not the oldest | `clock` "Next in line. A click works now." |
| `voice` false | `cursorarrow.click` "Needs a click. A spoken “no” still declines it." |
| armed | `mic.fill` "Say “yes” or “no” now." |
| the voice has said its question and is still speaking | `mic.fill` "The voice is asking…" |
| `voice` true, otherwise | `mic.fill` "Say “yes” and it asks once more." (a yes outside the window makes the voice ask again) |

**Answered approvals stay in Talk** where they happened, as the page keeps them in its work log: a line, left,
`checkmark.circle.fill` green or `xmark.circle.fill` secondary (11 pt), "Approved" / "Denied" (+ " by voice") 12 pt
semibold, then exactly what (SF Mono 11, secondary, one line, cut in the middle). Clicks, voice and Stop all leave one;
the 0.8 s `Confirmation` still marks a spoken answer in Pinned.

**Coming forward.** When a `voice` false request arrives and the window is not the front window: deminiaturize it if
needed, then `orderFrontRegardless()`. It does not activate the app or take the keyboard (the launcher's
"opening by itself", moved here). A `voice` true request never moves the window: the voice asks.

## 8. Banners

The launcher's `Banner`, first in Pinned, newest last. At most one of each kind.

| Kind | Symbol | Text | Button | Goes when |
|---|---|---|---|---|
| Server problem (`error` event) | `exclamationmark.triangle.fill` orange | the server's sentence, " (error NNN)" removed | | `turn_end` (launcher 5.9) |
| Usage limit, warning | `gauge.with.needle` secondary | the voice's sentence, as said | | a newer limit line, or the call ends |
| Usage limit, hit ("You’ve hit…") | `exclamationmark.triangle.fill` orange | the voice's sentence | | as above |
| Stop failed | | Stop didn’t go through. Try again. | | the next Stop |
| Recogniser stopped | | Speech recognition stopped. | Listen Again (accent) | the ears listen again |
| Audio device changed | | The microphone changed. | Listen Again (accent) | as above |
| Microphone not allowed | | Oh Kevin isn’t allowed to use the microphone. | Open Settings (accent) | the app is allowed (checked on becoming active) |

**Listen Again** closes the ears and opens them again (`Sound` + `Recognizer`, as `Call.open` does) without ending
the call. **Open Settings** opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`.
The last three make the Light `cantHear` (orange mark, word "Can’t hear you"): the call is live and deaf, which needs you.

## 9. Act zone, and the ends of the call

**Text field.** Placeholder "Type instead of speaking". Return sends: the text is trimmed; if not empty, the voice is
hushed and the words go in as yours (the page's `typed.onsubmit`). Empty Return does nothing. From the first
character an SF `arrow.up.circle.fill` 18 pt accent button appears at the field's right, which also sends. Disabled at
50% while connecting.

**Call row** (36 high, the launcher's `CallRowButtonStyle`):

| State | Row | Above it |
|---|---|---|
| Connecting | **Cancel** (end style, `phone.down.fill`) | the field, disabled |
| Live | [Stop / Stop All] **End Call** | the field |
| Ending | **Ending…** disabled (`tertiarySystemFill`, tertiary label) | nothing |
| Ended, handed over | **Close** (plain) | nothing |
| Ended, not handed over, work exists | **Close** (plain) · **Open in Claude** (accent, `arrow.up.forward.app`) | nothing |
| Ended, no work was asked of Claude Code | **Close** (plain) | nothing |
| The call stopped | **Close** (plain) · **Call Again** (callGreen, `phone.fill`) | nothing |
| The call didn’t start | **Close** (plain) · **Try Again** (callGreen) | nothing |

- **Ending** begins with End Call, ⌘Q, or the voice hanging up: the ears and the mouth close at once (the microphone
  goes first), then the launcher's ending (launcher 5.10). Sub line: "Then its work opens in the Claude app." when it
  will hand over, else "Claude Code is saving its work."
- **Ended**: word "Call ended", the title bar shows the length ("12 min") where the timer was, sub line "Its work is
  open in the Claude app." or "Its work is saved in Claude Code." (launcher 9). Talk stays readable. The window does
  not come forward for this.
- **Open in Claude** runs `claude --desktop --resume <id>` for each worker's session (the command `handover.mjs`
  uses), then the button reads "Opened" disabled. On failure the sub line reads "That didn’t open. Try again." and the
  button comes back.
- **Close** closes the window; the menu-bar icon is back to quiet. **Call Again / Try Again** starts a call in the
  same project, in this same window (talk cleared).

## 10. Failures

The launcher's `Failure` values, shown in the window instead of the panel (the window is open from Start Call on):
red triangle, the title as the word, the line as the sub. Pinned and the field are gone; Talk stays.

| Cause | Word | Sub | Buttons |
|---|---|---|---|
| launcher's four "didn’t start" causes | The call didn’t start | the launcher's lines | Close · Try Again |
| The local voice did not load in 2 minutes | The call didn’t start | The voice didn’t load. | Close · Try Again |
| The server exited during the call | The call stopped | Claude Code’s work so far is saved. | Close · Call Again |

A failure brings the window forward (`orderFrontRegardless`, no keyboard). "Show Details" (the log) moves to the ⋯
menu while a failure shows: **Show Log**.

## 11. Title bar and the ⋯ menu

- Title: the project's folder name (`NSWindow.title`, so Mission Control and the Window menu show it).
- Trailing accessory (`NSTitlebarAccessoryViewController`, `.trailing`): the timer (launcher `TimerStyle`, updated
  each second only while the window is visible) then the launcher's `MoreMenu` button, 6 apart, 10 from the edge.
- ⋯ menu, a standard menu:
  - **Voice ▸** a submenu: one section per group, headed "US female", "US male", "British female", "British male",
    "Other" (only groups that have voices), names as the page writes them (`af_heart` → "Heart"), a checkmark on the
    current one. Choosing one saves it (the setting the launcher keeps) and the voice says "This is how I sound now."
    The item shows the current name at its right, secondary. Hidden until the server's `hello` lists voices.
  - divider · **Settings…** ⌘, (the launcher's Settings window) · divider · **End Call** (no shortcut).
  - With a failure: **Show Log** above Settings.
- There is no other menu in the window.

## 12. Window behaviour

| | |
|---|---|
| Size | 400 × 600 default; minimum 360 × 440; maximum width 640; height free. Resizable. |
| First position | Top right of the screen holding the menu-bar icon: 12 from the right of `visibleFrame`, 12 below its top. Then remembered (`setFrameAutosaveName("Call")`). |
| Level | Normal. Not always on top: you talk while working in other windows; it comes forward by itself only for a click-needed approval and a failure. |
| Opens | At Start Call, key and front (the user just clicked). The text field does not take focus, so M and Space work at once. |
| Close (red button, ⌘W) | **Hides the window; the call goes on.** The menu-bar icon stays live, the microphone stays open (macOS shows its own microphone indicator). A click on the menu-bar icon brings it back. After the call has ended, closing releases it. |
| Minimise | Allowed; a click-needed approval or a failure deminiaturizes it. |
| Full screen | Off (`collectionBehavior` `.fullScreenNone`). The green button zooms within the maximum width. |
| Quit (⌘Q) | Ends the call first (section 9), as the launcher does. |
| Dock | Interim: a regular Dock app (`.regular`) until the launcher shell exists; then none, a menu-bar app (`LSUIElement`). |

## 13. Keyboard

Keys go to the window's own handler (`NSEvent` local monitor or the hosting view's `keyDown`), as the panel's do.
When the text field has focus, only Return, Escape, ⌘Return, ⌘. and ⌘ shortcuts act; everything else is
typing (⌘Delete there edits the field, it does not Deny).

| Key | When | Does |
|---|---|---|
| M | the field is not focused | Mute / unmute |
| Space | the field is not focused, the voice is speaking | Cuts the voice off (`hush`), as the page does |
| Tab | anywhere | Focuses the field (the window's only key view) |
| Return | in the field | Sends |
| Escape | in the field | Clears it if not empty, else leaves it |
| ⌘Return / ⌘Delete | a request is open, the field is not focused (⌘Return also in it) | Approve / Deny the oldest (launcher) |
| ⌘. | Claude Code working | Stop (launcher) |
| ⌘, | | Settings (not built yet: the launcher's Settings window) |
| ⌘W | | Closes the window (the call goes on) |
| ⌘Q | | Ends the call, then quits |

End Call has no shortcut, and Escape never ends anything, on purpose (launcher 12).

## 14. Copy deck (every string, final)

**Words**: Connecting… · Listening · Hearing you · Thinking · Speaking · Paused · Mic off · Can’t hear you ·
Ending the call… · Call ended · The call didn’t start · The call stopped

**Sub lines**: The voice is warming up. · Just talk. It answers when you pause. · Waiting for the rest of your thought. ·
It stopped mid-word to hear you. · Press M to talk again. Typing works. · Typing still works. ·
Then its work opens in the Claude app. · Claude Code is saving its work. · Its work is open in the Claude app. ·
Its work is saved in Claude Code. · That didn’t open. Try again. · The voice didn’t load. · the launcher's failure lines

**Buttons**: Cancel · Stop · Stop All · End Call · Ending… · Close · Open in Claude · Opened · Call Again · Try Again ·
Listen Again · Open Settings · Approve · Deny

**Field**: Type instead of speaking

**Banners**: Speech recognition stopped. · The microphone changed. · Oh Kevin isn’t allowed to use the microphone. ·
Stop didn’t go through. Try again. · (server and limit sentences, as sent)

**Card hints**: Say “yes” or “no” now. · Say “yes” and it asks once more. · The voice is asking… · Next in line. A click works now. ·
Needs a click. A spoken “no” still declines it. · That didn’t go through. Try again.

**Answered (Talk)**: Approved · Approved by voice · Denied · Denied by voice

**⋯ menu**: Voice · US female · US male · British female · British male · Other · Settings… · Show Log · End Call

**Voice sample**: This is how I sound now.

**Window title**: the project's folder name.

## 15. Motion

The launcher's table (launcher spec 11) holds for the mark, worker bars, cards, the confirmation and Stop. The window
adds only:

| What | How | Reduce Motion |
|---|---|---|
| A new talk line | fades in, 0.15 s; no slide | instant |
| Your outline becoming a bubble | fill and stroke cross-fade, 0.15 s | instant |
| Pinned zone growing or shrinking | 0.25 s ease-in-out (the launcher's panel height) | instant |
| Banner arrives / leaves | the launcher's card arrival, 0.25 s | 0.15 s fade |
| Window coming forward | none: it just appears in front | |

Nothing else moves: no level meters, no waveform, no typing animation, no pulsing orb. The live words are the motion
of talk, and they are the user's own.

## 16. Accessibility

- **The Now zone** is one element: "Speaking. On a call, 4 minutes 12 seconds." (word, then the Light words of the
  launcher spec 9, then the timer); the sub line follows when present. Word changes are **not** announced (they change
  several times a second during talk); VoiceOver users read Talk.
- **Talk**: each line one element, "You: …" / "Claude: …". A line with an unsaid rest: "Claude, cut off: <said>. Not
  heard: <rest>." Your outline: "You, speaking: …", not announced. New voice lines are announced politely only when
  VoiceOver is running and the window is key, since the voice already speaks them aloud: off by default.
- **Announcements**: a request arriving (launcher), "Approved by voice" / "Denied by voice", a banner arriving, the
  failure title, "Call ended".
- **Microphone button**: "Mute microphone" / "Unmute microphone", a toggle (`.isToggle` trait), with its state; help
  tag "Mute (M)" / "Unmute (M)".
- **Field**: label "Type instead of speaking"; the send button "Send".
- **Colour is never alone**: every state has its word; the mark's shape differs (launcher 13); unsaid text is also
  in the label; the muted button changes symbol (`mic.fill` → `mic.slash.fill`) as well as fill.
- **Contrast**: all text is system label colours and follows Increase Contrast. Tertiary unsaid text is decoration
  of a fact also given to VoiceOver; under Increase Contrast it becomes `secondaryLabelColor` with a 1 pt
  `separatorColor` underline (dotted) so it still reads as different. The outline bubble's stroke becomes
  `secondaryLabelColor`.
- **Targets**: nothing clickable under 24 pt; the microphone button 32.

## 17. How it is built

**Only the Command Line Tools, macOS 26.** Checked against the Command Line Tools' compiler on this Mac:

- `@Observable` and `@Bindable` **compile** (the Observation macro plugin ships with the Command Line Tools; the
  launcher's `Launcher` is `@MainActor @Observable` and its views take it as `@Bindable var launcher`).
- SwiftUI's `@State` **does not** (its macro plugin, `SwiftUIMacros`, is not there). `@FocusState`, `@Environment`
  and `defaultScrollAnchor` compile.

So, as the launcher does: one model class, `@Observable final class CallModel` (not `@MainActor`: the main queue is the rule, as for `Turns` and `Call`), holds all state,
including view state (the field's text, which cards are expanded, whether the user scrolled up); views take it as
`@Bindable var model` and have no `@State`. The field's focus may use `@FocusState`.

**The bridge from `Turns`.** `Turns` and `Call` stay plain classes, as in `app/` today, driven on the main queue.
`Call.changed()` (the `Host`'s `changed`, which `Turns` and the call call) calls `model.update()`, which copies what the window shows
(`state`, `ghost`, `lines`, `paused`, `waiting`, `armedAsk`, `voices`, `voiceName`, `problem`) into the model's
observed properties, **assigning only values that changed**: `changed` fires on every 20 ms tick and every
recogniser result, and an Observation write re-renders even when equal.

**The window** is AppKit, like the launcher's `PanelWindow`: an `NSWindow` (titled, closable, miniaturizable,
resizable) whose content is an `NSHostingView` of the root SwiftUI view; the title-bar accessory hosts the timer and
⋯. `windowShouldClose` returns false and orders the window out while a call is live (section 12).

**What it reads:**

| Shown | From |
|---|---|
| Mark, Light, timer | `Light(phase:status:cantHear:)`, `timer()`, `callLength()` (VoiceCore) |
| Word, sub, talk | `Turns` (Ears) through `CallModel` |
| Worker rows, cards, Stop, banners from the server | `CallStatus` (VoiceCore), applied to the same event stream `Turns.server` reads |
| Step words, card questions | `plainWords` (VoiceCore), unchanged; no new wording |
| Failures | `Failure` (VoiceCore), plus `.voiceDidNotLoad` |

**Small additions outside the window** (each a few lines):

1. `Turns`: expose `paused` (`held != nil`), `waiting` (turn state "waiting"), `armedAsk` (the id a spoken yes now
   answers, while its 20 s window is open), whether anything has been heard this call, and for the voice's lines the
   heard length (set by `hush` from `heardSoFar`, and while held from the player's clock).
2. `Turns.server`: a `say` that matches `LIMIT` goes to a `limit` property instead of `lines`.
3. `CallStatus`: keep each worker's session id (`session` event: `worker` → `id`); today it keeps only the names.
4. `Failure.voiceDidNotLoad`.
5. `WorkerRow`, `AskCard`, `Confirmation`, `Banner`, `HuggingScroll`, `HeaderMark`, `MoreMenu` move from LauncherKit
   into a module both the launcher and the call window link, taking values and closures instead of `Launcher`.

## 18. The launcher and this window

The future is one app: the launcher's menu-bar item and panel are this app's shell, the call window is the call, and
there is no Chrome. Rule: **the menu bar starts calls and shows state at a glance; the window is the call.** Nothing
appears in both.

| | Menu-bar icon | Panel | Call window |
|---|---|---|---|
| When | always | before and after a call | from Start Call to Close |
| State at a glance (the mark's forms, orange pill) | ✓ | | ✓ (the same mark, larger) |
| Project, Start Call, Choose Folder | | ✓ | |
| Something missing and its fix | | ✓ | |
| Connecting, Cancel | | | ✓ |
| The turn, live words, talk, typing, mute | | | ✓ |
| Worker rows, approval cards, Stop, End Call | | | ✓ |
| Problems during the call, failures, the call ended, the hand-over | | | ✓ |
| Voice | | | ✓ (⋯) |
| Settings…, Quit | | ✓ (⋯) | Settings… (⋯) |

- **Clicking the icon during a call** brings the call window forward (and shows it if it was closed). The panel does
  not open during a call. So the panel's call states (launcher 5.5 to 5.10), "Show Call Window", the panel opening
  itself for approvals, and "The call can’t hear you / Reopen" (a closed window no longer stops the microphone) all go.
- **Start Call** in the panel closes the panel and opens the window, which shows Connecting.
- **Settings** loses "Speaks with": the voice is chosen in the call, where you can hear it.
- The Chrome-only parts of the launcher go: Chrome in "Something missing", the Chrome instance, the port's microphone
  memory, the privacy note's "Chrome sends your speech to Google" (speech now stays on this Mac: the note should say so).

## 19. Left out, on purpose

| Left out | Why |
|---|---|
| The who-is-speaking strip (three lanes over the last minute) | It shows the turn-taking for whoever is tuning it. The word, the live words and the faint unsaid text show it for whoever is talking. |
| Speaker colours (pink you, blue voice, amber work) and the coloured orb | Colour means live, needs you, broke. Side and shape say who spoke. |
| The work log (every step, the worker's full written answers, rendered Markdown) | The voice reports the result; the row says what it is doing; the whole session opens in the Claude app at the end, where it is readable properly. A second reader inside a call window is a second product. *The owner may want this back as a later item.* |
| "What you can say" and "Keys" | The voice understands plain speech; a list of phrases teaches commands to a product that does not need them. M is in the microphone button's help tag; Space works as it did on the page. |
| This call's numbers (reply delay, joins, waits, false pauses, cut-offs) | Measurements for the builder; they stay in the call log. |
| The headphones setting | Voice processing always cancels the echo here, so talking over the voice always works. |
| "Latest" button, tabs for narrow windows | One column at every width; the anchored scroll does the rest. |
| The hang-up box with commands to copy | One button, Open in Claude, does it. |
| Timestamps and names on lines; "said on its own" tags | Side, shape and the limit banner carry them. |
| Always on top, a mini mode, a level meter | Each adds a mode or motion; the window comes forward exactly when it is needed. |
| A Stopped tag on a stopped task | The worker row goes back to "Ready when you are."; the voice says it stopped. |
| A sound per step and at the end of work | The launcher's "no sounds" rule; the voice already speaks. |
