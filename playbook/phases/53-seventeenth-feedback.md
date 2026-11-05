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
    - Also in the file list's flat view.
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

## Research, plans only (items 34–38)

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

- D and E both touch `plugins/explorer`: D owns the tree and its header, and E owns the file cards. Each bumps
  File Explorer's version when it lands, rebasing on the other.
- D puts the history keys (10) in `web/oriel`; F rebases onto it.
- F's destructive role (25) touches `ToastView` and the plugin API.

The whole phase is about 6 h of wall time with all tracks at once, then the finish (docs pass, final review, two full
CI runs and on-demand) at about 2–3 h.

## Findings

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
  sheet (`NSWindow.confirm`).
- **Decisions (25).** File Explorer's "changed on disk" toasts (Reload, Keep Mine; Overwrite, Reload) are choices in a
  conflict, not confirmations of a delete or a discard, so they stay plain.
