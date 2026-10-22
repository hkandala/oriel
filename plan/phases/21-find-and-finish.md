# Phase 21: find, links, states and finish

Goal: the last Rex features that work over herdr (find in a pane, opening links), Rex-style empty
states and notices, the "Controlled in another window" state, the Open Session failures, small launch
and Dock touches, and a final pass over the whole UI against the Rex references and the mock-ups.

Read first: `resources/research/clients/rex-internals.md` (§3.6 find bar, §3.8 notices; facts only, write your own code), `plan/ui-polish.md`, `plan/ui-layout.md`, `resources/research/clients/rex-ui.md` (find
bar, empty and loading states, notices, launch cover), `docs/content/docs/ui/states.mdx`,
`docs/content/docs/talking-to-herdr.mdx` (scrolling, queries and links; `pane.read`),
`Oriel/App/OrielApp.swift` (`Detail`, notice).

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
   distance from the end, minus half the screen, so the match line is centered). `ponytail:` no
   highlight over the match cells (mapping herdr's scrolled viewport to libghostty cells is fragile);
   add it if users ask. Closing the bar scrolls back to the bottom (offset 0). herdr's viewport is
   shared; scrolling it shows in a herdr TUI attached to the same pane too.
3. **Find bar.** A small glass bar at the card's top right, 8 pt in: field, "3 of 12", ↑ ↓ buttons,
   ×. ⌘G next (as in Rex, Find Previous has no shortcut: ⇧⌘G is Go to Directory), Enter next, ⇧Enter
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

10. Compare every screen with the Rex references and `resources/mockups/layout.html` side by side (title
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
## e2e

- Print 200 numbered lines in a throwaway pane; ⌘F, type "line 42": the bar shows "1 of 1" and
  herdr's scroll offset is not 0 (snapshot `scroll.offset_from_bottom`); ⎋ sets it back to 0.
- ⌘-click on a printed `https://example.com` URL: the app asks the system to open it (test through a
  launch argument that records opened URLs instead of opening them).
- A failed write shows the notice capsule with its symbol.
- With `ORIEL_SESSION5` open as a second page, stop its server through the helper: that page shows
  the not running state with Start; Start brings its workspaces back; the first page is not touched.
- A start that fails: the sheet stays open and the notice shows "Could not start" with Retry. It
  needs a sixth session name: add it to `scripts/e2e.sh` and the helper. Make it fail with the
  smallest hook that works (for example a launch argument that sets the start timeout to 0 s); if
  none is small, check it by hand and record it.
- The reconnecting state (the bridge fails while the server runs) is checked by hand.
- Two windows on `ORIEL_SESSION`: the watching window's capsule has the notice look and Take
  Back works.

## Done when

- The whole e2e suite is green locally and in CI.
- A final set of screenshots in light and dark, Glass and Classic, next to the matching Rex
  references, is in the phase report.

## Findings
