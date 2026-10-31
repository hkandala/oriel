# Phase 46: Thirteenth feedback: chat bubbles and long chats, pane speed, File Explorer and Git

Goal: the fixes from the user's thirteenth round. The chat reads like Messages (blue and gray bubbles), opens long
chats at the bottom without blanks and loads the oldest part on request. Panes never slow the window: browsers
switch without a flash, the overview draws pictures, and web cards join a 20 + 20 memory budget. Swipes go back to
⌥ + two fingers. The five plugin kinds become two plugins: File Explorer (browse, open, back and forward in one
card) and Git (changes, commit, pull and push, the history of every branch, diffs with back and forward).

Design: [Chat view](../../docs/content/docs/ui/chat-view.mdx), [Plugins](../../docs/content/docs/ui/plugins.mdx),
[Browser](../../docs/content/docs/ui/browser.mdx), [Swiping](../../docs/content/docs/ui/swiping.mdx),
[Window](../../docs/content/docs/ui/window.mdx). The user's words are quoted; the decisions under them are the
orchestrator's. Where this file and a design page disagree, this file wins (the docs pass updates the page).

## Track A: the chat (items 1–10)

Files: `Oriel/Chat/**`, the chat's tests. Owner of the card header's state capsule (item 10).

1. **Reply box height.** "let's reduce chat view max input length from 10 to 5, i am referring to prompt input".
   The reply box grows to 5 lines, then scrolls.
2. **Scroll to bottom.** "clicking scroll to bottom button is not taking fully down, like there is some one or two
   line space left". The button lands on the true end: the last row's bottom edge sits at the bottom padding of
   item 7, the same place a freshly opened chat sits. Find why it stops short (likely an estimated row height or
   the reply box's inset) and fix it there.
3. **Bubbles as in Messages.** "in chat view can we show agent messages as well in a bubble but in grey, use exact
   colors used in imessage for sender and receiver, tool calls and stuff should stay as is". The user's message:
   the Messages blue bubble with white text, on the right. The agent's reply text: the Messages gray bubble with
   the label color, on the left. Use the colors macOS Messages draws, light and dark (look them up and check them
   against a Messages window; they go in `Look` in `Style.swift`). The summary line, tool rows, Working and Worked
   stay outside the bubbles, as now.
   ```
   before                                  after
                   ┌─────────────────┐                     ┌─────────────────┐
                   │ fix the test    │ accent             │ fix the test    │ Messages blue, white text
                   └─────────────────┘                     └─────────────────┘
   Ran 3 commands >                        Ran 3 commands >
   Done. The test passes now.              ┌──────────────────────────────┐
                                           │ Done. The test passes now.   │ Messages gray
                                           └──────────────────────────────┘
   ```
4. **Send in an empty chat.** "chat starting view can be improved, let's not grey out the send button at least,
   send button shouldn't work but at least let's not grery it out". Send is always drawn in the accent; with an
   empty box a click does nothing.
5. **Room inside the reply box.** "let's increase inner padding of input box a bit? make sure to align content as
   well accordingly, basically content text and input text should be aligned on left and right like now even after
   increasing inner padding". About 4 pt more padding on each side inside the box; the box grows outward so its
   text keeps the same left and right edges as the chat's text above.
6. **The Show button.** "so the show: replies dropdown, let's change it look like liquid glass button simlar to
   chat and tui button, on click it should show dropdwon, remove show: text, change the dropdown options to like
   replies only, activity, everything". `Show: Replies ⌄` becomes a glass pill like Chat | TUI that reads the
   current choice (`Replies only ⌄`); a click opens the menu: Replies only, Activity, Everything.
7. **Room above the reply box.** "let's also add some padding at the end basically between input and last
   content". About 16 pt more space between the last row and the reply box, at rest and after item 2's button.
8. **Long chats open right.** "scrolling is better now but i still see sometimes content being blank especially
   when loading huge transcripts and it positions itself in different scroll positions and i have to scroll a bit
   for it to align, try to cleanup and improve the way we render content so these edge cases can be avoided". A
   long chat opens drawn, at the bottom, and stays put; no blank screen, no drift that needs a scroll. Measure on
   the biggest transcripts on this Mac (read only), find each cause, fix it there, and simplify the rendering
   where it removes a case.
9. **Huge chats and splits.** "when split is done with huge transcript in chat view, rerender sometimes flickers,
   see if we can improve that, see overall how the content rendering and scrolling and everything can be improved
   with very huge transcripts, its okay as an option we can limit how much we load and show an option like load
   more if that improves performance". The chat shows the newest turns (a few hundred rows; pick the number from
   the measurements) and a **Show Earlier** row at the top that loads the next block above without moving what is
   in view. A split or resize redraws without a flicker and keeps the place.
10. **The state capsule.** "can we make sure the status chip is aligned and may be move it to like another line?
    check t3code how they do it overall we can replicate their style". Study t3code's thread header and status
    (github.com/pingdotgg/t3code, read only). Align the capsule with the title's baseline or move it to row 2 (or
    a row of its own) as t3code does, in its style. Send the orchestrator a rough dark screenshot before polish.

## Track B: panes, speed and memory (items 11–15)

Files: `Oriel/Terminal/PaneViewRegistry.swift`, `Oriel/Browser/**`, the overview, the strip's scroll and card
mounting, the bench harness. `WebCard.swift` belongs to track D; ask it for any hook you need there.

11. **Browser flash on a switch.** "browser works good now, no issues, only thing is when i switch between
    workspaces or tabs, browser content has a bit of flash and then content settles, its very minor flicker and
    very few ms, see if we can improve and keep it more snappy". Switching to a tab with a kept browser shows its
    page in the first frame. Find the frame that differs (record it) and fix the cause.
12. **Scrolling to a tab that is still loading.** "and especially with browser if content is not loaded yet and we
    scroll to that tab, that scroll is very janky". The strip scrolls at full frame rate while a browser on the way
    is created or loads; heavy work waits until the scroll ends or runs off the main thread.
13. **No shell behind a new browser.** "and when i open browser and enter an url , there is a brief time few ms
    where i see the shell behind, let's make sure to not show that". From the URL's Return to the page, the pane
    shows the browser card (its background or the old picture), never the terminal.
14. **Panes drawn on their own.** "any pane contents like brwoser pane loading or chat view loading affects our
    window scrolling or pane switching etc, is there a way to separate these rendering processes, i mean like
    whatever the pane contents, that should not impact frame rate of overall app like tabs workspaces etc, pane
    should be independently rendered you know, that way we can avoid many of janky scrolls etc, think about it, i
    am not 100% sure if its possible, but investigate this approach, also this same thing applies to overview view
    as well where we shown screenshots of all panes, if those pane contents are rendered individually and overview
    just shows them like images, that takes the load?". First a spike (at most 2 hours): measure what blocks the
    main thread while the strip scrolls past a loading browser or chat, a switch, and the overview (signposts,
    `sample`); list what already draws off the main thread (WebKit's web process, Ghostty's renderer) and what
    does not (SwiftUI layout of the whole window, `WKWebView` creation, chat layout). Report the options with
    their costs to the orchestrator (for example: a hosting view per card so a card's updates do not lay out the
    window, heavy work off the main thread, out-of-process drawing through XPC and IOSurface) before building
    anything large. Decided now: the **overview draws pictures**, not live views: each tile shows the card's last
    picture, taken when the overview opens for the cards in view and kept from the card's last show for the rest.
15. **20 + 20 now.** "let's increase that 20+20 thing now itself, and also i want to understand what happens if
    the limit is even higher, i mean is there a way to keep even higher limit as long as free ram is there and use
    it? i mean mac can ask to cleanup if needed, is that possible, i am just curious why we need to limit ourselves
    to 20+20". As in the proposed design ([Plugins, memory](../../docs/content/docs/future-work/plugins/index.mdx)):
    the shown tab's cards plus the 20 most recently shown terminals (spare 16 → 20) and the 20 most recently shown
    web cards (plugins and browsers). A dropped web card keeps its last picture and comes back from its label when
    shown. Floating windows and cards with unsaved edits are never dropped. Defaults `spareTerminals` and
    `spareWebCards` set the numbers. On a memory-pressure warning (`DispatchSource.makeMemoryPressureSource`) drop
    the kept ones beyond the shown tab down to half. Measure with the bench harness (branch `bench-web`:
    `scripts/bench.sh`, `scripts/bench-sample.swift`, `BenchTests`): with 20 + 20 kept plus a shown tab, the
    overview (time to open, frames, CPU, memory while open) and the app at rest and in use (CPU, memory, processes,
    threads, wake-ups), before and after; then once at 40 + 40 to answer the user's question with numbers.

## Track C: swipes (item 16)

Small fix, straight to main. Files: the strip's gesture code, `swiping.mdx` (this track updates it).

16. **⌥ + two fingers again.** "let's remove three finger swipes and go back to option plus two finger scroll,
    three finger swipe is very unreliable and doesn't work many times". Remove the three-finger `NSTouch` reading
    and bring back the earlier ⌥ + two-finger scroll (git history of phase 41 has it). Delete the code, the
    settings text and the tests that only served three fingers.

## Track D: File Explorer (items 17–19, 21, 23–28, 31)

Files: `Oriel/Plugins/**` except `Oriel/Plugins/Diff/**`, `web/src/{file,files,markdown,preview}*`, `web/src/lib/**`,
`Oriel/Store/Chooser.swift` rows. Owner of `PluginKind`, labels, `WebCard.swift`, Open With and the open gestures.
Its first commit is the rename of the kinds (`explorer`, `git`; old label words still parse), merged early so
track E rebases on it.

17. **One File Explorer.** "on the other plugins we shipped, i think we should merge all these into one plugin
    except changes one, and have back and forward buttons, what i mean is once i open file explorer (btw let's call
    it file explorer not files), i can double click to open a file and it should open in same pane and then use
    back button to go back similar to browser back and forward buttons. this way we can basically explore and open
    any files within one pane, and on right clikc we should have options like open in new tab and open in beside
    pane or some better wording which basically opens the file as a new pane in new tab or pane beside the current
    one". File, Preview, Markdown and Files become one kind, **File Explorer** (chooser row and commands say File
    Explorer). Its home is the tree; a double-click (or Return) on a file shows the file in the same card, with
    the File, Preview or Markdown view by its name as today. Back and Forward (`chevron.left`, `chevron.right`,
    ⌘[ and ⌘]) on the left of row 2 walk the card's history, as a browser does (the web view's own history is
    the simplest fit). The label follows the current place so a reload or a dropped card comes back there. The
    context menu on a file: **Open in New Tab** and **Open to the Side**.
18. **Move around inside.** "we should be able to change location of file explorer, right now i have to exit file
    explorer pane and change locaiton in terminal and then open, we should have an option to change dirs within
    explorer. and similarly we should be able to open file explorer from any file preview, basically think through
    and integrate all these such that these plugins are well integrated and make them as one file explorer plugin
    and one changes plugin". Row 2 of the home shows the root as a path control: a click lists the parent folders
    and **Choose Folder…** (a folder field on a remote machine); a folder's context menu has **Open as Root**. A
    file view has a button that goes to the tree with the file revealed (Back returns).
19. **The tree loads blank.** "file explorer plugin takes some tiem to load the tree, and it stays blank, either
    add a loader or improve performance of loading it". Measure the load; make the first listing show fast, and
    show the app's loader until the first rows draw.
21. **Open gestures.** "also by default cmd+click should open in new tab, and option + click should open in beside
    pane". Everywhere a plugin card opens a file or a diff (explorer, Git, a ⌘-click on a diff line): ⌘-click opens
    in a new tab beside the card's tab (today's linked open), ⌥-click opens in a pane to the side of the card. The
    plain click or double-click stays in the card. Track E uses the same code.
23. **A modern tree.** "update file explorer ui especially arrows and stuff much more modern and fit to our ui
    design". Disclosure chevrons, folder and file symbols, row height, hover and selection in the app's style
    (SF Symbols look, `Look` colors), as in Finder's list or Xcode's navigator on macOS 26.
24. **Open With in Markdown.** "in markdown plugin the open with should show to the right and should have app icons
    similar to other ADEs how they show". Open With sits at the right end of row 2, as a button with the default
    app's icon and a menu listing each app with its icon (`NSWorkspace` icons sent to the page or drawn
    natively).
25. **Room above Markdown.** "for markdown pane add some padding top to content basically buttons and markdown
    content are bit too close". About 12 pt more between row 2 and the rendered text.
26. **App icons in File.** "open with app icons apply for regular file editor as well". The same Open With in the
    File view (and Preview).
27. **The dirty dot.** "that dirty changes dot icon can be improved, somehow it feels bit off". Redraw it the macOS
    way: the dot sits vertically centered on the title's x-height, 7 pt, in the label color at secondary, with a
    "Edited" tooltip; check it next to the title in light and dark.
28. **The wrong tab shows.** "with multiple plugins, somtimes the tabs i selected and tab content being shown is
    sometimes different, this happens occaionaly but does happen, like in file explorer if i open using double
    click multiple files, instead focusing on the latest double clicked file, it focuses on different tab". Repro
    with several quick ⌘-click opens (the new-tab path); the newest open wins, and the selected tab and the shown
    card always agree. Find the race (likely two `layout.apply` + `tab.move` replies landing out of order) and fix
    the cause, with a test that fails on the old code.
31. **One look, also floating.** "overall take a relook at all these plugins and revamp the ui making minor fixes
    such that they fit to overall app design better and look consistent, also verify they look correct in the
    floating panes as well, there are some inconsistencies in flaoting panel, like file explorer has filter not
    aligned well in floating pane, and markdown controls are aligned center in floating pane, do a full review and
    fix everything". Review every File Explorer view in a pane and in a floating window, light and dark; row 2's
    controls start at the left edge in both (the filter aligned, Markdown's controls not centered). Send the
    orchestrator rough dark screenshots of the home and a file view before polish.

## Track E: Git (items 20, 22, 29, 30, 31)

Files: `Oriel/Plugins/Diff/**`, `web/src/diff*`, the new Git pages. Uses track D's kind, open gestures and back and
forward; ask track D for any change in its files.

20. **A Git view that fits.** "the ui of git view is pretty bad, it doesn't fit to our overall design well". The
    Git plugin's home is drawn in the app's style: rows like the sidebar's, SF Symbols, `Look` colors, the app's
    fonts, generous padding.
22. **Every branch.** "in the git view i am not seeing other branches for some reason". The history shows all
    branches (`git log --all`), with branch and tag names on their commits, HEAD marked.
29. **One Git plugin.** "in the file explorer git view, i should have options for basic git commands like pull,
    push, commit etc, something like vs codes git view. actually you know what let's merge git plugin to changes,
    so we have two plugins one for file explorer and git which has options to do basic git commands, shows pending
    changes etc, show entire git tree and clicking on any commit should open diff view with back and forward
    options again similar to file explorer, and from any dedicated diff view we should be able to go back to its
    home showing full git history, so we can remove the commit selection dropdown in diff view, so it essentially
    one git plugin with being able to open any diff and go back and forward". Changes becomes **Git**. Home, top
    to bottom: the branch (a menu to switch branch) with Fetch, Pull and Push; a commit message field with
    **Commit**; the changes, staged and unstaged, each file with Stage or Unstage (and Stage All); then the history
    graph of every branch. A click on a change opens the Uncommitted diff at that file in the card; a click on a
    commit opens its diff in the card. Back and Forward as in track D; the diff view's source pop-up goes. git runs
    on the card's machine with `GIT_TERMINAL_PROMPT=0`; a failure shows git's message in the card's toast. The
    File Explorer drops its Git section (its tree keeps the letters).
30. **No glass on the file header.** "in the diff view, there is some weird glass effect on file header, let's
    remove that, it doesn't look good". The sticky file header is opaque (the card's background), no blur.
31. **One look, also floating.** As in track D, for the Git home and the diff view, in a pane and floating, light
    and dark. Send the orchestrator rough dark screenshots of the home before polish.

## Track F: the window's graph (item 14 follow-up)

Files: `Oriel/Views/HoverCard.swift`, `Oriel/App/Commands.swift`, `Oriel/App/CommandList.swift`, the registry and
`Oriel/Terminal/WebCards.swift`. Option B of track B's spike, each change measured with the same sample before and
after (Release, `sample` over tab clicks, three swipes and two overview opens).

32. **The hover panel's preference.** Replace `OpenPanelKey`, which every trigger wrote, with observed state.
33. **The menu bar's lists.** Stop making every command twice per change.
34. **Neighbors made ahead.** Make the selected tab's neighbors' web cards when idle, within the 20 bound.
35. **The chooser test on this Mac.** `testSplitShowsTheChooserArrowsMoveAndEscGivesATerminal` fails only locally
    (the pane not hittable after the tab click): find why.

## Findings

### Track B

- **Cause, item 11.** WebKit paints only what shows: a page scrolled back into the strip's view, or put back into a
  window when the lazy strip had dropped its page, drew blank for one to six frames (60 fps recordings of the window
  with clicks on far tabs: blank frames in two of three runs on the old code). **Fix:** a web card takes its picture
  (`takeSnapshot`, about 8 ms in WebKit's process, also out of a window) as it leaves view, and shows it over the page
  as it comes back, until WebKit's next presentation update after its visible rect changed (SPI, else 100 ms; 2 s at
  most). No blank frame in the runs after. The web view also keeps its size when a new host adopts it.
- **Cause, item 13.** The chooser's "Opening Browser…" loader went when herdr's close returned, about 150 ms before the
  snapshot that puts the new pane in the old one's place: the old pane's shell showed (recorded). **Fix:** a
  successful replace keeps the chooser until that snapshot.
- **Cause, item 12, and the spike (item 14).** `sample` of a Release build: a page that came into view mid-swipe made
  its browser's web view in that frame (WKWebView plus WebKit's process attach, about 40 ms on the main thread), and
  pane labels were parsed with a Swift Regex at every render (87 ms while the overview opened, 198 ms over three
  swipes). The rest of the main thread is SwiftUI's one graph for the window (update, layout, preferences). **Fix:**
  web cards are made where the strip rests (a fingers' drag sets the strip moving: its scroll phase stays idle); the
  label is parsed by hand. Web cards are made only in the selected tab: a neighbor page the lazy strip lays out shows
  their last picture, and a card past the bound is not made again there (it looped: dropped, made, dropped). Options
  B–D went to the orchestrator (B is track F).
- **Item 14, decided part.** Overview tiles are pictures: a terminal's snapshot (one with none streams until it drew,
  then lets go), a web card's picture, a chat's picture from the window's layers at its place as it leaves view
  (`cacheDisplay` drew SwiftUI's content blank; rendering the window's root layer took 120 ms, the deepest layer that
  holds the chat's rows under 1 ms, without the reply box). Taken as the overview opens for the cards in view. A tile no longer
  takes a web view from its card. The zoom to the page stays live.
- **Runs, item 15** (CI's 1x VM, `testKeptCardsCost` / `testManyKeptCardsCost`, before = main with the same
  `-spareTerminals`, which kept every web card). 20 + 20 at rest: the app 221 → 211 MB, WebKit's 22 processes 615 →
  663 MB, all 50 processes 925 → 963 MB, CPU 1.7 → 1.3 %, 184 → 182 threads, 17 → 16 wake-ups a second; in use
  (a switch every 0.5 s) 44 → 49 % CPU, switches median 296 → 288 ms; overview open 327 → 205 ms. 40 + 40 at rest:
  89 processes 1683–1701 → 1731–1739 MB, CPU 1.9–3.0 → 2.0–3.1 %, 327–330 → 323–325 threads, 32 wake-ups a second;
  switches median 409–448 → 437–484 ms (a first run's 2× was the VM: a second pair gave 448 vs 437). So each kept web
  card costs about 28 MB (its WebKit process), a kept terminal about 7 MB of herdr run plus its surface; neither costs
  CPU at rest. A higher bound works as long as memory does: the pressure source drops to half when macOS warns.
- **Runs, the pictures** (this Mac, Retina, Release, 20 browser tabs over 4 workspaces each shown once, then at rest):
  all of the app's processes 693 MB on main, 1275 MB with pictures at pixel size, 833 MB at 1x (the app 303 → 406 →
  328 MB, WebKit's 345 → 827 → 460 MB: a snapshot costs in WebKit's process too). **Decision:** every picture is
  taken at 1x (6 MB for a full-window card, not 24): a cover shows a few frames, a tile is scaled down. One cap over
  all pictures in the app, 200 MB, the least recently taken out first (a card with none shows its loader).
- **Decisions.** Pictures are not purgeable (macOS takes volatile surfaces back within seconds). `Page.shownTerminals` now holds web cards' panes
  too, so a switch between two browser tabs reaches the registry, and Oriel's `mark` writes cover them as floats did.
  Web cards' views get `renewGState` 50 ms after a show, so WebKit learns where the strip put them.
- **Item 28: not reproduced.** Track D's CI recording shows a File Explorer card and a file card beside it blank for
  good after a jump to a new tab two pages away, the tree's accessibility frame one strip page left of its card: WebKit
  painted where it thought the page was. Three tests of that path (a page moved along the strip while out of view, a
  browser and an explorer two pages away, shown by key as they come) passed on the old code locally and on CI, so
  none was kept. What changed on that path: web cards are made only in the selected tab once the strip rests, a new
  host fits a web view at once, and a web card coming into view is told its place (`renewGState`, which WebKit uses to
  read its frames again). None of these is proven to be the cause: watch for it.
- **For the user.** Switch between tabs with browsers and File Explorer cards: no blank flash. Pick Browser in a new
  pane: no shell shows. Swipe across tabs whose browsers never showed: smooth, the card fills in where it rests. The
  overview opens with pictures, not live content; a chat's tile is its picture from its last show.

### Track C

- **Fix:** the three-finger reading is gone: the `.gesture` monitor, `ThreeFingers` and its check script, and the
  window frame view's indirect touches. ⌥ + two-finger scroll is back in `SwipeRouter` as phase 30 had it: ⌥ held as
  the gesture begins sends a sideways swipe anywhere to the window's sidebar pages (one session step with no
  sidebar: hidden, the overview, a floating window does nothing), and up or down one row step; a ⌥ wheel burst steps
  once. The gesture and its momentum never reach what is under the pointer.
- **Decisions:** up and down keep phase 31's rows, not phase 30's workspaces: in the Agents view they step the agent
  row, else the workspace. Fingers up (or a wheel turned away) go to the row above whatever the scroll direction
  (`isDirectionInvertedFromDevice`), as the user asked for three fingers. Sideways follows the sidebar's pages, so
  it goes with the scroll direction as a swipe over the sidebar does.
- **Runs:** the restored UI test (sessions both ways, workspaces both ways, a ⌥ wheel, the hidden sidebar) passes
  locally; on the old code its first ⌥ swipe pages the strip and the header stays on session one.
- **For the user:** with natural scrolling off, check that ⌥ + fingers up still goes to the row above.

### Track D

- **Decisions:** the File Explorer's label is the place it shows: a folder's argument ends in `/` (the tree, rooted
  there), a file's picks File, Preview or Markdown by its name (`PluginPage`). Old labels (`file`, `preview`,
  `markdown`, `files`, `diff`) still open. Back and Forward are a stack per card in `Plugin` (not WebKit's history),
  so Git's native rows share it; each move renames the label, and a rename from elsewhere (an agent) is a new place
  in the stack. The tree comes back on Back with the file it opened revealed.
- **Decisions:** ⌘[ ⌘] go Back and Forward over a plugin card only while the card has a place that way; else they
  select a pane as before (a card made from a label has no history). Leaving a file with unsaved edits shows the
  toast "‹name› has unsaved edits." with Discard and **Keep Editing**.
- **Decisions:** ⌥-click (Open to the Side) makes the pane in a new tab and moves it beside the card, as Replace Pane
  does (herdr's split runs no command): the new tab can show for one snapshot. The row menu is a native `NSMenu`
  the page asks for (`menu` report): Open (Open as Root on a folder), Open in New Tab, Open to the Side.
- **Cause (item 19):** the tree waited for git (status, the last 100 commits and their graph) before its first
  listing. **Fix:** the listing first, git's letters after; the Git section is gone (Git has it). Measured on this
  Mac: 0.5 s from the page's load to the first rows (most of it WebKit's process and the module), then the app's
  spinner shows past 150 ms.
- **For the user:** Open With is the default app's icon (a click opens the file in it, its menu lists every app with
  its icon); check it on a file whose default app has no icon.
- **Cause (item 28): not found.** No repro on the new-tab path: the second FilesTests test ⌘-clicks three files one
  at a time from the tree (a burst is no longer possible: each open selects its tab, so the tree leaves the screen)
  and checks after each that the new tab sits right after the card's, is selected and shows its own card. One CI
  run showed a File Explorer page whose web view sat exactly one strip page left of its card (its accessibility
  frame) after a jump to a tab two pages away, its card blank: handed to track B (the strip and `WebHost` are
  theirs) as the likely root of "the content shown is another tab's".
### Track E

- **Cause (22):** the history ran `git log` of HEAD alone, so other branches never showed. It now runs `--all`
  (500 commits, `--decorate=full`), with each branch, remote branch and tag as a capsule on its commit, HEAD's branch
  on the accent and HEAD's dot a ring.
- **Cause (30):** the diff's sticky file header was a 6 % tint with `backdrop-filter: blur`. It is now opaque in the
  card's color (`--card`, `Look.cardSolid`) with a hairline under it.
- **Fix (20, 29):** Changes is now **Git**. Its home is a web page (`git.ts`); row 2 stays native: Back and
  Forward, the branch menu (local branches, then remote ones; a pick runs `git switch`, `--track` for a remote one),
  Fetch, Pull with the commits behind, Push with the commits ahead. The page has the message and Commit (staged
  changes only; on the accent when it can commit; ⌘↩), Staged Changes and Changes with Stage, Unstage, Stage All and
  Unstage All, then the history. A click opens the diff in the card, ⌘ in a new tab, ⌥ to the side; a right click
  shows the app's menu. The diff lost its source pop-up and got Git Home (`house`). git's writes run one at a time
  through `Exec` with `GIT_TERMINAL_PROMPT=0`; a failure shows git's message in the toast (Copy, OK).
- **Decisions:** Commit needs staged files (no "stage all and commit"). Pull is plain `git pull`, so the user's
  `pull.rebase` rules; diverged branches with no setting fail with git's own message. Push on a branch with no
  upstream runs `-c push.autoSetupRemote=true push` (git 2.37 or later), which publishes it under its name. No
  Discard (it loses work). The page's SF Symbols come from the app as PNG masks, so the rows draw real symbols in
  the text's color. The diff's file list uses the home's row style.
- **Decisions:** `Look.cardSolid` is exact in Classic; in Glass it is measured on a card (dark `#2E`, light `#F9`),
  so an unusual wallpaper moves the card a few steps off the header, and the keyboard card is a step brighter.
- **Cause (review):** a root whose last word was short hex (`Project 2`) read as a commit (a hash now needs 7 hex
  digits); Stage passed paths as pathspecs, so `a*` staged `ab` too (`--literal-pathspecs`); `--all` drew the stash
  and notes (now `--branches --remotes --tags HEAD`); the page lost a typed message at each move (the app keeps the
  draft); Back came to the home's top (it lands at the change or commit it opened).
- **Runs:** the Git UI test (stage, unstage, commit, push, every branch, back and forward, the diff's controls, a
  refused switch's toast, the switch) is green in a chosen-tests CI run; its first runs found the push count that
  XCUITest cannot read as a button's value (now in the label) and the diff checks on a diff with no far change.
- **For the user:** try Pull and Push on a real remote with SSH keys (a key with a passphrase and no agent fails
  with ssh's message, since nothing can prompt), commit hooks and signing, and the branch menu with many branches.

### Track A

- **Measured** on the biggest transcript on this Mac (a 108 MB pi session, 3,850 entries, 936 rows at Replies only),
  opened in a dev build with a scroll-geometry log, a display-link frame log (120 Hz) and screenshots, on a Mac at a
  load of 30–120: the history arrives 1.1–4.5 s after the open.
- **Cause, a loading chat slowed the window (item 14's words).** The backlog was parsed on the main actor
  (JSONSerialization, half the main thread's samples while it loaded). **Fix:** the backlog is read in a detached
  task, a run of lines at a time, the parser's state handed over and back (pi's `/tree` waits for it); OpenCode's
  first load and per-event rebuild too. While the 108 MB session loads, frames stay at 8.3 ms (p95 8.4); one frame of
  150 ms when the rows first lay out.
- **Cause, blank after a split (items 8, 9).** The lazy stack guessed the height of the rows it had not built: on a
  split its content height swung between 14,000 and 59,000 pt within 150 ms, and the chat stayed blank (5 s and on)
  until something else changed. **Fix:** the rows are a plain `VStack` of the newest 40 (about 10 turns), so every
  height is real: open, split and Scroll to Bottom land exactly. After a new width (or Show Earlier) the row at the top
  is scrolled back to the top. The width already holds during a split's motion, so the rows lay out once at its end:
  split and close p95 8.4 ms (phase 45's lazy stack: 2–11 ms), worst frame 40–50 ms; with 100 rows it was 110–160 ms
  (and 680 ms at the open), so the block is 40. At Everything an open run counts its steps toward it.
- **Cause, blank above the messages and drift (item 8).** The scroll view was made while the history was empty; its
  bottom anchor held the empty content down with an 841 pt top inset, and the inset stayed after the long history
  came, until the next change. **Fix:** the empty chat (its glyph, or a loader while a history loads) has no scroll
  view; the scroll view is made with the rows, at the bottom.
- **Cause, Scroll to Bottom short (item 2).** It scrolled to a marker above the bottom padding, through the lazy
  stack's guessed heights. **Fix:** the end is the stack's last row, holding the room above the reply box (item 7,
  32 pt), in a stack with real heights.
- **Decisions.** Show Earlier is a glass pill over the messages' top, shown at the very top, as Scroll to Bottom is
  at the bottom; a block starts at a user's message near its cut. Once the chat leaves the bottom the block stays put
  (new rows do not take rows from its top); back at the bottom, or on a level change, it is the newest 40 again.
  Restoring the place snaps the top row's top to the top, so the stack has no top padding while earlier rows exist.
  The dark gray bubble is #3B3B3D (ChatKit's catalog has only the light gray, #E5E5EA).
- **Cause, review and CI.** The loader turned on when the follow started, but Claude Code and pi write their
  transcript only with the first message: a new chat showed a spinner, not its glyph; it now turns on when the file
  opens. And a message on its way was confirmed only by the history's last entry: a burst that brought the user's
  message with the reply after it left it Not sent; any new entry confirms it now.
- **For the user.** Open a long chat: the loader, then the newest messages at the bottom, while the window stays
  smooth. Split beside it and close the split: no blank, at most one short hitch at the end. Scroll up to Show Earlier
  and click it: the messages in view stay.

### Track F

- **Runs** (Release, `sample` of the same pass on this Mac; before → after, main-thread ms): the hover panel's
  preference reduction 99–155 → 0; `CommandList.all` 81–94 → 19–24 and `MenuBar.body` 78–94 → 24–28; making browser
  cards on the pass (`Browser.init`) 61–77 → 8–23. SwiftUI's update and layout of the window's one graph stays most
  of the main thread (2.5 s in the 16 s pass, with `sample` attached): the rest is option C's to win.
- **Cause, item 32.** Each trigger (tab capsules, the Agents button and rows) wrote an anchor preference; SwiftUI
  combined them at every update. **Fix:** the trigger sets the window's `HoverPanels` as it opens and its frame while
  open; only the host observes it. Its frame is kept unobserved: a first version stored it as state and redrew every
  trigger while the tab bar moved.
- **Cause, item 33.** The fingerprint that tells SwiftUI to rebuild the menu bar and the menu itself each made every
  command. **Fix:** the menu bar takes the fingerprint's list.
- **Decisions, item 34.** 0.5 s after a show, while the strip rests and the kept bound has room, the neighbors' web
  cards are made at their size in the page; they count as the least recently shown. A browser loads out of a window
  and takes its picture as it ends, which covers its first frames in a window. A File Explorer or Git card's page
  loads only once shown (its theme starts it), so only its web view is made ahead.
- **Cause, item 35.** On this Mac the window's empty compact toolbar had an accessibility frame over the title row
  (y 33–72, the capsules 39–73): an accessibility hit test at a capsule's center found the toolbar, and only the
  capsule's bottom point found the capsule. XCUITest clicked that point, which missed the button, so the tab never
  selected; CI's screen (no notch) has a lower toolbar. VoiceOver's hit test met the same toolbar. **Fix:** no toolbar
  (`TrafficLights` already places the buttons). The hit test at a capsule's center now finds the capsule; a dark
  screenshot's title row matches pixel for pixel; the chooser test passes on this Mac. Hiding only the toolbar's view
  from accessibility gave the window instead of the capsule (tried, dropped).
- **Review.** One code review, no blocker: neighbors are now made one a turn 0.1 s apart, once per selected tab (a
  herdr snapshot restarted the wait, so with busy agents it never ran), not under the overview, and only with room
  for the cards in view too (else the next switch dropped one never shown); the Agents button is made per session, as
  the tab bar (an open Agents panel held the old session). A 60 fps recording of clicks onto prewarmed browser tabs
  showed no blank frame.
- **Measurement note.** The scroll meter's frame counts were 3–5 a swipe for before and after alike late at night
  (the display was likely asleep): swipe frame rates are not compared here.


### Final review fixes

- 7 (D): `Opening.now` deleted: no caller (the Git home sends `how` from its page).
- 8 (D): `Plugin.go` opens nothing for a path that makes no label, so the next snapshot no longer pulls the card back.
- 15 (D): Markdown's link comment says an http(s) link opens a browser pane in a new tab (⌥ to the side).
- 2 (A): OpenCode's first load shows the loader in the empty chat, as a history file does.
- 10 (A): a backlog read off the main actor stops with its follow (checked every 500 lines); its marks end at the last
  line it read.
- 18 (A): OpenCode reads each event once off the main actor, and again on it only for the events the waits read.
- 6 (B): the cover's SPI path runs only when WebKit answers both selectors, else the 100 ms fallback (an unchecked one
  would crash on a WebKit without it).
- 9 (B): a window that closes drops its own web cards and kept entries at once, with no picture and no trim of other
  windows' kept cards.
- 14 (F): the strip's page inset is one `Strip.inset`; cards made ahead take their area from `Strip.area`.
- 3, 4, 16 (B, F docs): no toolbar (window, platform); neighbors made ahead (browser, window, D46); no phase history in
  the plugin pages.
- 1 (E): Git places end the root in `/` (`<root>/` the home, `<root>/ <source>` a diff); a source counts only after
  `<root>/ `, old `diff` labels keep their last word (`PaneLabel.place`, now in HerdrKit with a test).
- 11 (E): one walker over `git status`'s fields (`Change.entries`) for the tree's letters and the home's two lists.
- 12 (E): a `ponytail:` note on the home's watch (each event reads it all; skip ignored folders if it costs).
- 13 (E): the list rows, titles and symbols live in `web/src/lib/rows.css`, which `git.css` and `diff.css` import.
- 17 (E): the finding names the push the code runs (`-c push.autoSetupRemote=true push`).
