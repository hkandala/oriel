# Phase 27: The user's third round of feedback

The user built main at about 04:20 on 2026-10-25 and tried phases 24–26. The orchestrator settled the open
points; each lane writes `## Findings` at the end. Read the Findings of phases 24 and 25 first: most items
change code those lanes wrote.

The user is testing on this Mac: `/tmp/oriel-gui.lock` is held for "user" until the orchestrator says
otherwise. UI tests run on CI (Reduce Motion is on there; `-forceMotion YES` turns motion on).

## Lane A3: live surfaces stay (item 1)

1. **Going back to a tab must show at once.** Lane O freed the libghostty surface of every hidden terminal
   past the 4 most recent, so a tab visited a while ago fades in when shown again. The user accepts more
   memory for snappiness. Keep the surface (and stream) of terminals the user has visited, drawing paused
   while hidden, so showing them again is instant: no rebuild, no fade, no wait for herdr's frames. Look
   at how Ghostty does it (its surfaces for hidden tabs and occluded windows: what it keeps, what it
   pauses, whether it shrinks or drops the swap chain), and copy that. Free surfaces only past a memory
   budget chosen from measurements (for example the last 16 visited terminals, or about 600 MB), oldest
   first. Lane O's other wins stay: dots on Core Animation, hidden terminals not drawing, no surface before
   the first stream. Measure before and after (lane O's scenario and numbers in phase 25's Findings).

## Lane G3: agents sidebar (items 2–5)

2. The sort control reads "Workspace" (not "Workspace order") and "Priority", and looks like a small
   button (a capsule with a fill on hover, like the header buttons), not plain text.
3. **The session named `default`** is not shown by that name anywhere in the sidebar header: it shows the
   machine's name instead ("This Mac", or a remote host's name). Other sessions show their own name. The
   Open Session panel and the palette keep the real session names.
4. The session name in the header is the rows' size, bold (not larger).
5. **Collapsible groups:** each group header (a status in Priority, a workspace in Workspace) folds and
   unfolds its rows with a chevron; the folded state is kept per session and mode across relaunches. A
   folded group keeps its header and count.

## Lane T3: tabs, panes and motion (items 6–9)

6. **⌘T fast, then ⌘W fast:** after several quick ⌘T, each ⌘W closes the shown tab and goes to the one
   used before it, one step back each time, even while the new tabs are still stand-ins or their shells
   are starting. Now it jumps to a tab whose shell has loaded. The tab history must follow a stand-in to
   herdr's real tab id.
7. **Closing a pane** gives the keyboard to the pane used before it in that tab (most recent first), as
   closing a tab does; else the neighbor as now.
8. **Pane motion faster:** split, close and zoom about a third shorter than lane A2's.
9. **Session swipe:** lane S's spring (response 0.14 s) feels too fast and odd. Make it calm and quick:
   somewhere between the tab spring and lane S's, no bounce, and the page must track the fingers during the
   swipe and finish from the release speed. Check it on the CI recording with motion forced; the user
   judges by hand.

## Lane F3: floating panes (items 10–14)

10. A new floating window opens bigger: about 60% of the main window's size (at least 720 × 460 pt),
    centered over it.
11. **The placeholder** in the tab shows the pane's quick info like the floating window's title row (icon,
    program, folder, agent status) and the whole card is a button that brings the floating window forward;
    drop the separate Show button.
12. **The floating title row** is taller: room above and below the traffic lights like the main window's
    title row (match its height and the lights' position).
13. **Its buttons** (pin, Close, Detach) use the same icons, size, weight and color as the card header
    buttons and the main title row; they look like one app.
14. **herdr's own floating panes.** herdr shows popups from plugin panes (`placement = "popup"` in a
    plugin's `herdr-plugin.toml`; methods `plugin.pane.open`, `plugin.pane.close`, `popup.close`; events
    `plugin_pane_opened`, `plugin_pane_closed`; see `herdr api schema --json`). Example: the user's pi-herd
    extension (`/Users/hkandala/code/pi-hkandala/extensions/pi-herd`, plugin in
    `/Users/hkandala/code/pi-hkandala/herdr/plugin`) opens an agent in a popup from pi-footer. When herdr
    opens a popup in a session Oriel shows, Oriel opens its floating window for it, streams it, and closes
    it when herdr closes the popup; closing or detaching the window closes the popup in herdr
    (`popup.close`). It must work for any plugin popup, not only pi-herd's. Find what the snapshot and the
    events give (is a popup a pane with a terminal id? its size?) before building. Phase 25 lane F2 said
    "herdr's popup is not a pane": check that again with the plugin API.

## Lane V: overview instead of tab previews (items 15, 16)

15. **Drop the tab preview** in the hover card (phase 25 lane T's TabPreview, its read loop and timer):
    the hover card goes back to its state before lane T (title, rows, the needs-you lines). Keep lane T's
    card rim (item 28).
16. **Overview** (`.build/fb/overview.png`, phase 25 item 29): a mode that hides the tab bar and sidebar and
    shows a canvas of live tab previews. Each tab is a miniature of its real layout at its real proportions,
    drawn live (not text), with its title row. Tabs are grouped under their workspace's name; scrolling
    vertically goes through the workspaces of the session; scrolling horizontally (or swiping) goes to the
    next session of the window. Clicking a tab leaves the overview and shows that tab, zooming from its
    miniature to the full window. A title-row button, a command (palette, View menu) and a key toggle it
    (pick the key with lane I2's pattern in phase 25; ⌃⌘O or similar, not taken). Esc leaves it.
    - Live miniatures must be cheap: decide from measurements how to draw them (for example a small
      observe-only surface per terminal with a scaled font, or the live surfaces of lane A3 scaled down).
      Write the choice in the design pages; coordinate with lane A3 through the orchestrator if it
      touches the surface registry.
    - New view: send the orchestrator one rough CI screenshot before polishing.

## Checks

- `make lint build test`; a UI test for each item a test can see; the full CI suite green on each lane's
  last code commit; one review round per lane (spec and ponytail, read only).

## Findings
