# Phase 52: Sixteenth feedback: clean back and forth, Markdown done right, the sidebar's final design

Goal: the fixes from the user's sixteenth round. Going back in File Explorer and Git restores the page at once,
with no flicker and no scroll jump. Markdown renders every construct correctly. The chat scrolls without jumps.
The sidebar gets the design the user picks from the mockups. New tabs open at the end. The tab pill animations go.

Design: [Sidebar](../../docs/content/docs/ui/sidebar.mdx), [Chat view](../../docs/content/docs/ui/chat-view.mdx),
[Plugins](../../docs/content/docs/plugins/index.mdx), [Browser](../../docs/content/docs/ui/browser.mdx). The user's
words are quoted; the decisions under them are the orchestrator's.

Screenshots in `.build/fb52/` (not committed): `1.08.48.png` (chat tool rows), `1.26.38.png` (Git toast),
`1.31.25.png` (Working Tree header), `1.34.54.png` (Markdown task boxes), `1.41.11.png` (Markdown table),
`1.44.12.png` (Markdown lists), `2.29.45.png` (the tab hover card). Mockups: `~/Downloads/oriel-research/sidebar-mockups.html`.

**Do not start until the user confirms.** The sidebar design is picked: B as in `resources/research/ui/sidebar-mockup-B.html` (Track F). Tracks push straight to main after review and green checks.

## Track A: the chat (items 1–2)

1. **Tool rows as wide as messages.** "tool calls width should be as much as assistant messages and should not take
   up full width". The folded run and its open rows take the agent bubble's maximum width and left edge.
2. **No jump at the end.** "so there is this weird behavior with scroll when we are at the end of the chat, if i
   scroll slowly at the end up or down, chat kinda jumps a bit moving further than i scrolled, is this probably
   because i asked to make sure the scroll till bottom reaches bottom? coz i think i am seeing this only after that,
   let's remove any stupid workarounds added to handle scroll to bottom, and figure out a clean way to scroll to
   bottom with no jumps". Remove every scroll-to-bottom workaround (the position set at the bottom, the kept-row
   pinning, the anchor juggling of phases 46–51) and rebuild the bottom on one mechanism (for example
   `defaultScrollAnchor(.bottom)` plus one `scrollTo` for the button). Record real trackpad scrolls (phases, not
   XCUITest wheels) at 60 fps near the end, before and after: no frame may move further than the fingers.

## Track B: back and forth in plugin pages (items 3–6, 9) — File Explorer and Git

The user: "when i scroll a bit and open some commit, and come back, i see briefly unscrolled version and then it
scroll to previous position, can we not show that switch, and show by default in that position itself? i think both
file explorer and git both has this state problem where when we open something and come back we have bunch of weird
bugs, see if we can make it like a proper page cached or something like some router and coming back should just
restore that dom, instead of doing weird flickers etc, it can also be an overlay on top of the tree and going back i
just removing the overlay, idk, figure out a better option so going back and forth shouldn't feel like we have lot
of flickers and stuff and its clean". And: "there is a good delay before i see the file tree, like i press back
button, it takes noticeable time before i see file tree? why this is so complex? why can't we quickly go back like
we were in one page and go back to previous page? is there a way to cache it or something?"

3. **A page cache in the plugin runtime.** Each place a card visits keeps its DOM (detached, or hidden in place) for
   the last few history entries; Back and Forward show the kept DOM at once with its scroll, and refresh its data
   behind it only if it changed. One mechanism in `web/oriel` for every plugin, not per plugin. Remove the
   restore code it replaces (kept open folders, scroll restore, landing scroll, Parent's read-first path where the
   cache covers it). Measure Back (click to drawn frame) before and after: target under 50 ms.
4. **The first arrow selects the first row.** "when i press down or up arrow, first selection should be on first
   folder, it selects second folder?" The first ↓ selects the first row (`..` when shown, else the first item);
   the first ↑ selects the last.
5. **Empty folder.** "in file explorer if i double click an empty folder, can we show placeholder like its empty
   folder with some icon and text?" A centered folder icon and "This folder is empty".
6. **⌘-click and ⌥-click open in the background.** "cmd + click in file explorer should open tab in background
   without highlighting same with option+tab no highlighting please, like basically i can continuously click
   cmd+click on multiple files and they all open without highlight". The new tab or split opens but the selection
   and the keyboard stay where they are.
9. **Parent without a flicker** is covered by item 3.

## Track C: Git (items 7–8, 10–13)

7. **No Live marker.** "let's remove that live icon please, by default its live that's it".
8. **Toast buttons.** "these buttons in this view has no enough right padding, let's fix that, let's find all such
   similar toasts or confirmations and fix them". Fix the toast's padding at its source so every toast and
   confirmation (Git's reverts, File Explorer's, the app's) gets it.
10. **Gap under Working Tree's header.** "bit more padding between header and file header, it looks fine in regular
    commits, where commit info is there, but in working tree its weird".
11. **Sticky file headers.** "when i scroll quick for diff view, the sticky file header flickers specifically for
    long diffs, can we use proper css or something to handle the sticky file header better and avoid flickers
    please". Use `position: sticky` on the header inside its file's box (no JS repositioning), and find what makes it
    repaint late (virtualized rows replacing the header, a transform, a backdrop filter).
12. **New tabs at the end.** "in diff view when i press open file it opens in a tab beside the current tab, i think
    that sometimes shows a flicker where the tab opens briefly at the end of existing tabs and then it moves to the
    tab beside the git view tab, let's drop that, open file should just open new tab at the end of the tab list and
    show it, let's not complicate it, let's make sure this same logic works anywhere new tab is opened, its just
    opened at the end of the list to keep it simple and avoid flickers". Every new tab (⌘T, Open File, ⌘-click,
    `oriel open --tab`, the chooser, drags to the bar's end) goes at the end; remove the move-after-current code.
    Owner: this track, also in the app.
13. **Not here:** item 9 is Track B's.

## Track D: Markdown done right (items 14–18)

14. **Task boxes.** "the checklist items are not aligned with text vertically, i mean text and checkbox should be at
    same baseline, let's improve the checkbox as well a bit". Box centered on the first line's x-height, a cleaner
    box (thin border, rounded, filled accent with a white check when ticked).
15. **Tables.** "table alignments are bit messed up in markdown view". Screenshot `1.41.11.png`: the first column
    collapses to one letter per line and code cells use a serif monospace. Columns size to content with wrapping only
    when the table is wider than the card; inline code uses the app's monospace.
16. **Lists.** "why lists are a mess in markdown, why are the list items are not aligned well?". Screenshot
    `1.44.12.png`: a list item's continuation lines (soft-wrapped in the source) start at the left edge instead of
    under the item's text.
17. **The whole syntax.** "can you review full markdown syntax and verify and fix all these weird shit". Build one
    fixture covering CommonMark and GFM (headings both styles, emphasis, links of every kind, images, code spans and
    fences, block quotes with nested lists, ordered and unordered lists with continuation lines and nesting, task
    lists, tables with alignment, HTML blocks and inline HTML, footnotes, horizontal rules, hard breaks, entities).
    Read must render each correctly; Edit must look the same except the caret's line. If the CodeMirror live preview
    cannot draw a construct correctly, Read renders that construct (or the whole document) with markdown-it and Edit
    shows it rendered unless the caret is in it. Before/after pictures of the fixture in both modes, light and dark.
18. **No empty outline.** "in markdown if there is no outline to show, don't show the sidebar, right now it opens up
    to an empty sidebar". No headings: the outline toggle is disabled and the sidebar stays closed.

## Track E: the app (items 19–21, 26)

19. **Palette hover.** "in cmd+k when my mouse is in one position hovering on top of cmd+k menu and i scroll using
    mouse, i see that highlighted blue section keeps moving and that's distracting, highlighted blue thing should move
    only when mouse is moved and hovering on certain item, when scrolling it shouldn't follow mouse". Hover selects
    only on a real mouse move, not when rows move under a still pointer.
20. **Address bar searches.** "in browser view if something is typed and that doesn't look like url, it should be
    opened in google search, so address bar acts like regular google search bar as well, so change placeholder to
    similar to chrome: 'Ask Google or type a URL'". Text with a space, or no dot and no scheme and not `localhost`,
    goes to `https://www.google.com/search?q=…`.
21. **No tab pill animations.** "recently we added tab pill animations right showing the tab pill movements on cmd+t
    and cmd+w, can we drop those animations and go back as before, i am not liking them much". Remove the tab motion
    (the transaction, the born views kept for it, the test step) and go back to the instant bar.
26. **`oriel open` of a local file with a query.** Found by the orchestrator: `oriel open browser "/tmp/x.html?v=3"`
    encodes the `?` into the file name (`x.html%3Fv=3`), so the page does not load. A local path keeps its `?query`
    and `#fragment` as the URL's.

## Track F: the sidebar, tab pills and hover card (items 22–25) — design B

The user picked design B and refined it: "okay i like B, but let's improve it a bit more, let's use all t3code icons
for each status, just the icons and color scheme, workspace view is good, in agents view, instead of showing icon
space time, let's wrap them in a box of color same as status color, with icon and time in same status color", then
"i don't like blocked icon, is there anything in red or orange color and circular in shape so all icons are
circular, and in agent view that status thing should take only first line, right now i see it takes up both lines
and then in middle, that's weird as hell, and also in workspace view, tell me the order of status priority, coz
within workspace there can be many agents in different status, we should show needs you first, followed by done and
then working and no status when all idle". Build exactly `resources/research/ui/sidebar-mockup-B.html`:

- **Icons, static, all circular** (lucide shapes drawn as the app's own symbols, like `source.branch`): Working
  `circle-dashed` in blue, Needs you `circle-alert` in orange, Done `circle-check` in emerald. Dark: blue #60a5fa,
  orange #fb923c, emerald #34d399; light: #3b82f6, #ea580c, #10b981. Idle: no icon. No animation anywhere: the
  spinner (`Spinner`) and the working dots (`WorkingDots`) go, with their code.
- **Workspaces view:** no leading slot. The session header's text, the names, the branch lines and "No matching
  workspaces" start at one x. The state icon (16 pt) sits at the row's right end. No word, no time.
- **Agents view:** the program tile on the header's x, the name after it. At the end of the **first line** a box in
  the state color: a 14 % tint, a 1 px border at 45 %, 6 pt corners, the icon and the time in the state color
  (tabular digits). The second line (workspace · program) runs full width under it. Idle: no box, its age in gray.
  Group labels on the header's x. The header stays where it is in the Workspaces view.
- **Priority** (a workspace or a tab with several agents): Needs you, then Done (unseen), then Working; nothing when
  all are idle. This is `AgentState`'s order today; write it in the design pages.

22. **Static icons everywhere.** "in workspace view, we don't need to show any timer or status full text, just an
    icon should be good to indicate things, and any working icon etc let's not have animations please, same with tab
    pill as well, right now in tab pill we show a working dot animation, instead one standard static icon for working
    no animated ones" and "also same status icons should be shown in tab pills as well instead of dots". The tab pill
    loses the dot on its program tile and the working dots; its state icon (12 pt, by the priority above) sits at the
    pill's trailing end, where the close button shows on hover. The card header uses the same icons.
25. **The tab hover card.** "on tab hover we show the same icon with no text, but that icon should be shown only for
    the agent, like in the screenshot you see there are two dones, where there is only one pane, for tab header also
    we show done, let's not show that, only show status beside the pane info". Screenshot `2.29.45.png`. The card's
    title row shows no state; each agent pane's row ends with its state icon only (no word); other panes show none.

23. **Done stays put.** "when the agent is done and the agents view is grouped by status, and its in done status, and
    then i select that agent then the sidebar quickly jumps to idle status as it moves to immediately as we opened it,
    let's not do that jump, when in done and that agent is opened unless that agent is no longer active, don't jump
    and move it to idle, we can remove the done icon on it, but in the groups let's not jump it". A seen Done row
    stays in the Done group (it may lose its icon) until the agent works again or leaves.
24. **One edge.** "session header never changes its position whether its workspace view or agent view, and that
    session header text starting should be aligned for other elements below it". A UI test measures the header's
    text x in both views and the left x of every row's first element and every group label.

## Findings

### Track E

- **Cause, palette hover (19).** A row lit on hover only when the pointer had moved since the panel opened or the keys
  last moved the light. After the first move that held forever, so every row that scrolled under the resting pointer
  took the light. **Fix:** a local monitor takes the pointer's place on each scroll event, before the rows move, so
  only a real move lights a row. Not the last hover's place: a busy app runs hovers late (phase 24).
- **Decisions, address bar (20).** Return searches Google (`https://www.google.com/search?q=…`) for text with a space,
  or with no scheme, no dot and a host that is neither `localhost` nor IPv6. So `localhost:3000`, `example.com` and
  `foo/bar.html` load; `swift actors`, `oriel` and `devbox:3000` search. A typed path (`/tmp/x.html`) does nothing, as
  before. Only the address field searches: labels, links and `oriel open` never do. Placeholder "Ask Google or type a
  URL". Pictures: `/tmp/oriel-shots/t52e/address-before-crop.png` → `address-after-crop.png`.
- **Fix, tab pills (21).** The phase 49 motion is gone in full (`Transaction.tabMotion`, the scale transition,
  `Ahead.born`, FlickerTests' ⇧⌘W step): `git diff c034b5c3^` is empty for the files it touched, except later work.
- **Cause, `oriel open` query (26).** `URL(filePath:)` encodes `?` and `#` into the file name (`x.html%3Fv=3`).
  **Fix:** the path ends at the first `?` or `#`; the rest is appended to the file URL. A file whose name holds `?` or
  `#` opens only as a `file://` URL with them encoded.
- **For the user.** In ⌘K, rest the pointer on a row and scroll with the wheel and the trackpad: the light stays. Type
  `swift actors` and `localhost:3000` in a browser card's address field. Press ⌘T and ⌘W: the bar changes at once.

### Track C

- **Cause, new tabs (12).** A linked open (Git's Open File, ⌘-click in a plugin card) and `oriel open --tab` made the
  tab with `layout.apply`, which herdr adds last, then `tab.move`d it after the card's tab: the snapshot between the
  two showed it at the end. **Fix:** no move; `PanePlace.tab` has no index. ⌘T, links opened in a new tab and drops on
  `+` already went last. The UI tests check the new tab is last once it is selected, with a tab after the card's.
- **Fix, toast (8).** One source for every toast and confirmation: `ToastView`. Its buttons were rounded rectangles
  6 pt from the capsule's right end, so a corner ran into the curve. They are capsules (`buttonBorderShape`) 7 pt from
  the top, bottom and right edge, concentric with the toast. The notice capsule (`NoticeCapsule`, Open Session's and
  the Plugins panel's) draws round buttons too. Pictures: `/tmp/oriel-shots/t52c/toast-before.png` →
  `toast-after.png` (a probe window: inactive, so no accent).
- **Fix, Live (7).** The marker, its manifest control and its line in `main.ts` are gone. Git is 1.5.0.
- **Decisions, gap (10).** The user then asked for the gap in every diff and to keep it while scrolling, with no
  divider in it: the whole diff page (`#diff`) starts 8 pt under row 2, so a file header sticks below the gap and the
  file list's line starts below it; the list's top padding is 3 px, so its title's middle meets the file header's.
  Pictures (the built page in a bare WKWebView with a stand-in bridge, dark): `/tmp/oriel-shots/t52c/wt-before-scroll0.png`
  → `wt-after-scroll0.png`, `wt-{before,after}-scroll700.png`, `commit-{before,after}-scroll{0,700}.png`.
- **Cause, sticky headers (11).** `@pierre/diffs`' CodeView draws only the lines near the view: each file's box holds
  just those lines, inside one container that script moves with `position: sticky` and a top and bottom set at each
  render. A file header is CSS-sticky only inside that box. When a scroll runs past the drawn lines before script
  draws again, the box leaves the view and the header goes with it: whole frames with no header and no lines. Shown in
  the built page in a bare WKWebView with trackpad-phased scrolls (3000 px a frame, recorded with `screencapture -v`):
  4–6 frames with no header in 3 of 4 runs on main, `/tmp/oriel-shots/t52c/sticky-before-frames.png`.
- **Fix (11).** A copy of the top file's header sits under the files' own, in the diff's scroll right after a commit's
  facts, with `position: sticky; top: 0` and no room taken, so the compositor keeps it in place with no script. A scroll
  (`subscribeToScroll`) only changes which file it names. The file's own header covers it whenever drawn, also while the
  next file's header pushes it up, so the look and the push are unchanged; it is inert. After: 0 frames with no header
  in 5 runs (`sticky-after-frames.png`: the lines blank for two frames, the header stays; on the page factories,
  `sticky-after-sheet-{wt,commit}.png`). A file box that spans the whole file would need pierre's other virtualizer and
  a rewrite of the diff page. The real app, a fast swipe over 16 files: the header in all 293 frames
  (`sticky-real-boundary.png`). Git is 1.6.1.
- **For the user.** Flick fast through a long Working Tree diff and back: the file header stays; the lines may be
  blank for a frame or two. Open File and ⌘-click open tabs at the end. A toast (Revert) and a notice (Retry): round
  buttons. A commit's diff: the 8 pt gap under row 2 stays when scrolled, and the file list's line starts below it.

### Track A

- **Fix, item 1.** A run's line and its open rows now take a reply bubble's place: they start 18 pt left of the replies'
  text and stop 48 pt short of the messages' right edge. Their text stays on the replies' edge, and an open call's
  input and output boxes end where the bubbles' widest width ends. Before: the user's `.build/fb52/1.08.48.png`
  (`/tmp/oriel-shots/t52a/tools-before.png`); after: `/tmp/oriel-shots/t52a/tools-after.png` and
  `tools-after-crop.png`.
- **Cause, item 2.** The chat gave the scroll view back the place the scroll view itself reported. With
  `.scrollTargetLayout()`, the scroll view names the row at the top as a scroll begins or ends; that name went into
  the `ScrollPosition` state, and the next body (the Scroll to Bottom button showing, a pin, a hold) handed it back,
  so the scroll view snapped that row to the top: 9–11 pt past the fingers. Phase 51's `scrollTo(id: end)` at the
  bottom added a snap of up to 40 pt as the chat came within the button's 40 pt.
- **Fix, item 2.** The bottom is one modifier, `defaultScrollAnchor(.bottom)`. A spike showed that it already does
  all of it: the chat opens at the bottom; exactly at the bottom it follows new rows and resizes; scrolled up by any
  amount it keeps its offset. Gone: the `held` state and `hold`, the anchor switch for size changes, the scroll to
  the end at the bottom, the Show Earlier offset kept per frame and its pre-pin. The `ScrollPosition` binding now
  drops what the scroll view writes, and the app writes it only for Show Earlier's offset. The oldest row shown is
  pinned as soon as rows show (also when a new chat's first message showed before any row), not when the chat leaves
  the bottom, so a new row never takes a row off the top while the chat is between 1 and 40 pt above the end. Kept:
  the top row put back after a new width while scrolled up, now at any offset above the exact bottom, not only past
  the button's 40 pt.
- **Measured** (real trackpad scrolls posted to the HID system, `scripts/swipe.swift`, 2 pt every 16 ms, the
  offset logged at every frame by a temporary probe): before, 50 pt of fingers moved the chat 61.5 pt (a 9 pt step
  in one frame as the scroll began); after, each scroll near the end moved the fingers' distance plus 1–3.5 pt, all
  of it after the lift (below).
- **Cause, the 1–3.5 pt and the test's helper.** After a lift with no momentum events, AppKit runs its own momentum
  at the last moves' speed, about 9 pt, in every scroll view (a bare SwiftUI probe window did it too). A trackpad
  sends an empty momentum right after a rested lift; `swipe.swift` with a pause now does too, which cuts it to a
  frame or two before that event lands. The new test allows 4 pt for it.
- **Runs.** The new test (slow scrolls up past the button's 40 pt, down past it, and around; the run's edges; a new
  turn while 40 pt up) was red on the old code (61.5 against 50) and is green. The new turn's check is red with no pin
  (the row in view moved 859 pt); the reviewer's case, a pin missed because a new chat's first message showed before any
  row, depends on timing and stayed green without its fix, so its fix stands by its reading.
- **For the user.** In a long chat at the bottom, scroll up and down slowly by a few lines with the trackpad: the
  messages move only as far as the fingers, with no snap as the Scroll to Bottom button shows or hides. Let an agent
  work while scrolled up a few points: what is in view stays put. Open a run of tool calls: its rows end where a long
  reply's bubble ends.
- **Cause, found on CI (full run 41643504903): the split lost its place.** After a new width, the row at the top was
  the first with any part in view, scrolled to the very top. When only its bottom padding showed, that moved the view
  down by most of the row's height (Question 148 came back above Reply 148). **Fix:** the rows report their tops in the
  messages when they lay out; the scroll action keeps the row at the view's top and how far into it the view starts;
  when that row reports a new top (a new width, rows that come above with Show Earlier, a row taken off the top), the
  view goes back to the same point on it. This replaces the visibility list, the scroll targets and Show Earlier's
  height arithmetic. A new content height reads the place from before it, since a wider card's shorter content moves
  the offset to the end in the same update (the reviewer's catch; the test now also widens while scrolled up). The
  block is fixed once the chat leaves the exact bottom, not from the first rows shown: then a slow load pinned the
  block at the first message and laid out all 600 rows (a local run). Only a scroll sets it: an update during a load
  can report the grown rows before the anchor follows.

### Track F

- **Fix (22, 25).** One `StateIcon`: lucide's `circle-dashed`, `circle-alert` and `circle-check` drawn as a SwiftUI
  `Shape` with lucide's own geometry (strokes of 2 in 24, round ends), 12 pt everywhere, in t3code's colors (the
  `Look` tokens). `WorkingDots`, `Spinner`, the tile badges (`StatusBadge`), the `offscreen` environment and
  `Tab.working` are gone. A tab shows one icon by priority at its end, where the × shows on hover; the hover card's
  title shows no state and its agent rows end with the icon alone.
- **Fix (24).** Everything starts 18 pt in, as in the mockup's guide line: the header in both views (it moved 20 pt
  between the views before), the names, the branch lines, the group labels and the tiles. The workspace icon sits
  at the end of the name's line, 8 pt in; the Agents box ends on the same x.
- **Fix (23).** `Seen.seenFinishes`: an idle agent whose finish was seen keeps its place in the Done group (no box,
  its gray age) until it works again or leaves. The Agents popover still lists only unseen finishes.
- **Decisions.** The tab pill keeps its program tile and puts the icon at the trailing end (the phase file, not the
  mockup's leading icon). A shape, not a `.symbolset`: exact sizes and no stroke-to-outline step, and nothing outside
  SwiftUI draws a state. The colors change in `Look`, so the Agents button's dot, warnings, ahead counts and the
  chat's question card follow. The chat's loader takes the still Working icon. A chat's Error is the alert circle in
  red (t3code's Failed). The workspace menu drops its idle ring and no-agent dot. Group labels are 11 pt, the count after
  a dot in the same secondary color ("Working · 2"). The user then asked for smaller workspace icons: 12 pt, not
  the mockup's 16.
- **Pictures.** Before `/tmp/oriel-shots/t52f/before/`, after `/tmp/oriel-shots/t52f/after2/`, side by side in
  `/tmp/oriel-shots/t52f/compare/` (workspaces, agents by priority and by workspace, tab pills, hover card).
- **For the user.** Check the icons at 1x and in light mode (emerald `#10b981` on a light sidebar is faint), and open
  a Done agent from the Agents view by priority: its row stays under Done.

### Track B

- **Cause (3, 9).** File Explorer drew every place anew: Back made a new tree, listed the root, listed the open folders
  again and set the scroll after two frames, so it took one listing per depth. Git's home hid with `display: none`,
  which dropped the body's scroll, so Back showed the home at the top while git read, then jumped to the landing.
- **Fix (3).** One router in the plugin runtime, `oriel.pages.route(draw)` (plugin API 2). Each place draws in a page
  of its own. The card keeps the last five pages, hidden with `inert` (and `visibility: hidden`), so a page keeps its
  layout, scroll, open folders and selection. A page's own `oriel` scopes everything to when it shows: its handlers
  run only then (`theme` and `visible` always), its watches wait while it is hidden and call back once when it shows
  again, and its header controls are recorded and come back with it (the user's changes too). The tab's title comes
  back with the page, a hidden page's media pauses, a page left with unsaved edits is dropped, and all pages share one
  watch of the machine per path (on a remote machine each watch polls). File Explorer and
  Git both draw through it; Git's home and diff became factories per page. Removed: the tree's memory of open folders
  and scroll, the frame waits, the move queue in `main.ts`, Git's hide and clear, the move checks and the control
  dedupe (the runtime dedupes).
- **Numbers.** The built pages in headless Chromium with a stand-in API that waits as the real calls do (a listing
  120 ms, `git.log` 150 ms). File Explorer, Back from a file to a scrolled tree with an open folder, from the place
  event to the first frame that shows the tree as it was left: 318–336 ms before, 10–22 ms after. Git, Back from a
  commit to the scrolled home: 159–163 ms before, with 9–10 frames of the home at the top; 2–4 ms after, with none.
- **Decisions.** A kept tree keeps its filter text and matches: the field shows the text but no longer takes the
  keyboard (FilterField asks for focus only when edited or autofocused; else Back to a filtered tree, or an agent's
  rename back to it, would take the keyboard from the pane in use). Back to a kept tree shows the row of the file it
  came back from and scrolls only when that row is out of view. A kept diff keeps its own Side by Side, Word Wrap and
  file list; a new diff starts with the card's. Back to a kept Git home does not jump to the commit it opened: it is
  where it was left. A place that is not kept still draws while the old page stays (Parent's read-first path stays).
- **Cause (4).** The tree's first row had the keyboard with no ring, so the first ↓ moved past it. **Fix:** with no
  row selected and no ring yet, the first ↓ goes to the first row (`..` when shown) and the first ↑ to the last.
- **Fix (5, 6).** An empty folder shows `folder` and "This folder is empty" in the middle of the card. ⌘-click,
  ⌥-click and the row menu's Open in New Tab and Open to the Side open behind: a new `background` option of
  `oriel.open` (API 2) skips the app's `follow`, so the selected tab and the keyboard stay. Git's Open File (a plain
  click) still selects its new tab.
- **Runs.** 41625748826 was red on the Back test: ⌘] with the filter field's keyboard went to Select Next Pane (the
  test now clicks a row first, and a field shown only for its text no longer takes the keyboard). Green on the
  reviewed code before the rebase: 41625753041, 41628369745, 41628374278.
- **Pictures.** Empty folder: `/tmp/oriel-shots/t52b/empty-folder-before.png` → `empty-folder-after.png`. Git, no look
  change (the same home and diff): `/tmp/oriel-shots/t52b/git-{before,after}-{home,diff}.png`.
- **For the user.** In a File Explorer card, open folders, scroll, open a file, Back and Forward a few times: the tree
  and the file come back at once, where they were. Filter, open a match, Back: the matches are still there and the
  keyboard stays in the tree. In Git, scroll the history, open a commit, Back: no jump. ⌘-click three files: the tabs
  open behind and the tree keeps the keyboard. Play a video in Preview and go Back: it stops.

### Track D

- **Cause, items 15–17.** The live preview drew each source line as its own screen line and styled only some nodes.
  So a soft-wrapped paragraph kept its source breaks (the ragged lists of `1.44.12.png`), a list item's later lines
  started at the left edge, and reference links, footnotes, entities, inline HTML, setext underlines and `1. 1.` showed
  as written. Tables broke their words anywhere: CodeMirror's `overflow-wrap: anywhere` gives every cell a one-letter
  minimum width, and `<code>` fell back to the serif monospace.
- **Fix.** The live preview moves to `live.ts` and stays one CodeMirror view. A paragraph's soft breaks are replaced
  by spaces off the caret's paragraph (a state field, as they cross lines), so text flows; an item's later lines hang
  at its text; numbers count from the list's first; definitions and footnotes come from one field per document change.
  Inline HTML of text elements, `<br>` and entities draw in place; other inline tags show as written. An element opened
  in one HTML block and closed in a later one (`<details>` with Markdown inside) draws as one markdown-it block. Tables
  break a word only when it alone is too wide.
- **Decisions.** Footnotes stay where they are written (a live preview cannot move text): a raised number links to a
  definition shown in smaller secondary text after its number. Front matter still shows (dim YAML). `~sub~` and
  `^sup^` show as written, as on GitHub. Hidden lines (definitions, comments) open with the arrow keys at their edge, as
  tables do. In Edit only the caret's lines are source lines: the rest of their paragraph still flows above and below.
- **Item 14.** The box is drawn by the page (`appearance: none`): 0.95 em, a 1 px border at 40 % text, 0.25 em corners,
  `vertical-align: middle` (the line's x-height center); ticked, the accent with a white check.
- **Item 18.** The outline's toggle is enabled only while the file has a heading; the last heading gone closes it.
- **Review.** A blocker: hides from the view plugin that crossed a line break (a link's address on the next line, a
  tag or comment over two lines) threw in CodeMirror and blanked the card; every hide now stops at each line's end.
  Also fixed: a footnote whose text is an address, tables and HTML blocks in list items, quotes and lists composing
  their indents (CSS variables), the block walk only when the caret's lines change. Round 2: a quote in a list item
  and code in a quote keep their bars and fill, a comment over two lines shows on the caret's line, code inside an HTML
  block draws as one block. Left: a table in a quote draws markdown-it's own quote bar, a few px off the quote's.
- **Pictures** (the built pages in headless Chrome with a stand-in API, before at cdf2568f on the left, after on the
  right, the fixture `resources/research/ui/markdown-syntax.md`): `/tmp/oriel-shots/52d/fixture-{dark,light,edit,
  edit-light}-{0..3}.png`, and phase 51's file (the user's list) `lists-phase51.png`.
- **For the user.** Open a doc with wrapped paragraphs and lists (a phase file), and the fixture; ⌘E into a wrapped
  paragraph and type; tick a box in Read; open a file with no heading and see the outline toggle off.

### Final review fixes

- **Docs pass.** The track pages matched the code. Fixed: the chat's history spinner was also called "the loader",
  the name of the Working row. The talking-to-herdr row said a ⌘-click selects its tab. The glossary had badges and
  no kept page or background open. Features had no background opens and no kept places.
- **Cause, angle-bracket links (Track D).** Lezer's `URL` node holds the `<>` of `[a](<my file.md>)`, and the live
  preview's link took it whole (the old `href()` stripped it), so the link opened `<my file.md>`. **Fix:** `target()`
  strips it for every link. Inline HTML `<code>` and `<samp>` fell back to WebKit's serif Courier: one rule gives every
  code element the app's monospace. Also an image with no alt text links its address, a `<details>` over HTML blocks
  merges inside a list item too, and a cut-off syntax tree no longer closes the outline. The fixture has each.
- **Cause, Show Earlier (Track A).** The scroll position was bound through a closure the body never read, so Show
  Earlier's offset reached the scroll view only because `earlier` changed in the same action. **Fix:** it is read
  into the body as a `.constant` binding, which still drops the scroll view's writes. The bubble's place is one
  modifier (`replyPlace`, `ChatView.gutter`). The end-of-chat test checks the swipe that leaves the bottom too and
  allows 6 pt (3.5 measured).
- **Decisions, the sticky header copy (Track C).** It stays. CodeView turns pierre's virtualization buffers off, so a
  file's box spans only the drawn lines and no option keeps its header in CSS alone. `overscrollSize` only shortens
  the blank frames; pierre's simple `Virtualizer` keeps the buffers but is a rewrite of the diff page. The comment
  names pierre 1.6's container order, which a bump of `@pierre/diffs` must check.
- **Fix, kept pages (Track B).** A move to a page still being drawn kept no landing: the page's place handlers get it
  when it shows. Control records compare by sorted keys, so an equal control is not sent again on each switch. File
  Explorer drops its `keep()` around the scoped handlers and watches, and its editor and Markdown take the keyboard
  only while their page shows.
- **Tests.** The background-open checks read the card's tab once, as the bar showed the new tab, but the app follows
  a moment later: they now wait 0.5 s for a change that must not come. `StateIcon` lost its unused size, and its
  three accessibility copies are one modifier.
- **Runs.** 41636711212, the 16 UI tests of the touched code (the chat's end and Show Earlier, tool rows, the
  palette, state icons, the hover card, Markdown, File Explorer, Git, the browser's new tabs) at 81814ea7: green.
- **Left as nits.** Two chat scroll-geometry observers not merged; Markdown's per-keystroke walks (under their
  `ponytail:` note), a two-line setext heading not joined, `<style>` and `<img>` in HTML blocks (the CSP covers
  scripts); the width asserts stay in the end-of-chat test.
- **For the user.** In File Explorer, open a Markdown file with `[a](<other file.md>)` and inline `<code>`: the link
  opens the file, the code is in the app's monospace.
