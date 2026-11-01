# Phase 48: Instant tabs

Goal: switching tabs swaps the window's content in one step. The strip that scrolled between tabs, its swipes, its
slides and the overview's zoom are gone, with every workaround and test that only served them. The code that was
complicated by the moving strip is rewritten simpler.

Design: [Window](../../docs/content/docs/ui/window.mdx), [Swiping](../../docs/content/docs/ui/swiping.mdx),
[Layout](../../docs/content/docs/layout.mdx). The user's words are quoted; the decisions under them are the
orchestrator's. This file wins over the design pages; the feature updates them.

## Feature (items 1–6)

1. **No strip.** "actually let's drop animation altogether between tabs, we can add back when needed may be later.
   for now fully remove all code related to it, all hacks or workarounds or tests we included for it, see if certain
   part of code is complicated just because of this rewrite it to make it further simpler, use ponytail to make the
   code clean and simpler and drop all tab animations". The window shows only the selected tab's page. A switch (a
   click on a tab, ⌘1–9, ⌘[ ⌘] or ⌃⇥, the palette, a new tab, a close, an open from a card, the overview) replaces it
   at once: no scroll view, no paging, no slide, no fade.
2. **Swipes.** A sideways two-finger swipe no longer changes tabs: it goes to the content under the pointer, as any
   scroll does. ⌥ + swipe keeps stepping sessions (sideways) and sidebar rows (up and down).
3. **The overview** appears and goes at once, and a tile opens its tab at once: no zoom.
4. **What goes:** the strip's scroll view and paging, the follow of the selected tab after a move (the item 28
   fixes), making web cards only where the strip rests, the strip half of the swipe router, the in-between states,
   the overview zoom and its sidebar fade, and the tests that check only those. Keep what still serves an instant
   switch, and say why in the Findings: the kept views (25 + 25), the overview's pictures, a dropped card's picture, and
   the cover picture over a re-shown web view only if WebKit still draws blank frames on an instant switch (record it
   at 60 fps first). Neighbor web cards made ahead stay only if a measured switch needs them.
5. **Simpler code.** Read every file the strip touched (Strip, TabBar, Page, WindowPages, SwipeRouter, Overview,
   PaneViewRegistry, WebCards, BrowserView, the hosts) with the ponytail-audit eye; delete or rewrite what was there
   only because pages moved.
6. **Measure** before and after on a Release build: tab switch (click to drawn frame) to a terminal tab, a kept browser
   tab and a chat tab; the overview open and a tile open; the main thread over a pass of switches. Put the numbers in
   the Findings.

## Findings

### Feature

- **Removed.** The strip's scroll view and paging (`Strip`, `Paging`, `stripPage`, `stripMoving`, the item 28 follow),
  the router's half that sent sideways gestures and wheels to the strip and the overview, the overview's session
  paging, zoom, fades and their state (`leaving`, `afterOverview`, `overviewSliding`, `Grow`, `Frames`), the pill's
  slide and its records, `Animation.tab`, web cards made only where the strip rests, `renewGState`, the cover
  picture over a re-shown web view, the neighbors' web cards made ahead, `make strip-check` (script, target, CI
  step), and the tests that checked only motion (the strip's and the overview's
  swipes, the zoom's sizes, the pill's place). The window shows `TabPage`, the selected tab's page, a view of its own
  per tab.
- **Decisions (the orchestrator's).** The overview shows only the session in view: ⌥ + swipe, ⌥⌘[ ] and the palette
  step sessions there. The tab bar's pill jumps; its dividers' fade goes. Split and close motion inside a tab, the
  spring-load pulse and the tab drag's slide-apart stay.
- **Decisions (mine).** The page and the pill fall back to the first tab until a snapshot settles the selection. A
  sideways swipe over a browser card is WebKit's back and forward (or the page's own sideways scroll). A terminal
  takes no sideways scroll: herdr's `terminal.scroll` takes only up and down (spiked). The chat's tool detail is one
  scroll view of both axes again (the nested pair was for the strip). `ScrollAnchor` is `PagesAnchor`: it marks only
  the sidebar's pages.
- **Kept, and why.** The kept views (25 + 25): a switch back shows a kept terminal's surface and a kept web card's
  page with no new stream or WebKit process. The overview's pictures: its tiles are still pictures (D70). A dropped
  web card's picture: it shows until the card made again has loaded.
- **Cause (CI, plugins).** A hidden tab's page now leaves the window, and a first responder that leaves its window
  gets no `resignFirstResponder`: a plugin page kept `keyboard: true` out of view and never heard a change when it
  came back. A plugin card now tells its page as it leaves the window. The strip had kept the neighbor page in the
  window, so the keyboard moved by a resign there.
- **Cause (CI, flicker).** After a resize (the sidebar, the window), every hidden tab came back at a new size and
  reflowed in view: `hold()` keeps the old picture until herdr settles, but libghostty already draws at the new size
  during it, so a slow pass showed the old picture, libghostty's reflow and herdr's. **Fix:** the selected
  workspace's hidden tabs' kept terminals take their card's new size once it settles, as Ghostty's hidden tabs do;
  a card shown in a new host fits at once (no motion to wait for). Then a blank first frame showed instead: a swap
  chain made again at a new size can show an empty frame first. **Fix:** a hold keeps a copy of the old picture over
  the surface, which goes with the first picture that has text or a cursor (three empty ones in a row: the screen is
  empty), not with any contents change; no timer.
- **Runs** (Release, `open -n` on this Mac, a 6-tab bench session (terminals, two browsers, a long chat, a split
  with a streaming chat), clicks posted to the HID tap, `-recordLatency`; base 9bcb88b5, after c20af4bd; medians,
  click to the drawn frame): a terminal tab 59 → 45 ms, a kept browser tab 88.5 → 78.5 ms, a chat tab 60 → 48 ms;
  the overview open 52.5 → 52 ms, a tile open 239.5 → 37.5 ms (the 0.18 s zoom is gone); a pass of 20 switches
  0.45 s apart 67 → 51 ms. Main thread over a pass of 18 switches under `sample`: busy 51 % → 21 % of its samples
  (SwiftUI 1729 → 896, Core Animation commits 1769 → 848, AppKit layout 1593 → 763). The cover: 60 fps recordings of
  8 switches to kept browser tabs each, with and without it: no blank frame either way, so it went. Neighbors made
  ahead: the first show of a browser tab took 61 ms with them, 62 ms without, so they went. CI: the touched classes
  green on c20af4bd's code (41288845507, 41288851061, 41289783012, 41289788395, 41290732026).
- **For the user.** Switch tabs every way (click, ⌘1–9, ⇧⌘[ ], ⌃⇥, the palette, the overview's tiles): the page
  changes in one step. Swipe sideways over a wide browser page, a Side by Side diff and a wide Markdown table: they
  scroll; over a narrow browser page the swipe goes back or forward. Hide the sidebar, then switch to a split tab
  with long lines: no reflow on the switch. ⌥ + swipe still steps sessions and rows. In the overview, ⌥⌘] shows the
  next session.
