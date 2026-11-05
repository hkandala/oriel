# Phase 53: Seventeenth feedback: a Finder-like File Explorer, one file-card header, clean Git diffs, the active pane

Goal: the fixes from the user's seventeenth round:

- File Explorer behaves like Finder.
- Every file card shares one header.
- Markdown gets four modes.
- Git's diff stops flickering and its files get their own boxes.
- The active pane gets a subtle border, and ⌘W works right after ⌘D.
- A workspace with many browser or plugin tabs switches as fast as any other.
- The browser keeps the typed address and takes a click on its empty and error pages.
- Glass stays readable over a bright window.
- The `oriel` skill moves into this repo.

Five research reports (herdr-core, releases with an updater, telemetry, onboarding, the Settings window) are plans only. They change no code.

Design:
- [File Explorer and Git](../../docs/content/docs/plugins/default-plugins.mdx)
- [Window](../../docs/content/docs/ui/window.mdx)
- [Browser](../../docs/content/docs/ui/browser.mdx)
- [Sidebar](../../docs/content/docs/ui/sidebar.mdx)
- [Chat view](../../docs/content/docs/ui/chat-view.mdx)
- [Theme](../../docs/content/docs/ui/theme-and-accessibility.mdx)

The user's words are quoted; the decisions under them are the orchestrator's.

Screenshots in `.build/fb53/` (not committed):

| File | Shows |
|---|---|
| `7.38.18.png` | find and replace in a file card |
| `4.27.56.png` | an image card's absolute path |
| `4.28.58.png` | stray change dots in File Explorer |
| `4.54.31.png`, `crop-4.54.png` | Git's file header over the scroll bar |
| `5.01.55.png` | Git's files merged, with sharp corners |
| `5.12.18.png` | the palette's bottom gap |
| `sticky.mov`, `v/sheet*.png` | the sticky header jumping, 120 fps; the user says it is far worse on screen than in the capture |

**Do not start until the user confirms.** The GUI lock stays with the user until then. Tracks push straight to main
after review and green checks.

## Track A: the chat (item 1)

1. **Every tool in a run.** "in chat view, everything works but for the tool call groups when there are read, write
   or edit calls, i don't see them when you expand those groups, i only see bash, codemode and thoughts, in the tool
   call groups we should see all tool calls including read, write and edit".
   - An opened run lists every step in order: read, write, edit, grep, find, ls, bash, codemode, subagents and
     thoughts.
   - Find where read, write and edit drop out (the parser, the run's fold, the lazy load of opened rows) and fix
     it there.
   - Use a real pi session with all three; this orchestrator's session has hundreds.
   - Check Claude Code, Codex and OpenCode transcripts for the same loss.
   - Add a test with a run that holds each kind.

## Track B: panes and tabs (items 2, 3, 28)

2. **The active pane's border.** "can we add a bright border for the active pane when there are multiple panes? not
   too bright, just subtle bright border to distinctly identify the activated pane, if there is only one pane no
   border should be shown".
   - A 1 pt border inside the active card's rounded edge, only when the tab shows two or more panes.
   - Colour: the label colour at about 30 % in dark and 22 % in light. Tune it by eye against both Looks, glass and
     classic.
   - No border on a single pane, on a floating window, or in the overview.
   - The border does not animate when focus moves.
3. **⌘W right after ⌘D.** "when i hit cmd+d quickly and create multiple panes and then i press cmd+w immediately,
   cmd+w does't work, i have to wait for couple of seconds and then press cmd+w for it to work, i think this is
   probably due to we are waiting for actual herdr pane to be created may be? fix it such that even if it create
   back to back cmd+d and press cmd+w to close it should work".
   - ⌘W always closes the card that has the keyboard, at once, including a split herdr has not answered yet.
   - When herdr's pane for a closed placeholder arrives, Oriel closes it; nothing shows in between.
   - A UI test presses ⌘D three times and ⌘W three times with no waits: one pane is left, with nothing extra after
     herdr settles.
28. **Tab drops without a flicker.** "for tab drag and repositioning, when i leave the tab at a certain position, i
    see some flicker before it settles, may be this is because we are waiting for herdr? let's make it snap into
    position without any flicker".
    - The bar shows the dropped order at once and keeps it until herdr's order matches.
    - No frame shows the old order or the drag's lifted state.
    - Record at 60 fps before and after.

## Track C: the browser (items 4, 5, 31)

4. **Keep the typed address.** "in browser plugin when i open some address which is not reachable or not available
   like localhost ones where nothing running on that port or some unreachable address, address bar changes to show
   the previous url instead of that wrong url, i think we shouold keep it to show whatever url last entered".
   - After a failed load, the field and the error page show the address that failed.
   - Reload tries that address again.
5. **A click anywhere activates.** "when those errro messages are shown on the browser plugin, cannot find url or
   nothing answers on localhost, when i click on the browswe pane it won't get active, i mean if i have multiple
   panes and i am active on other pane, and browser pane already has this error message thing, it won't activate
   browser pane on clicking anywhere on the pane except i click address bar, if a site is loaded then it works fine
   though, only when those error messages are shown that's when i see this issue, same when on empty browser as
   well, like the moment i open browser pane we have that globe icon right, i cannot activate the browser when i see
   that too".
   - A click on the empty page (the globe) or on an error page makes the card active, as a click on a loaded page
     does.
   - Find why those views drop the click; the phase 51 `_hitTest:dragTypes:` override is a suspect.

31. **Remote browser: this Mac's network.** "for browser plugin when opened in remote machine, we should have an
    option to toggle to local network instead of remote, we show right now machine name in address bar, clicking on
    it should disable it, that time, browser routes to local network".
    - The machine chip in a remote card's address bar becomes a toggle. Clicked, the chip goes plain ("This Mac")
      and the card loads through this Mac's network. Clicked again, the card goes back through the machine.
    - The card reloads its page on each switch.
    - The choice is kept per card, through relaunches, like its address.
    - Document it in `browser.mdx` (remote localhost).

## Track D: File Explorer behaves like Finder (items 6–12, 16, 17)

The user: "basically review entire file explorer and let's try to make it close to macos file explorer in terms of
behavior". Review every click, key and menu against Finder's list view. Write the table in the design page. Change
what differs unless a card needs it otherwise, and give the reason in Findings.

6. **The filter behind a button.** "can we make the filter collapsed by default with may be like search icon button
   and clicking on it should just show a search bar below like how we show cmd+f bar on regular terminals. i don't
   like having two input boxes big in the file explorer, so we should have back and forward buttons, main path bar,
   then three buttons including the search".
   - Row 2 holds Back, Forward, the path bar (full width), then three icon buttons: Filter (`magnifyingglass`),
     Collapse All and Hidden Files.
   - Filter, ⌘F, or typing a letter in the tree opens a find bar under row 2. It looks like the terminal's ⌘F bar.
   - Esc, or a second click, closes it and clears the filter.
7. **Clicks outside clear the selection.** "when i click on any folder now that activates by highlighting that
   folder but if i click outside anywhere like empty sapce or any other buttons etc, can we remove that focus".
   - As in Finder, a click on the tree's empty space clears the selection.
   - A click on a header button or on the path bar removes the selection's highlight from the tree.
8. **`..` takes a click.** "i also cannot click on .. folder to activate them, keyboard arrows work though, but
   clicking with mouse doesn't activate it, it should work similar to other folders or files in the xplorer".
   - A click selects `..`, a double-click goes up, and the context menu works, like any folder row.
9. **⌘O.** "similar to macos file explorer, can we have shortcut cmd+o to open folder, in our case which makes that
   as root?". ⌘O (and ⌘↓) opens the selection: a folder becomes the root, and a file opens in its card.
10. **⌘← and ⌘→ for history, in File Explorer and Git.** "in both file explorer and git plugins, cmd + left/right
    arrow should work for navigating back and forth similar to browser, right now i cannot go back or forward in
    history using keyboard".
    - ⌘← / ⌘→ and ⌘[ / ⌘] go Back and Forward. ⌘↑ goes to the parent, as in Finder.
    - Put this in the runtime's page router (`oriel.pages`), so every plugin with history gets it. A text field
      with the keyboard keeps ⌘← / ⌘→ for its caret.
11. **Return renames.** "also when using keyboard, enter should rename the file instead of opening, same for
    folder/files, and cmd+o should open the file".
    - Return starts a rename of the selected row, as in Finder; Return saves it and Esc cancels it.
    - ⌘O and ⌘↓ open, and a double-click opens.
    - → and ← expand and collapse.
    - Space opens a Quick Look–style preview card only if one already exists; otherwise Space does nothing.
    - ⌘⌫ moves to the Trash and ⌘D duplicates, if the API has them; otherwise note them as gaps.
    - This replaces phase 51's "Return opens".
12. **A Git status bar.** "within file explorer can we show a footer showing git status if and only its a git repo,
    show pending changes, or any commits to pull/push etc, keep it minimal it should be just a simple status bar and
    should have an icon button to open the git plugin from there, which opens git plugin with that folder active".
    - A one-line footer, only when the root is inside a Git repo: the branch, then "3 changes", then ↑2 ↓1 when
      ahead or behind its upstream.
    - At the right end, the `source.branch` icon button opens Git on that repo, in a new tab at the end.
    - Hidden in a folder that is not a repo.
    - It refreshes with the tree's status, with no extra polling.
16. **No stray change dots.** "i don't know why for some folders, yellow dots are shown: … even though there are no
    pending changes in it, its bit random, just expand few folders by clicking that chevron icon, for some folders
    i see yellow dot after they are expanded". Screenshot `4.28.58.png`: dots on `docs`, `plugins` and `web` with a
    clean tree.
    - A folder's dot shows only when a path under it has a change in `git status`.
    - Find why an expand marks it. Suspects: the lazy listing's ignored files, untracked caches, or a stale status
      merged into a new listing.
    - Add a test on a clean repo.
17. **Sticky folders.** "when a long file explorer is scrolled, i see .. folder stays sticky, instead last folder
    should stay sticky, like if i am inside a > b > c folder and c has lot of file items, a b c should stay sticky
    when scrolling basically to have quick awareness of which folder we are in, i think pierre tree might support
    this by default, check and implement that".
    - When scrolled, each open folder above the view stays stuck at the top, nested, until its last child scrolls
      past.
    - `..` scrolls away like any row.
    - Use `@pierre/trees`' sticky folders if it has them; else CSS `position: sticky` on the folder rows.

## Track E: one header for every file card, Markdown's modes (items 13–15, 18, 19, 26)

19. **One header.** "so essentially keep the header similar, with back/forward, file path breadcrumbs and other
    options, for all file previews and review and make sure they are all consistent in terms of ui". Every file
    card (code, Markdown, image, video, PDF, other previews) shares one row 2:
    - on the left: Back, Forward, the outline toggle (only when an outline exists), and the path breadcrumbs;
    - on the right: Show in File Explorer, the mode menu (Markdown only), and Open With.
    - Same spacing, icon sizes and order everywhere.
    - Pictures of every card kind, before and after, dark and light.
13. **Find and replace.** Screenshot `7.38.18.png`: "find and replace looks shit in the file preview, please make it
    look good following our app design standards".
    - Restyle CodeMirror's search panel for every file card, Markdown included, as the terminal's ⌘F bar:
      - a rounded field, glass or row fill;
      - icon buttons for previous and next, and a match count;
      - toggles for Match Case, Regex and Whole Word as small icon buttons;
      - a second row with Replace, Replace and Replace All only when replace is open (⌥⌘F).
    - The app's font, colours and focus ring. No default HTML buttons or checkboxes.
14. **Show in File Explorer goes to the file's folder.** "in file preview, that show in file explorer button should
    take it to the nearest folder where that file is in, right now it takes it to kinda user directory level".
    - The tree opens with the file's folder as its root and the file selected.
    - Check that the tree also scrolls the file into view.
15. **Relative paths in previews.** "in image or video preview, can we show relative path instead of long absolute
    path". Screenshot `4.27.56.png`. Preview cards use the same breadcrumbs as code cards: relative to the repo root,
    else to `~`.
18. **Markdown's modes.** "in markdown edit mode, right now we show raw markdown on selected line, can we also another
    edit mode where we have side by side mode, where full raw markdown on one side and the preview rendered on the
    other, they should be able to collapse the rendered view if they want to, only markdown view should have some
    monospace font, with markdown syntax highlight similar to file preview for other files. and also the sidebar
    expand/collapse button should go fully left, and should not be shown if there is no outline available for it.
    also change the read edit toggle button to dropdown button with options read only, inline edit, markdown only,
    side by side, use better phrasing where possible. basically user can switch between different modes when needed
    and also move that dropdown to right side, and on the left we show the file path breadcrumb similar to regular
    file preview, so essentially in the header, we see back and forward buttons, sidebar expand/collpase only when
    outline is present, file path breadcrumbs, show file explorer button, dropdown for mode, dropdown for open with,
    also we should fix ui for find and replace here as well".
    - A mode menu on the right of row 2 with four modes:

      | Mode | What it shows |
      |---|---|
      | **Read** | read only |
      | **Live Edit** | today's Edit |
      | **Source** | the whole file in monospace with Markdown syntax colours, as code cards draw |
      | **Side by Side** | Source on the left and Read on the right |

    - The menu lists the shortcuts: ⌘E cycles Read ↔ the last edit mode, and ⌘1–⌘4 pick a mode inside the card.
    - In Side by Side:
      - the two halves scroll together, by source line;
      - a button on the divider collapses the preview, leaving Source full width, and expands it again;
      - a tick in the preview edits the source.
    - The mode is kept per card.
    - The outline toggle sits at the far left after Back and Forward, and only when the file has a heading.
26. **Bigger task boxes.** "markdown checkboxes can we make the checkboxes slightly big, i feel they are bit too
    small". From 0.95 em to about 1.15 em, still centred on the x-height. Check it on the Retina screen.

## Track F: Git (items 20–25)

20. **Commits select, then open.** "for git plugin, clicking on commit should just select it, doublt click should
    open it, with keyboard, arrow keys should select the commit and highlight similar to file explorer and clicking
    enter should open the commit".
    - In Git's home and every commit list:
      - a click selects a commit, and a double-click or Return opens it;
      - ↑ and ↓ move the selection, with the same highlight as the explorer;
      - a click on empty space clears the selection.
    - The first arrow selects the first row, as phase 52 did for the explorer.
21. **The file list starts closed.** "in diff view, by default collapse the file paths sidebar". A diff opens with
    its file list closed. The toggle stays, and a card keeps the user's choice once they change it.
22. **The header under the scroll bar.** Screenshot `4.54.31.png`: "file header is above the scrollbar, it should be
    below". The scroll bar draws over every sticky header and the header copy.
23. **No jumping header.** "check this video, there is this weird issue, for the sticky file header, i see some
    flicker or its like its position moves around or i can see text below it something like that, actually for some
    reason when i did screen capture its not very evident, but when i check it normally i can see it very evidently,
    i am guessing the file header is sticky using some javascript which makes it bit laggy when i scroll too fast,
    figure out and fix this". Video `sticky.mov`.
    - Phase 52 added a CSS-sticky copy under pierre's own header, but pierre's header still moves by script, a frame
      late, so the two show apart.
    - Fix it at the cause: the header must be CSS-only sticky with no script position. Either move pierre's file
      header out of the virtualized box into a sticky element of the file's own box, or use pierre's simple
      Virtualizer and rebuild the diff page. The user has now asked for the real fix, so the rewrite is allowed.
    - Remove the phase 52 copy.
    - Measure with real trackpad flicks at 120 fps:
      - no frame shows text through or above the header;
      - the header never moves while its file is in view;
      - the push to the next file is smooth.
24. **Files in their own boxes.** Screenshot `5.01.55.png`: "can we have some separation between each file, and have
    slightly rounded border radius, right now all files are kinda merged and have sharp corners".
    - Each file is a box with about 8 pt corners and a 1 px border in the separator colour, and 8 pt between boxes.
    - The sticky header takes the box's top corners while it sticks.
    - The same in every diff layout (Unified and Side by Side, file list open or closed, Working Tree and commits);
      the file list's rows stay plain rows.
25. **Revert is red.** "toast button showing revert, it should be red in color as its destructive action".
    - `ToastView` buttons get a destructive role.
    - Revert, Revert All and every delete or discard confirmation in the app and the plugins use it.
    - Add the role to the plugin API's toast options and document it.

## Track G: the window, the sidebar, glass and the skill (items 27, 29, 30, 32, 33)

27. **The palette's bottom.** Screenshot `5.12.18.png`: "in cmd+k at the bottom can we not have padding, like i see
    some empty gap where an item is aprtially cut, only when you scroll to the end you should have some gap at the
    bottom".
    - The list's clip reaches the panel's bottom edge, so a cut row runs to the edge.
    - The bottom padding is inside the scrolled content, after the last row.
    - The same in every FilterList (palette, chooser, pickers).
29. **Agent times.** "coming to agent sidebar, it looks much better now, few nits are let's not show timer for done
    items, timer should be shown only for working ones, also if its below 1m show <1m instead of changing every sec".
    - Only Working rows show a time; Needs you and Done show the icon box alone.
    - Under a minute the time reads "<1m", then 1m, 2m, …, and it ticks once a minute.
30. **Sort by priority.** "default sorting on agent view should be priority not workspace". New windows and fresh
    settings group the Agents view by priority. A user's saved choice stays.
32. **Glass over a bright window.** "with glass mode when on dark mode, keep an bright white colored window or
    something behind our window, that bright window makes our window bit unreadable coz glass windows making it seep
    through it, can we improve it better, such that even having a bright window below doesn't mess up much, check
    with rex, they handle that well, you can still see the window behind but it doesn't interrupt with making it
    unreadable or anything, let's use similar thing what they do".
    - Study `/Applications/Rex Beta.app`: its window material, any tint or dimming layer, its opacity, and how its
      text keeps contrast. Take pictures of Rex and Oriel over the same white window.
    - Then match Rex's approach in dark glass: for example a darker tint under the content, a stronger blur, or a
      vibrancy-aware label colour.
    - Light glass is checked the same way over a black window.
    - Text contrast must stay at or above WCAG AA (4.5:1) over white, with the window behind still visible.
33. **The skill lives in this repo.** "i also noticed our oriel skill is in pi-hkandala, why? pi-hkandala is
    compleltely independent repo, we should have skills within oriel repo, create may be skills folder and keep it
    in there".
    - Move `~/code/pi-hkandala/skills/oriel/` to `skills/oriel/` here, with its history in one commit and the source
      named.
    - `make install` links it into `~/.agents/skills/oriel` (pi and Codex) and `~/.claude/skills/oriel` (Claude
      Code), if absent.
    - Delete it from pi-hkandala and push there.
    - Update the docs that name pi-hkandala (agent-control, the CLI's hints).
    - A remote machine gets the skill the way the docs say: copy or link it. Shipping it with the app waits for the
      herdr-core plan.

## Track H: snappy workspace switches (item 39)

39. **Workspaces with many plugin tabs switch at once.** "when there are too many plugin panes are there specifically
    browser panes, in some workspace, and clicking on that workspace when switching worksapces, i see a noticeable
    delay when clicking on the workspace that has many tabs, i noticed this exactly in the current workspace where
    we have so many reports opened in tabs, let's improve the workspace switching overall and make it snappy".
    - Measure first, from the click to the first drawn frame of the new workspace. Use real HTML reports (the
      `~/Downloads/oriel-research/*.html` files).
      - For a target workspace with 1 tab, with 10 terminal tabs, with 10 browser tabs, and with 10 mixed plugin tabs
        (browser, File Explorer, Git).
      - For both directions, and for a workspace seen before versus not seen since launch.
    - Profile the slow case with Instruments (Time Profiler and SwiftUI). Find what scales with the number of tabs.
      Suspects: every hidden card of the workspace being made, attached or sized, web views laid out or resized when
      hidden, the tab bar's pills, snapshot rebuilds, label or state work per pane, and `PaneViewRegistry` trims.
    - Fix the cause: a switch does work only for the tab that shows. Hidden tabs wait until they are shown, keeping
      phase 48's rule that hidden terminals of the current workspace stay sized.
    - Target: under 50 ms to the first frame for any tab count, and the same speed as a terminal-only workspace.
    - Add a pacing test with counts, not wall-clock bounds (the `wall_clock_bounds` lint rule). For example: the
      number of web views laid out, or of cards made, on one switch.
    - Before and after numbers in Findings, also for the phase 48 table's measures.

## Track I: the chat view's load (item 40)

40. **A chat tab slows every switch.** "that workspace switch thing right, i mentioned its because of browser plugin,
    but its not actually due to browser, its due to chat view, so create a tab with this session: pi --session
    01a1a982-7be3-7238-8079-7fb4260c4712, opened in chat view, and even tab switching is slow when i am activating
    that tab, and workspace switch becomes slow if that tab is active tab, so i am thinking this chat view is adding
    some extra cpu load or something making everything slow, investigate this properly, reproduce measure and fix
    it".
    - Reproduce with a copy of that session file, never the user's live one. Open it in a chat card, idle, with no
      messages sent.
    - Measure, on a Release build:
      - the main thread's idle CPU with the chat tab shown versus a terminal tab;
      - a switch to the chat tab;
      - a switch away from it to another tab or workspace;
      - a workspace switch while the chat tab is the active tab.
    - Profile with Instruments: Time Profiler, SwiftUI, and hangs.
    - Find what grows with the chat's length or keeps working while idle. Suspects: phase 52's pinned rows, which
      keep every row from its first show (D95); geometry observers on every row (`onGeometryChange` for the top-row
      anchor); Markdown laid out again on every update; the transcript watcher re-parsing; scroll position bindings;
      timers.
    - Fix the cause:
      - an idle chat costs nothing;
      - showing or leaving a long chat costs no more than a terminal;
      - a switch never lays out rows out of view.
    - A pacing test with counts, for example rows laid out or bodies run per switch, and idle updates per second.
    - Before and after numbers in Findings.

## Track J: agents that are not installed (item 41)

41. **Grey out missing agents in New Pane.** "in new pane we show agents and lists 4 agents right, we should verify
    if those agents exist on the device, if not that particular agent option should be grayed out like disabled and
    show like not installed text to the right of it or somewhere yk, also we shouldn't do that check everytime we open
    the pane, that makes the new pane loading slow". Then: "let's just do it on window launch, and no need to cache
    every 10s thats bit too redundant, so once user installs the agent they can just clsoe the window and open new one
    to update it. this also keeps the overall logic very simple, basically cache it within window for a device".
    - One check per window per machine: when a window opens, and the first time that window uses a remote machine.
      A single call through the machine's exec runs
      `$SHELL -ilc 'for c in claude codex pi opencode; do command -v "$c" >/dev/null && echo "$c"; done'`, so the
      login shell's `PATH` and aliases count. It stops after about 3 s.
    - The answer lives on the window, by machine, for the window's life. It is not saved and not refreshed. A new
      window checks again.
    - Unknown (the check has not answered, timed out or failed) means enabled, so no row flashes grey.
    - A missing agent's row is dimmed and shows "Not installed" in secondary text at its trailing end, in place of
      its number key. It takes no click, and the arrow and number keys skip it. Its hover tip gives the install
      command.
    - New Pane never waits for the check.
    - A UI test with a stand-in `PATH` where one agent is missing. A picture of the disabled rows, dark and light.

## Track K: New Pane's folder (item 44)

44. **Where the pane opens, editable.** After the mockups (`new-pane-mockups.html`): "honestly, the current one looks
    better than anything else, one improvement we can do to current one is add that opens in filepath text at the
    bottom like shown in idea 1, one more addition to that, let's make that path editable, like user can click on
    that path, and that becomes editable and they can type in their path there, adn we can have an icon or something
    clicking on it should open macos file picker, basically similar to what the file explorer plugin has in its
    address bar, similar to that, do not show full absolut path all the time, same like file explorer again".
    - Keep today's chooser as it is. Add one quiet line under the list: "Opens in", then the folder the new pane will
      start in.
    - The folder shows short, as File Explorer's path bar does: `~/code/oriel`, or relative to the repository, never
      the full absolute path at rest. Name the machine only when it is not This Mac.
    - A click on the path turns it into a text field with the path selected. Return applies it and Esc cancels it.
      `~` and relative paths are taken. A folder that does not exist on that machine shows an inline error, and the
      old folder stays.
    - A folder icon at the line's leading end, before the path as in File Explorer's path bar, opens the macOS folder
      picker (NSOpenPanel, folders only) at the current folder. The user, after the first pictures: "keep folder icon to
      the left of the path not to the right, and make sure error message comes below the input, i saw it was
      overlapping". The error has its own line under the field, kept free, so the list does not move.
      On a remote machine the icon is hidden, because the Mac's picker cannot browse that machine; typing still works.
    - The picked folder is the start folder of whatever the user picks next: Terminal, an agent, File Explorer, Git,
      or a plugin. It is kept for that chooser only, not saved.
    - Keys: the number keys and arrows work as today while the field is not editing. ⌘L, or Tab from the list,
      starts editing.
    - Reuse File Explorer's path bar look and its short-path rule; do not copy its code if it can be shared.
    - A UI test: type a folder, pick Terminal, and check the shell's folder; a bad folder shows the error.
    - Pictures, dark and light.

## Track L: a seen Done leaves when the user leaves (item 45)

45. **Done moves to Idle after the user looked and left.** "in previous runs, we have updated sidebar, and one
    speciifc thing i mentioned in there is, if something is done, we shouldn't remove it from done immediately after
    its activated, instead it should be removed from done once user looks at the agent and goes to some other agent,
    basically when user looking at agent when its done for first time, it shouldn't be removed from that section, as
    soon as user left that agent it should be moved to idle. right now after done, they are just stuck at done, even
    after i go back to other agents etc".
    - Phase 52 (item 23, `Pane.finishSeen`) kept a seen Done in its group until the agent works again or leaves. The
      user meant: it stays while they look at it, and moves to Idle as soon as they leave it.
    - Leaving means the agent's pane stops being the one with the keyboard. The user selects another pane, tab,
      workspace or session, or the window closes. Not leaving: the app losing focus, or the pane staying shown
      while the keyboard moves within it.
    - The same rule for the tab pill's icon, the hover card and the Workspaces view's priority. A Done that was never
      looked at stays Done.
    - A UI test: an agent finishes, the user opens it (it stays under Done), selects another agent (it moves to Idle).

## Track M: a flicker at the end of a session swipe (item 46)

46. **No flicker when a session slides in.** Scrawl capture `scrawl-1793877050856-1c27-3` (in
    `~/Library/Application Support/scrawl/captures/`): "so let me have multiple sessions. And then I do swipe between
    them, there is a slide flicker at the end of the animation, if you notice. I'm doing this multiple times so I can
    capture what I'm trying to say. Yeah, this was not there before. I don't know. I think this has started recently.
    Let's investigate and fix this."
    - The page that slides in shows a Claude Code chat card. In the capture's frames 2 and 3, its rows sit at
      different scroll places at the end of the slide, so the chat seems to jump. The user's installed build is
      `efa26b24`, so the cause landed by then. Suspects: phase 52's place keeping (`d404044c`: rows report their top
      in a named space, and a new top restores the place) reacting to the page moving, and the bottom anchor.
    - Reproduce on a build at `efa26b24` and on main, with two sessions and a long chat card, swiping (⌥ +
      two-finger swipe and the session keys). Record at 120 fps, and bisect if the cause is not plain.
    - Fix it at the cause. A page that moves is not a new width: nothing in a card moves at the end of a slide.
    - A UI test that counts scroll changes during a session switch, and before/after recordings.

## Research, plans only (items 34–38, 42, 43)

No code changes. Each report is one self-contained HTML file in `/tmp/oriel-research/`, copied to
`~/Downloads/oriel-research/`, written in plain English.

34. **herdr-core.** "herdr has recently introduced herdr-core, can you check how that works, i think we can ship
    herdr-core within our app and use it without need to ask user to install herdr or anything, i think herdr core
    maintains separate session from herdr tui, investigate on this herdr core in detail and give me a html report on
    it, on the plan and what would be the changes, essentially we should use herdr-core internally, and user don't
    need to be aware of herdr at all when using our app, no mention of herdr anywhere in our app ui after this
    change". Report: `herdr-core-plan.html`.
35. **Releases and an updater.** "we should have ci pipeline to build dmg and .app files and upload them to github,
    preferably this should run only when we introduce a version tag or something, we should also have app updater
    within our app, which should check for updates and notify users when there are updates. check how general open
    source projects do it and give me full html plan on this as well". Report: `release-and-updates-plan.html`.
36. **Telemetry.** "our app should collect anonymous telemetry data which we can use to understand some things like
    DAU, any error reports, or any other metrics in general that are useful to track in our apps. check how people
    generally do telemetry in open source projects, we can may be go with posthog, suggest if there are any better
    alternatives as well, and tell me what all things we should collect by default in our app". Report:
    `telemetry-plan.html`.

37. **Onboarding.** "invoke another research agent for onboarding flow as well, start this after herdr-core research
    keeping that in mind, as in our onboarding as well we shouldn't mention on herdr things, so this onboarding should
    be minimal and clarify basic things to user, like may be we can open one session with some tabs, workspaces and
    plugins opened, and during the onboarding, we should switch to tab or workspace and explain each item briefly,
    with text info hovering somewhere, give me some ui mockups for this, you can give me different ideas as well,
    give me like 5 onboarding flow ideas and how we can do it. in all ui mockups keep in mind of our native mac app
    style with minimal style and may be glass effects where needed". Report: `onboarding-plan.html`, with five flows
    and mockups of each. It starts after item 34's report and builds on its plan.
38. **The Settings window.** "once all research agents are done, invoke another research agent on settings window.
    basically we need new settings window, look through entire code, and figure out what can go into our settings
    window, we should group our settings window into multiple pages like macos settings with sidebar. let's not
    overload with too many settings, we should keep it minimal but shouold have enough required things to configure.
    consider all the research agents are implemented, that's why this should be started after all research agents
    are done. give me 5 ui mockups and different way settings can be grouped etc, plugins should have settings as
    well". Report: `settings-plan.html`, with five groupings and mockups, and settings for plugins. It starts after
    items 34–37 and assumes they are built.
42. **New Pane redesign.** "can you give me multiple design mockups for the redesign of current new pane, invoke an
    agent to work on it, its quite simple at the moment, i want it to be simple but may be some improvements to ui
    overall, give me like 5 alternative ui mockups for it". Report: `new-pane-mockups.html`, five alternatives.
43. **Notifications.** "can you also work on another research report similar to other 5 we already worked on, i want
    to have notifications support for our app, specifically for the agent notifications, and may be new app updates or
    any other notifications that makes sense, investigate everything, what notifications we would need, how we will
    implement it, describe it in the html report cleanly". Report: `notifications-plan.html`.

## Order and estimates

The tracks run in parallel, each in its own worktree. Estimates are in agent hours.

| Track | Items | Estimate |
|---|---|---|
| A, chat | 1 | 1.5 h |
| B, panes and tabs | 2, 3, 28 | 3 h |
| C, browser | 4, 5, 31 | 2.5 h |
| D, File Explorer | 6–12, 16, 17 | 6 h |
| E, file cards | 13–15, 18, 19, 26 | 6 h |
| F, Git | 20–25 | 5 h |
| G, window | 27, 29, 30, 32, 33 | 3.5 h |
| H, workspace switches | 39 | 3 h |
| I, the chat view's load | 40 | 3 h |
| J, missing agents | 41 | 2 h |
| K, New Pane's folder | 44 | 3 h |
| L, a seen Done | 45 | 1.5 h |
| M, session swipe flicker | 46 | 2 h |

- D and E both touch `plugins/explorer`: D owns the tree and its header, and E owns the file cards. Each bumps
  File Explorer's version when it lands, rebasing on the other.
- D puts the history keys (10) in `web/oriel`; F rebases onto it.
- F's destructive role (25) touches `ToastView` and the plugin API.

The whole phase is about 6 h of wall time with all tracks at once, then the finish (docs pass, final review, two full
CI runs and on-demand) at about 2–3 h.

## Findings

### Track A

- **Cause.** The missing reads, writes and edits were calls made inside codemode scripts. The run's summary counted
  them as their own ("Ran 13 commands, read 9 files"), but the parser kept only their names, so the open run drew
  just the codemode row. pi's own read, write and edit calls always had rows. Found by replaying a slice of the
  orchestrator's real session through the pi stand-in on CI: the run said "read 9 files" and showed only bash and
  codemode rows.
- **Fix.** pi's parser keeps each call of a codemode script as a tool row: its tool, target, time taken and error,
  from the result's `nestedCalls` (whole arguments) or `details.calls` (arguments cut at 200 characters, and the only
  source when pi leaves a large call's arguments out). A cut call keeps its first path, command or pattern. The rows
  sit 20 pt in under their codemode row. The summary counts the calls' failures too.
- **Other agents.** Claude Code and OpenCode already drew every tool call. Codex dropped its subagent items: a
  subagent's start now shows as an `agent` row and each message sent to it as an `agent_send` row, named by its
  path; its `wait` tool reads as an MCP tool. A subagent's end is no row: Codex writes it for 20 of 438 subagents.
- **Decisions.** The calls show once the script ends (pi writes them only in the result), with no result text unless
  one failed (pi keeps no per-call output). They are rows of their own, not folded under the codemode row, so every
  tool the summary counts is in view when the run opens.
- **Runs.** The new UI test on the old code: red with 9 rows of 10 (run 41962205822). On the fix: green
  on the pushed head.
- **Pictures.** Before, the real run in dark: `/tmp/oriel-shots/t53a/before-real-run-dark.png`. After:
  `/tmp/oriel-shots/t53a/after-real-run-dark.png` and the stand-in's run with every tool,
  `/tmp/oriel-shots/t53a/after-tools-light.png`.
- **For the user.** In pi's chat, open a run whose summary says "read N files" after codemode scripts: each read sits
  under its codemode row. Open a run with a large write inside a script: its row shows the file. In a Codex chat
  that starts subagents, the run lists each start and each message.

### Track G

- **Cause, item 27.** Each panel padded all four sides of its content, so the scroll view's clip stopped 10 pt (palette)
  or 8 pt (Open Session) above the panel's edge: a cut row hung over an empty strip. **Fix:** the panel pads only its
  top and sides, and `FilterList` puts that padding inside the scrolled rows, after the last one. ↓ onto the last row
  scrolls the gap into view. The workspace menu keeps its own padding: its pinned rows sit under the scroll. Before:
  the user's `.build/fb53/5.12.18.png`.
- **Decision, item 29.** Only Working rows show a time. Idle rows lost their age too: a seen finish is idle under Done,
  so it still showed a time there. The time shows "<1m", then minutes, on SwiftUI's `.periodic(from:by: 60)`, which
  replaces the custom schedule.
- **Cause, item 30.** The default was already Priority. The user's windows had saved Workspace in scene storage, so
  they kept showing it. **Fix:** the key is now `agentOrder`. Every window starts at Priority once and keeps any later
  choice (agreed with the orchestrator).
- **Item 33.** The skill moved unchanged (byte for byte) from pi-hkandala `skills/oriel` at `7ac9136`. `make install`
  links it where no `oriel` skill exists, and `-f` replaces a link whose checkout is gone. The agent-control page
  tells how to copy it to a remote machine.
- **Cause, item 32.** Dark Glass darkened the blur with black blended `overlay`, under a `#1e1e1e` tint at 0.5. An
  `overlay` blend leaves white as it is and turns dark parts black, so it raised the contrast of whatever was behind:
  a bright window's text and edges came through as dark streaks and colored blots. The `hudWindow` blur is too
  narrow to hide them. Rex keeps the same `overlay` step, but puts the system glass on top of it (Liquid Glass, with a
  much wider blur) under its tint. **Fix:** dark Glass adds `glassEffect(.regular.tint(#1e1e1e at 0.5))` between the
  blur and the tint, as Rex's Modern window does. Light Glass is unchanged: its white tint at 0.7 already hid a black
  window (2 to 5 levels of spread before and after).
- **Decisions, item 32.** The top tint stays at 0.5. At 0.6 and 0.75 the window was darker than Rex's and hid the window
  behind more (8 levels between a white and a black window at 0.75, 17 at 0.5). The glass layer alone removes the
  streaks: a white window behind now shows only as a soft, even light.
- **Numbers, item 32.** These are 8-bit sRGB levels from Retina screenshots, over a full-screen page of black text on
  white, or white text on black (mean, then the spread from min to max):

  | Where | Before over white | After over white | Before over black | After over black | Rex over white |
  |---|---|---|---|---|---|
  | Sidebar | 70, 18 | 51, 7 | 30, 8 | 34, 4 | 63, 1–3 |
  | Card | 82, 8 | 64, 3 | 46, 2 | 48, 1 | — |

  Contrast over white, at the brightest pixel: sidebar text (white 0.65) went from 4.4:1 to 6.0:1, and terminal text
  (`#d0d0d0`) from 4.9:1 to 6.6:1. The card header buttons are 3.2:1 (at least 3:1 is needed). Light over black:
  sidebar text is 6.3:1. `cardSolid` follows the card without the keyboard (`#2e` → `#34`). Pictures:
  `/tmp/oriel-shots/t53g/before-oriel-dark-over-white.png`, `after-oriel-dark-over-white.png`,
  `before-`/`after-oriel-dark-over-black.png`, `before-`/`after-oriel-light-over-black.png` (light is unchanged),
  `screen-rex-dark-white.png`; the 0.6 trial: `t0.6-oriel-dark-over-*.png`.
- **Cost, item 32.** The glass layer costs WindowServer about 5 points of one core while a terminal prints at full speed:
  28 % before, 33 % after (`top`, two runs each, alternating, load average 70 to 150). Oriel's own CPU is unchanged
  (16 %). Idle, no difference shows.
- **Runs, item 32.** `testGlassCardsHaveABrighterTopRim` failed on main after b9597cd5 (Track B's active border, item
  2): the border lies over the keyboard card's rim, so its side read 65 steps over the fill (run 41968008720). The test
  now gives w1:p1 the keyboard and reads the rim on w1:p2. The bounds are the same as before.
- **For the user, items 27–33.** ⌘K, then scroll to the end: a cut row runs to the panel's edge, and the gap shows
  only after the last row. In the Agents view, only Working rows show a time ("<1m", then 1m, 2m…), and Needs you and
  Done show the icon alone. Every window opens the Agents view in Priority order once, and keeps a choice you make
  after. In a new pi or Claude Code session, the `oriel` skill loads from this repo
  (`~/.agents/skills/oriel` and `~/.claude/skills/oriel` link to `~/code/oriel/skills/oriel`).
- **For the user, item 32.** Put a white window (a web page) behind a dark Glass window: no text or edges come
  through, only a soft light. Do the same in light Glass over a dark window. With Reduce Transparency on (System
  Settings ▸ Accessibility ▸ Display), Glass turns opaque and stays readable.
- **Runs.** The first chosen-tests run (41961078819) failed the new palette check. At the end of the list, the lazy
  stack no longer held the row the query used to find the list. The test now reads the list's frame first.

### Track F

- **Fix, commits (20).** A plain click selects a commit (the accent at 24 %, as File Explorer's rows); the second click
  of a double-click, Return on the selected row and a VoiceOver press open it; ⌘- and ⌥-click still open in a new tab
  or to the side. ↑ and ↓ move the selection, the first arrow takes the first commit (↑ the last), and the ring shows
  from an arrow key until the next click, with File Explorer's `data-keys` rule. A redraw (after every write and every
  change in the work tree) keeps the selection without a scroll and takes the keyboard only if the row had it.
- **Fix, file list (21).** A diff starts with its file list closed; the card keeps the user's choice once changed.
- **Cause, red buttons (25).** `role: .destructive` draws nothing on `.glass` or `.glassProminent`, and AppKit draws an
  alert's destructive button red only while it is not the default button. **Fix:** `Toast.Action` carries a role; a
  destructive main button takes `.tint(look.error)` and a destructive other button a red label (a red fill would read
  as a second default). The plugin API's toast gets `{ destructive: true }` for its main button (folded into API 2, which
  has no release yet). Git's Revert and Revert All use it, and so does the app's Discard. The Remove Plugin and Replace
  alerts mark their button destructive and drop its Return key, so AppKit draws it red; Return still clicks it in a
  sheet (`NSWindow.confirm`). File Explorer's "changed on disk" toasts (Reload, Keep Mine; Overwrite, Reload) are
  choices in a conflict, not confirmations of a delete or a discard, so they stay plain.
- **Cause, the jumping header (23).** `@pierre/diffs`' CodeView puts every drawn file into one `position: sticky`
  container whose `top` and `bottom` script sets again at each render (with a random jitter of up to a line), and a
  file's header is sticky only inside that file's drawn part. The compositor scrolls at once and the script follows a
  frame or more later, so pierre's header moved on screen, and phase 52's copy under it and the lines between showed.
  **Fix:** CodeView is gone. Each file is our own box (`section.box`) with our own header row, `position: sticky` in the
  box, and its lines in a `VirtualizedFileDiff` under pierre's simple `Virtualizer`, which keeps the whole file's height
  (buffers above and below the drawn lines). No script moves a header; the phase 52 copy is deleted.
- **Runs (23).** The real app on this Mac, two 30-step trackpad flicks (HID) over a 483-line file: the header sat at
  the same pixel row in all 131 frames while it stuck, and no frame showed text above it
  (`/tmp/oriel-shots/t53f/sticky-after-real.mov`, `sticky-after-real-sheet.png`). Synthetic probe flicks: the header
  in every frame, a few frames of blank lines at file boundaries while the next lines draw. First draw, probe, 1,000
  new 30-line files: CodeView ~550 ms, every view at once ~2,300 ms, lazy views ~500 ms; 53 files about the same
  before and after. A file growing 40 lines above the one in view moved it 800 px without `steady`, 0 px with it; the
  UI test for it fails without `steady` (run 41974415624: c.txt moved 194 pt) and passes with it (41974411474). Git is
  1.8.0.
- **Cause, the scroll bar (22).** WebKit draws a scroll's overlay scroll bar under its descendants' z-index layers
  unless the scroll is a stacking context; the sticky header needs `z-index: 1` over pierre's lines. **Fix:**
  `isolation: isolate` on the diff's scroll. With the boxes pushed to the edge, the thumb hid under the header without
  it and drew over it with it (`zorder-padding0.png` → `zorder-padding0-isolate.png`); the boxes' 8 pt inset also keeps
  the thin thumb clear of them (`scrollbar-before.png` → `scrollbar-after-inset.png`).
- **Fix, boxes (24).** 8 pt corners, a 1 px divider border and 8 pt between and beside the boxes. The header draws the
  box's top on a square of the card's color, so its round corners show no lines while it sticks; the lines draw the
  sides and the bottom; a folded or bare file is the header alone, round all over.
- **Decisions (23).** A box makes its view only within about 1,500 pt of the view (pierre adds a 16 KB icon sprite to
  every view: 1.5 ms each), with an estimated height till then. A height change above the view keeps the file in view
  where it is (`steady`), as CodeView's own anchor did; WebKit's `overflow-anchor` is off, since it exists only from
  macOS 27 and moved the view twice with pierre's anchor. The themes load before the first draw.
- **For the user.** In Git: click a commit (selected, nothing opens), ↑/↓, Return opens; double-click opens; Revert's
  toast button is red, as is Discard in an unsaved file's toast; Remove Plugin's button is red and Return still removes.
  Open a long commit diff: the file list starts closed; flick fast through it and back: the header never moves or
  shows text above it; the boxes have round corners, 8 pt apart; scroll so the scroll bar shows and point at it over
  a stuck header: the bar draws over the header. With an agent editing files, scroll into a lower file of Working Tree:
  it stays put while files above it change.

### Track C

- **Cause, item 4.** The field follows WebKit's `url`. During a load, `url` moves to the new address. When the load
  fails, `url` goes back to the last page's address, and the field followed it. Now the field ignores `url` while an
  error shows. The error writes the address that failed, and the next commit shows the page's address again. Reload
  already loaded the field's address after an error, so it now tries the failed address again.
- **Cause, item 5.** The web view is hidden (opacity 0) while the empty card, an error, "Open this page?" or the
  loader shows, and a hidden SwiftUI view takes no click. The globe's own tap asked for the address field, but the
  field takes the keyboard only on the tab's keyboard card, so the request was dropped. The error view had no tap at
  all. The phase 51 `_hitTest:dragTypes:` override was not the cause: it decides only drags. **Fix:** one tap over
  the whole cover, its buttons too, makes the card the keyboard card, then gives the keyboard to the page, or to the
  field when there is no address.
- **Decisions, item 31.**
  - A web view's store fixes its network, so each switch makes a new web view on This Mac's store or the machine's,
    and loads the field's address. The back and forward list starts again, because its entries hold the other
    network's addresses (`<machine>.localhost`).
  - The choice is kept in this Mac's defaults (`browserViaMac.<machine id>`), not in the state file: each Mac has
    its own This Mac, and a process on the machine must not choose This Mac's network.
  - On This Mac's network, `localhost` is This Mac's, so it is not on the safe list: a label or state file from the
    machine asks first. A switch approves the address it loads (the user clicked). So that machine can later open
    that This Mac port by itself on its cards on This Mac's network. On This Mac's network, a machine can also send a
    card to a safe-list site (github.com) with This Mac's logins.
  - A link opened in a new tab keeps the card's network. `file://` stays closed to remote cards on both networks.
- **Left.** While an error shows, the hidden old page takes the keyboard, as it did before after a tab switch. Back to
  a same-document entry after an error (`#a`) still leaves the error up: such a load has no commit.
- **Runs.** On the old code (run 41960236424), the new test failed at the click on the empty card, and the remote test
  failed at the chip's label, which a plain `Text` leaves empty. With only item 4's fix taken out (run 41962790361), it
  failed at the field, which showed the page before. Green: 41961436471 (with the browser tests that use the empty card,
  the error page and "Open this page?") and 41962785281.
- **The error click's check.** A web view reports no keyboard focus of its own in XCUITest, so the test checks that
  the terminal lost the keyboard and that ⌘L then acts on this card.
- **Pictures** in `/tmp/oriel-shots/t53c/`: before (old code, CI, dark): `before-remote-chip.png`,
  `before-empty-click.png`. After: `after-failed-address-dark.png`, `after-chip-machine-dark.png`,
  `after-chip-this-mac-dark.png`, `after-chip-machine-light.png`, `after-chip-this-mac-light.png`.
- **For the user.**
  1. In a browser card, open a page, then type `localhost:4999` (nothing listening). The field keeps
     `http://localhost:4999/`. Start a server on 4999 and click Reload: that page loads.
  2. With two panes, click the other pane, then click anywhere on the browser's error page, or on a new browser
     card's globe. The browser card becomes active.
  3. On a remote machine, open a browser card on `localhost:<port>`. Click the machine chip: it says "This Mac", and
     the page loads from this Mac's `localhost`. Click it again: back to the machine's page. Quit and reopen Oriel:
     the card keeps its choice.

### Track B

- **Cause, ⌘W after ⌘D (3).** `closePane` returned early on purpose while a split's lit card waited for herdr's pane,
  so each ⌘W in that time did nothing. There was no way to close a stand-in split: only new-tab stand-ins had one.
- **Fix, ⌘W after ⌘D.** ⌘W closes the lit card. Its split is not made when its write has not started; a pane herdr made
  for it in the same write is closed in that write and stays hidden while the split settles. The lit card steps back
  through the quick splits before it (`Page.splitsBefore`), so each ⌘W closes the next newest. A split's starting pane
  closes at once, as a new tab's does (`Ahead.fresh`). A close of a stand-in that herdr already made closes herdr's
  pane.
- **Cause, the drop's flicker (28).** At the drop, `over = nil` slid every capsule back to the old order, the dragged
  capsule stayed dimmed until the drag session ended, and herdr's snapshot then moved the tabs to the new order.
- **Drop at 60 fps** (a drag of the third of three labelled tabs to the front): before, 13 frames (217 ms) showed the
  old order, then 5 frames (83 ms) the new order with the dropped capsule still dimmed. After: 0 and 0; the first
  frame after the drop has the new order at full opacity. In both, the system's own drag image fades over about 18
  frames on top; that is AppKit's, not the bar.
- **Fix, the drop.** `HostStore.move(tab:to:)` is synchronous now: it shows the new order ahead (`Ahead.order`) in the
  drop's own update, then writes. The order holds until a snapshot has herdr's order, the first or second after the
  answer, or a tab comes or goes. The drop clears the dim in the same update. Move Tab Left and Right get the same.
- **Active border (2).** A 1 pt `strokeBorder` inside the keyboard card's edge, over the content, only when the tab
  shows two or more cards and none is zoomed. No fade: `.transition(.identity)`. Pixels at the card's left edge (2x,
  sRGB), glass dark: edge 65 then fill 50 before, a 2 px line at 113/102 after; classic light: edge 202 then fill 253
  before, 202 then 206/206 after. The light border sits next to the card's own dark edge and reads as a firmer edge.
- **Decisions.** The border is the label colour at 30 % / 22 % in both Looks, glass and classic: by eye it stays
  subtle on both, so no per-Look value. A zoomed card counts as one shown card (no border). The quick-close rule also
  covers a split's pane whose shell still starts: it closes at once and comes back with the question if a program
  runs, as a new tab already did.
- **Runs.** The new test on the old code (local, 19:14): herdr kept 4 panes. CI on the first fix (41960707188) failed
  the same test with 3 panes (the lit card did not step back once a snapshot had its pane); the reviewer found it too.
  Green, 12 chosen tests: 41961788350 and 41963184169 (the pushed head before its last rebase onto Track C's browser
  commits).
- **Pictures** in `/tmp/oriel-shots/t53b/`: `border-before-*.png` and `border-after-*.png` (glass and classic, dark
  and light); the drop at 60 fps, `drop-before-60fps.mov` and `drop-after-60fps.mov` (the tab bar, cropped), with the frames
  around the drop in `drop-before-frames.png`, `drop-after-frames.png` and the `drop-*-sheet.png` strips.
- **For the user.**
  1. In a tab with one pane, press ⌘D three times fast, then ⌘W three times fast. One pane is left, and no pane shows
     up after.
  2. With two panes, click each: the active one has a thin light border (dark) or grey border (light); with one pane,
     or when zoomed, none. Check Glass and Classic.
  3. Drag a tab to another place and let go: it stays where you dropped it, with no slide back and no blink.
### Track E

- **Cause, Show in File Explorer (14).** The button went to the last tree the card had shown that held the file, and
  a card that started on `~/` always matched that first. **Fix:** it now roots the tree at the file's own folder;
  the tree's `reveal` selects the file and scrolls it into view (`focusPath` and `scrollToPath`).
- **One row 2 (19, 15).** File, Preview and Markdown share the manifest's order: Back, Forward, the outline toggle
  (Markdown, only while the file has a heading; it was disabled before), the breadcrumbs; then Preview's page and
  zoom, Show in File Explorer, the mode, Open With. The breadcrumbs start at the repository's root (its name first),
  else `~`, else `/`, for every kind; Preview's absolute dim path is gone. git names a root with links resolved, so a
  `/private` prefix is stripped to match `/tmp/…`. ponytail: the home folder is found by its usual place
  (`/Users/<name>`, `/home/<name>`, `/root`).
- **Decisions, narrow cards.** In a 360 pt card the row had no room left for the breadcrumbs (they showed as `t…` or
  nothing). The mode menu shows its symbol alone (a new menu `"style": "icon"`, the mode's name in the tooltip and
  in VoiceOver's value). Open With keeps its full name: a Menu let free to shrink clipped at the card's edge instead
  of cutting its name. In a narrow PDF card the breadcrumbs still give way to the page and zoom buttons.
- **Find bar (13).** CodeMirror's own panel was a band of HTML buttons and checkboxes over the text. A custom panel
  draws the terminal's ⌘F bar: a 32 pt capsule floating at the top right (no line pushed down), the field, the
  count ("3 of 12"), Match Case, Whole Word and Regular Expression as SF Symbol toggles, Previous, Next, Close. The
  first match is selected as you type. **Decision:** ⌥⌘F (Find and Replace) is the page's own key: no menu item
  has it, and the find bar is per card.
- **Markdown's modes (18).** One editor with two compartments (editable, look) gives Read, Live Edit and Source;
  Side by Side adds a second CodeMirror view of the same text (`split.ts`), kept in step by passing each view's
  changes to the other under an annotation that stops the echo. They scroll together by source line; the side the
  user last scrolled, clicked or typed in leads (not hover, which broke typing under a resting pointer). The mode is
  the header control's value, so the card keeps it through other files, Back, and relaunches.
- **Cause, a mode pick that did not show.** The runtime keeps each page's controls and sends a page's change only when
  it differs from that record. A menu pick reached the record at once, but the app does not store a menu's value (the
  page does), so the page's own set of the picked value was dropped and the menu kept "Read". The runtime now also
  sends a change the app's header was not told yet.
- **Cause, typed letters lost in the find field.** CodeMirror's `findNext` selects the field's text after each step,
  so the next letter replaced the query ("w = 4" became "4"). Typing selects the first match itself.
- **Decisions, keys.** No ⌘1–⌘4 for the modes: they are the app's Show Tab 1–9 jumps, and ⌃⌘, ⌥⌘ and ⇧⌘ digits are
  taken too (workspaces, sessions, screenshots). ⌘E switches Read and the last edit mode; it is listed in View ▸ Edit
  Mode and the palette, not in the mode menu (no hint text in the UI).
- **Task boxes (26).** 0.95 em → 1.1 em (13.3 → 15.4 px at the 14 px prose size), not 1.15: the box sits in the
  bullet's 1.1 em slot, and a wider box pushed the first line 0.05 em right of its wrapped lines.
- **Pictures** in `/tmp/oriel-shots/t53e/`: `before-{dark,light}.png`, `step1-after-{dark,light}.png` (the row),
  `step2-after-{dark,light}.png` (Side by Side and Source), `find-replace-dark.png`,
  `markdown-side-by-side-dark.png` (from the UI tests).
- **For the user:** open a code file, an image and a Markdown file from a repository and from `~/Downloads`: the
  breadcrumbs start at the repository's name or at `~`. Show in File Explorer on a deep file: the tree's root is its
  folder, the file selected. ⌘F in a code card, then ⌥⌘F: the capsule, the toggles, Replace and All. In Markdown,
  pick each mode; in Side by Side scroll each half (the other follows), tick a box in the preview (the source
  changes, the dot shows), fold and unfold the preview. Check the task box size on the Retina screen.

### Track D

- **Cause of the stray dots (16).** `@pierre/trees` counts every git status entry as a change of the folders above
  it, `ignored` ones too. A folder lists which of its own names git ignores, so opening `docs` added
  `docs/node_modules/` as ignored, and `docs` got the dot. Root-level ignored names have no folder above them, which
  is why it looked random. **Fix:** each tree's shadow root gets one style that hides pierre's dot and shows it only on
  the folders above a path in `git status`; the dimming of ignored names stays pierre's.
- **Cause of the sticky `..` (17).** `..` was a button above the tree, outside its scroll view. **Fix:** `..` is the
  tree's first row (a folder with no entries, `../`), so it scrolls away, and a click selects it, a double-click goes
  up and its menu works (8) with no code of its own; pierre's `stickyFolders` keeps the open folders above the view at
  its top. The old `..` keys (↑ from the first row, ↓ back) went: they are the tree's own now.
- **History keys (10)** live in the runtime: in the capture phase, before a page's own keys (pierre takes ⌘← as ←),
  unless a text field has the keyboard. A `card.step` bridge call runs the app's Back or Forward. ⌘↑ is the tree's
  (the parent folder), as in the Finder.
- **Decisions.** The find bar (6) is HTML in the page, styled as the terminal's ⌘F bar (a capsule, the count, ×):
  row 2 is native and has no second row. Its filter is the page's, so a kept tree keeps it with no header value. The
  selection (7) goes on a click on no row or on a row 2 button; while the tree lacks the keyboard (the path field,
  the find bar, another card) it shows in gray, as the Finder's does, rather than going. Return renames (11) through
  pierre's inline rename and a new `files.move` call (`files:write`, never replaces), so a remote machine renames too.
  The match list renames as well: both trees and the folders' entries follow the move, and a failure moves it back
  with a toast.
- **Gaps (11).** ⌘⌫ (Trash): the plugin API has no Trash, and a remote Linux machine has no standard one. ⌘D
  (Duplicate) is the app's Split Right. Space does nothing: there is no preview card. The table of keys against the
  Finder is in default-plugins.mdx.
- **The Git bar (12)** reads `git status` and `git.head` of the repository the root is in, in the tree's own refresh,
  with no polling: one more git process per refresh (`status --branch --untracked-files=no`, 0.07 s on this repo).
  A root below the repository's root counts the whole repository's changes. Its button opens Git's home in a new tab
  at the end.
- **Limits.** Accessibility sees a tree row as one button, so the change dot is checked by its pixels (needs-you
  orange at the row's end) and the sticky folders only by picture. VoiceOver reads `..` as "dot dot": pierre labels a
  row with its name. A case-only rename (`a.txt` to `A.txt`) works on a case-blind disk.
- **Runs.** Chosen-tests runs 41960833327 (item 10, 2 tests), 41964834494 and 41971911545 (the File Explorer tests, a file card and web drags, 8 tests on the landed head) green. The
  first runs on the new code went red where the tests expected the old `..` button and the old first row. The dot's
  pixel check runs only on a Mac (CI's screenshots draw no web content, so there it is skipped): locally it is red
  with the dots style taken out ("a clean folder shows a change dot") and green with it.
- **Pictures** in `/tmp/oriel-shots/t53d/`: `before-*` and `after-*`, dark and light, of the tree, the tree scrolled
  (sticky folders) and the find bar.
- **For the user.**
  1. In a File Explorer card, row 2 shows Back, Forward, the path (wide), then Filter, Collapse All and the eye. Click
     Filter: the find bar opens under row 2 with the keyboard; type, then Esc: it closes and the tree is whole again.
     Type a letter on the tree: the bar opens with it.
  2. Click a folder, then empty space under the rows: the highlight goes. Click a folder, then Collapse All: the same.
     Click the path field: the selection turns gray.
  3. Click `..`: it highlights like a folder. Double-click it, or press ⌘O: the parent becomes the root. ⌘↑ does the
     same from any row; ⌘← and ⌘→ go Back and Forward (also in Git).
  4. Select a file and press Return: its name, without the extension, is selected for a rename. Type, press Return:
     the file is renamed on disk. A name in use shows a toast and keeps the old name.
  5. In a clean repository, open `docs`, `plugins` and `web` (folders with `node_modules` inside): no yellow dot.
     Touch a file in one of them: that folder gets the dot.
  6. Scroll a long open folder: its folder rows stay stuck at the top, nested; `..` scrolls away.
  7. The bar at the bottom shows the branch, "N changes" and ↑/↓ when ahead or behind; the branch button opens Git
     in a new tab. A folder outside a repository has no bar.

### Track H

- **How measured.** Release builds on this Mac, the bench session's workspaces: one (1 terminal tab), terms (10
  terminal tabs), webs (10 browser tabs on the `oriel-research` reports, copied to `/tmp`), mixed (10 tabs: browsers,
  File Explorer, Git) and many (30 terminal tabs). `-recordLatency` gives each switch's time from the click to the end
  of the turn whose commit drew it, and (a local patch) the main thread's CPU time in it. Clicks went to the HID tap
  under the GUI lock; an in-app driver (local patch) switched workspaces in a background window with no lock. The Mac's
  load was 40–290 all along (other tracks building), so wall times moved ±20 ms between runs: I compared CPU times,
  medians of 6–12 switches, before and after in turns, and checked each cause with a count.
- **Cause.** What grew with the tab count was the tab bar: a switch made a capsule for every tab of the workspace, in
  view or not, at about 2–3 ms of the main thread each (a build with no capsules took every switch down to the 1-tab
  time). Browser, File Explorer and Git tabs cost the same as terminal tabs: only the shown tab's card is made, and a
  kept web card is reused, not made again. Each capsule also followed its frame in the window and wrote it to its state
  at every layout (DragSource).
- **Fix.** The row is a lazy stack: a switch makes only the capsules in and near the row's view (SwiftUI makes about a
  view's width ahead: 13 of 16 on a full-width Retina window, 3 to 8 on CI's). The drag preview takes its place from the
  pointer and the view's size. The new pacing test counts the capsules a switch makes: 24 of 24 on the old code (run
  41972567123, red), at most twice the row's fit on the new.
- **Cause, repeated first visits.** A web card shown for the first time since launch costs 80–145 ms of main thread
  (a new WKWebView and WebContent process, the page loads); a kept one is reused. Cards were dropped by the memory
  trim, which halved both kept sets (to 12 web cards, 12 terminals) on every pressure *warning*. The user's installed
  Oriel got one every 30 minutes like clockwork (16:47, 17:17, … 19:17 in the log) while
  `kern.memorystatus_vm_pressure_level` read normal with 43 % of 32 GB free. **Fix (agreed with the orchestrator):**
  only critical pressure trims; a warning does nothing. D46 and the design pages say so.
- **Numbers** (main-thread CPU ms, then wall ms; medians):

  | Switch | Before | After |
  |---|---|---|
  | one → many (30 tabs), clicks | 99, 110 | 58, 67 |
  | many → one, clicks | 57, 66 | 46, 56 |
  | one → webs (10 browsers), clicks | 76–79, 88 | 68–75, 82–86 |
  | webs → one, clicks | 46–48, 50–54 | 45–48, 50–54 |
  | one → terms / one → mixed (driver) | 48–71 / 57–66 | 49–54 / 56–72 |
  | first visit, one → webs (driver) | 85–145 | 78–82 |
  | phase 48: a terminal tab, a kept browser tab, the overview open, close (driver) | 34–46, 24–36, 38–58, 24–33 | 34–43, 34–42, 47–48, 28–34 |

  The phase 48 measures did not change beyond the noise.
- **Left, and why.** A switch to a 1-tab workspace still costs about 45 ms of main thread here: the whole window's
  update for a new selection (SwiftUI's graph about a third, layout, Core Animation's commit, accessibility queries
  from a client on this Mac). Under 13 tabs a full-width window makes every capsule, so 10 tabs still cost about 20 ms
  more than 1 (68–75 against 45–48): the 50 ms target holds on CI-sized windows and from 30 tabs down to that floor
  here, not for 10 tabs on this loaded Mac. Also left: leaving a terminal tab copies each of its terminals' last picture
  (about 4 ms each, `keepPicture`, phase 48's guard against a blank frame), once per leave.
- **Decisions.** Tried and dropped, no gain beyond the noise: `TabButton` as `Equatable`, a hover panel that follows
  its frame only while hovered, deferring or skipping the terminal snapshot. VoiceOver reads the capsules in and near
  the row's view; ⌘1–9, ⇧⌘[ ] and the palette reach the rest, and a workspace row's value carries its strongest state
  (theme-and-accessibility). The tests wait on a new `tabs.count` value instead of the last capsule.
- **Cause, on-demand tests.** Three on-demand tests (run 41988021088) still asked for a capsule out of view, which the
  lazy row no longer makes: the kept-cards costs waited for the last tab's capsule, and the stress test checked t1's
  capsule after ⌘T scrolled the row to the new tab. The product was right; they now wait on `tabs.count` and on t1's
  page being gone. Then the stress test's `heap` of the app (37 s at 400 panes on CI) ran past the e2e helper's 60 s
  on a runner half as fast: that bound is for a hung tool, now 180 s. Runs: 41991682831 (red at heap),
  41994389862 (the three tests green).
- **Pictures.** The look does not change: `/tmp/oriel-shots/t53h/before-webs-dark.png` and
  `/tmp/oriel-shots/t53h/after-webs-dark.png` are the same pixels.
- **For the user.**
  1. Open a workspace with 20 or more tabs, then switch to it and away a few times: it shows at once, as a small one
     does.
  2. Switch to your reports workspace after the Mac has been up for an hour: the browser tab shows its page at once,
     with no reload.
  3. In a workspace with more tabs than fit, drag a tab to the row's end and hold: the row scrolls; check that the
     dimmed capsule and the drop place look right as it scrolls.
  4. With VoiceOver on, move through the tab row: it reads the tabs in view; ⌘1–9 reach the others.

### Track I

- **How measured.** Release builds on this Mac, the user's session copied to `/tmp` and opened with pi in a chat card of
  a throwaway session, idle, no message sent. An in-app driver (local patch) switched tabs and workspaces in a
  background window, 1.2 s apart, and logged each switch's main-thread CPU time to the end of the turn that drew it,
  with counts of the bodies run. The Mac's load was 100–140, so I compared CPU medians of 6–7 switches, before and after
  in the same hour, and checked each cause with a count. Time Profiler and SwiftUI traces of 14 switches to the chat
  tab are in `/tmp/oriel-shots/t53i/` (`tp-before`, `tp-lines`, `sui-before`, `sui-after`). Under the SwiftUI
  instrument (which slows the app) the 14 switches had 15 hangs of 250–930 ms and 731,000 SwiftUI updates before, 4
  hangs of 256–304 ms and 235,000 updates after.
- **Cause.** An idle chat costs nothing (13–50 ms of main thread per 5 s, as a terminal tab). The cost is each show:
  the card's views go with its tab, so every switch to the chat builds and lays out its whole block of rows again, each
  body once. The block was the newest 34 rows: here 31 rows of long replies, 383 Markdown blocks of selectable text
  (TextKit 2 layout and text selection were about a third of it; SwiftUI's graph and layout the rest). Leaving the chat
  tore all of that down and took the chat's picture (phase 52's overview tile, 10–20 ms).
- **Fix.** The block is the newest rows that hold about 120 lines of text (each line break, and each 90 characters,
  counts as a line), at most 34 rows; Show Earlier adds the next block by the same rule. Here that is 5 rows. A long
  chat of short rows still gets 34. The block no longer moves its start to a user's message (fewer rules, and a smaller
  block would lose its turn's last rows to it). D95 and chat-view say so.
- **Numbers** (main-thread CPU ms, then wall ms; medians):

  | Switch | Before | After |
  |---|---|---|
  | terminal tab → terminal tab (the floor) | 32–34, 36–40 | 34, 39–42 |
  | terminal tab → chat tab | 394, 410 | 124, 131 |
  | chat tab → terminal tab | 100, 104 | 56, 60 |
  | workspace → workspace whose active tab is the chat | 430, 438 | 135, 143 |
  | that workspace → another | 96, 98 | 56, 58 |
  | the same, with a terminal tab active | 41, 46–50 | 44–48, 48–57 |

- **Tried and dropped.** A host view per chat that the window keeps, as browsers and terminals are kept, adopted by the
  card when it shows: SwiftUI builds every row again whenever the host view moves to another superview (also within the
  window, also unhidden), so the cost only moved to after the switch's first frame.
- **Left, and why.** Two targets hold only in part. A show still costs about 90 ms more than a terminal: the rows in
  view must be laid out, and this session's last reply alone is a table and 50 lines (SwiftUI keeps no layout of a card
  that left). And the block holds about one view of rows above the view on purpose, so that the view is full and the
  user can scroll back a little before Show Earlier. Lines are an estimate: long code lines (they do not wrap) and blank
  lines count too many, so a block of long logs, or a very tall card, can show the block's top with room above it
  (a `ponytail:` note says so).
- **Runs.** The new UI test counts the rows built (the stack's rows in the accessibility tree), then again after Show
  Earlier and a workspace switch back. Its first version (the count after a switch back) on the old code: 33 rows,
  red (run 41985315591); at most 10 on the new.
- **Pictures.** The chat at the bottom looks the same, pixel for pixel: `/tmp/oriel-shots/t53i/before-chat.png`,
  `/tmp/oriel-shots/t53i/after-chat.png`.
- **For the user.**
  1. Open your long session in a chat tab, then switch to another tab and back, and to another workspace and back,
     a few times: it shows about three times faster than before (124 ms of main thread against 394 here; a terminal
     tab takes 34).
  2. In that chat, scroll up: Show Earlier comes after about two views of text (not 34 rows) and adds the next ones in
     place.
  3. Scroll up, click Show Earlier, switch away and back: the chat shows its newest rows at the bottom.

### Track J

- **Fix.** Each window runs one check on its machine when it opens (`WindowPages.findAgents`): `$SHELL -ilc` with the
  `command -v` loop and an end marker, through the machine's exec, stopped after 3 s. The answer is one set on the
  window, never saved or refreshed. New Pane reads it and never waits; the first ⌘T after launch shows every agent
  enabled until the check answers (about 0.2 s here).
- **Decisions.** One set per window, not a dictionary by machine: a window has exactly one machine (D43), and its floats
  are of that machine too. A check that failed (a remote machine that needs Connect first) runs again after Connect;
  one that answered never runs again. A missing end marker (fish cannot run the POSIX loop, a broken rc file) means
  unknown, so no shell makes every agent grey. The hover tip names an npm package for each agent.
- **Decisions, keys.** A missing agent keeps its place in the numbering (Pi stays 3 when Codex is missing), so the keys
  of the others never change. If the answer comes while a missing agent is selected, Return does nothing on it.
- **Tests.** CI has no agents, so its UI test job puts stand-in `claude`, `codex`, `pi` and `opencode` files on the
  login shell's `PATH` in its rc files: This Mac's and the sshd machine's (the remote chat tests pick agents in a
  remote window). The agent test hides the user's real
  agents with a stand-in login shell that reads no profile, and a `PATH` of the stand-ins without `codex` plus herdr's
  folder (the e2e helper passes herdr's path).
- **For the user.** Open New Pane, then Agent, in a window on a Mac without one of the four agents: its row is dimmed
  with "Not installed", the pointer does not select it and its hover tip gives the install command. Install it, open a
  new window: the row is enabled there, and still dimmed in the old window.

### Track K

- **Fix.** A folder line under the chooser's list: "Opens in ‹folder›", the pane's folder from herdr until the user
  sets one. A click on it, Tab or ⌘L (Open Location, now enabled on a chooser card) makes it File Explorer's capsule
  field. The pane's machine resolves the typed path in its shell (`cd` then `pwd -P`), so `~`, relative paths and remote
  machines work with one call. The folder is kept on the `Chooser`, not saved.
- **Fix, the pick.** Terminal and Esc type `cd -- '‹folder›'`, and an agent's first line starts with it
  (`cd -- … && claude …`), as Go to Directory types its `cd`. A plugin pane is made with that folder as herdr's `cwd`.
- **Decisions.** The short path is the path bar's rule (`PathField.short`): `~` for the home folder. On a remote machine
  it uses File Explorer's breadcrumb rule (`/Users/x`, `/home/x`, `/root`), so the path bar on a remote machine shows
  `~` now too. Repository-relative names are left to the breadcrumbs: they need a git call per line. The folder shows
  with links resolved, as herdr reports it (`/private/tmp`).
- **Decisions, sharing.** Choose Folder… (the NSOpenPanel, and the remote folder dialog) moved from the plugin bridge to
  `HostStore.chooseFolder`, which both use; the path resolve is `HostStore.folder(_:from:)`. The line's field is its own
  small view rather than `PathField`, which is bound to a plugin's header control.
- **Decisions, look.** The folder icon leads, before "Opens in" and before the path in the field, as in the path bar
  (the user's word after the first pictures). The error has its own line under the field, kept free at all times, so
  the list never moves. A card too short for the list and the line has no line.
- **Fix, Track J.** A missing agent's row drops its command: only "Not installed" shows at its end.
- **Decisions, review.** The line keeps its room while a stand-in waits for herdr's pane, so the list never moves. The
  folder icon is one view in both looks, so a click on it as the field lets go still lands. Return on the shown folder
  types no `cd`. On a remote machine any user's home reads as `~` (a `ponytail:` note): asking each machine for its home
  costs a call per line.
- **Runs.** Chosen-tests run 42001994405 (ChooserTests and File Explorer's path bar test): six green, the remote
  folder test red at its last step. The remote line, the typed `/usr` and its "Opens in /usr on Key Host" worked; the
  pointer's way to the folder line crossed File Explorer's row, which took the selection, so Return opened File
  Explorer. The test picks Terminal with 1 now. Run 42003266529 on the same tests: 7 green.
- **Moved.** Relaunch with Chat's part of `Chooser.swift` went to `Store/Relaunch.swift`: the file was at 392 lines.
- **For the user.** Choose Folder… on This Mac (the panel opens at the folder; the picked one shows); File Explorer
  and Git picked after a typed folder open on its repository.

### Final review fixes

- **Docs pass.** The design pages already had most of the phase from the tracks. It added: a Git home commit opens on a
  double-click or Return (a click selects), the tab row makes only the capsules near its view, Markdown's Side by Side
  follows the side last scrolled, clicked or typed in, ⌘E names the four modes, only Working agents show a time, and
  ⌘F names the find bars.
- **Review.** No blockers. The change dots (a): pierre counts every git status as a change of the folders above it,
  `ignored` included, and has no option to stop it. Leaving the ignored entries out would mean copying pierre's ignored
  look (the dim color, the icon's opacity, the folder's rows inheriting it) into our CSS: the same size, so the style
  stays, with its `ponytail:` drop condition. It now rewrites only when the dots change. The diff rewrite (b), the ⌘W
  stand-ins and the lazy tab row with its pointer-placed drag preview (c) were clean.
- **Cause, the warning check (d).** It still catches warnings that Swift lets through (a `nonisolated` taken off), but
  it matched `$(CURDIR)`, the real path, while the compiler prints a symlinked one (`/tmp` copies): the build passed.
  And a rerun passed, because Xcode prints a warning only when its file compiles. **Fix:** it matches the path inside
  the repo, and touches each warned file, so the next build fails again (checked: two runs red, then green).
- **Cause, Unified ↔ Side by Side.** A switch gave the boxes far above the view new estimated heights with nothing
  holding the file in view, so it moved. **Fix:** the switch runs under `steady`, as a refresh does. Git is 1.8.1.
- **The tree's find bar.** Track D and Track E built two "terminal ⌘F" bars in parallel. The tree's now uses the
  editor's `find.css` and `symbols()`, and floats at the tree's top right as a compact capsule, as the user asked ("why
  the ehck the filter input is taking all the width"): the rows no longer move under it. File Explorer is 1.9.1.
  Pictures: before `/tmp/oriel-shots/t53d/after-{dark,light}-find.png`, after
  `/tmp/oriel-shots/p53f/after-{dark,light}-find.png`.
- **Nits.** `WindowBackground` has its own file. The quick-close step back before a question gets a `ponytail:` note:
  a cancelled question leaves the earlier card lit. Left: the capsule width in the lazy-row test stays a constant (the
  bound is twice the fit, and a width change shows in the tab tests); the change-dot pixel check stays Mac-only.
- **For the user.** Open File Explorer's Filter (or type a letter): a small capsule at the top right, the rows stay
  put; Esc closes it. In a long commit diff, scroll down without stepping changes, switch Unified and Side by Side: the
  file in view stays.

### Track L

- **Cause (45).** Phase 52 kept a seen finish in the Done group by a second flag (`Seen.seenFinishes` →
  `Pane.finishSeen`) that held until the agent worked again, while the state itself turned Idle the moment the tab
  showed. So the row stayed under Done after the user left, and the tab and workspace icons had already gone.
- **Fix.** One rule in `Seen`: a finish counts as seen when the user leaves its pane, not when they reach it. The pane
  looked at is the keyboard card on the page in view of the last key window, or a key floating window's pane
  (`HostStore.lookingKey`, the terminal, so a moved pane stays looked at; set by `AgentsWatch` and `FloatingWindow`
  while their window is active), so the app going to the background keeps it. The flag, its grouping and
  its docs are gone; the tab pill, the hover card, the Workspaces view and the Agents groups all read the one state.
- **Decisions.** Looking is now one pane, not the whole shown tab: a finish in another card of the shown tab stays Done
  until the user gives that card the keyboard and leaves it. Notifications still key on the shown tab
  (`lookingTabID`). Closing a window needs no code: the next key window, main or floating, or the page switch, sets the pane again.
- **For the user.** Open a done agent from the Agents view, switch to another app and back (still Done), then open
  another agent: the first moves to Idle.

### Track M

- **What the capture shows.** Both sessions' cards are terminals (Claude Code and pi TUIs, glow), not chat cards: the
  shift between keyframes 2 and 3 is Claude Code's own redraw (its tool output lost a line), not Oriel. Frame by frame
  at 240 fps, every session swipe ends the same way. The sidebar's page comes to about 2 pt short of its place. Then
  no frame is drawn for 83–125 ms. Then the window shows the new session with the page still 1.5 pt short, and the
  next frame jumps it onto its place. Nothing in a card moves, apart from a TUI's timer updating as its stream comes
  back.
- **Cause.** The window showed the session when the slide's spring was *logically* complete. That is at its 0.2 s,
  where a spring from rest is still about 1.4 % of its way short. So a slow swipe, one that rests before the lift,
  ended 1–3 pt short. The show takes about 100 ms of main thread (it builds the new session's page). That froze the
  slide's last frames short of the page, and the page jumped onto it afterwards. A quick flick goes on at the fingers'
  speed and ends within a fraction of a point, which is why the old tests never saw it.
- **Bisect.** No regression found. The slide and its show have not changed since Oct 26 (`b80e59f1`). The same
  probe (two sessions, a ticking TUI in a two-pane tab, 16 swipes) gave the same show cost of 85–135 ms in a Debug
  build on `fa375b18` (Oct 29), `efa26b24` (your build) and main, with the same timing. The jump depends on how the
  user swipes: how far the page still had to go at the lift, and how slowly.
- **Fix.** The session spring is a `CustomAnimation` around the same spring, and it counts as logically complete only
  once it is within half a point of its end. The slide still ends on SwiftUI's `.logicallyComplete` completion. A slow
  swipe's session now shows about 45 ms later (252 ms after the lift, not 205), with the page 0.3 pt from its place
  (before: 1.3 pt, and it jumped after the hold). A quick flick is unchanged. The swipe record now keeps tenths of a
  point.
- **Cause, the first fix (59935e85).** That fix watched each frame's offset in `Slid` and showed the session from a
  `Task` started there. The on-demand `testATabComesIntoViewWithoutAFlicker` then recorded a commit in which the new
  tab's terminal sat in no card (`-`), after each session swipe (runs 42026085641 and 42030510917). The show ran as a
  main-queue job outside SwiftUI's update, so a commit came after the page changed and before SwiftUI had built the
  new page. SwiftUI's own completion runs the show inside its update, as it always did; the `Task`, `Swipe.arrived`
  and the `Slid` target are gone.
- **Runs.** `testSessionSwipeFollowsTheFingersAndSlidesOnFromTheirSpeed` gets a slow swipe that rests before it lifts,
  and checks that the page is within 0.5 pt of its place in the last frame before the show. Locally on the old code:
  red, "1.6 is not equal to 0.0 +/- 0.5". On the new code: green, with the quick flick test. The show now waits about
  50 ms longer after the pages come within 2 pt, so the two tests' bound on that wait went from 80 to 120 ms: still
  well under the old 150–200 ms tail it guards against.
- **Recordings.** The UI test's screen recordings, before and after:
  `/tmp/oriel-shots/t53m/before-swipe-test.mp4` and `after-swipe-test.mp4`. Each frame's offsets:
  `before-latency.txt` and `after-latency.txt`. I made no screen recording at 120 fps, because the Mac was in use.
- **Left.** The new session still appears about 100 ms after its page lands: that is the cost of building its page.
  Making the show cheaper is a separate job.
- **For the user.** Swipe slowly between two sessions on the sidebar: drag past half a page, hold the fingers still,
  then lift. The page should settle with no stop and jump at the end. Then flick quickly: the same as before.
