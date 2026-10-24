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
