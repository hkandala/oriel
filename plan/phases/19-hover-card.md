# Phase 19: hover card and tooltips

Goal: Rex's tab "peek": hover a tab to see what runs in it, and click a pane there to go to it. Plus
native tooltips with the shortcut on the chrome buttons.

Read first: `resources/research/clients/rex-internals.md` (§3.4, §3.8, §5.1, §5.4: hover card, tooltips; facts only, write your own code), `plan/ui-polish.md`, `plan/ui-layout.md` (title row),
`resources/research/clients/rex-ui.md` (hover card, pane minimap, tooltips),
`docs/content/docs/ui/window.mdx`, `docs/content/docs/talking-to-herdr.mdx` (`pane.read`),
`docs/content/docs/future-work.mdx` (thumbnails stay future work), decision D63.

## Build

1. **When.** The pointer rests 0.25 s on a title-bar tab capsule or a row of the Agents view (not the
   rows of the Agents button's popover, which is itself a hover panel).
   It stays while the pointer moves from the tab into the card (a 0.15 s grace), and goes on exit,
   on a click elsewhere, on a scroll, and with Esc. Only one card at a time. Not while dragging. Uses
   the phase 15 hover-panel modifier.
2. **Where.** Under a capsule (centered, 6 pt below the bar), to the right of an Agents row (6 pt
   from the sidebar edge). Kept inside the window. For an Agents row the card shows that
   row's tab.
3. **Look.** A glass panel (system `glassEffect`, radius 12), at most 280 pt wide (built 280 pt: see Findings), fade and scale in
   from 0.97 over 0.13 s.
4. **Content**, top to bottom:
   - The tab title, the folder part dimmed, and the tab's rolled-up status capsule (phase 15) if any.
   - A minimap of the tab's split tree: the cards as small rounded rects (radius 2, gap 2 pt) in a box
     as wide as the card and 56 pt tall, the keyboard card filled with the accent at 0.5, the others
     with the hover fill. Hidden for a one-pane tab.
   - One row per pane (at most 6, then "+N more"): the program glyph, the program or agent name, the
     folder in secondary text, and on the right the status capsule or the working dots.
   - For a pane that needs you: its last 3 non-empty screen lines, monospaced, secondary, read with
     `pane.read {pane_id, source: "visible", format: "text"}` when the card opens (not before; one
     call per such pane; show nothing if it fails). herdr 0.9.5 has no blocked message, so this is the
     message.
5. **Actions.** A click on a pane row selects the workspace and tab and gives that pane the keyboard.
   A click on the title selects the tab. VoiceOver: the card is a popover with the rows as buttons;
   the tab's accessibility action "Show Panes" opens it.
6. **Tooltips.** `IconButton`'s `.help` and accessibility label carry the action name and its
   shortcut ("New Tab ⌘T"), from the command list: the title-bar buttons (sidebar toggle, machine,
   workspace, ⌘, +), the page header's `+`, the footer's Open Session button and the card header
   buttons. The Agents button has no `.help`: its hover shows the needs-you popover (phase 15).
7. **Docs.** `ui/window.mdx`: a Hover card section. `future-work.mdx`: thumbnails stay, Rex has none
   either. Glossary: hover card.

## e2e

- Hover a capsule of a two-pane tab: the card shows (id `hovercard`) with two rows; click the second
  row: that tab is selected and the second pane's card has the keyboard.
- A blocked pane (helper `pane.report_agent`) shows its screen lines in the card.
- Esc closes the card.
- Hover a row of the Agents view: the card shows that row's tab.
- The `+` button's tooltip (its `help` / `toolTip` attribute) is "New Tab ⌘T".

## Done when

- Screenshots: a hover card for a three-pane tab with a blocked agent; a tooltip.

## Findings

### Deviations

- **Hover panels are drawn at the window's root**, not hung from their trigger. The tab track is a clipping
  `ScrollView` under a fade mask, and the Agents view is a scroll view in a paging scroll view, so a card hung
  from a capsule or a row would be cut off. The phase 15 `hoverPanel` modifier now publishes its open panel as an
  anchor preference (`anchorPreference`), and `hoverPanelHost()` on the window's content draws it with
  `overlayPreferenceValue`, placed by a small `Layout` that keeps it 8 pt inside the window. The Agents button's
  panel uses the same path (`PanelPlace.underTrailing`), so the title row's `zIndex(1)` is gone. One preference
  slot means one panel at a time.
- **Every hover panel fades and scales in** (0.97, 0.13 s, about its own top edge): the transition sits on the
  host, so the Agents button's panel gets it too (Rex fades its popups in about as fast). It goes at once: on
  the way out the host no longer knows its place.
- **The card is always 280 pt wide**, not "at most" (E2E review): narrower cards widened when the screen lines
  came in after the card showed, so the card jumped sideways; a narrow card's minimap was tiny too.
- **"6 pt below the bar"** is 6 pt below the 40 pt title row, so 9 pt below the 34 pt capsule.
- **Esc goes to a text field that edits** (a rename, the sidebar filter) while a panel is open; the panel closes
  either way. Over a terminal Esc only closes the panel, as phase 15's did.
- **The tooltip test reads the button's label, not the help tag** (20-minute rule): macOS shows the tip as an
  `AXHelpTag` whose label, title and value are all empty in XCUITest, and on CI the tag showed in one run of two.
  `IconButton` builds `.help` and the label from one string. The tooltip screenshot is a frame of CI's recording.
- **The title's capsule skips Idle**, like the capsule's own accessibility value: an all-idle tab has no status.
- **A scroll closes a hover panel only outside it**, like a click: the needs-you list scrolls inside its panel.
- **"Zoom" and "Restore" are now "Zoom Pane" and "Restore Pane"** on the card header, the menu items' names, so
  the tooltip reads as the command list does ("Zoom Pane ⇧⌘↩"); "Close" is "Close Pane ⌘W". The ⌘ button says
  "Command Palette ⌘K" (it said "Commands"). The workspace button got `.help("Workspace")` (no shortcut).
- **No popover role.** SwiftUI has no way to give the card AppKit's popover role; it is a contained group labelled
  "Panes of ‹tab›" with the rows as buttons, and the capsule's accessibility action "Show Panes" opens it.

### Decisions

- **`PanelPlace {trigger, panel, offset}`**: the panel's unit point on the trigger's unit point. `under` (a
  capsule: centered, 6 pt below), `beside` (an Agents row: 20 pt right of the row, which is 6 pt past the
  sidebar's edge: the list's 8 pt padding and the 6 pt width handle lie between) and `underTrailing` (the
  Agents button, as before).
- **Shortcuts shared by the menu and the tooltips** are `KeyboardShortcut` statics (`.newTab`, `.palette`, …) in
  `Commands.swift`; `glyphs` draws them as the menu does ("⇧⌘N", "⇧⌘↩"). `IconButton(key:)` appends them to its
  `.help` and accessibility label.
- **`Multiplexer.screen(_:)`** is `pane.read {source: "visible", format: "text"}`; the card keeps the last 3 lines
  that are not blank, read in the card's `.task` (so once per opening, never before), one pane after another.
- **Ids:** `hovercard`, `hovercard.title`, `hovercard.<pane id>` (value: the capsule word, then the screen lines,
  one per line). Rows follow herdr's pane order, which is the minimap's depth-first order.
- **Row name:** the agent's name, else the program's (`programName`), else "terminal". A pane's label is not used:
  the phase asks for the program or agent name.
- **`gap` is `nonisolated`**: the panel `Layout`'s methods are not main-actor isolated.
- **Row VoiceOver label** is "name, folder"; the value carries the capsule word and the screen lines.

### Assumptions

- **Two panels open at once can only happen through VoiceOver** ("Show Panes" while another card is open): the
  preference keeps the last one, both monitors stay until Esc or a click. Not worth shared state.
- **A pane of a tab that never showed reads "terminal"**: the app asks herdr for its program only when its card
  shows (phase 12), so the card has no program name for it yet.

### Learned

- **A view removed under the pointer sends no `onHover(false)`** (spec review): after a row click the panel's
  `overPanel` stayed true, so the next card never closed when the pointer left, and clicks outside did nothing.
  `show(false)` now clears it; the row test hovers the capsule again and leaves.
- **XCUITest relaunches leave the pointer where the last test left it**, which opened a card under it at launch
  (E2E review, seen in a recording). `setUp` now moves the pointer over the strip.
- **Scroll views clip overlays**: the tab track (a `ScrollView` with a mask) and the sidebar's pages would cut off
  any card hung from a capsule or a row; `anchorPreference` + `overlayPreferenceValue` is SwiftUI's portal.
- **Spike (herdr 0.9.5):** `pane.read {source: "visible", format: "text"}` answers
  `{"read": {"text": "…\n", "truncated": false, …}}`; an unknown pane is the `pane_not_found` error.
- **Screenshots:** `/tmp/oriel-shots/19/rough-hover-card.png` (three-pane tab, blocked claude, CI attachment),
  `/tmp/oriel-shots/19/tooltip.png` ("New Tab ⌘T", CI recording frame), `/tmp/oriel-shots/19/agents-row-8.png`.
