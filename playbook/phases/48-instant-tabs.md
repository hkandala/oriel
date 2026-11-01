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
