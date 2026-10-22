# Phase 19: find, links, states and finish

Goal: the last Rex features that work over herdr (find in a pane, opening links), Rex-style empty
states and notices, small launch and Dock touches, and a final pass over the whole UI against the Rex
references.

Read first: `plan/ui-polish.md`, `resources/research/clients/rex-ui.md` (find bar, empty and loading
states, notices, launch cover), `docs/content/docs/ui/states.mdx`, `docs/content/docs/talking-to-herdr.mdx`
(scrolling, queries and links; `pane.read`), `Oriel/App/OrielApp.swift` (`Detail`, notice).

## Build

### Find (⌘F)

1. **Spike first (half a day).** herdr has `pane.copy_search` (needs a `content_revision` and a cursor
   in copy mode) and `pane.read {source: "recent", lines}` plus `pane.scroll {offset_from_bottom}`.
   Try `pane.copy_search` on a throwaway pane; if it works without moving herdr's own copy mode for
   other clients, use it. Otherwise use the fallback below. Record the result in the phase findings.
2. **Fallback.** Read the pane's text with `pane.read {source: "recent", lines: 5000, format: "text"}`
   when the find bar opens and again 0.3 s after each edit of the query, search it locally (case
   blind), and count matches. Next and previous scroll herdr's viewport to the match with
   `pane.scroll {pane_id, offset_from_bottom}` (the match line's distance from the end, minus half
   the screen), and draw a highlight over the match cells in the card. Closing the bar scrolls back to
   the bottom (offset 0). `ponytail:` herdr's viewport is shared; scrolling it shows in a herdr TUI
   attached to the same pane too.
3. **Find bar.** A small glass bar at the card's top right, 8 pt in: field, "3 of 12", ↑ ↓ buttons,
   ×. ⌘G next (as in Rex, Find Previous has no shortcut: ⇧⌘G is Go to Directory), Enter next, ⇧Enter
   previous, ⎋ closes. One bar per card.

### Links

4. ⌘-click on a URL in a terminal opens it in the default browser, http and https only (design).
   Check whether libghostty-spm reports the clicked link for herdr's frames (a link-click callback or
   OSC 8); if not, find the URL in the clicked row's text (`pane.read visible`) around the clicked
   column. The pointer shows a hand while ⌘ is down over a URL if libghostty-spm tells us; otherwise
   skip the hover state.

### States and notices

5. **Empty and loading states** with Rex's wording and one button each, in a `ContentUnavailableView`
   with our layout:
   - Connecting: "Connecting to ‹machine›" with a spinner, after 0.3 s (no flash on a fast connect).
   - Reconnecting: "Reconnecting to ‹machine›", cards dimmed to 0.5 (design: gray cards), "Attempt N
     failed. Trying again." under it.
   - A workspace with no tabs (rare in herdr): "Open a new tab to start a terminal." and a New Tab
     button with its shortcut.
   - No workspaces: "No workspaces" and a New Workspace button (today it shows a command).
   - Keep the herdr install, too old and not running states (D38, D47).
6. **Notice.** Today's 4 s notice becomes a capsule at the bottom center of the strip, 30 pt above the
   bottom: glass, a tone color for the leading symbol (error red, warning amber, info blue), an
   optional action button ("Retry"), a ✕. Same text rules as now.
7. **Launch.** Cards fade in (0.2 s) when their terminal's first frame arrives, instead of popping in
   empty.
8. **Dock drop.** Folders dropped on the Dock icon (add `public.folder` to the document types, Viewer,
   Alternate) open a new workspace in each folder (`workspace.create {cwd, focus:false}`), selected
   when it appears.
9. **Window restore.** `@SceneStorage` keeps the selected workspace and tab and the sidebar state
   (design `data.mdx`); a restored id that is gone falls back to herdr's focused workspace.

### Final pass

10. Compare every screen with the Rex references side by side (tab bar, sidebar, Activity, hover card,
    cards, palette, Settings, light and dark, Glass and Classic). Fix spacing, font weights, colors
    and timings until they match in spirit. List what you changed in the findings.
11. Update the docs site's mock-ups to the new look: the components in `docs/components/design/`
    (main window, split demo, chat card) and the interactive overview `docs/public/overview/index.html`.
    If that is large, record it as the next task instead.
12. **Docs.** `ui/states.mdx` (new texts), `ui/window.mdx` (find bar, notice), the keyboard table (⌘F,
    ⌘G), `features.mdx` (final list), `inspirations.mdx` ("What we take" from Rex).

## e2e

- Print 200 numbered lines in a throwaway pane; ⌘F, type "line 42": the bar shows "1 of 1" and
  herdr's scroll offset is not 0 (snapshot `scroll.offset_from_bottom`); ⎋ sets it back to 0.
- ⌘-click on a printed `https://example.com` URL: the app asks the system to open it (test through a
  launch argument that records opened URLs instead of opening them).
- Stop the session's server: the reconnecting state shows; start it: the cards come back.
- A failed write shows the notice capsule with its symbol.

## Done when

- The whole e2e suite is green locally and in CI.
- A final set of screenshots in light and dark, Glass and Classic, next to the matching Rex
  references, is in the phase report.
