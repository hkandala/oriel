# Phase 24: Fixes from the user's first hands-on use

The user ran the app (`make run`) on 2026-10-24 and listed 12 issues. The orchestrator settled the open
points below without asking; each lane records what it changed in `## Findings` at the end of this file.

The user works on this Mac and runs Oriel from the main checkout. Never launch Oriel locally, take the GUI
lock, or use `.build/DerivedData`. Build with your own `DERIVED_DATA=/tmp/oriel-dd-24<lane>`. UI tests run
on CI (`gh workflow run ci.yml --ref main -f only_testing=…`, see `plan/ci.md`); their screenshots and screen
recordings are the visual check.

Screenshots from the user: `.build/fb/12.40.27.png` (tab bar, item 6) and `.build/fb/12.33.37.png` (agents
list, item 10), in the main checkout `/Users/hkandala/code/oriel`.

## Lane A: terminal reveal and resize (items 1, 2)

1. **Empty panes.** The hide-then-fade-in used against the first-frame flicker sometimes leaves a pane
   empty until the user switches tabs and back. Find the root cause, and replace the opacity hide with a
   way that cannot get stuck: for example keep the last drawn content visible until the new frame is drawn,
   or reveal on the first frame with a guaranteed reveal on every path (tab switch, workspace switch, page
   switch, new pane, reconnect, window restore). No flicker may come back.
2. **Resize.** While a card is resized (window resize, split divider drag, sidebar toggle), the text reflows
   badly. Do not reflow on every frame: keep the grid size while the size keeps changing, show the old
   content clipped or anchored to the top left, then send the new size once it settles (live resize end, or
   about 150 ms without change) and reveal the reflowed frame with a short fade. Pick the simplest way that
   looks calm; say what you picked.

## Lane B: tab bar (items 4, 5, 6, 7)

4. **Wrong icon on a new tab.** A new tab shows a GitHub or other icon for a moment before the zsh icon.
   Find why (likely the icon is guessed from a title or folder before the program is known). Show nothing
   or the plain terminal icon until the program is known; never a guess that changes.
5. **Tab width.** Tabs keep their default width and never shrink; when they do not fit, the tab row
   scrolls horizontally inside its space.
6. **Edge fade.** Where tabs are cut off at either end of the scrolling row, fade them out with a soft
   gradient mask instead of a sharp cut. Show the fade only on a side that has hidden tabs.
7. **No scroll on click.** Clicking a tab selects it with no scroll and no snap animation. Scroll and snap
   only happen for a horizontal scroll gesture. When a tab is selected another way (keys, palette, new tab)
   and it is out of view, bring it into view without animation.

## Lane C: pane input (items 8, 9)

8. **Right click.** Right click in a terminal card does nothing now. Match herdr: check herdr 0.9.5's
   behavior and its option that sends right clicks to the program (`herdr --help`, its config docs, the
   source if needed). Default: a native context menu (Copy, Paste, Select All, then pane commands from the
   command list: split, zoom, move, close). Support herdr's pass-through the simplest way that fits; record
   the choice.
9. **Drop files and images.** Dropping files from Finder on a terminal card pastes their shell-quoted paths,
   separated by spaces, into that pane, as herdr does (check herdr's exact quoting and whether it uses a
   bracketed paste). An image dragged without a file (for example from a browser or a screenshot thumbnail)
   is saved to a temporary file and its path is pasted. Pane drags keep their drop zones; only file and
   image drops paste.

## Lane D: window chrome and lists (items 3, 10, 11, 12)

3. **Traffic lights flicker** when the user switches workspaces. Find the root cause (for example the title
   bar, toolbar or window style being rebuilt) and fix it there. They must stay still on every switch.
10. **Agents list alignment** (`.build/fb/12.33.37.png`). Decision: line 1 holds the program name, then on
    the right the status badge and the time, on one centered line. Line 2 holds the place (`mira · G4`).
    The icon centers on both lines. The header (`default · agents` and the sort control) shares one
    baseline. More space between rows. Same rule for every row style that shows an agent.
11. **Empty text.** "Nobody needs you" becomes "All caught up".
12. **Menus with the sidebar collapsed.** In the New Session menu and the workspaces menu, the highlight
    must follow the mouse; now it stays on the default item (keys and clicks work).

## Checks

- `make lint build test` green; a UI test for each item a test can see (tab width and scrolling, no
  scroll on click, context menu, file drop, empty text, menu highlight if reachable), run on CI.
- One CI run green on each lane's last push. One review round: spec and ponytail, read only.

## Findings

### Lane A (items 1, 2)

- **Root cause of empty panes (item 1), by reading and spikes, not reproduced** (no local GUI runs). The hide
  went through SwiftUI: `ready` → `TerminalCard` passed alpha 0 → `updateNSView` animated the host only when that
  host's own alpha read 0. So the content showed only when SwiftUI updated the very host that held the terminal
  after `ready` flipped, and the 1 s fallback was armed only at a stream's first frame. A host made or moved
  mid-way (SwiftUI's newest host adopts the view) could keep alpha 0; a spike showed an NSView fade that is not
  layer-backed yet stalls at 0 while the run loop tracks events. A tab switch made a new host, which set alpha
  at once: the user's fix.
- **Item 1 fix.** The terminal hides and shows its own view; SwiftUI only sets the card's dim on the host. A
  frame while not ready sets the view's alpha to 0 before libghostty gets it; `reveal` sets alpha 1 and adds a
  fade that only animates up from 0 (0.12 s), so a fade that does not run leaves the content shown. Shown once
  frames stop for 100 ms, at the latest 0.4 s after the first hiding frame or grid change (under the spinner's
  0.5 s). Watchers show at once. The empty surface gets `ESC[?25l`, so no cursor shows before herdr's first
  frame.
- **Item 2, what was picked.** `TerminalHost.Host` keeps the terminal view's frame (clipped, top left) while the
  card's size changes, and fits it 150 ms after the last change or at `viewDidEndLiveResize`; at once while the
  terminal has no grid yet, so the first stream still opens at the card's size. A grid change (libghostty calls
  `terminalDidResize` synchronously inside the frame set) hides the content in the same transaction, the new
  grid goes to herdr at once (the 100 ms settle stays only for the first grid), and the content fades in as in
  item 1. One mechanism for the first attach and every resize. Strip's `Motion` / `layoutMoving` went: the
  Host's wait covers layout motion.
- **Deviation.** The cap is 0.4 s, not 1 s: an agent that redraws all the time stayed blank for a second.
- **Learned.** herdr 0.9.5 answers every `terminal.resize`, even to the same size, with a full frame
  (`"full":true`); all other frames are diffs on herdr's last screen, wrapped in `?2026h…?2026l`.
  libghostty swaps the view's layer when it makes the surface, and the new layer ignores an alpha set earlier,
  so the view's alpha is only set from the first frame on. ⌘+ steps now resize once per step, each with its
  fade. `RevealTests` read terminal pixels (the share far from the median brightness): the one place an empty
  card shows, a deliberate exception to "not through pixels".

### Lane B (items 4, 5, 6, 7)

- **Root cause of the wrong icon (item 4), found in a spike.** Polling `pane.process_info` on a new tab every
  30 ms showed the user's shell startup run `path_helper`, `brew shellenv`, `gh auth token` (+ `security`),
  `nvm`'s `ls` and `sort` in the first 0.3 s. The store already waited 1 s before its first ask for a new pane,
  but the card asks again as it shows (`PaneCard.onAppear`), and a new tab's card shows at once: that answer was
  `gh`, so the GitHub icon showed until the 1 s ask said zsh. Fix: `Pane.starting` blocks every ask (card,
  Return, title word, agent) in a new pane's first second, then waits while a program other than the shell runs
  (every 0.5 s, 3 s at most, for a slow nvm). A new terminal under a reused pane id counts as new.
- **Decisions.** Tabs are a fixed 220 pt (D42's old maximum, the width with room to spare); the kept width
  after a close and the 52 pt rules went with the shrinking. Fades are 24 pt, only on a side with tabs out of
  view (`onScrollGeometryChange`); no rubber band while all tabs fit (`scrollBounceBehavior(.basedOnSize)`):
  the user's sharp cut was the rubber band pulling the end tab past the edge. Item 7 is about the tab row's
  own scroll: a click or a spring-load selects without scrolling (an explicit `clicked` flag; `hovered` went
  stale under a still pointer); keys, palette and a new tab scroll it into view without animation, and once
  more a moment later, as the Strip does, for a capsule that lays out in the same update. The strip's paging
  spring on a click is unchanged.
- **Deviations.** A program typed in a new tab within its first seconds gets its icon up to ~4 s after the tab
  opened (the terminal icon until then). A pane id reused inside that window can end the wait early (rare).
- **Known limit.** Dragging a tab along an overflowing row does not auto-scroll, so it cannot reach a slot out
  of view; drag it in steps, or add an edge auto-scroll if it matters.
- **Learned.** Only 3 tabs fit on CI's 1024 pt window now: tests select tabs past the row's end with ⌘n, not
  clicks (`ProgramIconTests`), and one test uses a split instead of a fourth tab (`AgentTests`). CI's shell is
  bash; the startup test writes `.zshrc`, `.bashrc` and `.bash_profile` into a throwaway `HOME` passed through
  `tab.create`'s `env`. CI: 40077507385 and 40077694680 green (the lane's tests and the tab tests).

### Lane C: right click and drops (items 8, 9)

- **Root cause, right click.** `PaneSurfaceView` sent every right click to herdr as a mouse event and to
  libghostty. herdr hands a click to the program only when it reads the mouse, and libghostty only showed its
  own Copy menu over a selection; so in a shell nothing happened. herdr 0.9.5's TUI (`client/shell/mouse.rs`)
  opens its pane menu on a right click unless the program reads the mouse and either the pane's
  `right_click = pane` flag (`pane input-set`, `pane split`) is set or the click's modifiers equal
  `right_click_passthrough_modifier` exactly (default off).
- **Decision, right click.** A right click goes up the responder chain to a SwiftUI `.contextMenu` on the
  terminal: Copy, Paste, Select All (sent to that terminal's view, not the keyboard card), then the header's
  pane commands. ⌥ alone sends the click to the program with ⌥ stripped, as herdr with the modifier set to
  `alt`. herdr's per-pane flag is not in the socket API's `PaneInfo`, so Oriel ignores it. ⌃-click stays a
  ⌃-left click for the program (not in the item).
- **Root cause, drops.** The terminal view registered for no drag types. herdr itself does nothing with
  drops: its host terminal pastes. Ghostty (macOS) pastes file URLs as `Shell.escape` paths (a backslash
  before space and `\()[]{}<>"'`!#$&;|*?` and tab), joined by spaces, through `pasteText`: a bracketed
  paste. Oriel does the same with libghostty's `paste(text:)`, which herdr frames again for the program.
- **Decision, drops.** Order: file URLs, then image data (saved as `image.png` in a new `$TMPDIR/oriel-*`
  folder), then a file promise (browsers may give only that), received into such a folder. Web URLs and text
  are not taken. Only `.fileURL`, `.tiff`, `.png` and the promise types are registered, so a pane drag
  (`orielDrag`) goes on to the card's drop zones. ponytail: only the first promise is received, each of its
  files pasted on its own; paths are This Mac's (no remote machines yet).
- **Learned.** On macOS, `XCUICoordinate.press(forDuration:thenDragTo:)` moves nothing (it is the touch API);
  `click(forDuration:thenDragTo:)` drags. A drag from Finder works in a UI test: the e2e helper makes the
  file and `open -R`s it; Finder's window opens at 920 × 436 pt at the top on CI, so the drop goes on the
  terminal below it.
- **For the user to check by hand:** dragging an image from Safari, from Chrome and from a screenshot
  thumbnail (no CI test drives those); a ⌥-right click in a mouse app (lazygit, vim with `mouse=a`).

### Lane D: window chrome and lists (items 3, 10, 11, 12)

- **Root cause, traffic lights.** Every window title change (each tab or workspace switch: `navigationTitle` is
  "‹tab› - ‹session›") makes AppKit re-tile the title bar (`NSThemeFrame _titleDidChange` →
  `_tileTitlebarAndRedisplay:` → `_updateButtonPositions`), which moves the three buttons back to the compact
  toolbar's place, twice per change. `WindowReader` put each back from its frame notification, but AppKit's
  `_NSThemeWidget setFrameOrigin:ignoreRentry:` drops a move of the button it is moving, so the last one, the zoom
  button, waited for the next main-queue turn; a frame drawn before that showed it 4 pt up and left (CI's
  recording: 1 to 4 frames at launch and on switches). Fixed where the layout happens: a frame notification only
  marks `WindowReader`'s view for layout, and its `layout()` places the buttons, after AppKit's tiling and before
  the frame is drawn.
- **Root cause, agent rows and header.** The status capsule sat on line 1 and the age on line 2, so neither line
  lined up; the header centered a 12 pt name against an 11 pt menu label. Line 1 is now name, capsule and age;
  line 2 the place; rows 48 pt with 4 pt gaps (Agents view and the needs-you panel, the two row styles that show
  an agent; the hover card's rows are one line already). The header uses `firstTextBaseline` in the Agents view
  (the workspaces header's `+` has no text and stays centered).
- **Root cause, menu highlight.** `FilterList` lit only `index` (keys, start row); the pointer gave just the
  hover tint. A real pointer move over a row now lights it (`onContinuousHover`, compared with
  `NSEvent.mouseLocation`, so a row scrolled under a still pointer or the row under the pointer as the panel opens
  does not take the light). The palette shares `FilterList`, so it follows the pointer too.
- **Decision, palette.** The pointer lights palette rows too, so resting 0.75 s on an Appearance or Interface
  Style row previews it, as the arrows do; passing over does not. A row lit by the pointer is not scrolled to.
- **Deviations.** Item 3's fix is in `WindowReader.swift` and item 12's in `FilterList.swift` (not the lane's
  files; no other lane touched them); `OrielApp.swift` got the e2e test value.
- **Tests.** `testTrafficLightsStayStillWhenWorkspacesSwitch` (`-recordLights YES` counts run-loop turns that
  end, after Core Animation's commit at `beforeWaiting` or a loop's `exit`, with a light off its place; it counted
  3 on the old code, 0 with the fix; the test checks that switches add none, since launch drew one such turn in 1
  of 4 CI runs), `testMenuLightFollowsThePointer`, the "All caught up" check in
  `testBlockedAgentNeedsYouAndThePopoverGoesToIt`; the agent rows are checked by the agents tests' screenshots.
- **Learned.** A one-frame glitch shows in the xcresult's 60 fps screen recording: crop the region with ffmpeg
  and diff frames. Only the exit-of-loop observer caught the commit that drew it; `beforeWaiting` alone saw 0.
- **Open, not this lane's.** `testTrafficLightsSitInTheTitleRow` fails on main: the first ⌥-click zoom gives a
  frame wider than CI's screen (the zoom button lands at x = −27). It fails the same with this lane's fix reverted
  (db6b2ce, run 40078529794) and passed before phase 24 (39911397369). Suspect: lane A's held terminal frame
  (`TerminalHost.Host` keeps the old size for 150 ms) feeding SwiftUI's ideal size, which the zoom uses.
