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

### Lane A2: pane animations (item 3)

3. Split, close and zoom animate (short, about 0.2 s, ease out): a split slides the new card in from its
   side as the others make room; a close shrinks the card away as the others grow; zoom grows the card to
   the full tab and back. The terminal text keeps phase 24's no-blank rule during these (hold the old
   picture, reveal once at the end). Reduce Motion turns them off.

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

## Checks

- `make lint build test` green; a UI test for each item a test can see; the full CI suite green on each
  lane's last code push. One review round per lane (spec and ponytail, read only).

## Findings
