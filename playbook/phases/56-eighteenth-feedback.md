# Phase 56: Eighteenth feedback: instant switches, a File Explorer status bar, two Markdown modes, one way to open links

Goal: the fixes from the user's eighteenth round:

- Tab and workspace switches never wait for a card's content, and cards keep their state.
- The palette gets a matching search field and Open File, Open Working Tree and Open Commit.
- New Pane shows its folder at once.
- The browser loads pages on a remote machine again.
- File Explorer gets a proper status bar and its fixes.
- Markdown gets two modes.
- Links open the same way everywhere.
- Git's diff gets a filter and hunk jumps.
- A new tab opens beside the current one, with no flicker.
- A check of the notifications plan against the code.

The user's words are quoted; the decisions under them are the orchestrator's. Screenshots in `.build/fb56/` (not
committed):

| File | Shows |
|---|---|
| `3.58.32.png` | the rename field's border clipped on the sides |
| `3.59.59.png`, `4.00.04.png` | after a click on the Git icon, icons turn into grey squares (the footer, the filter's close button) |
| `4.09.26.png` | a sticky folder over another folder's name |
| `4.12.02.png` | whitish selected text in a file card |

Tracks run in parallel and push straight to main after review and green chosen tests. The phase ends with two full
runs and on-demand on the final head.

## Track A: switches never wait for a card (item 1)

1. "like similar to the issue where when chat is open activating that tab or going to that workspace used to be
   significantly slower, now i see that issue when a markdown file opened in file explorer as well. i think this delay
   happens whenever there is something heavy? i think we should make the tab switches and workspace switches
   independent of the pane content, we can show a loader if we want in the pane but switching to the tabs or
   workspaces should be instant, also the previous fix we did for chat kinda refreshes the entire chat window losing
   its scroll posiition and loaded chat messages from show earlier, is there a way to preserve these pane contents
   separately without losing, basically something like independent processes".
   - Measure first: a tab and a workspace switch with a chat view, a big Markdown file in File Explorer and a Git
     diff, with signposts. Find what blocks the switch (a body that rebuilds, a web view that reattaches, a layout).
   - The switch draws the tab strip, the sidebar and the card frames in the same frame; a card's content may show a
     quiet placeholder until it is ready.
   - Cards keep their state across switches: the chat keeps its scroll place and the rows loaded by Show Earlier;
     web cards keep their page. Kept cards are already alive (25 + 25, D46); find why they rebuild and stop it.
   - A test: a switch to a tab with each heavy card finishes in one frame budget; the chat keeps its scroll offset
     and loaded rows.

## Track B: the palette (items 2, 14, 19)

2. "in cmd+k search input is fully round with actual cmd+k border radius less round, basically search input border
   radius and cmd+k pane border radius are different making them look weird, let's make the search input as well same
   border radius as outer cmd+k one, so it looks aesthetic, and make the grey of search box little more evident,
   right now it mostly merged with rest of window and is not evident".
   - The field's corner radius is the panel's radius minus the inset (concentric), and its fill is a step stronger,
     in dark and light, Glass and Classic.
14. "if i have a file path be it any source code, markdown, image or video etc,i should be able to quickly paste in
    path and open that file, like in cmd+k we can have open file here, which asks for path and i can paste the path
    and it opens that file in respective preview one using file explorer plugin, not sure how we can achieve this with
    our plugin architecture, let me know if there are any alternative ways to achieve this, essentially i have a file
    path, i want to open that quickly somehow in some pane".
    - Palette ▸ **Open File…**: a sub-page with a path field (`~` and relative paths from the active pane's folder),
      it opens the file with its default plugin, as `ovvi open <path>` does today (the same code path). Return opens
      in a new tab beside, ⌥Return to the side.
    - Pasting a path into the palette's main field offers "Open ‹path›" as the first row when it exists on the
      machine.
19. "also similar to open file here, we should also have open working tree here to directly open working tree diff
    view and also be able to open a commit given a commit id".
    - Palette ▸ **Open Working Tree** (the active pane's repo) and **Open Commit…** (a field for a sha or ref),
      both opening the Git plugin at that view. Add the plugin arguments Git needs if it lacks them.

### Findings (Track B)

- **Fix (item 2).** The palette's field (the one at `.controlSize(.large)`) has the panel's radius, 14 pt (both
  continuous). A concentric 4 pt, the panel's 14 less its 10 pt inset, looked square to the user. Measured at 1x
  on CI, the panel's corner leaves its straight edges about 12 pt from the corner. The other fields stay capsules.
- **Cause (item 2's grey).** On the glass panel a hierarchical fill (`.primary.opacity`) is vibrant: 7 % showed 3
  steps over the panel, and 10 % only 4. The field now takes a flat Look color, `paletteField`.
- **Fix (items 14, 19).** Open File…, Open Working Tree and Open Commit… resolve through `ovvi open`'s own code
  (`AgentCall.opening`), then open with `Page.open` as the plugins' links do: a new tab, ⌥ (Return or click) to the
  side. A path is checked and `~` expanded by one `sh` call on the page's machine, so it works on a remote machine.
- **Decisions.** A filter starting with `/`, `~`, `./` or `../` is checked as a path, 150 ms after the last key;
  when it exists, **Open ‹path›** is the first row. Open Commit takes a hash or a ref: the app resolves it with
  `git rev-parse --verify` (`Git.commit`) and the label holds the whole hash, so `ovvi open git . main` works too
  and a mistyped hash is a notice. A path or commit that names nothing closes the palette with a warning notice.
- **Cause (review).** "open file" lit Open File Explorer Here: both titles start with the filter, and the tie went
  to the earlier row. A title that is the whole filter now wins the tie.
- **For the user.** Return opens in a new tab at the end until Track J makes new tabs open beside.

### Runs (Track B)

- **Runs.** The first chosen-tests run of the new test failed on a tab it never selected (a test bug); the
  review's ranking blocker would have failed it too. Green on 14670eb2 (plus a throwaway picture test): run
  42144998994, Executed 4 tests (the new one, two palette tests for the ranking, the pictures).

## Track C: New Pane's folder (item 3)

3. "on the new pane thing, showing the path, it takes a brief second before its shown and that filckers the new
   pane, it should be shown immediately, not sure why it takes time, does it wait for underlying terminal to be
   ready? we should have that path populated automatically without waiting for terminal to be ready, from what i know
   the behavior is it takes the path from the last tab or pane or something like that, see what's the exact behavior
   of original herdr on what path to load for new terminal panes, and let's infer the paths from that logic, instead
   fo waiting for terminal to load or soemthing, and keep everything greyed out, right now path is white in color, it
   should be all grey in color same as opens in text, only when clicked on it or tabbed on it, it should be activated
   as input and white in color".
   - Read herdr's source for the folder a new pane, split and tab start in; compute the same folder from the
     snapshot Ovvi already has, with no wait. The New Pane card shows it in its first frame.
   - The folder is grey like "Opens in" until clicked or tabbed into; then it is a white field.

## Track D: the remote browser (item 4)

4. "so after the update to browser where we can flip between server and this mac, i can't laod any page in browser
   in devmv-aai, it used to load fine before, it this some regression? it works fine when i toggle it to this mac
   though".
   - Find the regression (bisect the browser commits since phase 52) and fix the cause; read only on the user's
     devvm; test with a throwaway session on a remote machine as the remote browser tests do.

## Track E: File Explorer's tree (items 5, 6, 8, 9, 10, then 7 and 20)

5. "rename border is getting clipped on the sides" (`3.58.32.png`).
6. "after i click git icon, it becomes like this greyed out, weirdly after clicking git icon cmd+f close icon also
   grays out" (`3.59.59.png`, `4.00.04.png`): icons turn into grey squares. Find why the glyphs stop drawing.
8. "right clicking on any folder should show rename option as well, as we support that now".
9. "also cmd + arrows work fine as long as we go to file editor view, i think there cmd arrows are used to move
   cursors and that overrides ig, let's figure out better shortcut for it so it works even in file previews, let's
   use that same shortcut for history navigation in both file tree and git, make sure that new shortcut works in any
   view".
   - Back and Forward become ⌘[ and ⌘] (Finder, Safari and Xcode use them; Ovvi has no plain ⌘[ ⌘]). They work in
     every view of File Explorer and Git, including an editor, where they replace CodeMirror's indent keys. Keep
     ⌘← ⌘→ where no text field has the keyboard.
10. "the sticky folders gets grey background, let's not show any grey background to it, also when there is another
    folder behind it, they are overlapping, we should fix that, for files it deosnt' overlap, only for folders it
    overlaps" (`4.09.26.png`).
7. and 20. The status bar, after the user picks a mockup from Track G: "can we improve the overall footer for git
   better, it looks bad, and not fitting to the view, use branch icon and then show branch name, then show line
   chanegs + and - and then pull and push things, also make those pull and push as buttons, show them only when there
   is something to pull, or something to push, and show fetch icon button all the time to fetch, and at the right edge
   show a button like open git or something like that which opens the git plugin" and "also in the file explorer,
   make the footer as proper status bar instead of just for git, we can show some useful info related to that
   folder, give me some ui mockups for the footer including git and with no git etc, and i can confirm which on to go
   with".

## Track F: file cards (items 11, 13, 15, then 12)

11. and 13. "selected text color is whitish and making the text not readable fix that, make sure it looks good in
    both dark and light mode" (`4.12.02.png`) and "simlar selection color problem is there with markdown as well".
15. "in file preview, we should have word wrap option simlar to word wrap button in git diff".
12. After the user picks from Track G: "in markdown, for the mode selection, i think we should basically simplify to
    two options, one for wyswig and one for source, so in source / preview, we can collapse the preview anyway now, so
    no need source only, in wyswig mode, we should have some kind read lock or something to disable edits and when
    unlocked inline edits works, give me some options on how we can simplify the options to just two, with like sub
    options etc, having 4 options is just confusing, also the icon dropdown should be greyed out like the file
    explorer button".

### Findings (Track F)

- **Cause (11, 13):** the editor's selection rule was less specific than CodeMirror's base rule for a focused
  editor (`&light.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground`, a pale lilac). The editor
  never says it is dark, so the light rule drew in dark too, under light text. File and Markdown share the editor.
- **Fix:** the same selector, so the accent at 35 % wins in both looks and in every Markdown mode; Side by Side's
  page (no drawn selection) gets the same rule for WebKit's own.
- **Decisions (15):** Word Wrap is a row 2 toggle in File only (Markdown's Read is prose; Source wraps as before). It
  starts on, as File always wrapped (cards are narrow), and the card keeps its choice for every file it shows. No
  setting: Git's has one, add one here when a user wants unwrapped files by default.
- **Runs:** the File test red on the old code (no Word Wrap button, 42142561012) and green with it
  (42143799483, 2 tests). CI's recordings draw no web content, so the pictures are local.

## Track G: mockups (items 7, 20, 12)

- HTML mockups in `~/Downloads/ovvi-research/phase56-mockups.html`, drawn from real screenshots of the current
  cards: 3–4 File Explorer status bars (in a repo with changes, ahead and behind, clean, not a repo, a remote
  machine) and 2–3 ways to make Markdown two modes with a read lock. The user picks; Tracks E and F build the pick.

Findings:

- Written: status bars A (one quiet line, recommended), B (capsules), C (folder first, then Git), D (icons only);
  Markdown A (segments and a mode button), B (one grey menu with sub-options), C (a lock button and a grey mode
  menu, recommended). Built by `~/Downloads/ovvi-research/phase56-src/build.py` on screenshots of `156a850b`.
- A plugin label's iid is exactly 6 `[a-z0-9]`: a 5-letter iid shows a plain terminal titled with the label.
- A launch with `open -n` can lose the 3 s login-shell lookup and show "herdr is not installed"; launch again.
- The window's height is the user's saved frame and changed between launches (1005 and 1084 pt): take every shot of
  one report in one hold, or measure each.
- No Side by Side shot: the GUI lock went to the user first. Source's row 2 is drawn on the Read shots.

Runs: none (no app code).

## Track H: one way to open links (item 16)

16. "in markdown, when there are links, clicking on it doesn't open by default clicking on it should open in new
    tab, and right clicking on it should have open in new tab and open to the side similar to what we show in file
    explorer, we should have open to the side option in browser as well for links, in markdown, even if its another
    markdown link, it should have option to open in new tab, open to the side, and open, basically if its markdown
    link clicking on it should open in the same pane, cmd+click opens in new tab, and option+click opens to the side,
    but if its webpage link, by default it opens in new tab, and option+tab opens to the side, and cmd+tab does the
    same as opens in new tab, in browser we should have option+click option as well, let's basically try to make
    things consistent on how we open etc, analyse all current state and updat things accordingly, same with open file
    option in diff view as well".
    - Write down today's behavior everywhere a link or a file opens (Markdown, file cards, File Explorer, Git's diff
      and file headers, the browser, the chat view), then one rule:
      - a file link: click opens in the same card, ⌘-click a new tab beside, ⌥-click to the side;
      - a web link: click and ⌘-click open a new browser tab beside, ⌥-click to the side;
      - the context menu offers Open, Open in New Tab and Open to the Side.
    - The rule goes in the design docs once, and every place follows it.

## Track I: Git's diff (items 17, 18)

17. "we should have similar cmd+f filter in diff view as well".
18. "we should also have keybinding ] and [ to jump files in diff view basically pressing ] should jump to next file
    and pressing [ should jump to previous file, it will be actually better if it can jump based on hunks instead of
    files, but check how feasible it is to do the hunk jumps correctly, if not fallback to file jump".

## Track J: new tabs beside (item 21)

21. "let's say i have so many tabs where not all tabs are in view, and when we open a new tab now that opens at the
    end, actually can we revert this to previous behavior, pressing cmd+click or open in new tab from any tab should
    open the tab beside the current tab, instead of moving it at the end. only thing is we should make sure there is
    no flicker in the tab movement, previously we reverted that coz by default tab goes to the end and it flickers and
    then shows in correct position, we should show it directly in its correct position withou flicker".
    - The new tab shows in its final place in its first frame (an optimistic tab placed beside, as instant tabs do),
      and the strip scrolls to it.

## Track K: notifications check (item 22)

22. "it also looks like we already implemented notifications as well right? check the research report we had earlier
    and then see if its fully implemetned or anything left, ignore the apple signing stuff etc for now though".
    - A report only: each part of `~/Downloads/ovvi-research/notifications-plan.html` against the code, built, part
      built or not built, with what is left and its cost.

### Findings (Track K)

- The plan is not built. Main has what the plan calls "today" (phases 15 and 50): generic needs-you and finished
  banners, `ovvi notify` (one per pane every 10 s), three switches (now in Settings ▸ Agents, phase 55), the Dock
  badge and menu. No commit since the plan touched the notification code beyond the rename.
- Of 57 parts: 16 built, 10 part built, 28 not built, 5 blocked (herdr-core status, Sparkle), 3 left out (signing).
- All 8 plan phases remain, 43 agent hours: about 35 can start now (phase 3's Settings window and phase 5's chat
  channels exist), 8 wait for herdr-core (phase 4) and Sparkle (the update kind). Optional 10 h unchanged.
- Report: `~/Downloads/ovvi-research/notifications-status.html`.

### Runs (Track K)

- None: a report, no code.

## Track L: the Agents view's Done, Idle and order (item 23)

23. "oh and finally one more thing on the agent sidebar thing, couple of things: this done and idle separation is bit
    weird i feel, what's the actual purpose or difference between done and idle? like why does herdr maintain those
    both, and how we can handle those better, coz now i know done moves to idle after we view it and then unfocus it,
    but it still the experience is weird, how does t3code does it? give me few options on how we can do it, give me a
    html report, and i also feel within a group we should sort the agents based on recently updated first, now they
    jump to different positions, check all of this, and give me good ux experience for agents view overall".
    - A report only: why herdr has both, how T3 Code and others do it, 3–4 options for the states and the order with
      mockups from real screenshots, and a recommendation.

### Findings (Track L)

- herdr's `done` is `idle` plus "not seen" (`pane_agent_status`, `src/app/api_helpers.rs`): an unread flag, not a
  state. herdr's own Priority sort puts the newest `state_change_seq` first inside each status.
- Rows jump because a change of state moves a row to another group, where it lands in workspace order, with no motion;
  and a click on one agent moves the one you leave from Done to Idle in the same frame.
- T3 Code has no Done group: a green Done mark on an unread thread, cleared by the visit; rows move 2 s late and slide.
  No app read (Superset, Vibe Kanban, cmux, Conductor, Codex, Claude Code, Cursor) has Done beside Idle.
- Recommended: Done folds into Idle as the check box on the row (it goes when you leave; the row stays); newest
  `state_change_seq` first in each group; no move while the pointer is over the list, then a 0.2 s slide; 1 s settle.
  About 6 agent hours, no herdr change.
- Report: `~/Downloads/ovvi-research/agents-view-ux.html`.

### Runs (Track L)

- None: a report, no code.

## Track M: Fetch, Pull and Push in a workspace's menu (item 24)

24. "also one more thing in the workspace sidebar as well we show the git status right, can we have an option where
    when we right click we see fetch, pull, push options there, only for theworkspaces with git repos identified, and
    have a separator for these options".
    - A row with a git line gets Fetch, Pull and Push between separators in its context menu, run on the session's
      machine in the folder of the git line, with a notice while git runs, git's message on failure, and the git line
      read again after.

### Findings (Track M)

- **Decisions:** the Git card's commands, shared (`Git.Sync`): `fetch --all`, `pull`, and `push` with
  `push.autoSetupRemote`, through `Git.run` (no password prompt, git's stderr is the error). The section sits before
  Close Workspace; the workspace menu shows only in the sidebar, so nothing else changed.
- **Decisions:** Pull and Push stay enabled at zero behind or ahead: the counts are from the last fetch (Pull fetches
  first), and a branch with no upstream shows zero ahead yet Push publishes it.
- **Decisions:** while git runs, an information notice ("Pulling ‹workspace›…"); on success it goes, and the git line
  shows the result; on failure git's words in the error notice. The items are disabled with the rest of the menu while
  the session is stopped.
- **Fix (review):** git puts its `hint:` lines before its error, and the notice shows two lines: it drops the hints and
  shows the last two lines. The 10 s refresh skips the workspace while a sync runs.
- **For the user:** right-click a repository's row: Fetch, Pull, Push; a row outside a repository has none.

### Runs (Track M)

- Chosen-tests runs of `testWorkspaceRowsShowGitWorktreesAndSync`: green at 581b7e6a (dark, 43 s), and green after the
  review's fixes with a throwaway light relaunch (27 s). Each step fails without the feature: no Fetch item, no
  behind 2 without a fetch, no notice without Push, no 0/0 without Pull.
