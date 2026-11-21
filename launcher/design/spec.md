# Oh Kevin launcher: build specification

Status: living. Kept in step with the launcher; the code is the truth where they differ.

The design is `design/final.html` (section "The launcher") with tokens in `design/system.css` (section 13).
Units are points. Where the drawing and this file disagree, the code's truth wins and this file says so (section 6).

## 1. The idea

A phone, not a control panel. One object, three rows, one inset of 16, **one size: 320 × 228 in every state**.

| Row | Height | Holds |
|---|---|---|
| head | 52 | line 1 at 22 (28 line), line 2 at 17 (24 line, grey, tabular digits). 36 kept clear on the right for the corner control |
| pill | 64 | the hero: the folder chooser before a call, the living pill on one |
| door | 48 | one full-width button, always here. Marigold only when it is the person's move |

Sizes used: 22 and 17 for text; 64, 48 and 28 for controls; radii: 20 for the panel, fully round for controls.
Marigold appears only where it is the person's move: a filled door (Start call, the next setup step), a marigold edge on the
door (Answer in the call, Allow microphone, Show the call when its window is gone), the one word "you", and the dot in the menu-bar item.

## 2. Structure in code

- `VoiceCore/PanelState.swift`: pure data. `PanelInput` (what the launcher knows) becomes `PanelData` (head, pill, door,
  menu-bar shape). Views send `PanelIntent`s. Tested in `swift test`.
- `CallViews/` (a library; depends on VoiceCore only): `PanelView(data:active:still:send:)` and its rows and controls, `Palette`,
  the chevron and wave art. It reaches into nothing (no launcher, no process): a host builds a `PanelInput`, shows
  `PanelView(data: PanelData(input), send: …)` and handles the `PanelIntent`s.
- `LauncherKit/`: `Launcher.panel` (the input mapping) and `Launcher.handle(_:)` (the intents), the `NSStatusItem`, `MenuBarItem`
  (the 52 × 22 item's art), the fixed-size non-activating panel window, `PanelHost`, Settings.

## 3. Tokens

Colours are system.css section 1 (light / dark): ground F6F3EC / 181715, ink 1B1A17 / F6F3EC, ink-2 57534B / B5B0A6, ink-3 6B665D /
9A958B, sunk ECE8DF / 262421, pill FFFFFF / 4D4941, marigold F4A62A (down E2951A / FFB84A), on-marigold 1B1A17, wrong B82E24 / FF8073,
wrong-on-ink FF8073 / B82E24, hairline ink at 12% / 14%. Type: New York (serif) and SF Pro; head line 1 SF 22 semibold, tracking -0.02em,
or serif 22 upright (the system's own lines) or serif italic 22 red ("Call lost", failures); line 2 SF 17; door 17 semibold; the pill's word
serif italic 22. Spacing: inset 16, rows 16 apart, pill padding 8, gap 8.

## 4. The rows

**Head.** Before a call "Oh Kevin" (the serif, upright) + "A voice call with Claude Code." Setup: "N steps to go" + "Then: …" (or "Then you can call.").
On a call "On a call" + the clock counting up from the call's start (m:ss). Someone asks: "We need you", only "you" in marigold.
Ended "Call ended." + the hand-over line, or "The call window has closed.". Failure: red serif italic title + the real line.

**Pill, before a call.** An outlined chooser (1.5 ink-3): folder glyph, the project name (middle cut at 16 characters, never inside a word,
`middleCut`), up/down arrows. A menu of recent projects and "Choose Folder…". Disabled (45%) while starting or ending.

**Pill, on a call.** Raised (white / 4D4941, short shadow). Left: round Mute (48, ink disc, mic glyph). Between: the mark's chevron
running into a wave of as many bars as fit, then the voice's word in serif italic. Right: round End call (48, well, red phone glyph).
Muted: the pill turns over (ink fill), Mute shows the crossed mic and reads Unmute. Mic blocked, window gone or reconnecting: flat
(sunk, no shadow), Mute disabled, the wave is still or lit in turn dots, never fewer than three bars. Keyboard focus is a marigold ring, 3 wide, on every control. A disabled control has no fill, ink-3 words or glyph and a faint ring; a busy or impossible setup step is a quiet disabled door, never a faded marigold one. The wave never shows fewer than three bars (the word may tighten its tracking a hair to leave room). The project name is cut to its measured room by `middleCut`.
The wave runs the design's loops (a swell when listening, tall and uneven when speaking, a bump walking when thinking); the launcher
hears no sound, so it never claims a level. It moves only while the panel is on screen and Reduce Motion is off.

**Door.** Primary (marigold fill): Start call, Call again / Try again, and the setup step's action. Quiet (1.5 ink-3 edge, no fill):
Show the call, Cancel, Ending…. Move (2 marigold edge): Answer in the call, Allow microphone, Show the call without a window.

**Corner.** A 28 round control with three dots, top right (10 from the edge): Settings…, Check for Updates… (only when the app can update itself), Show Details (only after a failure),
Quit (End Call and Quit on a call).

## 5. The menu-bar item

One box, 52 × 22, in every state; a template image (the bar tints it), drawn in whole pixels. States differ by shape:
bare mark `>_` at rest, with a small ring while setup steps remain; `>!` when it broke or cannot hear; `>` and three dots while reconnecting;
a small 44 × 18 pill with a little wave while a call is live (solid with the wave knocked out when muted); a marigold dot at the pill's right
end, no number, when something asks (the dot is a layer on the button, the one coloured thing).

## 6. What is real (and what the design draws that the code cannot know)

| Drawn | Source |
|---|---|
| Listening / Speaking / Thinking / Muted | server `voice` event (core): the page's `/live` floor and mute state, and whether the voice's talker is composing |
| Mute from the launcher | `POST /mute {on}` relayed to the page (core). Enabled only when the page has reported a mute state (`canMute`) |
| Clock | the launcher's own clock from the moment the call connected |
| Mic blocked | server `mic` event |
| Reconnecting | the launcher's feed from the server dropped while the call is live (the call is out of sight, not over) |
| "Not listening", "Its window isn’t open." (not drawn) | no call page connected: its window was closed. The code's truth; the design has no word for it |
| A server that breaks mid-call | started again once by the launcher, on the same port with the same key, while the call window is open: the panel says Reconnecting, the same window reconnects by itself and the call goes on (a new call: its clock starts again). A second break, or no window, is Call lost |
| Call lost, then Call again | the server stopped. The window stays open; Call again starts the server on the same port with the same key and that window reconnects (no new window, no page in between). The line is the design's: "The connection dropped." |
| Setup steps | the real health checks: project, the download, Claude Code (install or update), sign-in, Chrome, Node. "Allow the microphone" is not a step: the Mac can only be asked on a call |
| Starting | not drawn: "Starting the call." with the chooser disabled and a quiet Cancel |
| Ending | not drawn: "Ending the call." with a flat, still call pill (no word, Mute and End disabled) and a disabled "One moment" door, until the server exits |
| Before the page reports a voice state | no word, still dots, Mute disabled: nothing is claimed until the first `voice` event |
| A request while the mic is blocked, the window gone or reconnecting | "We need you" keeps line 1 and the dot stays in the menu bar; the door stays the fix |

Dropped with the old panel: worker rows, Approve and Deny cards, Stop, the error banner, the first-call note and the voice offer (Settings
keeps the voice download and the privacy note).

## 6b. Settings

One window, 400 wide, the design's ground (transparent title bar, no visible title), 24 round it, 16 between rows; built from CallViews'
settings pieces (`SettingsSheet`, `SectionTitle`, `SectionLabel`, `Chooser`, `ChooserListRow`, `HairlineRow`, `SwitchRow`, `InkToggleStyle`,
`PillButton`, `Fineprint`). A group's name is 17 semibold; a small grey label (14, ink-2) sits over each full-width chooser (sunk pill, 48 high,
value left, up/down arrows right). A chooser opens the design's own list in place, over what is below it: one straight column on a raised
surface, rows 48 high, a tick on the right of the chosen one; a press elsewhere or Escape closes it. Switches are drawn in ink (48 × 28),
never marigold. Rows are divided by hairlines. Nothing in Settings is marigold: the local voice's "Download" (or "Try Again") is a quiet button.
The window ends with one line and a link, "What leaves this Mac, and what Claude Code may do. Read more", which opens the privacy page (made from the Disclosure strings, shipped in the app's resources, light and dark) in the browser, in a new window where the browser allows it. "Open the work in Claude afterwards" is the switch's wording.

## 6c. The update line

Inside the card, under the last button: 16 above a 1 px hairline, 12 below it, then one row of 24 (the card grows from 228 to 281). The
sentence is on the left in ink-2; at most one word on the right (17 semibold): marigold-word when it is the person's move (Update, Try again,
Move), ink for an offer (What’s new); a light wash of its own colour under the pointer. While updating, a 2-high progress line (ink-2 on the
hairline's colour) takes the word's place. "Move to Applications?" + Move is one line, with no "Not now". Nothing shows during a call.
`LineView` (CallViews) draws it; `updateLine` (VoiceCore) says what it says; `--snapshots` checks its place (16 under the door, 16 above the foot, 16 in).

## 7. Keys

Return starts a call when Start call shows; Escape cancels a start or closes the panel; ⌘, Settings; ⌘Q Quit.

## 8. Checks

`swift run LauncherChecks --snapshots <folder>` draws every state, light and dark, at 2x, offscreen, and the menu-bar item beside it, and
runs the design's own check on the drawing: one panel size; head, pill and door in identical places; one menu-bar item width; nothing clipped.
`--ui-test` drives the real app through its accessibility tree (README).
