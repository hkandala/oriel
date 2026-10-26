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
- **Zoom test.** `testTrafficLightsSitInTheTitleRow` failed when it ran alone or early in a shard: the window
  asked for its 1200 × 760 default on CI's 1024 pt screen; AppKit shrank it to fit, and a ⌥-click zoom gave the
  1200 pt frame back, at x = −88 with the zoom button off screen (frames read in run 40081403841). Later in a shard
  an earlier test's saved frame hid it; lane A was not the cause. Fix: the default size is at most the screen
  (`defaultWindowPlacement`) and a zoom fills the screen (`windowIdealSize(.maximum)`; alone it did not help).
  The test checks the window stays on screen and lets each zoom settle.
- **Menu test.** In a full shard other tests' sessions push Open Session's last rows below its 320 pt fold, where a
  hover lands outside the list: the test hovers a Running row near the top. Full suite green on 2f55b6b (run
  40083116381).

## Round 2 (user, 2026-10-24 10:25, after trying the build)

Screenshots in the main checkout: `.build/fb/agents.png` (item 13), `.build/fb/needs.png` (item 15).

### Lane E: tabs (items 14, 16, 17, 18)

14. **No slide on click.** The user still sees a horizontal scroll animation when a tab is clicked, when
    the + button is clicked and on ⌘T. Rule: switching tabs any way other than a horizontal scroll gesture
    (click, +, ⌘T, ⌘1–9, ⇧⌘[ ], palette, closing a tab) changes the shown tab at once, with no animation,
    in both the tab row and the strip of cards. Only a trackpad or mouse horizontal scroll animates and
    snaps. Lane B fixed only the tab row; the strip's paging spring on a click is likely what the user sees.
16. **Closing a tab** selects the tab used before it (most recent first) if it still exists, else the tab
    to its left (the right one when it was first). Now it goes to the first tab.
17. **Drag auto-scroll.** While a tab is dragged in an overflowing tab row, holding it near either end
    scrolls the row further (lane B's known limit 1).
18. **Close Tabs to the Right** next to Close Other Tabs (tab context menu and the command list).

### Lane F: resize without a blank (item 19)

19. After a resize settles, the text fades out and back in, which reads as a flicker. Keep showing the old
    content until the reflowed frame is drawn, then switch to it (at once or with a short crossfade from
    the old picture). The text must never go blank on a resize. Check the same holds for ⌘+ and ⌘−.

### Lane G: agents list (items 13, 15)

13. **Agents view alignment** (`.build/fb/agents.png`): the header text (`default · agents`) starts further
    right than the section label (`Idle 10`) and the row icons. One leading edge for the header, the section
    labels and the rows; the sort control's right edge lines up with the rows' right edge (the times).
15. **Needs-you panel when empty** (`.build/fb/needs.png`): show only "All caught up", without the
    "Needs you · default" header.

## Findings, round 2

### Lane G (items 13, 15)

- **Root cause, item 13.** The header had its own insets (leading 22, trailing 3) from the workspaces view, while
  the Agents view's group labels and row icons sit at `Sidebar.rowInsets.leading` (10) + 8 = 18 and the rows'
  times end 3 + 8 = 11 pt from the edge; the sort label's text, inside its 6 pt button padding, ended at 9. So the
  name started 4 pt right of the labels and the sort text 2 pt past the times (the user's screenshot, at 2x: 8 px
  and 4 px). In the Agents view the header now pads 18 leading and 5 trailing; the workspaces view keeps 22 / 3.
- **Root cause, item 15.** `NeedsYouPanel` drew its "Needs you · ‹session›" header above both branches; it is
  now only in the branch with rows (`agents.popover.header`).
- **Tests.** `testAgentsViewListsEveryAgentByPriorityOrWorkspaceOrder` checks the header's text, a group label
  and a row icon share minX, and the sort text's end meets the times' end (a padded `Text`'s accessibility frame
  hugs the text, CI showed). `testBlockedAgentNeedsYouAndThePopoverGoesToIt` checks the header is gone when
  empty and shown with a row. CI 40116374403 green; the screenshot shows one edge.
- **Docs.** `window.mdx` say the empty panel has no header and the header's edges.

### Lane F (item 19)

- **Root cause.** Lane A hid each grid change by setting the terminal view's alpha to 0 until herdr's frames
  settled, then faded it in: the text went blank for about 0.25 s and came back (CI 40116832208 on the new test
  over the old code: 2 of 10 screenshots with no ink after the sidebar hid).
- **Fix.** No alpha hide: `PaneTerminal` pauses libghostty's drawing (`setSurfaceVisible(false)`: ghostty's
  occlusion plus libghostty-spm's display link) while it settles, so the view's IOSurface layer keeps its last
  picture, anchored top left (`kCAGravityTopLeft` in libghostty), and `reveal` switches to the new picture at once.
  The same 100 ms settle and 0.4 s cap as lane A, so every path still reveals; only a new card's first reveal still
  fades in (0.12 s) from its clear, empty surface. Picked over a crossfade: a copy of the old picture would be
  needed, as ghostty reuses its swap chain's surfaces.
- **Pause before libghostty hears of a change.** With the pause in `terminalDidResize` alone, CI's recording
  showed 3 frames of garbled glyphs after a ⌘- (ghostty's renderer thread drew the old cells with the new font
  before the occlusion reached it). `hold()` now runs first: the Host before it sets the new frame, `setFontSize`
  for every streaming terminal before the config; both go through ghostty's one renderer mailbox in order.
  libghostty's grid change still calls it for other paths (a scale change). A pixel-only size change holds 100 ms
  and shows the same picture.
- **Test.** `testResizeNeverBlanksTheText`: screenshots as fast as they come (about 10 in 1.5 s on CI) through a
  sidebar hide and show, ⌘+ and ⌘-; each must have ink, and each step ends with herdr's text drawn (not stuck).
  Red on the old code (40116832208), green on the fix with the reveal and font tests (40116872510, 40117447765).
  The recordings, frame by frame (crops of every frame around each step): old text at the top left, then the new
  grid, no blank and no garbled frame after 7b85ce7.
- **Known limit.** A watcher does not hold (it cannot resize, so it shows the reflow, as before); on ⌘± it can
  still show the garbled frames. bash's own redraw of a wrapped prompt after `SIGWINCH` leaves a stray piece of
  the prompt on its line (CI's right-hand cards); that is herdr's screen, not the card.

### Lane E (items 14, 16, 17, 18)

- **Root cause, item 14.** `Strip`'s selection change scrolled with `withAnimation(.tab)` whenever the workspace
  stayed the same, so every click, +, ⌘T, ⌘1–9, ⇧⌘[ ], palette pick and close slid the strip, and the tab marker
  (it reads the strip's offset) slid with it. Lane B had made only the tab row's own scroll instant. Now every
  selection change scrolls the strip without animation, and once more a turn later for a page that lays out in
  the same update (a new tab, another workspace). The mouse wheel's page turn (`SwipeRouter` → `Strip.turn`)
  keeps the spring: it scrolls before the selection's change runs, so that change has nothing to do. Trackpad
  swipes are unchanged.
- **Root cause, item 16.** `Page.settle` fell back to herdr's active tab, else the first tab, for any gone
  selection; herdr's active tab is the first in most workspaces made with `focus:false`. `Page` now keeps each
  workspace's used tabs (a `didSet` on `selectedTabIDs`, pruned to live tabs each snapshot) and the last
  snapshot's tab order: a closed selected tab gives way to the latest used tab still open, else the one on its
  left, else the new first. A saved selection gone at relaunch (no known order yet) still goes to herdr's active
  tab (spec review).
- **Item 17, found on CI: the row's `ScrollView` already scrolls on its own while a drop is held near an end**
  (its drop autoscroll; lane B's "known limit" was not measured). A step-a-tab-every-0.3-s scroll on top of it
  fought it: animated, the row crawled and jumped back; without animation, the steps never showed (CI
  recordings of 40116980056 and 40117528541, about 60 pt/s at 15 pt from the end). The steps went; the native
  scroll stays. ponytail: its speed is the system's; a faster one needs our own scroll that pauses the native one.
- **Item 18.** Close Tabs to the Right in the capsule's menu, after Close Other Tabs, and Close Other Tabs and
  Close Tabs to the Right in the command list (File menu and palette), for the selected tab. They share
  `Page.closeTabs(besides:right:)` and `.otherTabs(_, right:)`, whose dialog says "Close the 2 tabs to the right?".
  The new File menu items made `app.menuItems["Close Other Tabs"]` ambiguous in a test; tests pick the capsule's
  menu through the window.
- **Tests** (`TabTests.swift`). `testSwitchingTabsShowsTheirPageAtOnce`: `-recordStrip YES` counts strip scroll
  updates between two pages; a click, ⌘2, ⇧⌘], the palette, + then ⌥⌘W, and ⌘T then a herdr close add none, and
  a swipe at the end does (the counter sees slides). The recording, frame-diffed over the strip: each of those
  switches is a one-frame change; the swipe spans many. `testClosingTheSelectedTabGoesToTheOneUsedBefore`,
  `testCloseTabsToTheRightKeepsTheTabsOnTheLeft` (menu and palette), `testHoldingADraggedTabAtTheRowsEndScrollsTheRow`
  (held 6 s 5 pt inside the end, the tab lands past the fourth; without a scroll it lands third).
