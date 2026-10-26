# Phase 21: find, links, states and finish

Goal: the last Rex features that work over herdr (find in a pane, opening links), Rex-style empty
states and notices, the "Controlled in another window" state, the Open Session failures, small launch
and Dock touches, and a final pass over the whole UI against the Rex references and the mock-ups.

## Build

### Find (⌘F)

1. **Spike first (half a day).** herdr has `pane.copy_search` (needs a `content_revision` and a cursor
   in copy mode) and `pane.read {source: "recent", lines}` plus `pane.scroll {offset_from_bottom}`.
   Try `pane.copy_search` on a throwaway pane; if it works without moving herdr's own copy mode for
   other clients, use it. Otherwise use the fallback below. Record the result in the phase findings.
2. **Fallback.** Read the pane's text with `pane.read {source: "recent", lines: 5000, format: "text"}`
   once when the find bar opens. Search it locally on each edit (case blind) and count matches. Read
   again only on Next or Previous after Return was pressed in the pane. Next and previous scroll
   herdr's viewport to the match with `pane.scroll {pane_id, offset_from_bottom}` (the match line's
   distance from the end, minus half the screen, so the match line is centered). **Highlights** (user,
   mid-phase): after each scroll the matches on the screen are placed from `pane.read visible` and
   `pane.get`'s offset, the selected one in the accent at 0.45, the others at 0.2, in one overlay view;
   placed again when frames come. Closing the bar scrolls back to the bottom (offset 0). herdr's viewport is
   shared; scrolling it shows in a herdr TUI attached to the same pane too.
3. **Find bar.** A glass bar 320 pt wide (fixed, user: it must not jump while typing) at the card's
   top right, 8 pt in: field, "3 of 12" in a fixed slot, ↑ ↓ buttons, ×. ⌘G next (as in Rex, Find Previous has no shortcut: ⇧⌘G is Go to Directory), Enter next, ⇧Enter
   previous, ⎋ closes. One bar per card.

### Links

4. ⌘-click on a URL in a terminal opens it in the default browser, http and https only (design).
   `PaneSurfaceView` adopts libghostty-spm's `TerminalSurfaceOpenURLDelegate`
   (`terminalDidRequestOpenURL`: ⌘-click, the URL regex and OSC 8; open http and https only) and
   `TerminalSurfaceHoverLinkDelegate` (a pointing-hand cursor while ⌘ is down over a link). A ⌘-click
   is not forwarded to herdr as a mouse click (`PaneSurfaceView.mouse`).

### States and notices

5. **Empty and loading states** with Rex's wording and one button each, in a `ContentUnavailableView`
   with our layout:
   - Connecting: "Connecting to ‹machine›" with a spinner, after 0.3 s (no flash on a fast connect).
   - Reconnecting: "Reconnecting to ‹machine›" with a spinner, cards dimmed to 0.5.
   - A workspace with no tabs (rare in herdr): only a New Tab button with its shortcut, no text.
   - No workspaces: only a New Workspace button, no text (today it shows a command).
   - Keep the herdr install, too old and not running states (D38, D47). The not running state is per
     page: a page whose session stops while it is open shows it with **Start**; the page stays open.
   - **Controlled in another window** (phase 16): the watching window's capsule gets the notice look
     of step 7 (info tone, `macwindow.on.rectangle`, the **Take Back** button, no ✕). It sits under a
     notice when both show. VoiceOver reads "Controlled in another window" when it appears.
   - A pane another device holds: the card's button reads "In use elsewhere · Take Back", the one form
     the docs use (today the code writes "back" in lowercase).
6. **Open Session failures** (the sheet from phase 14):
   - Starting a session (create or stopped) fails, or its server does not answer within 10 s: the
     row's spinner stops, the sheet stays open, and the notice says "Could not start ‹session›" with
     herdr's reason and **Retry**.
   - A running session that stopped since the list was read, or a name created elsewhere since then:
     phase 14's one path (start if not running, then open the page) covers both, with no extra code.
   - Opening a page fails to connect (the bridge errors): the page shows the reconnecting state.
   No other text goes into the sheet.
7. **Notice.** Today's 4 s notice becomes a capsule at the bottom center of the strip, 30 pt above the
   bottom: glass, a tone color for the leading symbol (error red, warning amber, info blue), an
   optional action button ("Retry"), a ✕. Same text rules as now.
8. **Launch.** Cards fade in (0.2 s) when their terminal's first frame arrives, instead of popping in
   empty.
9. **Dock drop.** Folders dropped on the Dock icon (add `public.folder` to the document types, Viewer,
   Alternate) open a new workspace in each folder (`workspace.create {cwd, focus:false}`), selected
   when it appears, in the session of the key window's page in view. Handle `application(_:open:)` in
   the phase 15 `NSApplicationDelegateAdaptor`, and add `.handlesExternalEvents(matching: [])` to the
   `WindowGroup`, so a dropped folder opens no window. (Window restore is phase 16.)

### Final pass

10. Compare every screen with the Rex references side by side (title
    row and tab bar, machine and workspace menus, sidebar pages, Agents popover and view, Open Session
    sheet, two windows, hover card, cards, palette, light and dark, Glass and Classic). Fix
    spacing, font weights, colors and timings until they match in spirit. List what you changed in the
    findings.
11. Update the docs site's mock-ups to the new look: the components in `docs/components/design/`
    (split demo, chat card) and the interactive overview `docs/public/overview/index.html`.
    If that is large, record it as the next task instead.
12. **Docs.** `ui/states.mdx` (new texts, Open Session failures, the watching window),
    `ui/window.mdx` (find bar, notice), the keyboard table (⌘F,
    ⌘G), `features.mdx` (final list), `inspirations.mdx` ("What we take" from Rex).

- **Programs of panes never shown.** Phase 19 Findings: a pane in a tab that never showed reads
  "terminal" in the hover card, because the app asks herdr for a pane's program only when its card shows
  or when it is new (phase 13). Ask once per pane on the first snapshot too (same ask and counter).
- **Restore without the system setting.** Window restore (phase 16) works only when macOS keeps windows
  on quit, which is off by default. Register `NSQuitAlwaysKeepsWindows = true` in the app's own defaults
  (`UserDefaults.standard.register`), so Oriel restores its windows and pages after a normal quit.
## Findings

### Deviations

- **Final pass and docs mock-ups (Build 10, 11) go to phase 22 and after it.** Phase 22 runs in parallel and owns the
  visual match with Rex (tokens, title row, tab bar, cards, sidebar); this phase compared only its own views (find
  bar, notices, states). The docs site's mock-ups (`docs/components/design/`, `docs/public/overview/index.html`) are
  the next task once phase 22's look settles. The light/dark × Glass/Classic shots next to Rex are phase 22's
  `VisualTests` (`testScenesGlassDark` and the others) attachments in the full run, kept in
  `/tmp/oriel-shots/21/final/`.
- **Find highlights are built** (user, mid-phase), not left out as the phase file had it: one overlay view per card
  draws rectangles from herdr's visible text after each scroll (`pane.read visible` plus `pane.get`'s
  `scroll.offset_from_bottom` to pick the selected match's row), and again 100 ms after frames come
  (`PaneTerminal.onFrame`). libghostty's own search (`search:` binding action) was not used: our surface has no
  scrollback and its selected match would not be ours. `ponytail:` columns count characters, so wide characters
  before a match put its highlight off.
- **The find bar is 320 pt wide, fixed** (user): the count sits in a 72 pt slot with monospaced digits. It sits 8 pt
  under the header, not over it, so it never covers the header's buttons. One bar per window page.
- **A new query selects the last match** (nearest the bottom, as a terminal user looks for recent output); Next goes
  down, Previous up, round the ends. AppKit's text field selects its text after Return, so typing after Enter
  replaces the query (the test types the whole query again).
- **"No answer from herdr" is gone**: any failure while the session's server runs is the reconnecting state (the
  client retries every 2 s), also a page's first connect. herdr too old and not installed keep their pages.
- **The content fade is the terminal's, not the card's**: the card's frame and header show at once and the terminal
  view fades from alpha 0 over 0.12 s (the user's late request for the first-resize fix; the phase file had 0.2 s) through `NSAnimationContext` on the host view (SwiftUI's `opacity` moves the
  terminal's accessibility frame, phase 16). A card whose stream fails still shows its failure text.
- **No flicker of herdr's first resize** (user, late): a pane opened for the first time redraws once while herdr
  resizes its PTY to the card (herdr can size a PTY only by attaching). herdr's first `control` frame already has the
  asked size (spec review 4, by hand: vim gave a reflowed old screen, then its SIGWINCH redraw in the same
  millisecond), so a size check does nothing: `PaneTerminal.ready` turns on once frames stop for 100 ms, at most 1 s
  after the first frame (a watcher at once, as it cannot resize). Until then the card shows its fill, a small spinner
  after 0.5 s, and its value ends in ", loading". Background tabs are not attached ahead (D46).
- **Retry only in the Open Session sheet.** A write's notice has no Retry: after a timeout a retry is not safe (a
  create may have gone through), and "Busy, try again" with Retry was cut in the ponytail review.
- **The Open Session failure is a notice capsule inside the sheet** (the window's capsule lies under the sheet):
  "Could not start ‹session›. ‹herdr's reason›" with Retry and no ✕.
- **Programs of panes never shown were already asked** (phase 13's `watchProgram` asks every new pane, also in
  tabs never shown) but a second late; the first snapshot's panes are now asked at once (their shells started long
  ago), new panes still after 1 s.

### Decisions

- **Ids:** `find`, `find.field`, `find.count` (value "3 of 12"), `find.previous`, `find.next`, `find.close`,
  `find.highlights` (value "N shown, current row R"); `notice.symbol` (label Error, Warning or Information),
  `notice.close`, `notice.retry`, `open-session.notice`; `detail.connecting`, `detail.reconnecting`, `new-tab` (the
  empty workspace's button); `app.links` (the links recorded with `-recordLinks YES`).
- **Menu:** Edit ▸ Find… (⌘F), Find Next (⌘G), Find Previous (no key), so the palette lists them too.
- **Hooks for e2e:** `-startTimeout 0` (seconds; the server start waits 10 s by default, `startServer(within:)`):
  with no time the start throws right after `launchctl bootstrap`, but launchd still starts the server, so Retry
  finds it running. `-recordLinks YES` keeps ⌘-clicked links in `Links.recorded` instead of opening them.
- **`Multiplexer` grew** `recent(_:lines:)` and `scroll(_:offsetFromBottom:)`; HerdrKit's `Pane` decodes
  `scroll.offset_from_bottom` (`PaneScroll`); `startServer(within:)` takes the timeout.
- **Tones:** error `look.error` with `xmark.octagon.fill`, warning `look.needsYou` with
  `exclamationmark.triangle.fill`, info `look.working` with `info.circle.fill`; no new tokens.
- **A sixth e2e session** (`ORIEL_SESSION6`), made by the app in the failed-start test and cleaned up like four.
- **Dock drop:** `application(_:open:)` queues the folders (`WindowPages.folders`); the last key window's page in view
  makes a workspace per folder once it is live, and the last one is selected when it appears
  (`Page.newWorkspace(cwd:)` sets `arriving`). A drop that starts the app opens no window by itself
  (`handlesExternalEvents(matching: [])`), so the delegate opens one with SwiftUI's `openWindow`, kept from the menu
  bar's commands (they exist with no window). e2e: the helper's `open-folder` makes a folder and runs `open -a` on
  the built app (with `-session` for a launch), warm and cold.
- **Restore:** `UserDefaults.register(["NSQuitAlwaysKeepsWindows": true])` in `applicationWillFinishLaunching`; a
  user's own `defaults write` still wins.

- **Find closes when its card leaves view** (another tab, workspace or page) and when its page or window closes:
  herdr's viewport is shared, so it must not stay scrolled while the user is elsewhere (`dropFind`).
- **Kept, not dead code:** the empty workspace's New Tab button (the phase asks for it; herdr 0.9.5 closes a
  workspace whose last tab closes, so it shows only in a race). The sheet's "Could not start" notice has no ✕: it
  stays until the next try, and Cancel closes the sheet. No test shows the control capsule under a notice.
- **Not changed:** a page that connects again after a start that timed out does not get its first workspace in home
  (Retry finds the server running, so `startServer` returns false); the page offers New Workspace. `pane.scroll`'s
  reply decodes as `Created`, as the other writes with an ignored reply do. Known, left: a find pane moved to another
  workspace (a new pane id) drops the bar without scrolling that terminal back; a bar dropped while reconnecting, or
  open at quit, leaves herdr's viewport scrolled (no client, no terminate hook). Kept against the ponytail review: the
  `keep(_:)` helper (SwiftFormat turns `let _ = (a = b)` into `_ = …`, which a commands builder rejects), and the
  AppKit window check for a Dock drop (`WindowPages.windows` fills only once restored windows restored their pages, so
  a drop that starts the app with saved windows would open one more).
