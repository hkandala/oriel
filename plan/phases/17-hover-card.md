# Phase 17: hover card and tooltips

Goal: Rex's tab "peek": hover a tab to see what runs in it, and click a pane there to go to it. Plus
tooltips with keycaps on the chrome buttons.

Read first: `plan/ui-polish.md`, `resources/research/clients/rex-ui.md` (hover card, pane minimap,
tooltips), `docs/content/docs/ui/window.mdx`, `docs/content/docs/talking-to-herdr.mdx` (`pane.read`),
`docs/content/docs/future-work.mdx` (thumbnails stay future work).

## Build

1. **When.** The pointer rests 0.25 s on a title-bar capsule, a sidebar tab row or an Activity row.
   It stays while the pointer moves from the tab into the card (a 0.15 s grace), and goes on exit,
   on a click elsewhere, on a scroll, and with Esc. Only one card at a time. Not while dragging.
2. **Where.** Under a capsule (centered, 6 pt below the bar), to the right of a sidebar row (6 pt from
   the sidebar edge). Kept inside the window.
3. **Look.** A glass panel (system `glassEffect`, radius 12), at most 280 pt wide, fade and scale in
   from 0.97 over 0.13 s.
4. **Content**, top to bottom:
   - The tab title, the folder part dimmed, and the tab's rolled-up status capsule (phase 14) if any.
   - A minimap of the tab's split tree: the cards as small rounded rects (radius 2, gap 2 pt) in a box
     as wide as the card and 56 pt tall, the keyboard card filled with the accent at 0.5, the others
     with the hover token. Hidden for a one-pane tab.
   - One row per pane (at most 6, then "+N more"): the program glyph, the program or agent name, the
     folder in secondary text, and on the right the status capsule or the working dots.
   - For a pane that needs you: its last 3 non-empty screen lines, monospaced, secondary, read with
     `pane.read {pane_id, source: "visible", format: "text"}` when the card opens (not before; one
     call per such pane; show nothing if it fails). herdr 0.9.5 has no blocked message, so this is the
     message.
5. **Actions.** A click on a pane row selects the workspace and tab and gives that pane the keyboard.
   A click on the title selects the tab. VoiceOver: the card is a popover with the rows as buttons;
   the tab's accessibility action "Show Panes" opens it.
6. **Tooltips with keycaps.** The title-bar buttons (sidebar, session, eye, ⌘, +) and the card header
   buttons show, after 0.5 s of rest, a small glass label with the action's name and its shortcut as
   keycap chips (for example "New Tab ⌘T"). Fade in 0.13 s. One view (`KeyTip`) used by every
   `IconButton`; it replaces `.help` there, and keeps the accessibility label.
7. **Docs.** `ui/window.mdx`: a Hover card section. `future-work.mdx`: thumbnails stay, Rex has none
   either. Glossary: hover card.

## e2e

- Hover a capsule of a two-pane tab: the card shows (id `hovercard`) with two rows; click the second
  row: that tab is selected and the second pane's card has the keyboard.
- A blocked pane (helper `pane.report_agent`) shows its screen lines in the card.
- Esc closes the card.
- Hover the `+` button: a tooltip with "New Tab" and "⌘T".

## Done when

- Screenshots: a hover card for a three-pane tab with a blocked agent; a tooltip with keycaps.
