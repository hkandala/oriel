# Phase 25: The user's second round of feedback

The user tried phase 24 (it "works flawlessly") and sent this list on 2026-10-25. The orchestrator settled
the open points; each lane records its notes in `## Findings` at the end.

Same setup as phase 24: the user works on this Mac. Never launch Oriel, run XCUITest locally or take
`/tmp/oriel-gui.lock`. UI tests run on CI; their screenshots and recordings are the visual check (look at
animations frame by frame). Screenshot from the user: `.build/fb/glass.png` in the main checkout.

Wave 1 runs lanes H–L in parallel. Wave 2 (lanes S, A2, F2) starts when wave 1 is in.

## Wave 1

### Lane H: looks (items 1, 10, 11)

1. **Glass: less contrast between the keyboard card and the others** (`.build/fb/glass.png`: the right card
   is much darker and flatter than the left one). Find what makes the difference in the glass look (material,
   tint, dim, border, shadow) and bring the other cards close to the keyboard card: the keyboard card may stay
   a little brighter or carry the accent border, nothing more. Check it over a light and a dark wallpaper
   (CI screenshots). Classic stays as it is.
10. **Remove Fade Inactive Panes** altogether: the setting, the command, the code behind it and the docs.
11. **Font size wording:** "Bigger", "Smaller", "Actual Size" become "Increase Font Size", "Decrease Font
    Size", "Reset Font Size" (Ghostty's words), in the menu bar and the palette.

### Lane I: keys (items 2, 7)

2. **⌘-held tab shortcuts** sit on top of the program icon. Show the shortcut (⌘1…) at the capsule's
   trailing end, beside where the × shows on hover, never over the icon or the title; the title truncates
   first.
7. **Keys.** Keep every key that exists and add these, so each level uses the same pattern (`[` `]` steps,
   numbers jump, the modifier names the level):

   | Level | New | Previous / next | Jump to 1–9 |
   |---|---|---|---|
   | Pane | ⌘D, ⇧⌘D (exists) | ⌘[ ⌘] (exists) | — |
   | Tab | ⌘T (exists) | ⇧⌘[ ⇧⌘], ⌃⇥ ⌃⇧⇥ (exist) | ⌘1–9 (exists) |
   | Workspace | ⌃⌘T (new) | ⌃⌘[ ⌃⌘] (new) | ⌃⌘1–9 (new) |
   | Session | ⇧⌘N Open Session (exists) | ⌥⌘[ ⌥⌘] (new) | ⌥⌘1–9 (new) |

   **Keyboard Shortcuts panel on ⌘/** (Help menu and palette too): a floating panel over the window that
   lists every shortcut from the command list, grouped by section (Panes, Tabs, Workspaces, Sessions, View,
   Edit), two columns, glass like the palette, Esc or ⌘/ closes it. Built from the command list so it never
   goes stale. This is a new panel: send the orchestrator one rough CI screenshot before polishing.

### Lane J: agents sidebar (item 4)

4. In the sidebar's Agents view:
   - Workspace order groups agents under a workspace header (the workspace name, styled like the priority
     group labels), and the rows drop the workspace from their second line. Priority order keeps its groups.
   - A row's title is the pane's name when it has one, else the agent's name (pi, claude…).
   - The header shows only the session name (no "· agents") and the sort control, with a thin separator
     line under it, across the sidebar, so the header reads apart from the list.
   - The agent in the keyboard card of the shown tab is highlighted like the selected workspace row.

### Lane K: sessions and closing (items 5, 6, 8, 9)

5. **No confirmation when nothing runs.** Closing a pane asks only when a program other than the shell runs
   in it (`pane.process_info`). Closing a tab, other tabs, tabs to the right or a workspace asks only when
   one of its panes runs such a program. The dialog names what runs.
6. **Reset pane name:** after a rename, the pane's menus and the palette offer "Reset Pane Name", which
   clears herdr's label so the pane shows its program again.
8. **Sessions, not pages.** A session opened or created goes to the last place in the window's sessions,
   not beside the current one. The UI never says "page": "Close Page" becomes "Detach Session" (the session
   keeps running), "Previous/Next Page" become "Previous/Next Session". Code names may stay.
9. **Open Session panel:** a running session gets a Stop button; a stopped session gets a Delete button
   (asks first). Find herdr 0.9.5's commands for both (`herdr --help`, `herdr server --help`). Tests use
   only throwaway `oriel-e2e-*` sessions; never stop or delete a session the user owns.

### Lane L: pi extension keys (item 15)

15. The user's pi extensions register keys that do not reach pi inside Oriel, while pi's default keys work.
    They are all ⌃⇧ keys: ctrl+shift+s, ctrl+shift+b, ctrl+shift+enter, ctrl+shift+t, ctrl+shift+o,
    ctrl+shift+w (`/Users/hkandala/code/pi-hkandala/extensions/*/index.ts`). Likely cause to check first: pi
    turns on the kitty keyboard protocol, and the keys Oriel sends do not carry the shift (legacy encoding,
    or a menu shortcut that eats them). Compare with herdr in Ghostty, where they work. Fix the root cause so
    every key the program asks for arrives as the program expects, and keep Oriel's own shortcuts working.

## Wave 2

### Lane S: snappy (items 13, 14)

13. **New tab title:** a new tab shows its herdr number for a moment. Show "New Tab" until the program is
    known, never a number.
14. **Snappy.** ⌘T, ⌘W and ⌘K must react at once. Measure first (from the key to the first drawn change)
    on every main interaction: new tab, close pane and tab, palette, split, switching tabs, workspaces and
    sessions, the Open Session panel. Show the change at once and let herdr catch up (an optimistic tab or
    pane that the next snapshot confirms or removes), or remove the wait, whichever is simpler. The palette
    opens in the same frame as the key. The swipe between sessions is too slow: make its animation clearly
    quicker (about half), keeping the snap.
    Also from lane K: ⌘T then an immediate close can ask about the shell's startup programs (ls, sort, zsh);
    closing a big workspace starts one herdr process per pane to read process_info; ⌥⌘W pressed twice quickly
    starts two asks.

### Lane A2: pane animations (item 3)

3. Split, close and zoom animate (short, about 0.2 s, ease out): a split slides the new card in from its
   side as the others make room; a close shrinks the card away as the others grow; zoom grows the card to
   the full tab and back. The terminal text keeps phase 24's no-blank rule during these (hold the old
   picture, reveal once at the end). Reduce Motion turns them off.
   The user (2026-10-25): the new card's fade-in on a split is there, but the other cards do not animate
   their size change; they jump. So the frame animation in Strip (`.animation(…, value: tree)`) does not reach
   the screen, likely because the terminal host keeps its grid and the card frames change outside it. Fix that
   first.

### Lane F2: floating panes (item 16)

Check first whether herdr 0.9.5 has floating panes in its API (`herdr api schema --json`; the orchestrator
found none). If herdr has none, floating is Oriel's own.

- **Float a pane:** a new button in the card header (and the pane menus, palette) floats the pane into its
  own small window: traffic lights, then "session › workspace › tab" in small text, then on the right Close
  (closes the pane) and, rightmost, Detach (the user's word: closes the floating window and puts the pane
  back in its tab; nothing stops). Below: the glass card with the terminal only, no header
  buttons. The window has no tab bar and no sidebar; it can be moved and resized anywhere, and several can
  be open.
- **Stay on top:** a pin button in the floating window's header keeps it above other apps, like picture in
  picture.
- **In the tab,** the floated pane's card shows no terminal: a quiet placeholder with the pane's icon and
  name and a "Show" button that brings its floating window forward. Splits keep its place.
- **⌘K** in a floating window lists only commands that apply to it (detach, close, pin, font size, find,
  copy, paste).
- **Persistence:** floating panes are Oriel's state, saved and restored with the windows; a floated pane that
  herdr closed closes its window.
- A herdr-native floating pane, if herdr has one, opens the same window.
- New window: send the orchestrator one rough CI screenshot before polishing.

## Findings

### Lane L (item 15)

- **Root cause.** `PaneSurfaceView.herdrKey` dropped Shift from Ctrl chords on letters, digits and symbols
  (phase 4: "as xterm does"), so ⌃⇧S went to `pane.send_keys` as `ctrl+s` and pi read CSI 115;5u, plain ⌃S.
  Nothing else eats ⌃⇧ letters: no menu item, monitor or SwiftUI shortcut binds one, and libghostty's
  `performKeyEquivalent` hands ⌃↩ to `keyDown`. ⌃⇧↩ already went as `ctrl+shift+enter` (CSI 13;6u). Fix: the
  chord keeps `shift+` (d7eb8f7); herdr encodes it per program, as its own TUI does for Ghostty's keys.
- **Test.** `testControlShiftKeysReachAKittyProgram`: `printf '\033[>1u'; cat -v`, types ⌃⇧S B T O W ↩ and
  ⌃S, reads the tty's echo `^[[115;6u…^[[13;6u^[[115;5u` (the old code gave ;5u for the letters). CI
  40171964049 green.
- **Drop test (lane C's, asked by the orchestrator).** `testDroppingAFileFromFinderPastesItsPath` failed in full
  runs only (40172264488, 40173000382): the recordings show Finder starting no drag from the press (no drag image
  follows the pointer, even over Finder's window), so nothing drops; the geometry was the same as in a green run.
  The test drags again, up to 3 times (1567204). Full suite green on it (40174324533), where shard 3 needed the
  second drag.

### Lane J (item 4)

- **Root causes.** Workspace order was a flat list: `AgentsList` grouped only by priority, and each row's line 2
  always came from `Page.place` ("‹workspace› · ‹tab›"). The row title read `pane.agentName` only, never herdr's
  pane label. The header was an HStack of the name plus `" · agents"`, with no line under it. `AgentButton`
  used `ChromeStyle(radius:)` with no `selected`, so no row was ever lit.
- **Decisions.** Workspace groups reuse the priority labels' view (`label(_:id:)`, `agents.workspace.<id>`) in
  `store.workspaces` order; line 2 is the tab's title there (`AgentButton.place`), "‹workspace› · ‹tab›" in
  priority order and the needs-you popover. Title: `pane.label ?? agentName ?? "agent"`, the card header's
  order; the filter matches the pane name too (spec review). Lit: `page.keyboardCard(selectedTab)`, the same
  source as the lit card (follows a zoom and a focused text field); also in the needs-you popover, whose rows
  are the Agents view's. The separator is a `Divider()` across the page, in the Agents view only (the item's
  scope); the workspaces header keeps its look.

### Lane H (items 1, 10, 11)

- **Root cause, item 1.** Two things set the keyboard card apart in Glass. (a) The fade: the other cards drew
  their header and terminal at 0.7 (0.5 in a window that is not key). (b) The fills: the other cards took Rex's
  pane backdrop (black 0.14), a step *darker* than the window, and the keyboard card added white 0.05 (2/3 in
  light). The user's screenshot reads window 24, keyboard card 29, other card 18; CI on the old code 23 / 32 / 20
  (a gap of 12, 40172012490). Fix: no fade (item 10); Glass cards are white 0.03 (0.6 light), a step brighter
  than the window, and the keyboard card adds only white 0.02 (0.25 light, so it still ends at 0.7); Glass
  edges are the same on every card. Classic is unchanged. CI now: dark 35 / 30, light 253 / 252.
- **Item 10.** The setting, its `@AppStorage` key, the command, the opacity math and its test are gone; D64 now
  says no card fades. Only the watching window's 0.85 dim (D66) is left, so the card's value is "content 100%"
  or "content 85%".
- **Item 11.** Increase, Decrease and Reset Font Size, with the old words as palette keywords. Then "font size"
  in the palette tied Font Size › with Increase Font Size, and Return increased the size (spec review): a tie now
  goes to a title that starts with the filter (`Palette.rootItems`, a shared file; the docs say so).
- **Deviation.** No CI check over a light and a dark wallpaper: CI's VM draws the glass backdrop opaque. A test
  runner window under Oriel, in black, white and blue, changed no pixel of the window (frames of 40172258178).
  The keyboard card's lead is about the keyboard fill × (255 − card): dark about 4 to 5 over any desktop, light
  about 7 at most (light tint 0.7 and card 0.6 keep the card above about 225).
- **Test.** `testCardsLookAlikeWithAndWithoutTheKeyboard` (AppearanceTests): no Fade item in View; in Glass dark
  and light the keyboard card's median brightness leads the other's by 0 to 6 (red on the old fills, green on
  the new: 40172905682). `testSecondShortcuts` reads the three palette rows and opens Font Size › with Return.

### Lane I (items 2, 7)

- **Root cause, item 2.** The keycap was an `.overlay(alignment: .leading)` on the `IconStack`, so it was drawn
  over the front icon. It now sits at the capsule's end: in the status slot (where the working dots sit, which
  hide while it shows), or left of the × while hovered. A hidden copy in the label's `HStack` keeps its room, so
  the title fades out before it; the visible copy is an overlay on the button, so a test can read its frame
  (`tab.<id>.keycap`). It hides while the tab is renamed.
- **Root cause, item 7.** The new keys did not exist: workspaces had no steps or jumps, the session steps had no
  key, and New Workspace had none. Added to the one command list (menu bar, palette): ⌃⌘T, ⌃⌘[ ⌃⌘] (round the
  ends, as tabs), ⌃⌘1–9, ⌥⌘[ ⌥⌘] (stop at the ends, as the swipe), ⌥⌘1–9. Workspace order is the sidebar's
  (`Page.sidebarWorkspaces`: each workspace, its worktrees after it). Keyboard Shortcuts (⌘/, Help menu and
  palette) is a floating panel like the palette (`Shortcuts.swift`), built from `CommandList.all` on every draw.
- **Decisions.** A command's panel group comes from its menu section (`Section.group`); the mixed File-menu ones
  name theirs (`Command.group`). Go to Directory is under Edit, next to Insert Path. A set of commands that differ
  only by the key (the arrows, the 1–9 jumps) carries a `family` (title, keys) and shows as one row; a second key
  (⇧⌘P, ⌃⇥, ⌘=) shows on its first's row. Fixed split: Panes, Tabs, Workspaces | Sessions, View, Edit (about 22
  and 18 rows); a window too short for it scrolls the panel (`ViewThatFits`). The panel takes the keyboard
  (`focusable`), so Esc reaches it; closing gives the keyboard back to the card. Help's "Oriel Help" item went
  (`CommandGroup(replacing: .help)`). Copy, Paste and Select All are AppKit's, not in the list, so not shown.
- **Tests.** `testHoldingCommandShowsKeycaps` (keycap right beside the ×; it was over the icon),
  `testWorkspaceAndSessionKeysStepAndJump`, `testKeyboardShortcutsPanelListsTheCommandsKeys` (groups, two
  columns, family and second-key rows, Esc, ⌘/, Help menu, palette, click outside, a light classic screenshot).
  CI 40172090772 and 40172488406 (test fixes), 40172892960 green. Full suite on 9a2654d (40173113791): lane I's
  tests green; 4 reds in lanes K and C's areas (Open Session's Stop button shares the row's identifier, the long
  dialog text as a query, the Finder drag), fixed by them in 7c74def, ee3114e, 1567204. Full suite green on 1567204, which
  carries lane I's last code commit (40174324533).

### Lane K (items 5, 6, 8, 9)

- **Root cause, item 5.** A pane close already asked only when `pane.process_info` showed more than the shell,
  but every tab, other-tabs, tabs-to-the-right and workspace close set `page.closing` straight away (D41 said
  "always asks"). Now every close goes through `Page.close(_:)` → `HostStore.ask`. It reads `process_info` of each
  pane at once, closes at once when only shells run, and else asks, naming what runs ("sleep is running in it.
  Its 2 panes and…"). A failed read counts as "A program".
- **Root cause, item 6.** Nothing cleared herdr's label except an empty Rename. Reset Pane Name is one command in
  `CommandList.pane`, so the header menu, the right-click menu, View ▸ Pane and the palette all get it. It is
  enabled only while the pane has a label, and it sends `pane.rename` with `label: null`.
- **Root cause, item 8.** `WindowPages.open` put a new page after the current one; it now appends. The UI strings
  were "Close Page" and "Previous/Next Page"; they are now Detach Session and Previous/Next Session. Code names
  stay.
- **Item 9.** herdr 0.9.5 has `herdr --session S session stop|delete S --json`. stop is synchronous. delete
  refuses a running session with `session_delete_failed`. Errors come as JSON on stderr. A delete of a missing
  session succeeds.
- **Decisions.** Stop asks too, as Delete does (spec review: it ends every program, which is D41's reason to ask).
  The message says the workspaces stay: a spike showed the layout comes back on the next start. The Stop and
  Delete buttons show only on the lit row, since the pointer lights rows. FilterList now keeps the lit row by id,
  not by position. Otherwise, after Stop the light and the Stop button slid onto the next session.
- **Deviations.** The close dialog is built in `OrielApp.swift`, `FilterList.swift` got `Item.button`, and
  `Style.swift` got `RowButtonStyle` (the lint keeps `.white` there). The session tests moved to
  `SessionTests.swift`, because `SidebarTests` hit 400 lines. e2e.sh makes a seventh session for the Stop and
  Delete test.
- **Known limits.** ⌘T and then an immediate close can still ask "ls, sort and zsh are running" while a slow
  shell starts. A big workspace starts one `remote-api-bridge` per pane when it closes (for lane S). A double ⌥⌘W
  starts two asks.
- **Tests.** `testClosingATabAsksOnlyWhileAProgramRuns`, `testCloseTabsToTheRightKeepsTheTabsOnTheLeft`,
  `testCloseOtherTabsAsksOnceAndLeavesOneTab` and `testHeaderPlusAndRowMenuChangeHerdr` (Close Workspace): each
  asks with the program's name, or closes at once. `testContextMenuSplitsLeftRenamesAndMovesToNewTab` (menu) and
  `testPaletteRenamesTheWorkspaceAndThePane` (palette) reset the name. `testOpenedSessionsGoLast`.
  `testOpenSessionStopsAndDeletesASession`. One HerdrKit integration test for stop and delete, including herdr's
  refusal. CI: 40172562917 (red: the overlay's ids and the 128-character query), then 40173230145 (green, the
  lane's 15 tests).

### Lane P (items 18, 19, 20, 26)

- **Root causes.** 18: the session name was 12 pt semibold *secondary* and the group labels 11 pt medium secondary
  with 6 pt above, so the two read as one level; lane J's `Divider()` stood in for the hierarchy. 19: `OpenSession`'s
  open rows had no `button`, and `RowButtonStyle` drew every button white 0.2. 20: `NeedsYouPanel` drew "All caught
  up" and `hoverPanel` opened whatever the panel held; an empty panel also kept its Esc monitor. 26: every floating
  panel was `.glassEffect(.regular)` alone; Liquid Glass is thin on a small panel (it thickens with size, so the
  palette read fine), and the hover card showed the terminal's text clearly.
- **Decisions.** The title is 13 pt semibold primary in both views (one `Text`); group labels 10 pt semibold
  secondary with 12 pt above. `hoverPanel(enabled:)`: no open while false, and it closes at once when it turns
  false; it never opens under a still pointer (spec review: that would take the terminal's next Esc). Detach is
  on every open row of the window, not its last page (the guard of `WindowPages.close`); after it the light goes to
  the first row (FilterList keeps the light by id, and the row's id changes). Red is `look.error`, through a
  `FilterList.Item.buttonRole` (a 3-tuple trips `large_tuple`). `floatingGlass(in:)` (Style.swift) puts
  `.regularMaterial` under the glass of every floating panel: hover card, Agents popover, palette, Open Session,
  workspace menu, shortcuts, find bar, notices.
- **Deviation.** No CI check that fails on the old glass: CI's VM draws Liquid Glass with no backdrop, so the old
  hover card hid the terminal there too (40174324533). `testHoverCardBlursTheTextBehindIt` keeps a screenshot per
  look and guards only against a see-through panel (card 0.27 vs bare 52 steps per pixel).
- **Tests.** `testAgentsViewListsEveryAgentByPriorityOrWorkspaceOrder` (room above a group: old 10 pt, now 16),
  `testBlockedAgentNeedsYouAndThePopoverGoesToIt` (no panel when empty; it goes when answered, and does not come
  back under the still pointer), `testOpenSessionDetachesAnOpenSession`, `testOpenSessionStopsAndDeletesASession`
  (Stop red by pixels), `testHoverCardBlursTheTextBehindIt`. CI 40178592579 green. Full suite 40179423684 on bc8b3cc: every
  lane P test green; 5 reds outside lane P (lane I2's key moves: the latency test's ⇧⌘N, the shortcuts panel, ⌃⌘S
  in the windows test; lane K/S's tab close; the relaunch restore).

### Lane I2 (items 17, 21, 22, 23, 24, 31)

- **Root cause, item 22.** SwiftUI's `Commands` bodies do not observe `@Observable` state (a probe app: a menu item read
  from an observed model kept its first state), so the menu bar changes only when the window's focused `CommandList`
  changes. After a split nothing in that struct changed (same `pages`, same bindings), so Zoom Pane kept the
  `enabled: false` it got while the tab had one card; AppKit matched ⇧⌘↩ to the disabled item and nothing ran
  (libghostty and the key monitors do not take ⇧⌘↩). Fix: `menuBar(_:)`, a modifier that stores what the menu shows
  (`Command.shown`: title, enabled, checked, key) plus the window, page, floating pane and keyboard card in the focused
  value; `CommandList` is `Equatable` on that. Other stale states it fixes: ⌘[ ⌘] or ⌘D disabled from a menu built
  before the store went live, Show Next Tab after the first ⌘T.
- **Item 21.** ⌘[ ⌘] already stepped in tree order (`stepCard`); the keyboard simply stayed on the old card after a
  split. `HostStore.split` returns herdr's new pane and `Page.split` gives it the keyboard through `follow(select:
  false)`, as a move does, once a snapshot shows it. Every split path (header, menus, palette, ⌘D, ⇧⌘D) goes there.
- **Item 23.** The table as written; Close Window and Resize Pane have no key, ⇧⌘W in a floating window stays Detach
  Pane (it closes the window, as F2 chose). Orchestrator's addition: holding ⌃⌘ 0.7 s shows ⌃⌘1–9 keycaps at the end of
  the first nine workspace rows (`sidebarWorkspaces` order, as the jumps); the hold logic is one `keycapHints`
  modifier with the tabs' (`Keycap.swift`). ⌃⇥ / ⌃⇧⇥ stay second keys and show on the panel.
- **Item 17.** `KeyboardShortcut.caps` (one glyph per modifier, then the key); a family's `keys` is now only the key
  cap ("←→↑↓", "1–9"). Rows 30 pt, columns 380 pt and 48 pt apart, 24/28 pt padding; a small window scrolls it.
- **Item 24.** `TabButton` drops `!selected` from the dots; D42 updated.
- **Item 31.** Move Pane to Tab listed only the workspace's other tabs (`CommandList.pane`). Now New Tab, New
  Workspace, then each workspace of `sidebarWorkspaces` with its tabs but the pane's own; `Command.heading` makes a
  SwiftUI `Section` per workspace in the menus (headers and separators, AppKit hides the doubled ones) and a section
  header on the palette's sub-page (`FilterList.Item.section`).
- **Decisions.** `follow` without `select`: a split never pulls the page back to its tab. The menu identity strings
  came from the spec review: an equal value keeps SwiftUI's old one and its closures, so two floating windows of one
  session read the same and ⇧⌘W detached the first window's pane.
- **Deviation.** The shortcuts panel scrolls only vertically: a scroll view on both axes filled the whole window. A
  window under about 870 pt wide clips its sides (ponytail note).
- **Tests.** `testSplitsGiveTheNewPaneTheKeyboardAndKeysFollowTheTree` (⌘D and the header button, ⌘[ ⌘] in tree order
  that differs from creation order, ⇧⌘↩ after a split), `testHoldingControlCommandShowsWorkspaceKeycaps`,
  `testEachFloatingWindowsKeysActOnItsOwnPane`, KeyTests' new close keys and panel rows (moved keys' old rows gone),
  AgentTests' dots on the selected tab; the key tests that used ⇧⌘N, ⌥⌘W, ⌃⌘I, ⌃⌘→ moved.

### Lane F2 (item 16)

- **herdr.** 0.9.5 has no floating pane: its popup is not a pane, has no id in the API and is not in the snapshot
  (`herdr api schema --json`). So floating is Oriel's own (D50, rewritten): the pane stays in its herdr tab and keeps
  its place in the splits, and Oriel shows its terminal in a window of its own. No herdr call; the item's "herdr-native
  floating pane opens the same window" has nothing to open.
- **Decisions.** A SwiftUI `WindowGroup(id: "float", for: Floating)` (session + terminal id, so a second open brings the
  window forward) with `.restorationBehavior(.disabled)`: the main window saves its floats in its selection
  (`Page.floating`, terminal id → Stay on Top) and opens them after its pages restore; SwiftUI's own restore would
  bring them back before their page. The window uses its main window's page and `PaneViewRegistry` (one stream, D66
  unchanged); floated terminals stream whatever tab or page is in view. One window per terminal: a second main window
  on the session brings the first one's window forward. The red light and ⇧⌘W detach. Close asks (D41) in the
  floating window, also for a Close from the placeholder's header (`CloseDialog`, moved out of `OrielApp.swift`). The
  title row is the title bar's 28 pt, not a card header's 36 (the traffic lights stay where AppKit puts them); the
  card's insets are a pane card's (8, 10). Frame: AppKit's autosave per terminal. Stay on Top: `.floating` level and
  all Spaces. A floated pane is never the keyboard card; ⌘[ ⌘], Focus Follows Mouse and a move skip it; a move keeps
  the main window where it is.
- **Tests** (`FloatTests.swift`): float, keys, ⌘] in the main window, Show, Detach; two windows (palette, header),
  ⌘K's own list, Stay on Top, ⌘Q and relaunch, herdr's close, ⇧⌘W; the close dialog in the floating window and the main
  window's close; the four looks and the red light. CI 40176106059 (rough), 40176761922 (a click under the main window,
  fixed with Show), 40177294645 (green, with the ⌘W tests), 40179306253 (Dock drop green). Full suite on fa64713 (after
  the last code commit 399b2d4, 40179575565): every floating test green; the 9 reds are other lanes' areas (close
  dialogs and stand-ins, ⌘N/⌃⌘S window keys, relaunch's page in view, Finder drop, latency).

### Lane S (items 13, 14, lane K's leftovers)

- **Measured first.** `-recordLatency YES` (`Latency.swift`, e2e only) records, per key or click, the time from the
  event's timestamp to the end of the run loop turn whose Core Animation commit drew a change of the key window (page,
  workspace, tab, tabs, cards, panel, dialog), and the turns that took. CI, debug build, before → after (runs
  40176964309 → 40178588911 and later): ⌘T 79 ms / 20 turns → 68 ms / 0; ⌘D 82 / 17 → 25 / 0; ⌘W 136 / 21 → 31–53 / 0;
  close tab 165 / 39 → 0 turns; ⌘K 432 then 238 ms → 234 then 153 ms (both in the key's turn); tab, workspace and session
  keys were in the key's turn already (32–140 ms of SwiftUI render on the VM); the sidebar's snap after a lifted half
  swipe 217 ms → 53 ms (270 ms on a runner twice as slow, 40181336917, so the test records it and does not bound it).
  The herdr-backed keys are asserted in their turn or the next (the action's task); herdr's answer takes 10 or more.
  On this Mac (one local run, Retina, motion on, debug): ⌘K 219 then 175 ms, tab keys 44–47 ms, workspace keys
  101–144 ms, swipes 82 and 163 ms. A `sample` of that run shows about two thirds of the main thread in XCUITest's
  accessibility snapshots (and SwiftUI's accessibility focus walk, on only while accessibility is in use): without a
  test, opening and closing the palette took about 30 ms of main thread each. A slower runner (40175942806) had ⌘T 482 ms / 49 turns and a first ⌘K of 881 ms (the first menu
  key of a launch pays AppKit's one-time menu donation setup). A herdr call is a new `remote-api-bridge` run: 15–170 ms
  here (about 20 or 140), and the bridge takes one request per run, so calls cannot be batched.
- **Root cause, item 13.** A new pane's program is asked a second late (its shell's startup), and `Page.title` showed
  herdr's numeric label until then. Now "New Tab" while the tab is a stand-in or its pane's shell still starts; the
  startup watcher sets its last answer before it stops starting, so no number shows between. A pane whose program herdr
  cannot say keeps the number.
- **Root cause, item 14.** ⌘T, ⌘D and the closes waited for 2–5 sequential herdr runs (cwd, create, snapshot; split,
  swap, snapshot, ratios, snapshot; process_info, close, snapshot) before anything changed. `Ahead` shows them in the
  key's turn: a new tab or split is drawn as an empty card under a stand-in id (`new.‹uuid›`), a close leaves out what
  it takes; the next snapshots confirm it (herdr's tab or pane takes the stand-in's place) or a failed write takes it
  back. The palette took 230–430 ms to open on CI because `FilterList` built all ~100 rows (layout and the focus
  responder walk over every button, from `sample` on CI): its rows are a `LazyVStack` now. The session swipe snapped
  with the system's paging and showed the session only once the scroll was idle: `SessionPaging` shows the page a swipe
  lands on as the fingers lift and slides there with `Animation.session` (spring response 0.14 s, half the tab spring);
  dots and ⌥⌘[ ] use it too.
- **Lane K's leftovers.** ⌘T then an immediate close: a new pane's shell startup (`ls`, `sort`) is asked again for up
  to 0.8 s until only the shell runs; a close of the stand-in itself goes at once and herdr's tab is closed as it comes.
  A big workspace's close asks `process_info` 8 at a time. ⌥⌘W twice: one ask per close (`Page.asking`, by request);
  another close goes on.
- **Decisions.** A close is hidden at once only when every pane's last answer is its shell; herdr is still asked, and a
  program found brings it back with the question and the selection it moved (lane K's rule holds). A pane with no answer
  yet (a new one) waits for herdr's answer instead of a hide that could come back. Writes queue (FIFO) instead of "Busy,
  try again", so the buttons no longer disable during writes. Hidden panes keep their `Pane` objects and terminals
  until herdr closes them. herdr never reuses a closed id in a server's life (checked), so `closing` clears on absence.
- **Deviations.** Moved `choosePath` to `FileDrop.swift` and the tab title to `TabButton.swift` (Page.swift's 400
  lines). `playbook/workflow.md`'s "never patch local state" names `Ahead` as its one exception.
- **Tests.** `testPanelsAndSwitchesReactAtOnce` (every key drawn in its own turn, the names checked; the swipes
  recorded), `testNewTabSplitAndClosesShowAtOnce` ("New Tab", never a number; ⌘T ⌘D ⌘W ⇧⌘W in their turn; herdr closed
  it), `testQuickNewTabsAndAnEarlyClose` (two ⌘T select the second; ⌘T then ⇧⌘W closes herdr's tab, no dialog).

### Lane A2 (item 3)

- **Root cause, cards jumping.** `SplitLayout` nested one view per split and switched on the node, so a pane whose
  leaf became a split (the pane split) or whose sibling closed (the one left) was a new `PaneCard` in a new branch:
  it showed at its new size with a fade, and its terminal view moved to a new host. Zoom had no animation at all.
  Now the cards are one flat `ForEach` keyed by pane id, each placed by the rectangle the tree gives it (`Parts`),
  the dividers keyed by path: every tree change and zoom moves and sizes the same views (a64aa62).
- **Found on the way: CI's Mac has Reduce Motion on** (run 40176840327), so no motion that honors it had ever run on
  CI (layout motion, the sidebar slide). Tests of motion launch with `-forceMotion YES` (`Animation.forceMotion`,
  also read by lane S's session slide); `playbook/ci.md` says so.
- **Decisions.** A new card slides in from its side (from the left for Split Left), its edge one gap from the
  shrinking card's the whole way, through a `placed` state and `.position`. Not a transition: `.move` and `.offset`
  transitions moved nothing in CI's recordings (only their fade ran). Not padding: a card coming from the left got a
  size below zero. herdr's pane keeps the view of lane S's split stand-in, so the slide goes on (herdr answers within
  it, and a new view popped in at its place). A card with no terminal (the stand-in) now fills its frame; it was a
  header-high band. Zoom grows the card to the page and back while the others fade.
- **Deviation.** A closed card fades instead of shrinking: a scale shrank its SwiftUI parts but left its terminal
  view at full size (CI recording).
- **No-blank rule with motion on.** Checked frame by frame on CI (forced motion) and locally (Retina, Reduce Motion
  off): split left and right, zoom, restore, close and the sidebar slide keep the old picture (`TerminalHost` holds it
  until 150 ms after the last size) and never blank.
- **Test.** `testLayoutMotionAnimatesWithoutBlanking` (RevealTests): under Reduce Motion a split jumps (one size);
  with motion, Split Left (the stand-in path), zoom, restore, close and both sidebar toggles each give the staying
  card's host at least 4 sizes (`-recordMotion YES` counts them; the old code made a new host with 1 or 2) and keep
  text in a band of screen shots. The new card's slide has no per-frame hook (it moves, it does not resize): checked
  on the recordings. No red run on the old code: the first runs were red for Reduce Motion, not for the jump. Also
  `testPaletteSplitsTheKeyboardCardRight` now selects its tab before it clicks the terminal (flaky in 40183475845).
- **Known limits.** A divider send in flight when the tree changes under it targets its old path (as before). A swap
  now animates the two cards crossing. While a test loops on screen shots, CI's recording gets a frame every 0.3–0.6 s.

### Lane O (item 30)

- **Scenario** (`testMemoryAndCPUOverManyTabs`, the e2e helper's `usage`): session one's 5 panes plus a workspace of
  6 tabs and 12 panes, 8 of them printing 10 lines a second, 4 of them working agents (`pane.report_agent`), dots moving
  (`-forceMotion`); every tab shown once, then 10 s of `ps` CPU and `footprint` on a quiet one-pane tab and on a tab
  of 3 printing panes. 17 terminals, as on the user's Mac.

  | | Before | After |
  |---|---|---|
  | Footprint, Release, this Mac (Retina) | 909 MB | 190 MB |
  | IOSurface, Release, this Mac | 586 MB (69 surfaces) | 67 MB (stills purgeable, not counted) |
  | IOAccelerator (graphics), Release, this Mac | 85 MB | 8–21 MB |
  | CPU quiet tab, Release, this Mac | 54.9 % | 2.9 % |
  | CPU busy tab, Release, this Mac | 48.9 % | 5.7 % |
  | Footprint, CI (Debug, 1x VM) | 216 MB | 103–114 MB |
  | CPU quiet / busy, CI | 23.0 / 27.3 % | 4.0 / 1.2 % |
  | herdr `terminal session` runs | 16, 110 MB, 0.1–0.3 % | 5, 34 MB, 0.0–0.2 % |
  | Main thread in a 3 s `sample`, quiet tab (Debug, this Mac) | about half busy in SwiftUI's render (CI 91/187) | 1309 of 1316 samples idle |
  | Lane S's latency tests (`testPanelsAndSwitchesReactAtOnce`, `testNewTabSplitAndClosesShowAtOnce`, `testQuickNewTabsAndAnEarlyClose`) | green | green (this Mac and CI) |

  Steps, Debug on this Mac: the dots alone took CPU from 51.9 / 50.8 % to 19.6 / 18.0 % (memory unchanged, 917 MB);
  the surfaces and paused drawing took it to 3.4 / 6.5 % and 190 MB. CI: 23.0 / 27.3 → 6.8 / 6.2 (dots, 40183818674)
  → 3.1 / 0.9 % (40183996523). Baselines: CI 40183217191, this Mac 760133d.
- **What cost what.** (1) Memory: each libghostty surface is ghostty's Metal swap chain of 3 IOSurfaces
  (`swap_chain_count = 3`) at the card's pixel size; the user's were all 2574 × 1754 BGRA, 17.2 MB each, 51.6 MB a
  terminal, plus 4–5 MB of Metal buffers and atlases. The registry let go of streams only past 24 and never of a
  surface, and a lazy page's card made one even when never shown, so every terminal ever laid out kept 3 surfaces.
  (2) CPU, about 30 points: `WorkingDots` was a `TimelineView` at 15 frames a second per dots view (tab capsules,
  sidebar rows), and each tick made SwiftUI render and lay out the whole window's hosting view and commit its layers;
  the samples show no Oriel view body in it, only `NSHostingView.layout` → `ViewGraph` → `CA::Transaction::commit`.
  (3) CPU, about 15 points: hidden terminals drew. libghostty marks a view visible again when it leaves its window
  (`viewDidMoveToWindow` → `setWindowVisible(true)`), so ghostty's renderer drew each output of the 16 streaming hidden
  terminals. (4) Snapshots and output: no measurable SwiftUI work. Swift 6.4's `@Observable` skips a set to an equal
  value (checked in a probe), so the reconcile's unchanged fields notify nothing; frames are decoded off the main thread.
  (5) The herdr runs: about 7 MB and nearly no CPU each.
- **Changes.** Core Animation runs the dots: one dot in a `CAReplicatorLayer` (3 instances, 5.5 pt and 0.2 s apart),
  a keyframe animation at 15 fps at most, phased from the wall clock (d8fa6eb, 809cad8). Only the shown tab's terminals
  and floating panes draw (`inView`, `setSurfaceVisible`); the 4 most recently shown others (`PaneViewRegistry.spare`,
  over all windows) keep their stream and surface; the rest end their stream and free their surface (`free`:
  `controller = nil`). ghostty's old layer keeps showing its last IOSurface after the free (its `deinit` only
  releases its own reference), so that layer is the still: marked purgeable while its view is in no window, so it costs
  no footprint (a probe: 10 volatile 17 MB surfaces dropped from 176 MB to 3 MB). Shown again, the surface is made anew
  (`rebuild`), the still sits over the new surface's layer, drawing pauses until herdr's frames settle (the 100 ms
  settle, 0.4 s cap), and the still goes when the new surface's layer gets its first contents (KVO, in the same
  transaction). A terminal gets its first surface only when it first streams (86d22ce, 04d5464).
- **Decisions.** `spare = 4`: a kept terminal costs 52 MB at full-window Retina size and a herdr run; 4 covers going
  back and forth between the last few tabs at once, and an older tab comes back under its picture and redraws in one
  stream open plus the settle. A still the system took back gives the card's fill and the first fade-in. The hover
  card's preview pictures only cards that draw (the shown tab's, floating ones); others get lane T's text
  (`TabPreview.picture` reads `inView` and `view.picture`; told the orchestrator for lane T).
- **One herdr helper per session: not possible without cons, so one per terminal stays.** herdr 0.9.5's
  `terminal session control <TARGET>` takes one target, and its server ties each client connection to one terminal
  (`ControlTerminal {target}` is accepted only on a connection still pending terminal mode, `headless.rs`). Several
  terminals per process would need herdr's private client protocol spoken on its socket. The bound above cuts the runs
  from 16 to 5 instead.
- **Tests.** `testMemoryAndCPUOverManyTabs` (red on the old code: 16 runs over its bound of 5 and 7) and
  `testAnEvictedCardComesBackWithItsPicture` (red on the old code: w1:p1's stream never ends): five more tabs evict
  t1's three cards; back on t1, every screenshot has ink, herdr's text shows, its stream is back, and a `clear` is drawn
  (the still did not stay). Not covered by a test: a rebuilt watcher (D66's second window) and a card resized while
  evicted.
- **The user's Mac after the rebuild** (04:21 build, 6 minutes up, the user testing): 192–209 MB footprint, IOSurface
  66–89 MB (plus 44 MB purgeable), 4–5 herdr runs, 11–21 % CPU while in use (was 1.2 GB, 828 MB IOSurface, 18 runs,
  17–32 %). Idle CPU with agents working is still to read.

### Lane B2 (item 25)

- **Root cause.** `Strip` was one view for every workspace and session (the same place in `Detail`), so its
  `LazyHStack` and scroll state carried over a switch. Once the strip drew again while a middle tab was in view (the
  tab selected again: `page.selectedTabIDs[ws] = same` notifies, a dictionary write always does), a switch to a
  workspace with fewer tabs laid out no page: an empty strip until the next switch to a workspace with more tabs. That
  is the user's repro (top to bottom, the one-tab workspaces after mira's 4th tab are empty; bottom to top fine; gone
  after a relaunch). Fix: `Strip(…).id("\(page.id) \(workspace.id)")`, a strip per workspace of each session (9be880e).
- **Decisions.** `make strip-check` (`scripts/strip-check.sh`, `.swift`), run in CI shard 0 after e2e: the built app
  on a throwaway session, keys by `CGEvent.postToPid`, the window title to confirm each key, `screencapture -l` and the
  brightness spread under the title row. Old code: rounds 2–3 spread 0.000 (CI 40186393195; its capture is the user's
  screenshot); fix: 0.120 every round (40186370458). A last round closes the tabs around the shown one (spec review):
  the card stays. `testStripShowsEachWorkspaceClickedBackAndForth` guards the new strip landing on its tab, also after a
  session hop. `playbook/workflow.md` names the pixel exception.
- **Deviation.** The UI test cannot fail on the old code; the script check does. Old-code CI runs used throwaway tags
  (`b2-oldcode*`, deleted), not branches.

### Lane T (items 27, 28)

- **Approach, item 27.** The preview reuses what already exists, so it opens no stream, makes no surface or terminal,
  and moves no terminal view. `TabPreview` (new file) draws the tab's split tree with Strip's `Parts` (made internal)
  at a quarter of a 1056 × 660 pt page (264 × 165 pt) between the title and the rows. A card that draws (lane O: the
  shown tab's, a floated one) shows its libghostty layer's IOSurface, set as another layer's contents: no copy, refreshed
  5 times a second by an AppKit timer that lives in that view, so only while a card is open. Any other card shows its
  screen's text (`pane.read` on open and each second while open; a failed read keeps the last one). Both draw at the
  page's quarter: cells a quarter of their size, top left, cut at the edge, on the card fill over Classic's opaque window
  color (the orchestrator's note: text and picture cards must look alike). Design: window.mdx "The preview's pictures",
  D63.
- **Options weighed.** A view snapshot (`cacheDisplay` misses the Metal layer); a second observe-only surface per pane
  (a renderer, a font atlas and a herdr stream per pane on every hover, and observe cannot resize); `pane.read` for
  every pane (no colors where a picture is free); a hidden tab's last picture (stale, and lane O frees hidden surfaces);
  F2's way (it moves the terminal view, the card shows a placeholder). libghostty's renderer is an `IOSurfaceLayer`
  (strings in libghostty.a), so the layer's `contents` is the frame it shows.
- **Approach, item 28.** Measured from `rex-border.png` (Retina): the card's top line 46 and 28 steps over the fill, a
  glow of about 9 fading over 6 pt, the sides 15 and 7. `CardSurface` now draws the 0.7 pt rim at white 0.06 (was 0.1,
  sides were twice Rex's) and over it a 1 pt top line (white 0.09) masked to fade round the corners in 14 pt, plus an
  8 pt glow at half; `plusLighter`, the same on every card (item 1 holds: testCardsLookAlike green). Light: white 0.04 /
  0.3. Classic: none, as Rex's System and UseTheme cards (a flat stroke, no highlight).
- **Root causes on the way.** (1) The first CI run's mini cards were 60 pt apart: herdr's text, wider than its card
  (bash's long prompt), widened the card's accessibility frame though clipped; the text now keeps the cells that fit.
  (2) A SwiftUI `TimelineView` (5 Hz) cost about 20 % CPU in a debug build: each tick laid out the whole window
  (`sample`: `NSHostingView.layout` under `CA::Transaction::commit`); the AppKit timer costs about 1 point.
- **Numbers.** Local, debug, M-series, two printing panes: no card 4.7 %, a hidden tab's card 5.9 %, the shown tab's
  card 5.4 % (the herdr runs of the text reads are not counted). Rim on Retina over the user's wallpaper, Glass dark:
  top 42 → 45 after the bump, sides 15; light 10–15 / 9–10. CI (1x): top 38, sides 11.
- **Tests.** `testHoverCardPreviewsTheTabsCardsLive` (text with the pane's echo for a tab not shown, cards side by side
  2 pt apart, then pictures that follow a white block and a clear while the card stays open),
  `testHoverCardPreviewCostsLittle`, `testGlassCardsHaveABrighterTopRim` (top − side ≥ 12, every card alike; the old
  uniform rim fails). `testHoverCardBlursTheTextBehindIt` measures the pane row now (the preview took its old rect).

## Wave 3 (user, 2026-10-25 01:20, after trying wave 1)

Screenshots in the main checkout: `.build/fb/shortcuts.png` (item 17), `.build/fb/agents-header.png` (item 18).

### Lane I2: keys (items 17, 21, 22, 23)

17. **Shortcuts panel:** more spacious (row height and column gaps about 1.5×, more padding), and each key
    as its own keycap (a small rounded box per modifier and per key: `⌥` `⌘` `←→↑↓`), so long shortcuts read
    clearly. A family keeps one keycap for its keys (`←→↑↓`, `1–9`); a second key follows after "or".
21. **Split:** the new pane gets the keyboard, from the header buttons, menus, palette and ⌘D / ⇧⌘D.
    **⌘[ ⌘]** step panes in the split tree's order (left before right, top before bottom), as Ghostty does,
    going round at the ends.
22. **⇧⌘↩ does not zoom.** Find why (libghostty or the key monitor may take it) and fix it.
23. **One key pattern** (replaces lane I's table). The key says the action, the modifier says the level:
    `T` new, `W` close, `[` `]` previous / next, `1`–`9` jump. ⌘ is the pane or tab, ⇧⌘ the tab, ⌃⌘ the
    workspace, ⌥⌘ the session. Arrows always mean panes.

    | | Pane | Tab | Workspace (⌃⌘) | Session (⌥⌘) |
    |---|---|---|---|---|
    | New | ⌘D right, ⇧⌘D down | ⌘T | ⌃⌘T | ⌥⌘T Open Session (was ⇧⌘N) |
    | Close | ⌘W (the tab too when it is the last pane) | ⇧⌘W (was ⌥⌘W) | ⌃⌘W | ⌥⌘W Detach Session |
    | Previous / next | ⌘[ ⌘] | ⇧⌘[ ⇧⌘], ⌃⇧⇥ ⌃⇥ | ⌃⌘[ ⌃⌘] | ⌥⌘[ ⌥⌘] |
    | Jump | — | ⌘1–9 | ⌃⌘1–9 | ⌥⌘1–9 |

    Panes, with arrows: ⌥⌘ arrows select (Ghostty, iTerm2), ⇧⌥⌘ arrows move, ⌥⌘= balances (was ⌃⌘=),
    ⇧⌘↩ zooms. Resize Pane keeps its palette rows but has no key (was ⌃⌘ arrows; dividers and Balance
    cover it). The rest: ⌘N new window, Close Window has no key (was ⇧⌘W), ⌘K / ⇧⌘P palette, ⌘/ shortcuts,
    ⌘. agents, ⌘F / ⌘G find, ⇧⌘G go to directory, Insert Path ⇧⌘I (was ⌃⌘I), ⌃⌘S sidebar (it shows
    workspaces), ⌘+ ⌘− ⌘0 font size, ⌃⌘F full screen (the macOS key, the one ⌃⌘ that is not a
    workspace). Move Tab stays ⌃⇧PgUp / PgDn. Update the menus, panel, docs (theme-and-accessibility) and
    tests; a key that moved must not keep its old binding.

### Lane P: sidebar and panels (items 18, 19, 20)

18. **Agents view header** (`.build/fb/agents-header.png`): remove the separator line. Make the hierarchy
    clear at a glance: the session name is the title (primary color, semibold, a step larger than the
    rows' secondary text), the sort control stays quiet on the right, and the group labels ("Working 1",
    workspace names) are smaller section labels (secondary, like macOS sidebar section headers) with clear
    space above each group. Use the same title style for the session name in the workspaces view.
19. **Open Session panel:** the session shown in this window gets a Detach button (detaches it from this
    window; plain style). Stop and Delete buttons are red.
20. **Agents button hover:** when nobody needs the user, hovering shows nothing (no panel, no "All caught
    up"); the panel shows only when it has rows.

### More from the user (2026-10-25 01:45)

24. (Lane I2) **Working dots on the selected tab too.** D42 hid them on the selected tab, as Rex does; the
    user wants them on every tab, the selected one included. Update D42.
25. (Lane B2) **Empty strip again** (`.build/fb/blank.png`): the whole strip is empty, no card and no card
    header, in a workspace with one tab ("ui polish"); sidebar and tab bar are fine. The user's build is
    main at about 01:10 (wave 1, before any wave 2 code). Phase 24 lane A blamed the terminal reveal without
    a repro; this shot shows the cards themselves missing, so the cause is likely the strip: its scroll
    position or page layout (for example a scroll offset left from a workspace or session with more tabs,
    an instant `scrollTo` plus retry that targets a page not laid out yet, a stale tree, a strip page width
    of 0). Find a way to reproduce it on CI, find the root cause and fix it, with a test that fails on the
    old code.
26. (Lane P) **Tab hover card is hard to read** (`.build/fb/hovercard.png`): in Glass, the terminal text
    behind shows through it. Make it as readable as the palette: a thicker material or a tint under it, so
    text behind is only a soft blur; check over a busy terminal in all four looks. Apply the same to any
    other floating glass (agents popover, menus) that has the same problem.

### Lane T: tab preview and card rim (user, 2026-10-25 02:30)

27. **Live tab preview on hover.** The tab hover card also shows a preview of the tab: its cards in their
    layout, like the drag image when a pane is grabbed (240 × 150 pt), drawn from the panes' real terminal
    content. Live if it is not much work (refresh while the card is open; at most a few frames a second);
    else the last picture of each pane. It must cost nothing while no hover card is open, and must not take
    a terminal away from its card (a terminal view lives in one place). Pick the simplest way that can grow
    into item 29; write the choice in the design pages. New view: send the orchestrator one rough CI
    screenshot before polishing.
28. **Card rim like Rex** (`.build/fb/rex-border.png`): Rex's cards have a thin light glass rim (brighter at
    the top edge). Oriel's cards have none. Add the same rim to every card in Glass (Classic: check what
    Rex does and match it), light and dark, without making the keyboard card stand out more (item 1).

### Later (not in this phase)

29. **Overview of all tabs** (`.build/fb/overview.png`, the user's reference): a full-window view of every
    tab of a workspace as live previews in a grid, under the workspace name, scrolling through workspaces;
    for watching many agents at a glance. Item 27 lays its base.

### Lane O: memory and CPU (user, 2026-10-25 03:00)

30. Measured on the user's Mac (Release build, about 50 minutes up, agents working): Oriel used 1.2 GB
    (footprint; 828 MB IOSurface for 17 live terminals, about 49 MB each, plus 83 MB other GPU memory) and
    17–32% of one core (60% peak); its 18 `herdr … terminal session` helpers used 112 MB and about 0.1% CPU.
    A 5 s `sample` showed the main thread mostly in SwiftUI's AttributeGraph updates. The user: "our app
    shouldn't take this much memory and CPU". Analyse fully, then optimise wherever it pays:
    - **GPU buffers:** keep live terminal surfaces only for a bounded set (LRU, a small number beyond the
      visible cards, chosen by measurement); free the others' surfaces and rebuild on show, with phase 24's
      no-blank and reveal rules intact (a rebuilt card must not flash or stay empty).
    - **Hidden terminals:** pause drawing for every terminal not on screen (other tabs, other workspaces and
      sessions, minimized or occluded windows), and resume on show.
    - **One herdr helper per session** instead of one per terminal, if it has no cons (check herdr 0.9.5's
      stream API: can one `terminal session` process carry several terminals, and what happens to control
      hand-off, observe/takeover, sizes and floating windows); if it has cons, write them down and keep one
      per terminal.
    - **SwiftUI main-thread work:** find what invalidates the views on each snapshot or output change and
      on the working-dot animation, and cut it (narrower observation, equatable views, one clock for all
      dots).
    - Measure before and after on the same scenario (a script that builds a throwaway session with many
      tabs and panes, some running output, and samples footprint and CPU with `footprint`, `top`, `sample`).
      Targets: memory about what the visible cards need; idle CPU a few percent; no regression in snappiness
      (lane S's numbers). Put the numbers in the Findings.

31. (Lane I2) **Move Pane to Tab** (`.build/fb/move-to-tab.png`) lists only the other tabs of the current
    workspace. It lists New Tab and New Workspace first, a separator, then every tab of the session grouped
    by workspace: each workspace's name as a section header, a separator between workspaces, the pane's
    own tab left out. Same in the header menu, the right-click menu, View ▸ Pane and the palette's sub-page.
