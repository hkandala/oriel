# Phase 51: Fifteenth feedback: our own states, File Explorer and Git polish, palette keycaps, CLI additions

Goal: the fixes from the user's fifteenth round, plus the four CLI items parked after phase 50. The sidebar's
states become Oriel's own (inspired by t3code, not a copy) and line up. File Explorer and Git lose their flickers
and focus steals. Git gets reverts, flat diff headers and file icons. The palette shows keycaps. The `oriel`
command gains `view`, `balance` and opening on Chat.

Design: [Sidebar](../../docs/content/docs/ui/sidebar.mdx), [Chat view](../../docs/content/docs/ui/chat-view.mdx),
[Plugins](../../docs/content/docs/plugins/index.mdx), [Agent control](../../docs/content/docs/agent-control/index.mdx).
The user's words are quoted; the decisions under them are the orchestrator's. Where this file and a design page
disagree, this file wins (each track updates the pages it changes).

The user's screenshots are in `.build/fb51/` (not committed): `1.28.56.png` and `1.31.57.png` (sidebar),
`2.14.11.png` (herdr's TUI), `2.16.48.png` (Markdown checklist), `2.24.58.png` (File Explorer filter).

Tracks push straight to main, each step after its own review and green checks on its exact head
(`make lint build test`, a chosen-tests CI run of the classes it touches).

## Track A: the sidebar's states (items 1–3)

Files: `Oriel/Views/Sidebar*.swift`, `StateLabel`, the Agents view, the card header's state, their tests.

1. **Our own icons.** "so with the new sidebar my concern is it feels like direct copy of t3code, i want it to be
   an inspired one rather than straight away copy, so let's change the icons for statuses to be something
   different and suits better, done icon is fine as is, working icon let's change it". Done keeps
   `checkmark.circle`. Working gets a new symbol that fits Oriel: an animated one (for example SF Symbols'
   `progress.indicator` style or a small spinner of our own, drawn with `symbolEffect`), not t3code's dashed
   circle. Needs you: choose a symbol that is not t3code's `questionmark.bubble` either (for example
   `hand.raised.fill` or `exclamationmark.bubble.fill`). Show the user the three side by side in the Findings
   picture before pushing.
2. **No dot on Done in the Agents view.** "also for done in the agent sidebar view, we show done along with green
   dot indicator on the agent icon, let's remove that dot, done should be good enough, we should show the green dot
   on the tab though". The Agents view's row icon has no state dot; the tab bar keeps its dots.
3. **Two layouts, aligned.** "in the normal workspaces view things are not aligned, before we had dots on left, so
   it used to be aligned better, weirdly here it is different even though this is workspace view as well.
   basically make sure to align the session header with the text well without weird empty spaces or anything, i
   would say in the regular workspaces view just show icons to the left indicating something is working there or
   done there etc, no time need to be shown, when switched to agent view we show the icon and status along with
   time on the right with no dot indicators or anything, if that makes sense, in both cases make sure all text
   alignment is correct". Screenshots `1.28.56.png` (rows with a branch line) and `1.31.57.png` (rows without):
   the session header's text starts further right than the rows' text.
   - Workspaces view: a fixed leading slot for the state icon only (no word, no time), the same width on every
     row, empty when idle; the name, the branch line and the session header's text all start at one x.
   - Agents view: the state icon, word and time at the end of the row; no dots; text aligned with its header.
   - Check both views with and without git rows, light and dark, and with the classic look; measure the x of the
     header's and rows' text in a UI test.

## Track B: the chat (item 4)

Files: `Oriel/Chat/**`, its tests.

4. **Earlier rows stay.** "everything looks much better in the chat view now except one weird bug, so show earlier
   loads more chat messages which works fine, but the moment i reach to full bottom, all the previously loaded
   show earlier messages are gone? why is that? if within a chat view certain messages are loaded by clicking show
   earlier button, keep it as is even if we reach bottom? that's bit of over optimisation". Rows loaded by Show
   Earlier stay until the card closes or the chat starts again. Remove the trim at the bottom and the code that
   only served it.

## Track C: File Explorer (items 5–13)

Files: `plugins/explorer/**`, the header code it needs, the card focus code, its tests. Owner of the focus fixes
(items 12 and 13), which reach into the app.

5. **Focus ring only after a key.** "arrow navigation works now, but i don't want the highlight outline to be
   present as soon as file explorer is opened, it should be shown on any arrow key press, until then no blue
   outline on any folder should be shown, and also the arrows cannot go to the .. folder for some reason, that
   should be fixed as well". The ring shows from the first arrow key on (`:focus-visible` style); ↑ from the first
   row reaches `..`, and Return on it goes up.
6. **Back without a flicker.** "when i have opened few folders nested and opened a particular file, file opens up
   and i use back button to come back, i see for a split sec the folders are collapsed and it flickers and updates
   to show them expanded again. i don't want the flicker, if i have some folder opened state and i go to some file
   preview or anything and i come back it shouldn't flicker and show that previous state directly". The tree's
   first paint after Back already has the open folders (and the scroll position).
7. **Double-click makes root, no expand first.** "and when i double click a folder for a sec i see the folder
   expanding and then it becomes root, i don't want the expand to be visible when i am double clicking".
8. **Caret color.** "within dark mode i see text caret in markdown editor and file editor is black and not visible,
   it should be white caret in dark mode and black caret in light mode".
9. **Markdown lists and headings.** "checklist in markdown view looks pretty bad, they are not aligned well, and
   also for regular headers can we not add underline below them? we should show line only with proper line
   separator like ---". Screenshot `2.16.48.png`: the task boxes sit far right of the heading's left edge and the
   wrapped lines do not line up with the text after the box. Lists start at the text's left edge with a normal
   indent, a task's wrapped lines align with its text, nested lists indent one step. Headings have no rule; only
   `---` draws one. Same in Read and Edit.
10. **Tick tasks in Read.** "and i am also curious if its possible to toggle checkboxes in markdown even in read
    mode? coz it will be easier to click on checkbox to check things instead of switching to edit mode and manually
    adding x to the checklist items". Yes: a click on a task box in Read writes `[x]` or `[ ]` to the file (one
    character, through the card's save, so undo and the dirty state work as for an edit). Read stays read only
    for everything else.
11. **No matching files.** "no matching files text is not aligned to the folder, also why we show .. folder with
    no matching files? let's show some icon and text for no matching files". Screenshot `2.24.58.png`. While the
    filter has text, `..` is hidden. With no match: a centered empty state, an icon and "No matching files".
12. **No focus steal on return.** "actually i just realised file explorer kinda takes focus sometimes even when other
    pane is active and i went to another tab or workspace and i am back again". The tree takes the keyboard only
    when its card has the keyboard (opened by the user into focus, or clicked), never on a tab or workspace
    return.
13. **Git's buttons keep the keyboard.** "one weird bug, when i click fetch button, after fetch is done, it just
    activates the next pane losing focus on the git pane? this happens with pull and push button as well, actually
    i noticed only when the beside pane or below pane is file explorer one". Likely the same steal as item 12 (the
    explorer page focusing itself on a refresh or a files.watch event). Find the cause and fix it once.

## Track D: Git (items 14–21)

Files: `plugins/git/**`, its manifest, its tests.

14. **Flat file headers.** "file headers in diff view is weird, file headers seems separate and doesn't seem linked
    to the diff, let's keep it simple please, no overcomplication there, just a simple flat header should be fine".
    A flat row joined to its diff: no card, no gap, a hairline under it.
15. **File icons.** "in the file names in the sidebar and header, can we see the file icons similar to explorer".
    The same per-type icons as File Explorer, in the diff's file list and its headers. Share the icon set, do not
    copy it (for example both plugins depend on the same icon package, or `@oriel/plugin-api` offers it).
16. **Working Tree with no changes.** "when no changes are there in working tree, show the similar no changes with
    icon view in center, and sidebar should be disabled when no changes in working tree, we should just see no
    changes with icon in center". The home's empty state, centered; the file-list toggle disabled.
17. **Show More.** "in git tree at the bottom show more button is blue in color? that's weird can we keep it like
    regular button, also there is some extra space below that button? why? let's remove that".
18. **Parent without a flicker.** "when i navigate commits using parent button, i see a flicker before i see the diff,
    let's avoid that please, i don't see any flicker when i open a commit from the commit graph though". Find what
    the graph's open does that Parent does not, and use one path.
19. **The live icon.** "why there is enter icon in working tree changes? is it auto refresh icon? let's use better
    icon please, who uses arrow icon for auto reload". A "Live" marker: a small pulsing dot with the word Live (or
    `dot.radiowaves.left.and.right`), not an arrow.
20. **Revert.** "along with stage all, can we have revert icon button beside each file and also revert all".
    Each changed file gets a revert button (`arrow.uturn.backward`) beside stage/unstage; the group gets Revert
    All. Reverting asks first ("Revert changes to a.txt? This cannot be undone." / "Revert all N files?"), then
    runs `git restore --staged --worktree` (and removes untracked files only after naming them in the question).
21. **Not part of this track:** item 13 (Track C owns it).

## Track E: the palette, herdr's TUI, the CLI (items 22–28)

Files: the palette, the placeholder, `Oriel/Agent/**`, `Oriel/Agent/oriel.sh`, the agent-control docs, the `oriel`
skill in pi-hkandala, their tests.

22. **Keycaps in the palette.** "in cmd+k, for hotkeys can we show proper keyboard like icon buttons similar to how
    we show cmd1 etc things in tab on holding command". Each shortcut is drawn with the keycaps the tab bar shows
    while ⌘ is held (one cap per key: ⌘, ⇧, 1).
23. **A roomier palette.** "also in cmd+k can we make it bit spacious, like not too much, but bit more spacious would
    be good, like input can have more padding etc". More padding in the field and a little more row height; keep
    the panel's width.
24. **The browser placeholder shows its address.** "why don't i see path for browser plugin in regular herdr tui?"
    Screenshot `2.14.11.png`: File Explorer and Git placeholders show their argument, Browser ones only "Browser /
    Shown in Oriel". Show the address (short form) as the others do, and keep it current when the page navigates
    if the placeholder can follow the label cheaply; else the address it opened with.
25. **`oriel view`.** `oriel view <pane> chat|tui` switches a chat agent's card, for every window of the session,
    as the header's switch does; `oriel card` adds `"view": "chat"|"tui"`.
26. **`oriel agent` opens on Chat.** The card opens on Chat, as after Relaunch with Chat. Fix the skill's wording.
27. **`oriel plugins --for`** lists the Open With choices too, after the default (they do open it).
28. **`oriel balance [<pane>]`** evens out the splits of that pane's tab (Balance Splits), the caller's tab by
    default.

The `oriel` skill (`~/code/pi-hkandala/skills/oriel/`) gets items 25–28 in the right topic files; push pi-hkandala
master when the Oriel side is on main.

## Track F: dragging over web cards (item 29)

Files: the card drag and drop code (`Oriel/Views/Drag*.swift`, the web card hosts), its tests.

29. **Drop targets over web cards.** "one more bug i noticed with the plugin panes, drag and positioning them is bit
    janky like i don't see the blue hover thing clearly sometimes, it works well on regular terminal panes though".
    While a card is dragged, the blue drop highlight over a browser or plugin card must show and follow the pointer
    as smoothly as over a terminal. Likely cause: the WKWebView takes the drag session itself (it registers for
    dragged types) and the card's drop delegate gets late or no updates. Find the cause (record the drag at 60 fps
    over both kinds) and fix it once for every web card, without breaking drops of files or text into a page where
    that is meant to work (decide and write which).

## Findings

### Track F

- **Cause.** WKWebView overrides AppKit's private `_hitTest:dragTypes:` and claims every drag inside its frame, whatever
  it carries (WebKit's `WebViewImpl::hitTestForDragTypes`, for page drags that put nothing on the pasteboard). A
  card's `onDrop` is a SwiftUI `_PlatformDraggingDestinationView` beside the page, not above it, so AppKit gave the
  drag to the web view, which ignored it: the highlight showed only over the card's header and its 6 pt margin. A
  terminal registers drag types too but does not claim drags it cannot read, so AppKit goes on to the card there.
- **Before / after.** `CardDrop.dropUpdated` counted during one scripted drag (66 moves a second, four legs over the
  page of each web card): a terminal card heard about 2 updates per move; before the fix the browser card heard 1 (on
  its margin) and the plugin card none; after, about 2 per move over both (103 and 77 updates on the same path).
- **Fix.** `BrowserView` (the browser's view, its popups and every plugin card's `WebCardView`) answers
  `_hitTest:dragTypes:` itself: no view for the app's own drag type, WebKit's rule for every other drag. A private
  selector, but the one WebKit itself overrides; if AppKit drops it, both overrides go quiet together.
- **Decisions.** Files, text and links dragged from other apps or pages still go to the page, as in a browser (a page may take
  an upload). Only panes have drop zones on a card, so a tab or a workspace dragged over a web card does nothing, as
  over a terminal. The drop highlight is placed with padding, not an offset, so its accessibility frame is where it is
  drawn (the new test reads it mid-drag).
- **Runs.** The new test with the fix reverted: red twice, on the browser card (no highlight). Its plugin half passed
  there on CI: likely, whether a card's drop target lies in front of or behind its web view depends on the order SwiftUI added
  them (a plugin card relabeled live got it in front on CI, a session opened with it behind locally), which is the
  user's "sometimes". With the fix, the new test and every DragTests test green.
- **For the user.** Drag a pane slowly over a browser page and over a File Explorer or Git card: the half or whole-card
  highlight follows the pointer as over a terminal. Then drop a file from Finder on a page that takes uploads.
